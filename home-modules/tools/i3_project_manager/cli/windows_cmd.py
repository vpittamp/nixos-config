"""
Windows command implementation for Feature 025 (T030-T033).

Provides multiple display modes for window state visualization:
- --tree: ASCII tree view
- --table: Sortable table view
- --live: Interactive TUI with real-time updates
- --json: JSON output
"""

import asyncio
from argparse import Namespace

from ..core.daemon_client import DaemonClient, DaemonError
from .formatters import format_window_tree, format_window_table, format_window_json


async def cmd_windows_new(args: Namespace) -> int:
    """Show window state with multiple display modes (Feature 025: T030-T033).

    Args:
        args: Parsed arguments with display mode flags (--tree, --table, --live, --json)

    Returns:
        0 on success, 1 on error
    """
    try:
        # Get display mode flags
        show_tree = getattr(args, 'tree', False)
        show_table = getattr(args, 'table', False)
        show_live = getattr(args, 'live', False)
        show_json = getattr(args, 'json', False)

        # Get daemon client
        daemon = DaemonClient()
        await daemon.connect()

        # Query window tree from daemon
        tree_data = await daemon.get_window_tree()

        await daemon.close()

        # Handle --json mode (T033)
        if show_json:
            format_window_json(tree_data)
            return 0

        # Handle --live mode (T032) - Launch TUI
        if show_live:
            from textual.app import App
            from ..visualization.tree_view import WindowTreeView
            from ..visualization.table_view import WindowTableView
            from textual.widgets import TabbedContent, TabPane

            class WindowMonitorApp(App):
                """Window state monitor TUI application."""

                TITLE = "i3pm Window State Monitor"
                BINDINGS = [
                    ("q", "quit", "Quit"),
                    ("tab", "next_tab", "Next Tab"),
                ]
                CSS = """
                Screen {
                    background: $background;
                }
                TabbedContent {
                    height: 100%;
                }
                """

                def compose(self):
                    with TabbedContent():
                        with TabPane("Tree View", id="tree-tab"):
                            yield WindowTreeView(auto_refresh=True)
                        with TabPane("Table View", id="table-tab"):
                            yield WindowTableView(auto_refresh=True)

                def action_quit(self):
                    """Quit the application."""
                    self.exit()

                def action_next_tab(self):
                    """Switch to next tab."""
                    tabbed = self.query_one(TabbedContent)
                    if tabbed.active_pane:
                        current_idx = list(tabbed.children).index(tabbed.active_pane)
                        next_idx = (current_idx + 1) % len(list(tabbed.children))
                        tabbed.active = list(tabbed.children)[next_idx].id

            app = WindowMonitorApp()
            app.run()
            return 0

        # Handle --table mode (T031)
        if show_table:
            format_window_table(tree_data)
            return 0

        # Handle --tree mode (T030) or default
        if show_tree or not (show_table or show_json or show_live):
            format_window_tree(tree_data)
            return 0

        return 0

    except DaemonError as e:
        print(f"Error querying window state: {e}")
        print("Is the daemon running? Check with: systemctl --user status i3-project-event-listener")
        return 1
    except Exception as e:
        print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1
