"""Window inspector TUI application.

Provides real-time window inspection with i3 integration, allowing users
to inspect window properties, classify windows, and create pattern rules.
"""

import asyncio
import subprocess
from typing import Optional
from pathlib import Path

from textual.app import App
from textual.reactive import reactive

from i3_project_manager.models.inspector import WindowProperties
from i3_project_manager.core.config import AppClassConfig

try:
    from i3ipc.aio import Connection
    from i3ipc import Event
except ImportError:
    # Graceful degradation for testing
    Connection = None
    Event = None


# ============================================================================
# Window Selection Functions (T076-T078)
# ============================================================================


def inspect_window_click() -> Optional[int]:
    """Select window by clicking and return window ID.

    Uses xdotool selectwindow to let user click any window.
    Cursor changes to crosshair and waits for click.

    Returns:
        Window ID (i3 container ID) or None if cancelled

    T078: Click mode window selection
    FR-112: Window selection modes

    Examples:
        >>> window_id = inspect_window_click()
        >>> print(f"Selected window: {window_id}")
        Selected window: 94489280512
    """
    try:
        # Use xdotool to select window by click
        result = subprocess.run(
            ["xdotool", "selectwindow"],
            capture_output=True,
            text=True,
            timeout=30,  # 30 second timeout for user to click
        )

        if result.returncode != 0:
            # User cancelled (pressed Escape)
            return None

        # Parse window ID from output
        x11_window_id = result.stdout.strip()
        if not x11_window_id:
            return None

        # Convert X11 window ID to i3 container ID
        # xdotool returns X11 window ID, but we need i3 con_id
        # We need to query i3 tree to find matching container
        return _find_i3_container_by_x11_id(int(x11_window_id, 16))

    except subprocess.TimeoutExpired:
        return None
    except Exception as e:
        print(f"Error in click selection: {e}")
        return None


def _find_i3_container_by_x11_id(x11_id: int) -> Optional[int]:
    """Find i3 container ID from X11 window ID.

    Args:
        x11_id: X11 window ID from xdotool

    Returns:
        i3 container ID or None if not found
    """
    import i3ipc

    try:
        i3 = i3ipc.Connection()
        tree = i3.get_tree()

        def find_window(container):
            if container.window and container.window == x11_id:
                return container.id
            for child in container.nodes + container.floating_nodes:
                result = find_window(child)
                if result:
                    return result
            return None

        return find_window(tree)
    except Exception:
        return None


async def inspect_window_focused() -> WindowProperties:
    """Inspect currently focused window.

    Uses i3 IPC to get the focused window from the tree.

    Returns:
        WindowProperties for focused window

    Raises:
        ValueError: If no window is focused

    T076: Focused mode window selection
    FR-112: Window selection modes

    Examples:
        >>> props = await inspect_window_focused()
        >>> print(props.window_class)
        Code
    """
    if Connection is None:
        raise ImportError("i3ipc.aio not available")

    i3 = await Connection().connect()
    try:
        tree = await i3.get_tree()
        focused = tree.find_focused()

        if not focused:
            raise ValueError("No window is currently focused")

        return await extract_window_properties(focused)
    finally:
        if i3:
            i3.main_quit()


async def inspect_window_by_id(window_id: int) -> WindowProperties:
    """Inspect window by i3 container ID.

    Uses i3 IPC to look up window by container ID.

    Args:
        window_id: i3 container ID (con_id)

    Returns:
        WindowProperties for specified window

    Raises:
        ValueError: If window not found

    T077: By-ID mode window selection
    FR-112: Window selection modes

    Examples:
        >>> props = await inspect_window_by_id(94489280512)
        >>> print(props.window_class)
        Ghostty
    """
    if Connection is None:
        raise ImportError("i3ipc.aio not available")

    i3 = await Connection().connect()
    try:
        tree = await i3.get_tree()
        container = tree.find_by_id(window_id)

        if not container:
            raise ValueError(f"Window not found: {window_id}")

        return await extract_window_properties(container)
    finally:
        if i3:
            i3.main_quit()


