"""Monitor dashboard screen for i3pm TUI.

Displays daemon status, events, and system information.
Migrates functionality from i3-project-monitor tool.
"""

from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, Static, TabbedContent, TabPane
from textual.binding import Binding

class MonitorScreen(Screen):
    """TUI screen for monitoring daemon and system state.

    Features:
    - Live daemon status (Tab 1)
    - Event stream (Tab 2)
    - Event history (Tab 3)
    - i3 window tree inspector (Tab 4)

    Keyboard shortcuts:
    - Tab: Switch between tabs
    - r: Force refresh
    - Esc: Return to browser
    """

    BINDINGS = [
        Binding("r", "refresh", "Refresh"),
        Binding("escape", "back", "Back"),
    ]

    def compose(self) -> ComposeResult:
        """Compose the monitor dashboard layout."""
        yield Header()

        with TabbedContent():
            with TabPane("Live Status"):
                yield Static("Daemon Status: Connected", id="live_status")
                yield Static("Active Project: None", id="active_project")
                yield Static("Tracked Windows: 0", id="tracked_windows")
                yield Static("Uptime: 0s", id="uptime")

            with TabPane("Events"):
                yield Static("Event stream not yet implemented", id="event_stream")

            with TabPane("History"):
                yield Static("Event history not yet implemented", id="event_history")

            with TabPane("Tree"):
                yield Static("Window tree inspector not yet implemented", id="tree_inspector")

        yield Footer()

    async def on_mount(self) -> None:
        """Initialize the monitor dashboard."""
        await self._refresh_status()

    async def _refresh_status(self) -> None:
        """Refresh daemon status."""
        if hasattr(self.app, "daemon_client") and self.app.daemon_client:
            try:
                status = await self.app.daemon_client.get_status()

                self.query_one("#live_status", Static).update(
                    f"Daemon Status: {'Connected' if status.get('connected') else 'Disconnected'}"
                )
                self.query_one("#active_project", Static).update(
                    f"Active Project: {status.get('active_project', 'None')}"
                )
                self.query_one("#tracked_windows", Static).update(
                    f"Tracked Windows: {status.get('window_count', 0)}"
                )
                self.query_one("#uptime", Static).update(
                    f"Uptime: {status.get('uptime_seconds', 0):.0f}s"
                )
            except Exception as e:
                self.log.error(f"Failed to get daemon status: {e}")
                self.notify(f"Failed to get status: {e}", severity="error")
        else:
            self.notify("Daemon not connected", severity="warning")

    async def action_refresh(self) -> None:
        """Force refresh dashboard data."""
        await self._refresh_status()
        self.notify("Dashboard refreshed", severity="information")

    async def action_back(self) -> None:
        """Return to browser screen."""
        self.dismiss()
