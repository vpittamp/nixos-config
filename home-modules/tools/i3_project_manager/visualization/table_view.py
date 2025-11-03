"""
Table view for window state using Textual DataTable widget.

Provides sortable, filterable table view of all windows with columns:
ID, Class, Instance, Title, Workspace, Output, Project, Hidden status
"""

import asyncio
import logging
from typing import Dict, List, Optional

from textual.app import ComposeResult
from textual.containers import Container
from textual.widgets import DataTable
from textual.reactive import reactive

from ..core.daemon_client import DaemonClient, DaemonError
from ..models.layout import WindowState

logger = logging.getLogger(__name__)


class WindowTableView(Container):
    """Sortable and filterable table view of window state.

    Features:
    - Click column headers to sort ascending/descending (T024)
    - Filter by project, workspace, output, visible/hidden (T025)
    - Real-time updates from daemon events (T026)
    - Full window property display in columns (T023)
    """

    # Reactive properties
    filter_project: reactive[Optional[str]] = reactive(None)
    filter_workspace: reactive[Optional[int]] = reactive(None)
    filter_output: reactive[Optional[str]] = reactive(None)
    show_hidden: reactive[bool] = reactive(False)
    sort_column: reactive[str] = reactive("id")
    sort_reverse: reactive[bool] = reactive(False)

    # Column definitions
    COLUMNS = [
        ("ID", "id", 10),
        ("PID", "pid", 10),
        ("Class", "window_class", 20),
        ("Instance", "instance", 15),
        ("Title", "title", 35),
        ("Workspace", "workspace", 10),
        ("Output", "output", 15),
        ("Project", "project", 15),
        ("Status", "status", 10),
    ]

    def __init__(
        self,
        daemon_client: Optional[DaemonClient] = None,
        auto_refresh: bool = True,
        debounce_ms: int = 100,
        *args,
        **kwargs,
    ):
        """Initialize window table view.

        Args:
            daemon_client: DaemonClient instance (creates new if None)
            auto_refresh: Enable real-time updates from daemon
            debounce_ms: Debounce window for event batching (milliseconds)
        """
        super().__init__(*args, **kwargs)
        self.daemon_client = daemon_client
        self.auto_refresh = auto_refresh
        self.debounce_ms = debounce_ms
        self._table: Optional[DataTable] = None
        self._subscription_task: Optional[asyncio.Task] = None
        self._pending_update = False
        self._windows: List[Dict] = []

    def compose(self) -> ComposeResult:
        """Create child widgets."""
        self._table = DataTable(id="window-table", zebra_stripes=True)
        yield self._table

    async def on_mount(self) -> None:
        """Widget mounted, initialize table and start updates."""
        if not self._table:
            return

        # Setup table columns (T023: table structure)
        for label, key, width in self.COLUMNS:
            self._table.add_column(label, key=key, width=width)

        # Initial data load
        await self.refresh_table()

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

    async def refresh_table(self) -> None:
        """Refresh table from daemon state (T023: data population)."""
        if not self._table:
            return

        try:
            # Get daemon client
            client = self.daemon_client or await self._get_daemon_client()

            # Query window tree from daemon
            tree_data = await client.get_window_tree()

            # Extract all windows from tree structure
            windows = []
            for output in tree_data.get("outputs", []):
                for workspace in output.get("workspaces", []):
                    for window in workspace.get("windows", []):
                        # Apply filters
                        if not self._should_show_window(window):
                            continue

                        windows.append(window)

            # Store for sorting
            self._windows = windows

            # Sort windows (T024: sorting)
            sorted_windows = self._sort_windows(windows)

            # Update table
            self._table.clear()
            for window in sorted_windows:
                self._table.add_row(
                    str(window.get("id", "")),
                    str(window.get("pid", "")) if window.get("pid") else "-",
                    window.get("window_class", ""),
                    window.get("instance", ""),
                    self._truncate(window.get("title", ""), 35),
                    f"WS{window.get('workspace', '?')}",
                    window.get("output", ""),
                    window.get("project", "-") or "-",
                    self._format_status(window),
                )

        except DaemonError as e:
            logger.error(f"Failed to refresh table: {e}")
        except Exception as e:
            logger.error(f"Unexpected error refreshing table: {e}")

    def _format_status(self, window: Dict) -> str:
        """Format window status string.

        Args:
            window: Window data dict

        Returns:
            Status string with indicators
        """
        parts = []

        if window.get("hidden", False):
            parts.append("🔒Hidden")
        elif window.get("classification") == "scoped":
            parts.append("🔸Scoped")
        else:
            parts.append("Global")

        if window.get("focused", False):
            parts.append("●")

        if window.get("floating", False):
            parts.append("Float")

        return " ".join(parts)

    def _truncate(self, text: str, max_len: int) -> str:
        """Truncate text to max length.

        Args:
            text: Text to truncate
            max_len: Maximum length

        Returns:
            Truncated text with ellipsis if needed
        """
        if len(text) <= max_len:
            return text
        return text[: max_len - 3] + "..."

    def _should_show_window(self, window: Dict) -> bool:
        """Check if window should be shown based on filters (T025: filtering).

        Args:
            window: Window data dict

        Returns:
            True if window passes all filters
        """
        # Hidden window filter
        if window.get("hidden", False) and not self.show_hidden:
            return False

        # Project filter
        if self.filter_project and window.get("project") != self.filter_project:
            return False

        # Workspace filter
        if self.filter_workspace and window.get("workspace") != self.filter_workspace:
            return False

        # Output filter
        if self.filter_output and window.get("output") != self.filter_output:
            return False

        return True

    def _sort_windows(self, windows: List[Dict]) -> List[Dict]:
        """Sort windows by current sort column (T024: sorting).

        Args:
            windows: List of window dicts

        Returns:
            Sorted list of windows
        """
        # Get sort key function
        sort_key = lambda w: w.get(self.sort_column, "")

        # Handle numeric sorting for id, pid, and workspace
        if self.sort_column in ["id", "pid", "workspace"]:
            sort_key = lambda w: w.get(self.sort_column, 0) or 0

        # Sort
        return sorted(windows, key=sort_key, reverse=self.sort_reverse)

    async def _subscribe_to_events(self) -> None:
        """Subscribe to daemon events for real-time updates (T026: real-time updates).

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
                        await self.refresh_table()
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

    # Column header click handler (T024: sorting)

    async def on_data_table_header_selected(self, event) -> None:
        """Handle column header click for sorting.

        Args:
            event: DataTable header selected event
        """
        column_key = event.column_key

        # Toggle sort direction if same column, otherwise use ascending
        if self.sort_column == column_key:
            self.sort_reverse = not self.sort_reverse
        else:
            self.sort_column = column_key
            self.sort_reverse = False

        # Refresh table with new sort
        await self.refresh_table()

    # Reactive watchers for filters

    def watch_filter_project(self, project: Optional[str]) -> None:
        """React to project filter changes."""
        asyncio.create_task(self.refresh_table())

    def watch_filter_workspace(self, workspace: Optional[int]) -> None:
        """React to workspace filter changes."""
        asyncio.create_task(self.refresh_table())

    def watch_filter_output(self, output: Optional[str]) -> None:
        """React to output filter changes."""
        asyncio.create_task(self.refresh_table())

    def watch_show_hidden(self, show: bool) -> None:
        """React to show_hidden toggle."""
        asyncio.create_task(self.refresh_table())
