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
        Binding("right,l", "next_tab", "Next Tab", show=False),
        Binding("left,h", "previous_tab", "Prev Tab", show=False),
        Binding("1", "tab_1", "Live", show=False),
        Binding("2", "tab_2", "Events", show=False),
        Binding("3", "tab_3", "History", show=False),
        Binding("4", "tab_4", "Tree", show=False),
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
                tree_table = DataTable(id="tree_table")
                tree_table.cursor_type = "row"
                tree_table.zebra_stripes = True
                yield tree_table

        yield Footer()

    async def on_mount(self) -> None:
        """Initialize the monitor dashboard."""
        await self._refresh_status()
        await self._refresh_events()
        await self._refresh_history()
        await self._refresh_tree()

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

    async def _refresh_tree(self) -> None:
        """Refresh i3 window tree table."""
        try:
            # Import i3 client here to avoid circular imports
            from i3_project_manager.core.i3_client import I3Client

            async with I3Client() as i3:
                tree = await i3.get_tree()
                workspaces = await i3.get_workspaces()

                table = self.query_one("#tree_table", DataTable)
                table.clear(columns=True)

                # Add columns
                table.add_column("Type", width=12)
                table.add_column("Name", width=30)
                table.add_column("Class", width=20)
                table.add_column("Workspace", width=15)
                table.add_column("Marks", width=25)

                # Helper to recursively extract windows from tree
                def extract_windows(node, workspace_name=""):
                    rows = []
                    # If this node has a window, add it
                    if hasattr(node, 'window') and node.window:
                        window_class = getattr(node, 'window_class', None) or ""
                        marks = ", ".join(node.marks) if node.marks else ""
                        rows.append((
                            "window",
                            node.name or "",
                            window_class,
                            workspace_name,
                            marks
                        ))

                    # Recurse into children
                    for child in (node.nodes + node.floating_nodes):
                        # Update workspace name if we're entering a workspace
                        child_ws = workspace_name
                        if hasattr(node, 'type') and node.type == 'workspace':
                            child_ws = node.name
                        rows.extend(extract_windows(child, child_ws))

                    return rows

                # Extract all windows
                windows = extract_windows(tree)

                # Add rows to table
                for window_type, name, wclass, workspace, marks in windows:
                    table.add_row(window_type, name[:30], wclass[:20], workspace, marks[:25])

                if not windows:
                    table.add_row("No windows", "", "", "", "")

        except Exception as e:
            self.log.error(f"Failed to refresh tree: {e}")
            # Show error in table
            try:
                table = self.query_one("#tree_table", DataTable)
                table.clear(columns=True)
                table.add_column("Error", width=80)
                table.add_row(f"Failed to load tree: {e}")
            except:
                pass

    async def action_refresh(self) -> None:
        """Force refresh dashboard data."""
        await self._refresh_status()
        await self._refresh_events()
        await self._refresh_history()
        await self._refresh_tree()
        self.notify("Dashboard refreshed", severity="information")

    def action_next_tab(self) -> None:
        """Switch to next tab."""
        tabs = self.query_one(TabbedContent)
        tabs.action_next_tab()

    def action_previous_tab(self) -> None:
        """Switch to previous tab."""
        tabs = self.query_one(TabbedContent)
        tabs.action_previous_tab()

    def action_tab_1(self) -> None:
        """Switch to Live Status tab."""
        tabs = self.query_one(TabbedContent)
        tabs.active = "tab-1"

    def action_tab_2(self) -> None:
        """Switch to Events tab."""
        tabs = self.query_one(TabbedContent)
        tabs.active = "tab-2"

    def action_tab_3(self) -> None:
        """Switch to History tab."""
        tabs = self.query_one(TabbedContent)
        tabs.active = "tab-3"

    def action_tab_4(self) -> None:
        """Switch to Tree tab."""
        tabs = self.query_one(TabbedContent)
        tabs.active = "tab-4"

    async def action_back(self) -> None:
        """Return to browser screen."""
        self.dismiss()
