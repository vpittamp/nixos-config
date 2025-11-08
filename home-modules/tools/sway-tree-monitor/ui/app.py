"""Main Textual application for Sway Tree Monitor

Entry point for TUI with multiple views:
- Live: Real-time event streaming
- History: Query past events (Phase 4)
- Diff: Detailed diff inspection (Phase 5)
- Stats: Performance statistics (Phase 6)
"""

from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, TabbedContent, TabPane
from textual.binding import Binding

from ..rpc.client import RPCClient, RPCError
from .live_view import LiveEventView


class SwayTreeMonitorApp(App):
    """Sway Tree Monitor TUI application

    Keyboard shortcuts:
    - q: Quit
    - f: Filter events
    - d: Drill down into event
    - Tab: Switch between views
    """

    CSS = """
    Screen {
        background: $surface;
    }

    Header {
        background: $primary;
        color: $text;
    }

    Footer {
        background: $panel;
    }

    DataTable {
        height: 100%;
    }

    DataTable > .datatable--cursor {
        background: $accent;
        color: $text;
    }

    DataTable > .datatable--header {
        background: $primary;
        color: $text;
        text-style: bold;
    }

    TabbedContent {
        height: 100%;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit", priority=True),
        Binding("f", "filter", "Filter"),
        Binding("d", "drill_down", "Drill Down"),
        ("ctrl+c", "quit", "Quit"),
    ]

    TITLE = "Sway Tree Monitor"
    SUB_TITLE = "Real-time window state change monitoring"

    def __init__(self, socket_path: str = None):
        super().__init__()
        self.rpc_client = RPCClient(socket_path=socket_path)

        # Check daemon connectivity on startup
        try:
            status = self.rpc_client.ping()
            self.daemon_connected = True
        except (RPCError, ConnectionError):
            self.daemon_connected = False

    def compose(self) -> ComposeResult:
        """Create child widgets"""
        yield Header()

        # Main content with tabs
        with TabbedContent():
            with TabPane("Live", id="tab_live"):
                if self.daemon_connected:
                    yield LiveEventView(self.rpc_client)
                else:
                    # Show error message if daemon not running
                    from textual.widgets import Static
                    yield Static(
                        "[red]ERROR: Cannot connect to daemon[/red]\n\n"
                        "Make sure the daemon is running:\n"
                        "  systemctl --user start sway-tree-monitor\n\n"
                        "Or start manually:\n"
                        "  python -m sway_tree_monitor.daemon",
                        id="error_message"
                    )

            # History tab
            with TabPane("History", id="tab_history"):
                if self.daemon_connected:
                    from .history_view import HistoryView
                    yield HistoryView(
                        rpc_client=self.rpc_client,
                        last=100  # Show last 100 events by default
                    )
                else:
                    from textual.widgets import Static
                    yield Static(
                        "[red]ERROR: Cannot connect to daemon[/red]",
                        id="error_history"
                    )

            with TabPane("Stats", id="tab_stats"):
                from textual.widgets import Static
                yield Static(
                    "[dim]Statistics view coming in Phase 6 (User Story 4)[/dim]",
                    id="placeholder_stats"
                )

        yield Footer()

    def action_quit(self) -> None:
        """Quit the application"""
        self.exit()

    def action_filter(self) -> None:
        """Open filter dialog"""
        # Forward to active view
        active_pane = self.query_one(TabbedContent).active
        if active_pane == "tab_live":
            live_view = self.query_one(LiveEventView)
            live_view.action_filter()

    def action_drill_down(self) -> None:
        """Drill down into selected event"""
        # Forward to active view
        active_pane = self.query_one(TabbedContent).active
        if active_pane == "tab_live":
            live_view = self.query_one(LiveEventView)
            live_view.action_drill_down()
        elif active_pane == "tab_history":
            try:
                from .history_view import HistoryView
                history_view = self.query_one(HistoryView)
                history_view.action_drill_down()
            except Exception:
                # History view not initialized yet
                self.notify("History view not available", severity="warning")

    def on_mount(self) -> None:
        """Show connection status on mount"""
        if not self.daemon_connected:
            self.notify(
                "Daemon not running. Start with: systemctl --user start sway-tree-monitor",
                severity="error",
                timeout=10
            )
        else:
            self.notify("Connected to daemon", severity="information", timeout=2)


def run_app(socket_path: str = None) -> None:
    """Run the Textual application

    Args:
        socket_path: Optional path to daemon Unix socket
    """
    app = SwayTreeMonitorApp(socket_path=socket_path)
    app.run()
