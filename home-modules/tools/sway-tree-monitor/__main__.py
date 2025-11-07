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
    print("ERROR: 'history' command not implemented yet (coming in Phase 4)")
    print("Use 'live' mode for now to see events in real-time")
    sys.exit(1)


def cmd_diff(args):
    """Inspect detailed diff (Phase 5)"""
    print("ERROR: 'diff' command not implemented yet (coming in Phase 5)")
    print("Use 'live' mode and press 'd' to drill down into events")
    sys.exit(1)


def cmd_stats(args):
    """Show performance statistics (Phase 6)"""
    print("ERROR: 'stats' command not implemented yet (coming in Phase 6)")
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
        help='Query historical events (Phase 4 - not implemented yet)'
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
        help='Show events since timestamp (ISO 8601 format)'
    )
    parser_history.set_defaults(func=cmd_history)

    # Diff command (Phase 5)
    parser_diff = subparsers.add_parser(
        'diff',
        help='Inspect detailed diff (Phase 5 - not implemented yet)'
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
        help='Performance statistics (Phase 6 - not implemented yet)'
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
