"""CLI entry point for Sway Tree Monitor

Commands:
- live: Real-time event streaming (default)
- history: Query past events (Phase 4)
- diff: Inspect detailed diff (Phase 5)
- stats: Performance statistics (Phase 6)
- daemon: Run background daemon

Usage:
    python -m sway_tree_monitor live
    python -m sway_tree_monitor daemon
    sway-tree-monitor live  (if installed as script)
"""

import argparse
import asyncio
import sys
from pathlib import Path


def cmd_live(args):
    """Launch live streaming TUI"""
    from .ui.app import run_app

    socket_path = args.socket_path if args.socket_path else None
    run_app(socket_path=socket_path)


def cmd_daemon(args):
    """Run background daemon"""
    from .daemon import main

    # Run async main
    asyncio.run(main())


def cmd_history(args):
    """Query historical events (Phase 4)"""
    from .ui.app import SwayTreeMonitorApp
    from .ui.history_view import HistoryView
    from .rpc.client import RPCClient
    import time

    # Parse time filters
    since_ms = None
    until_ms = None

    if args.since:
        # Parse relative time (e.g., "5m", "1h", "30s")
        since_ms = _parse_relative_time(args.since)

    # Connect to daemon
    socket_path = Path(args.socket_path) if args.socket_path else None
    rpc_client = RPCClient(socket_path=socket_path)

    try:
        # Test connection
        ping_response = rpc_client.ping()
        if not ping_response:
            print("ERROR: Cannot connect to daemon. Is it running?")
            print("Start with: systemctl --user start sway-tree-monitor")
            sys.exit(1)

        # Create Textual app with history view
        from textual.app import App, ComposeResult
        from textual.widgets import Header, Footer

        class HistoryApp(App):
            """Standalone history query app"""

            BINDINGS = [
                ("q", "quit", "Quit"),
                ("r", "refresh", "Refresh"),
            ]

            CSS = """
            #filter-bar {
                height: 3;
                padding: 1;
                background: $surface;
            }
            #status-line {
                height: 1;
                background: $surface;
                padding: 0 1;
            }
            #event-table {
                height: 1fr;
            }
            #legend {
                height: 3;
                background: $surface;
                padding: 1;
            }
            .label {
                width: 8;
            }
            """

            def __init__(self, rpc_client, since_ms, until_ms, last, event_filter):
                super().__init__()
                self.rpc_client = rpc_client
                self.since_ms = since_ms
                self.until_ms = until_ms
                self.last = last
                self.event_filter = event_filter

            def compose(self) -> ComposeResult:
                yield Header()
                yield HistoryView(
                    self.rpc_client,
                    since_ms=self.since_ms,
                    until_ms=self.until_ms,
                    last=self.last,
                    event_filter=self.event_filter
                )
                yield Footer()

            def action_refresh(self):
                """Refresh history view"""
                history_view = self.query_one(HistoryView)
                asyncio.create_task(history_view._load_events())

        # Run app
        app = HistoryApp(
            rpc_client=rpc_client,
            since_ms=since_ms,
            until_ms=until_ms,
            last=args.last,
            event_filter=args.filter
        )
        app.run()

    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)


def _parse_relative_time(relative_str: str) -> int:
    """
    Parse relative time string to timestamp.

    Examples:
    - "5m" = 5 minutes ago
    - "1h" = 1 hour ago
    - "30s" = 30 seconds ago

    Returns:
        Timestamp in milliseconds
    """
    import time
    import re

    match = re.match(r'(\d+)([smhd])', relative_str)
    if not match:
        raise ValueError(f"Invalid time format: {relative_str}. Use format like '5m', '1h', '30s'")

    value = int(match.group(1))
    unit = match.group(2)

    seconds_map = {
        's': 1,
        'm': 60,
        'h': 3600,
        'd': 86400
    }

    seconds_ago = value * seconds_map[unit]
    timestamp_ms = int((time.time() - seconds_ago) * 1000)

    return timestamp_ms


def cmd_diff(args):
    """Inspect detailed diff (Phase 5)"""
    from .ui.diff_view import DiffView
    from .rpc.client import RPCClient

    # Connect to daemon
    socket_path = Path(args.socket_path) if args.socket_path else None
    rpc_client = RPCClient(socket_path=socket_path)

    try:
        # Test connection
        ping_response = rpc_client.ping()
        if not ping_response:
            print("ERROR: Cannot connect to daemon. Is it running?")
            print("Start with: systemctl --user start sway-tree-monitor")
            sys.exit(1)

        # Create Textual app with diff view
        from textual.app import App, ComposeResult
        from textual.widgets import Header, Footer

        class DiffApp(App):
            """Standalone diff inspection app"""

            BINDINGS = [
                ("q", "quit", "Quit"),
                ("escape", "back", "Back"),
            ]

            CSS = """
            #diff-header {
                height: 3;
                background: $surface;
                padding: 1;
            }
            #diff-title {
                width: 1fr;
            }
            #diff-status {
                height: 1;
                background: $surface;
                padding: 0 1;
            }
            #diff-content {
                height: 1fr;
            }
            """

            def __init__(self, rpc_client: RPCClient, event_id: int):
                super().__init__()
                self.rpc_client = rpc_client
                self.event_id = event_id

            def compose(self) -> ComposeResult:
                yield Header()
                yield DiffView(self.rpc_client, self.event_id)
                yield Footer()

            def action_back(self) -> None:
                """Exit app"""
                self.exit()

        app = DiffApp(rpc_client=rpc_client, event_id=args.event_id)
        app.run()

    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