async def extract_window_properties(container) -> WindowProperties:
    """Extract WindowProperties from i3 container.

    Extracts all window metadata, determines classification status,
    generates AI suggestions, and produces reasoning explanation.

    Args:
        container: i3ipc Container object

    Returns:
        Complete WindowProperties with all fields populated

    T069: Property extraction implementation
    FR-113: Extract all window properties
    FR-114: Extract classification status
    FR-115: Generate classification reasoning

    Examples:
        >>> container = tree.find_focused()
        >>> props = await extract_window_properties(container)
        >>> props.window_class
        'Ghostty'
    """
    # Load classification config
    config = AppClassConfig()
    config.load()

    # Extract basic window metadata
    window_class = container.window_class
    instance = container.window_instance
    title = container.name
    marks = list(container.marks) if container.marks else []

    # Get workspace and output
    workspace = ""
    output = ""
    try:
        ws = container.workspace()
        if ws:
            workspace = ws.name
            if hasattr(ws, 'ipc_data') and 'output' in ws.ipc_data:
                output = ws.ipc_data['output']
    except Exception:
        pass

    # Parse floating state (i3 uses "auto_on", "user_on", "auto_off", "user_off")
    floating = container.floating in ("auto_on", "user_on")

    # Parse fullscreen (0 = not fullscreen, 1 = fullscreen)
    fullscreen = container.fullscreen_mode != 0

    # Focused state
    focused = container.focused

    # Determine classification
    current_classification = "unclassified"
    classification_source = "-"
    pattern_matches = []

    if window_class:
        # Check explicit classifications
        if window_class in config.scoped_classes:
            current_classification = "scoped"
            classification_source = "explicit"
        elif window_class in config.global_classes:
            current_classification = "global"
            classification_source = "explicit"
        else:
            # Check pattern matches
            for pattern in config.list_patterns():
                if pattern.matches(window_class):
                    pattern_matches.append(pattern.pattern)
                    if not classification_source or classification_source == "-":
                        current_classification = pattern.scope
                        classification_source = f"pattern:{pattern.pattern}"

    # Generate AI suggestion (simplified - reuse wizard logic)
    suggested_classification = None
    suggestion_confidence = 0.0

    # Generate reasoning
    reasoning = _generate_reasoning(
        window_class=window_class,
        current_classification=current_classification,
        classification_source=classification_source,
        marks=marks,
        pattern_matches=pattern_matches,
    )

    return WindowProperties(
        window_id=container.id,
        window_class=window_class,
        instance=instance,
        title=title,
        marks=marks,
        workspace=workspace,
        output=output,
        floating=floating,
        fullscreen=fullscreen,
        focused=focused,
        current_classification=current_classification,
        classification_source=classification_source,
        suggested_classification=suggested_classification,
        suggestion_confidence=suggestion_confidence,
        reasoning=reasoning,
        pattern_matches=pattern_matches,
    )


def _generate_reasoning(
    window_class: Optional[str],
    current_classification: str,
    classification_source: str,
    marks: list[str],
    pattern_matches: list[str],
) -> str:
    """Generate human-readable classification reasoning.

    Args:
        window_class: WM_CLASS value
        current_classification: Current scope
        classification_source: How determined
        marks: i3 marks on window
        pattern_matches: Matching pattern rules

    Returns:
        Multi-line reasoning explanation

    FR-115: Classification reasoning
    """
    lines = []

    if not window_class:
        lines.append("No WM_CLASS detected - window cannot be classified.")
        lines.append("This window may be a popup or temporary overlay.")
        return "\n".join(lines)

    # Explain classification source
    if classification_source == "explicit":
        if current_classification == "scoped":
            lines.append(f"Explicitly classified as SCOPED in scoped_classes list.")
            lines.append("This window will only appear in its associated project workspace.")
        elif current_classification == "global":
            lines.append(f"Explicitly classified as GLOBAL in global_classes list.")
            lines.append("This window will appear across all project workspaces.")
    elif classification_source.startswith("pattern:"):
        pattern = classification_source.split(":", 1)[1]
        lines.append(f"Matched pattern rule: {pattern}")
        lines.append(f"Classification: {current_classification.upper()}")
        if pattern_matches:
            lines.append(f"\nAll matching patterns ({len(pattern_matches)}):")
            for p in pattern_matches:
                lines.append(f"  • {p}")
    else:
        lines.append(f"Not classified - using default behavior (scoped).")
        lines.append("Add to app-classes.json or create a pattern rule to customize.")

    # Explain project context
    if marks:
        project_marks = [m for m in marks if not m.startswith("_")]
        if project_marks:
            lines.append(f"\nCurrently marked with project: {', '.join(project_marks)}")
            lines.append("This indicates active project context.")

    return "\n".join(lines)


# ============================================================================
# InspectorApp (T080-T085)
# ============================================================================


