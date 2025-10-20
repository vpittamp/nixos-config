"""CLI entry point for i3 project monitor.

Provides command-line interface for monitoring i3 project system state.
"""

import argparse
import asyncio
import logging
import sys
from pathlib import Path
from typing import NoReturn

from .daemon_client import DaemonClient

# Display mode imports will be added as they're implemented
# from .displays.live import LiveDisplay
# from .displays.events import EventsDisplay
# from .displays.history import HistoryDisplay
# from .displays.tree import TreeDisplay


def setup_logging(verbose: bool) -> None:
    """Configure logging based on verbosity level.

    Args:
        verbose: Enable verbose (DEBUG) logging
    """
    level = logging.DEBUG if verbose else logging.WARNING
    logging.basicConfig(
        level=level,
        format="%(levelname)s [%(name)s] %(message)s",
    )


def create_parser() -> argparse.ArgumentParser:
    """Create argument parser for CLI.

    Returns:
        Configured ArgumentParser
    """
    parser = argparse.ArgumentParser(
        prog="i3-project-monitor",
        description="Terminal-based monitoring tool for i3 project management system",
        epilog="For more information, see: /etc/nixos/specs/017-now-lets-create/quickstart.md",
    )

    # Display mode selection
    parser.add_argument(
        "mode",
        nargs="?",
        default="live",
        choices=["live", "events", "history", "tree", "diagnose"],
        help="Display mode (default: live)",
    )

    # Common options
    parser.add_argument(
        "-s",
        "--socket",
        metavar="PATH",
        help="Daemon socket path (default: $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock)",
    )

    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose logging",
    )

    parser.add_argument(
        "--version",
        action="version",
        version="i3-project-monitor 0.1.0 (Feature 017)",
    )

    # Event stream options
    events_group = parser.add_argument_group("event stream options")
    events_group.add_argument(
        "-t",
        "--type",
        dest="event_type",
        metavar="TYPE",
        help="Filter events by type prefix (e.g., 'window', 'workspace')",
    )

    # History options
    history_group = parser.add_argument_group("history options")
    history_group.add_argument(
        "-l",
        "--limit",
        type=int,
        default=100,
        metavar="N",
        help="Number of events to display (default: 100)",
    )

    # Tree inspection options
    tree_group = parser.add_argument_group("tree inspection options")
    tree_group.add_argument(
        "-m",
        "--marks",
        metavar="MARK",
        help="Filter tree by marks (e.g., 'project:nixos')",
    )

    tree_group.add_argument(
        "--expand",
        action="store_true",
        help="Expand all nodes by default",
    )

    # Project filtering (for live and history modes)
    parser.add_argument(
        "-p",
        "--project",
        metavar="PROJECT",
        help="Filter by project name",
    )

    # Diagnose mode options
    diagnose_group = parser.add_argument_group("diagnose mode options")
    diagnose_group.add_argument(
        "-o",
        "--output",
        type=Path,
        metavar="FILE",
        help="Output file path for diagnostic snapshot (default: stdout)",
    )

    diagnose_group.add_argument(
        "--no-events",
        action="store_true",
        help="Exclude event buffer from snapshot",
    )

    diagnose_group.add_argument(
        "--no-tree",
        action="store_true",
        help="Exclude i3 tree dump from snapshot",
    )

    diagnose_group.add_argument(
        "--no-monitors",
        action="store_true",
        help="Exclude monitor client list from snapshot",
    )

    diagnose_group.add_argument(
        "--event-limit",
        type=int,
        default=500,
        metavar="N",
        help="Number of events to include in snapshot (default: 500)",
    )

    diagnose_group.add_argument(
        "--compare",
        type=Path,
        nargs=2,
        metavar=("FILE1", "FILE2"),
        help="Compare two diagnostic snapshots",
    )

    return parser


async def run_live_mode(client: DaemonClient, args: argparse.Namespace) -> int:
    """Run live display mode.

    Args:
        client: DaemonClient instance
        args: Parsed command-line arguments

    Returns:
        Exit code
    """
    from .displays.live import LiveDisplay

    display = LiveDisplay(client)
    await display.run()
    return 0