def cmd_stats(args):
    """Show performance statistics (Phase 6)"""
    from .ui.stats_view import StatsView
    from .rpc.client import RPCClient
    import time

    # Parse time filter
    since_ms = None
    if args.since:
        # Parse relative time (e.g., "5m", "1h", "30s")
        since_ms = _parse_relative_time(args.since)

    # Connect to daemon
    socket_path = Path(args.socket_path) if args.socket_path else None
    rpc_client = RPCClient(socket_path=socket_path)

    try:
        # Test connection
        ping_response = rpc_client.ping()
        if not ping_response:
            print("ERROR: Cannot connect to daemon. Is it running?")
            print("Start with: systemctl --user start sway-tree-monitor")
            sys.exit(1)

        # Create Textual app with stats view
        from textual.app import App, ComposeResult
        from textual.widgets import Header, Footer

        class StatsApp(App):
            """Standalone stats display app"""

            BINDINGS = [
                ("q", "quit", "Quit"),
                ("r", "refresh", "Refresh"),
            ]

            CSS = """
            #stats-header {
                height: 3;
                background: $surface;
                padding: 1;
            }
            #stats-title {
                width: 1fr;
            }
            #stats-status {
                height: 1;
                background: $surface;
                padding: 0 1;
            }
            #stats-panels {
                height: 1fr;
                overflow-y: auto;
            }
            """

            def __init__(self, rpc_client: RPCClient, since_ms: Optional[int] = None):
                super().__init__()
                self.rpc_client = rpc_client
                self.since_ms = since_ms

            def compose(self) -> ComposeResult:
                yield Header()
                yield StatsView(self.rpc_client, self.since_ms)
                yield Footer()

            def action_refresh(self) -> None:
                """Refresh stats"""
                stats_view = self.query_one(StatsView)
                self.call_later(stats_view._load_stats)

        app = StatsApp(rpc_client=rpc_client, since_ms=since_ms)
        app.run()

    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        prog="sway-tree-monitor",
        description="Sway Tree Diff Monitor - Real-time window state change monitoring",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Launch live streaming view
  sway-tree-monitor live

  # Run daemon in foreground (for debugging)
  sway-tree-monitor daemon

  # Or use systemd service (recommended)
  systemctl --user start sway-tree-monitor

For more information, see:
  /etc/nixos/specs/064-sway-tree-diff-monitor/quickstart.md
        """
    )

    parser.add_argument(
        '--socket-path',
        type=str,
        default=None,
        help='Path to daemon Unix socket (default: $XDG_RUNTIME_DIR/sway-tree-monitor.sock)'
    )

    subparsers = parser.add_subparsers(dest='command', help='Command to run')

    # Live command (default)
    parser_live = subparsers.add_parser(
        'live',
        help='Real-time event streaming (TUI)'
    )
    parser_live.set_defaults(func=cmd_live)

    # Daemon command
    parser_daemon = subparsers.add_parser(
        'daemon',
        help='Run background daemon'
    )
    parser_daemon.set_defaults(func=cmd_daemon)

    # History command (Phase 4)
    parser_history = subparsers.add_parser(
        'history',
        help='Query historical events with correlation'
    )
    parser_history.add_argument(
        '--last',
        type=int,
        default=50,
        help='Show last N events (default: 50)'
    )
    parser_history.add_argument(
        '--since',
        type=str,
        help='Show events since relative time (e.g., "5m", "1h", "30s")'
    )
    parser_history.add_argument(
        '--filter',
        type=str,
        help='Filter by event type pattern (e.g., "window::new")'
    )
    parser_history.set_defaults(func=cmd_history)

    # Diff command (Phase 5)
    parser_diff = subparsers.add_parser(
        'diff',
        help='Inspect detailed diff with enriched context'
    )
    parser_diff.add_argument(
        'event_id',
        type=int,
        help='Event ID to inspect'
    )
    parser_diff.set_defaults(func=cmd_diff)

    # Stats command (Phase 6)
    parser_stats = subparsers.add_parser(
        'stats',
        help='Performance statistics and daemon health metrics'
    )
    parser_stats.add_argument(
        '--since',
        type=str,
        help='Analyze events since relative time (e.g., "5m", "1h", "30s")'
    )
    parser_stats.set_defaults(func=cmd_stats)

    # Parse arguments
    args = parser.parse_args()

    # Default to 'live' if no command specified
    if not args.command:
        args.command = 'live'
        args.func = cmd_live

    # Execute command
    try:
        args.func(args)
    except KeyboardInterrupt:
        print("\nInterrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
