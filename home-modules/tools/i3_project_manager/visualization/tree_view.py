"""
Hierarchical window state tree view using Textual Tree widget.

Displays window state organized by monitors → workspaces → windows
with real-time updates from daemon events.
"""

import asyncio
import logging
from typing import Dict, List, Optional, Set

from textual.app import ComposeResult
from textual.containers import Container
from textual.widgets import Tree
from textual.widgets.tree import TreeNode
from textual.reactive import reactive

from ..core.daemon_client import DaemonClient, DaemonError
from ..models.layout import WindowState

logger = logging.getLogger(__name__)


class WindowTreeView(Container):
    """Hierarchical window state tree visualization.

    Displays window state in tree format:
    - Outputs (monitors)
      - Workspaces
        - Windows

    Features:
    - Keyboard navigation (arrows to navigate, Enter to focus window)
    - Expand/collapse nodes ('c' key)
    - Filter by project, monitor, workspace, class, status ('f' key)
    - Real-time updates from daemon events (debounced 100ms)
    - Window property display (class, title, workspace, project, marks)
    """

    # Reactive properties
    filter_text: reactive[str] = reactive("")
    show_hidden: reactive[bool] = reactive(False)

    def __init__(
        self,
        daemon_client: Optional[DaemonClient] = None,
        auto_refresh: bool = True,
        debounce_ms: int = 100,
        *args,
        **kwargs,
    ):
        """Initialize window tree view.

        Args:
            daemon_client: DaemonClient instance (creates new if None)
            auto_refresh: Enable real-time updates from daemon
            debounce_ms: Debounce window for event batching (milliseconds)
        """
        super().__init__(*args, **kwargs)
        self.daemon_client = daemon_client
        self.auto_refresh = auto_refresh
        self.debounce_ms = debounce_ms
        self._tree: Optional[Tree] = None
        self._update_task: Optional[asyncio.Task] = None
        self._subscription_task: Optional[asyncio.Task] = None
        self._pending_update = False
        self._node_map: Dict[str, TreeNode] = {}  # Map node IDs to TreeNode instances

    def compose(self) -> ComposeResult:
        """Create child widgets."""
        self._tree = Tree("Window State", id="window-tree")
        self._tree.show_root = True
        self._tree.show_guides = True
        yield self._tree

    async def on_mount(self) -> None:
        """Widget mounted, start real-time updates if enabled."""
        # Initial tree load
        await self.refresh_tree()

        # Start real-time updates
        if self.auto_refresh:
            self._subscription_task = asyncio.create_task(self._subscribe_to_events())

    async def on_unmount(self) -> None:
        """Widget unmounted, cleanup tasks."""
        if self._subscription_task:
            self._subscription_task.cancel()
            try:
                await self._subscription_task
            except asyncio.CancelledError:
                pass

        if self._update_task:
            self._update_task.cancel()
            try:
                await self._update_task
            except asyncio.CancelledError:
                pass

    async def refresh_tree(self) -> None:
        """Refresh tree from daemon state (T018: tree structure creation)."""
        if not self._tree:
            return

        try:
            # Get daemon client
            client = self.daemon_client or await self._get_daemon_client()

            # Query window tree from daemon
            tree_data = await client.get_window_tree()

            # Clear existing tree
            self._tree.clear()
            self._node_map.clear()

            # Build tree structure
            root = self._tree.root
            total_windows = tree_data.get('total_windows', 0)
            root.set_label(f"Window State ({total_windows} windows)")

            for output in tree_data.get("outputs", []):
                output_node = root.add(
                    self._format_output_label(output),
                    data={"type": "output", "name": output["name"]},
                )
                self._node_map[f"output:{output['name']}"] = output_node

                for workspace in output.get("workspaces", []):
                    ws_node = output_node.add(
                        self._format_workspace_label(workspace),
                        data={"type": "workspace", "number": workspace["number"]},
                    )
                    self._node_map[f"workspace:{workspace['number']}"] = ws_node

                    for window in workspace.get("windows", []):
                        # Apply filters
                        if not self._should_show_window(window):
                            continue

                        window_node = ws_node.add(
                            self._format_window_label(window),
                            data={"type": "window", "id": window["id"], "window": window},
                        )
                        self._node_map[f"window:{window['id']}"] = window_node

            # Expand root and first level by default
            self._tree.root.expand()

        except DaemonError as e:
            logger.error(f"Failed to refresh tree: {e}")
            self._tree.root.set_label(f"Error: {e}")
        except Exception as e:
            logger.error(f"Unexpected error refreshing tree: {e}")
            self._tree.root.set_label(f"Unexpected error: {e}")

    def _format_output_label(self, output: Dict) -> str:
        """Format output/monitor node label (T022: property display).

        Args:
            output: Output data dict

        Returns:
            Formatted label string
        """
        name = output["name"]
        rect = output["rect"]
        ws_count = len(output.get("workspaces", []))
        return f"📺 {name} ({rect['width']}x{rect['height']}) - {ws_count} workspaces"

    def _format_workspace_label(self, workspace: Dict) -> str:
        """Format workspace node label (T022: property display).

        Args:
            workspace: Workspace data dict

        Returns:
            Formatted label string
        """
        num = workspace["number"]
        name = workspace["name"]
        win_count = len(workspace.get("windows", []))
        focused = "●" if workspace.get("focused") else "○"
        visible = "👁" if workspace.get("visible") else ""
        return f"{focused} WS{num}: {name} - {win_count} windows {visible}"

    def _format_window_label(self, window: Dict) -> str:
        """Format window node label (T022: property display).

        Args:
            window: Window data dict

        Returns:
            Formatted label string with class, title, project, status
        """
        window_class = window.get("window_class", "?")
        title = window.get("title", "")
        pid = window.get("pid")
        project = window.get("project")
        classification = window.get("classification", "global")
        hidden = window.get("hidden", False)
        focused = window.get("focused", False)
        floating = window.get("floating", False)

        # Truncate title if too long
        if len(title) > 50:
            title = title[:47] + "..."

        # Build label
        parts = []

        # Focus indicator
        parts.append("🔹" if focused else "  ")

        # Classification/status
        if hidden:
            parts.append("🔒")
        elif classification == "scoped":
            parts.append("🔸")
        else:
            parts.append("  ")

        # Floating indicator
        if floating:
            parts.append("⬜")

        # Class and title
        parts.append(f"{window_class}: {title}")

        # PID (if available)
        if pid:
            parts.append(f"(PID: {pid})")

        # Project tag
        if project:
            parts.append(f"[{project}]")

        return " ".join(parts)

    def _should_show_window(self, window: Dict) -> bool:
        """Check if window should be shown based on filters.

        Args:
            window: Window data dict

        Returns:
            True if window passes all filters
        """
        # Hidden window filter
        if window.get("hidden", False) and not self.show_hidden:
            return False

        # Text filter (if set)
        if self.filter_text:
            filter_lower = self.filter_text.lower()
            searchable = (
                window.get("window_class", "")
                + " "
                + window.get("title", "")
                + " "
                + (window.get("project") or "")
            ).lower()

            if filter_lower not in searchable:
                return False

        return True

    async def _subscribe_to_events(self) -> None:
        """Subscribe to daemon events for real-time updates (T020: real-time updates).

        Implements debouncing to batch rapid events.
        """
        # Create a separate connection for event subscription to avoid conflicts
        subscription_client = DaemonClient()
        await subscription_client.connect()

        try:
            async for event in subscription_client.subscribe_window_events():
                # Event received, schedule debounced update
                if not self._pending_update:
                    self._pending_update = True
                    # Schedule update after debounce window
                    await asyncio.sleep(self.debounce_ms / 1000.0)
                    if self._pending_update:
                        await self.refresh_tree()
                        self._pending_update = False
        except asyncio.CancelledError:
            logger.debug("Event subscription cancelled")
        except DaemonError as e:
            logger.error(f"Event subscription failed: {e}")
        except Exception as e:
            logger.error(f"Unexpected error in event subscription: {e}")
        finally:
            # Clean up subscription connection
            await subscription_client.close()

    async def _get_daemon_client(self) -> DaemonClient:
        """Get or create daemon client.

        Returns:
            DaemonClient instance
        """
        if not self.daemon_client:
            from ..core.daemon_client import get_daemon_client

            self.daemon_client = await get_daemon_client()
        return self.daemon_client

    # Keyboard navigation handlers (T019: keyboard navigation)

    async def on_key(self, event) -> None:
        """Handle keyboard events for navigation and actions.

        Keybindings:
        - Enter: Focus selected window in i3
        - c: Toggle collapse/expand of selected node
        - f: Open filter dialog
        - h: Toggle show/hide hidden windows
        """
        if event.key == "enter":
            await self._focus_selected_window()
            event.stop()
        elif event.key == "c":
            self._toggle_node_collapse()
            event.stop()
        elif event.key == "f":
            await self._open_filter_dialog()
            event.stop()
        elif event.key == "h":
            self.show_hidden = not self.show_hidden
            await self.refresh_tree()
            event.stop()

    async def _focus_selected_window(self) -> None:
        """Focus selected window in i3 (T019: Enter keybinding)."""
        if not self._tree:
            return

        cursor_node = self._tree.cursor_node
        if not cursor_node or not cursor_node.data:
            return

        # Check if selected node is a window
        if cursor_node.data.get("type") != "window":
            return

        window_id = cursor_node.data.get("id")
        if not window_id:
            return

        try:
            # Use i3 IPC to focus window
            import i3ipc.aio

            async with i3ipc.aio.Connection() as i3:
                await i3.command(f"[id={window_id}] focus")
        except Exception as e:
            logger.error(f"Failed to focus window {window_id}: {e}")

    def _toggle_node_collapse(self) -> None:
        """Toggle collapse/expand of selected node (T019: 'c' keybinding)."""
        if not self._tree:
            return

        cursor_node = self._tree.cursor_node
        if not cursor_node:
            return

        cursor_node.toggle()

    async def _open_filter_dialog(self) -> None:
        """Open filter input dialog (T021: search/filter).

        TODO: Implement proper input dialog with Textual Input widget.
        For now, this is a placeholder for the filter functionality.
        """
        # This will be implemented when integrating with full TUI
        pass

    def watch_filter_text(self, new_filter: str) -> None:
        """React to filter text changes (T021: search/filter)."""
        # Refresh tree when filter changes
        asyncio.create_task(self.refresh_tree())

    def watch_show_hidden(self, show: bool) -> None:
        """React to show_hidden toggle."""
        # Refresh tree when show_hidden changes
        asyncio.create_task(self.refresh_tree())