async def run_events_mode(client: DaemonClient, args: argparse.Namespace) -> int:
    """Run event stream display mode.

    Args:
        client: DaemonClient instance
        args: Parsed command-line arguments

    Returns:
        Exit code
    """
    from .displays.events import EventsDisplay

    display = EventsDisplay(client, event_filter=args.event_type)
    await display.run()
    return 0


async def run_history_mode(client: DaemonClient, args: argparse.Namespace) -> int:
    """Run event history display mode.

    Args:
        client: DaemonClient instance
        args: Parsed command-line arguments

    Returns:
        Exit code
    """
    from .displays.history import HistoryDisplay

    display = HistoryDisplay(client, limit=args.limit, event_filter=args.event_type)
    await display.run()
    return 0


async def run_tree_mode(client: DaemonClient, args: argparse.Namespace) -> int:
    """Run i3 tree inspection mode.

    Args:
        client: DaemonClient instance (unused - tree mode connects directly to i3)
        args: Parsed command-line arguments

    Returns:
        Exit code
    """
    from .displays.tree import TreeDisplay

    display = TreeDisplay(marks_filter=args.marks, expand=args.expand)
    await display.run()
    return 0


async def run_diagnose_mode(client: DaemonClient, args: argparse.Namespace) -> int:
    """Run diagnostic snapshot mode.

    Args:
        client: DaemonClient instance
        args: Parsed command-line arguments

    Returns:
        Exit code
    """
    from .displays.diagnose import DiagnoseDisplay, DiagnoseDiffDisplay

    # Handle comparison mode
    if args.compare:
        display = DiagnoseDiffDisplay(
            client,
            snapshot1_path=args.compare[0],
            snapshot2_path=args.compare[1],
            output_file=args.output,
        )
        await display.run()
        return 0

    # Handle snapshot capture mode
    display = DiagnoseDisplay(
        client,
        output_file=args.output,
        include_events=not args.no_events,
        event_limit=args.event_limit,
        include_tree=not args.no_tree,
        include_monitors=not args.no_monitors,
    )
    await display.run()
    return 0


async def async_main(args: argparse.Namespace) -> int:
    """Async main function.

    Args:
        args: Parsed command-line arguments

    Returns:
        Exit code
    """
    # Create daemon client
    client = DaemonClient(socket_path=args.socket)

    # Connect with retry
    try:
        await client.connect_with_retry()
    except ConnectionError as e:
        print(f"Error: Failed to connect to daemon: {e}", file=sys.stderr)
        print("\nTroubleshooting:", file=sys.stderr)
        print("  1. Check if daemon is running: systemctl --user status i3-project-event-listener", file=sys.stderr)
        print("  2. Check socket path exists: ls -la $XDG_RUNTIME_DIR/i3-project-daemon/", file=sys.stderr)
        print("  3. Try restarting daemon: systemctl --user restart i3-project-event-listener", file=sys.stderr)
        return 1

    try:
        # Dispatch to appropriate display mode
        if args.mode == "live":
            return await run_live_mode(client, args)
        elif args.mode == "events":
            return await run_events_mode(client, args)
        elif args.mode == "history":
            return await run_history_mode(client, args)
        elif args.mode == "tree":
            return await run_tree_mode(client, args)
        elif args.mode == "diagnose":
            return await run_diagnose_mode(client, args)
        else:
            print(f"Error: Unknown mode: {args.mode}", file=sys.stderr)
            return 1

    finally:
        # Cleanup
        await client.disconnect()


def main() -> NoReturn:
    """Main entry point.

    Exits with appropriate status code.
    """
    # Parse arguments
    parser = create_parser()
    args = parser.parse_args()

    # Setup logging
    setup_logging(args.verbose)

    # Run async main
    try:
        exit_code = asyncio.run(async_main(args))
        sys.exit(exit_code)

    except KeyboardInterrupt:
        print("\n\nInterrupted by user", file=sys.stderr)
        sys.exit(130)  # Standard exit code for SIGINT

    except Exception as e:
        print(f"Fatal error: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