class InspectorApp(App):
    """Window inspector TUI application.

    Provides real-time window inspection with classification actions,
    live mode updates, and pattern creation.

    Features:
    - Display all window properties from i3
    - Classify windows as scoped/global with s/g keys
    - Create pattern rules with p key
    - Live mode with i3 event subscriptions
    - Copy WM_CLASS to clipboard

    T080: InspectorApp implementation
    T081: Live mode with i3 events
    T082: Classification actions (s/g/u keys)
    T083: Pattern creation integration
    """

    TITLE = "i3pm Window Inspector"
    SUB_TITLE = "Inspect window properties and classifications"

    window_props: reactive[Optional[WindowProperties]] = reactive(None)
    live_mode: reactive[bool] = reactive(False)

    def __init__(
        self,
        window_props: Optional[WindowProperties] = None,
        window_id: Optional[int] = None,
        **kwargs
    ):
        """Initialize inspector app.

        Args:
            window_props: Pre-loaded window properties
            window_id: Window ID to inspect (if props not provided)
        """
        super().__init__(**kwargs)
        self.window_props = window_props
        self._window_id = window_id
        self._i3_connection = None

    async def on_mount(self) -> None:
        """Load window properties and show inspector screen."""
        # Load properties if not provided
        if not self.window_props and self._window_id:
            try:
                self.window_props = await inspect_window_by_id(self._window_id)
            except Exception as e:
                self.notify(f"Failed to load window: {e}", severity="error")
                self.exit()
                return

        if not self.window_props:
            self.notify("No window properties available", severity="error")
            self.exit()
            return

        # Push inspector screen
        from i3_project_manager.tui.screens.inspector_screen import InspectorScreen
        await self.push_screen(InspectorScreen(self.window_props))

    # ========================================================================
    # Classification Actions (T082)
    # ========================================================================

    async def action_classify_scoped(self) -> None:
        """Mark window as scoped (s key).

        FR-117: Direct classification from inspector
        FR-119: Immediate save and daemon reload
        """
        if not self.window_props or not self.window_props.window_class:
            self.notify("Cannot classify - no WM_CLASS", severity="warning")
            return

        try:
            config = AppClassConfig()
            config.load()

            # Remove from global if present
            if self.window_props.window_class in config.global_classes:
                config.global_classes.remove(self.window_props.window_class)

            # Add to scoped
            config.scoped_classes.add(self.window_props.window_class)

            # Save and reload
            config.save()
            await self._reload_daemon()

            # Update properties
            self.window_props.current_classification = "scoped"
            self.window_props.classification_source = "explicit"

            self.notify(
                f"✓ Classified '{self.window_props.window_class}' as scoped",
                severity="information"
            )

            # Refresh display
            await self._refresh_properties()

        except Exception as e:
            self.notify(f"Failed to classify: {e}", severity="error")

    async def action_classify_global(self) -> None:
        """Mark window as global (g key).

        FR-117: Direct classification from inspector
        FR-119: Immediate save and daemon reload
        """
        if not self.window_props or not self.window_props.window_class:
            self.notify("Cannot classify - no WM_CLASS", severity="warning")
            return

        try:
            config = AppClassConfig()
            config.load()

            # Remove from scoped if present
            if self.window_props.window_class in config.scoped_classes:
                config.scoped_classes.remove(self.window_props.window_class)

            # Add to global
            config.global_classes.add(self.window_props.window_class)

            # Save and reload
            config.save()
            await self._reload_daemon()

            # Update properties
            self.window_props.current_classification = "global"
            self.window_props.classification_source = "explicit"

            self.notify(
                f"✓ Classified '{self.window_props.window_class}' as global",
                severity="information"
            )

            # Refresh display
            await self._refresh_properties()

        except Exception as e:
            self.notify(f"Failed to classify: {e}", severity="error")

    async def action_create_pattern(self) -> None:
        """Create pattern rule for window (p key).

        T083: Pattern creation from inspector
        Integration with US1 (pattern dialog reuse)
        """
        from i3_project_manager.tui.screens.pattern_dialog import PatternDialog

        if not self.window_props or not self.window_props.window_class:
            self.notify("Cannot create pattern - no WM_CLASS", severity="warning")
            return

        # Open pattern dialog (reuse from wizard)
        pattern_rule = await self.push_screen_wait(
            PatternDialog(
                initial_pattern=self.window_props.window_class,
                apps=[],  # Inspector doesn't have app list
            )
        )

        if pattern_rule is None:
            return

        # Add pattern to config
        try:
            config = AppClassConfig()
            config.load()
            config.add_pattern(pattern_rule)
            config.save()

            self.notify(
                f"✓ Pattern '{pattern_rule.pattern}' created",
                severity="information"
            )

            await self._reload_daemon()
            await self._refresh_properties()

        except Exception as e:
            self.notify(f"Failed to create pattern: {e}", severity="error")

    # ========================================================================
    # Live Mode (T081)
    # ========================================================================

    async def action_toggle_live(self) -> None:
        """Toggle live mode (l key).

        FR-120: Live mode with i3 event subscriptions
        SC-037: <100ms property updates
        """
        self.live_mode = not self.live_mode

        if self.live_mode:
            await self._enable_live_mode()
        else:
            await self._disable_live_mode()

    async def _enable_live_mode(self):
        """Enable live mode and subscribe to i3 events."""
        if Connection is None:
            self.notify("i3ipc not available", severity="error")
            self.live_mode = False
            return

        try:
            # Create i3 connection
            self._i3_connection = await Connection().connect()

            # Subscribe to events
            self._i3_connection.on(Event.WINDOW_TITLE, self._on_window_title_change)
            self._i3_connection.on(Event.WINDOW_MARK, self._on_window_mark_change)
            self._i3_connection.on(Event.WINDOW_FOCUS, self._on_window_focus_change)

            self.notify("Live mode enabled", severity="information")

        except Exception as e:
            self.notify(f"Failed to enable live mode: {e}", severity="error")
            self.live_mode = False

    async def _disable_live_mode(self):
        """Disable live mode and unsubscribe from events."""
        if self._i3_connection:
            try:
                await self._i3_connection.main_quit()
                self._i3_connection = None
            except Exception:
                pass

        self.notify("Live mode disabled", severity="information")

    async def _on_window_title_change(self, i3_conn, event):
        """Handle window::title event."""
        if not self.window_props or event.container.id != self.window_props.window_id:
            return

        # Update title
        new_title = event.container.name
        self.window_props.title = new_title

        # Update property display with highlight
        screen = self.screen
        if hasattr(screen, 'query_one'):
            try:
                property_table = screen.query_one("#property-table")
                await property_table.update_property("Title", new_title)
            except Exception:
                pass

    async def _on_window_mark_change(self, i3_conn, event):
        """Handle window::mark event."""
        if not self.window_props or event.container.id != self.window_props.window_id:
            return

        # Update marks
        new_marks = list(event.container.marks) if event.container.marks else []
        self.window_props.marks = new_marks

        # Update property display
        screen = self.screen
        if hasattr(screen, 'query_one'):
            try:
                property_table = screen.query_one("#property-table")
                mark_str = self.window_props.format_marks()
                await property_table.update_property("i3 Marks", mark_str)
            except Exception:
                pass

    async def _on_window_focus_change(self, i3_conn, event):
        """Handle window::focus event."""
        if not self.window_props:
            return

        # Update focused state
        new_focused = event.container.id == self.window_props.window_id
        self.window_props.focused = new_focused

        # Update property display
        screen = self.screen
        if hasattr(screen, 'query_one'):
            try:
                property_table = screen.query_one("#property-table")
                focused_str = self.window_props.format_focused()
                await property_table.update_property("Focused", focused_str)
            except Exception:
                pass

    # ========================================================================
    # Helper Methods
    # ========================================================================

    async def action_refresh(self) -> None:
        """Refresh window properties (r key)."""
        await self._refresh_properties()

    async def _refresh_properties(self):
        """Re-query i3 for updated window properties."""
        if not self.window_props:
            return

        try:
            updated_props = await inspect_window_by_id(self.window_props.window_id)
            self.window_props = updated_props

            # Update display
            screen = self.screen
            if hasattr(screen, 'query_one'):
                property_table = screen.query_one("#property-table")
                property_table.set_properties(updated_props)

            self.notify("Properties refreshed", severity="information")

        except Exception as e:
            self.notify(f"Failed to refresh: {e}", severity="error")

    async def action_copy_class(self) -> None:
        """Copy WM_CLASS to clipboard (c key).

        T087: Copy to clipboard action
        """
        if not self.window_props or not self.window_props.window_class:
            self.notify("No WM_CLASS to copy", severity="warning")
            return

        try:
            # Use xclip to copy to clipboard
            subprocess.run(
                ["xclip", "-selection", "clipboard"],
                input=self.window_props.window_class.encode(),
                check=True,
            )
            self.notify(
                f"Copied '{self.window_props.window_class}' to clipboard",
                severity="information"
            )
        except Exception as e:
            self.notify(f"Failed to copy: {e}", severity="error")

    async def _reload_daemon(self):
        """Reload i3 project daemon."""
        try:
            await asyncio.to_thread(
                subprocess.run,
                ["i3-msg", "-q", "tick", "i3pm:reload-config"],
                check=True,
            )
        except Exception as e:
            self.notify(f"Warning: Daemon reload failed: {e}", severity="warning")
