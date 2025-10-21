"""Monitor dashboard screen for i3pm TUI.

Displays daemon status, events, and system information.
Migrates functionality from i3-project-monitor tool.
"""

from datetime import datetime
from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, Static, TabbedContent, TabPane, DataTable
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
                events_table = DataTable(id="events_table")
                events_table.cursor_type = "row"
                events_table.zebra_stripes = True
                yield events_table

            with TabPane("History"):
                history_table = DataTable(id="history_table")
                history_table.cursor_type = "row"
                history_table.zebra_stripes = True
                yield history_table

            with TabPane("Tree"):
                yield Static("Window tree inspector not yet implemented", id="tree_inspector")

        yield Footer()

    async def on_mount(self) -> None:
        """Initialize the monitor dashboard."""
        await self._refresh_status()
        await self._refresh_events()
        await self._refresh_history()

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

    async def _refresh_events(self) -> None:
        """Refresh recent events table."""
        if not hasattr(self.app, "daemon_client") or not self.app.daemon_client:
            return

        try:
            response = await self.app.daemon_client.get_events(limit=20)
            events = response.get("events", [])

            table = self.query_one("#events_table", DataTable)
            table.clear(columns=True)

            # Add columns
            table.add_column("ID", width=6)
            table.add_column("Type", width=15)
            table.add_column("Time", width=12)
            table.add_column("Window", width=20)
            table.add_column("Project", width=12)
            table.add_column("Duration", width=10)

            # Add rows
            for event in reversed(events):  # Show newest first
                event_id = str(event.get("event_id", ""))
                event_type = event.get("event_type", "")
                timestamp = event.get("timestamp", "")

                # Format timestamp
                try:
                    dt = datetime.fromisoformat(timestamp)
                    time_str = dt.strftime("%H:%M:%S")
                except:
                    time_str = timestamp[:12] if timestamp else ""

                window_class = event.get("window_class", "")
                project = event.get("project_name") or "-"
                duration = f"{event.get('processing_duration_ms', 0):.2f}ms"

                table.add_row(event_id, event_type, time_str, window_class, project, duration)

        except Exception as e:
            self.log.error(f"Failed to refresh events: {e}")

    async def _refresh_history(self) -> None:
        """Refresh event history table."""
        if not hasattr(self.app, "daemon_client") or not self.app.daemon_client:
            return

        try:
            response = await self.app.daemon_client.get_events(limit=100)
            events = response.get("events", [])
            stats = response.get("stats", {})

            table = self.query_one("#history_table", DataTable)
            table.clear(columns=True)

            # Add columns
            table.add_column("ID", width=6)
            table.add_column("Type", width=15)
            table.add_column("Timestamp", width=20)
            table.add_column("Window", width=20)
            table.add_column("Project", width=12)

            # Add rows (newest first)
            for event in reversed(events):
                event_id = str(event.get("event_id", ""))
                event_type = event.get("event_type", "")
                timestamp = event.get("timestamp", "")

                # Format timestamp
                try:
                    dt = datetime.fromisoformat(timestamp)
                    time_str = dt.strftime("%Y-%m-%d %H:%M:%S")
                except:
                    time_str = timestamp[:19] if timestamp else ""

                window_class = event.get("window_class", "")
                project = event.get("project_name") or "-"

                table.add_row(event_id, event_type, time_str, window_class, project)

        except Exception as e:
            self.log.error(f"Failed to refresh history: {e}")

    async def action_refresh(self) -> None:
        """Force refresh dashboard data."""
        await self._refresh_status()
        await self._refresh_events()
        await self._refresh_history()
        self.notify("Dashboard refreshed", severity="information")

    async def action_back(self) -> None:
        """Return to browser screen."""
        self.dismiss()
