"""CLI entry point for eBPF AI Agent Monitor.

This module provides the command-line interface for running the
eBPF-based AI agent process monitor as a daemon.

Usage:
    python -m ebpf_ai_monitor --user vpittamp
    python -m ebpf_ai_monitor --user vpittamp --threshold 2000 --log-level DEBUG
"""

import argparse
import sys
import logging

from . import __version__, configure_logging


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments.

    Args:
        argv: Command-line arguments. Defaults to sys.argv[1:].

    Returns:
        Parsed arguments namespace.
    """
    parser = argparse.ArgumentParser(
        prog="ebpf-ai-monitor",
        description="eBPF-based AI Agent Process Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --user vpittamp
      Monitor AI processes for user 'vpittamp'

  %(prog)s --user vpittamp --threshold 2000
      Set waiting threshold to 2 seconds

  %(prog)s --user vpittamp --processes claude codex aider
      Monitor custom list of process names

  %(prog)s --status
      Check if the monitor is running and healthy
""",
    )

    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )

    parser.add_argument(
        "--user",
        type=str,
        required=True,
        help="Username to monitor AI processes for (required)",
    )

    parser.add_argument(
        "--threshold",
        type=int,
        default=1000,
        metavar="MS",
        help="Milliseconds before considering process as waiting (default: 1000)",
    )

    parser.add_argument(
        "--processes",
        type=str,
        nargs="+",
        default=["claude", "codex"],
        metavar="NAME",
        help="Process names to monitor (default: claude codex)",
    )

    parser.add_argument(
        "--log-level",
        type=str,
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        default="INFO",
        help="Logging level (default: INFO)",
    )

    parser.add_argument(
        "--status",
        action="store_true",
        help="Check monitor status and exit",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate configuration without starting monitor",
    )

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Main entry point for the eBPF AI monitor daemon.

    Args:
        argv: Command-line arguments. Defaults to sys.argv[1:].

    Returns:
        Exit code (0 for success, non-zero for errors).
    """
    args = parse_args(argv)

    # Configure logging
    logger = configure_logging(args.log_level)

    logger.info(f"eBPF AI Monitor v{__version__}")
    logger.info(f"Monitoring user: {args.user}")
    logger.info(f"Target processes: {', '.join(args.processes)}")
    logger.info(f"Waiting threshold: {args.threshold}ms")

    if args.status:
        # TODO: Implement status check (T046)
        logger.info("Status check not yet implemented")
        return 0

    if args.dry_run:
        logger.info("Dry run - configuration is valid")
        return 0

    # Import and run daemon
    from .daemon import EBPFDaemon

    daemon = EBPFDaemon(
        user=args.user,
        threshold_ms=args.threshold,
        target_processes=set(args.processes),
    )
    return daemon.run()


if __name__ == "__main__":
    sys.exit(main())
