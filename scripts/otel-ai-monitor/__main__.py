#!/usr/bin/env python3
"""CLI entry point for OpenTelemetry AI Assistant Monitor.

This module provides the command-line interface for starting the OTLP receiver
and session tracking service. It handles argument parsing for configuration
options like port, timeout settings, and output mode.

Usage:
    python -m otel_ai_monitor [OPTIONS]
    otel-ai-monitor [OPTIONS]

Options:
    --port PORT             OTLP HTTP receiver port (default: 4318)
    --quiet-period SECONDS  Quiet period for completion detection (default: 3)
    --session-timeout SECS  Session expiry timeout (default: 300)
    --no-notifications      Disable desktop notifications
    --pipe PATH             Write JSON to named pipe instead of stdout
    --verbose               Enable verbose logging
"""

import argparse
import asyncio
import logging
import os
import signal
import sys
from pathlib import Path

from . import __version__


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        prog="otel-ai-monitor",
        description="OpenTelemetry AI Assistant Monitor - Track Claude Code and Codex CLI sessions",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Start with default settings
    otel-ai-monitor

    # Custom port and quiet period
    otel-ai-monitor --port 4319 --quiet-period 5

    # Output to named pipe for EWW consumption
    otel-ai-monitor --pipe $XDG_RUNTIME_DIR/otel-ai-monitor.pipe

Environment Variables:
    OTLP_PORT               Override default port (4318)
    OTEL_AI_QUIET_PERIOD    Override quiet period (3 seconds)
    OTEL_AI_SESSION_TIMEOUT Override session timeout (300 seconds)
""",
    )

    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )

    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("OTLP_PORT", "4318")),
        help="OTLP HTTP receiver port (default: 4318, env: OTLP_PORT)",
    )

    parser.add_argument(
        "--quiet-period",
        type=float,
        default=float(os.environ.get("OTEL_AI_QUIET_PERIOD", "3")),
        help="Seconds of quiet before marking session completed (default: 3)",
    )

    parser.add_argument(
        "--session-timeout",
        type=float,
        default=float(os.environ.get("OTEL_AI_SESSION_TIMEOUT", "300")),
        help="Seconds before expiring inactive sessions (default: 300)",
    )

    parser.add_argument(
        "--completed-timeout",
        type=float,
        default=float(os.environ.get("OTEL_AI_COMPLETED_TIMEOUT", "30")),
        help="Seconds before auto-transitioning completed to idle (default: 30)",
    )

    parser.add_argument(
        "--no-notifications",
        action="store_true",
        help="Disable desktop notifications on completion",
    )

    parser.add_argument(
        "--pipe",
        type=Path,
        default=None,
        help="Write JSON stream to named pipe (default: stdout)",
    )

    parser.add_argument(
        "--broadcast-interval",
        type=float,
        default=float(os.environ.get("OTEL_AI_BROADCAST_INTERVAL", "5")),
        help="Seconds between SessionList broadcasts (default: 5)",
    )

    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose logging",
    )

    return parser.parse_args()


def setup_logging(verbose: bool) -> None:
    """Configure logging based on verbosity level."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stderr,  # Log to stderr, JSON output goes to stdout
    )


async def main_async(args: argparse.Namespace) -> int:
    """Async main entry point."""
    # Import here to avoid circular imports and speed up --help
    from .output import OutputWriter
    from .process_monitor import ProcessMonitor
    from .receiver import OTLPReceiver
    from .session_tracker import SessionTracker

    logger = logging.getLogger("otel-ai-monitor")
    logger.info(f"Starting OpenTelemetry AI Monitor v{__version__}")
    logger.info(f"OTLP receiver on port {args.port}")

    # Create output writer
    output = OutputWriter(pipe_path=args.pipe)

    # Create session tracker with output writer
    tracker = SessionTracker(
        output=output,
        quiet_period_sec=args.quiet_period,
        session_timeout_sec=args.session_timeout,
        completed_timeout_sec=args.completed_timeout,
        enable_notifications=not args.no_notifications,
        broadcast_interval_sec=args.broadcast_interval,
    )

    # Create OTLP receiver with session tracker
    receiver = OTLPReceiver(
        port=args.port,
        tracker=tracker,
    )

    # Create process monitor for fallback detection (Codex batches telemetry)
    process_monitor = ProcessMonitor(
        tracker=tracker,
        poll_interval_sec=2.0,
    )

    # Setup signal handlers for graceful shutdown
    loop = asyncio.get_event_loop()
    shutdown_event = asyncio.Event()

    def handle_signal(signum: int) -> None:
        logger.info(f"Received signal {signum}, shutting down...")
        shutdown_event.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda s=sig: handle_signal(s))

    try:
        # Start the output writer (creates pipe if needed)
        await output.start()

        # Start the session tracker (background tasks)
        await tracker.start()

        # Start the OTLP receiver
        await receiver.start()

        # Start the process monitor (fallback for batched telemetry)
        await process_monitor.start()

        logger.info("Service started successfully")

        # Wait for shutdown signal
        await shutdown_event.wait()

    except Exception as e:
        logger.error(f"Service error: {e}")
        return 1

    finally:
        # Graceful shutdown
        logger.info("Shutting down...")
        await process_monitor.stop()
        await receiver.stop()
        await tracker.stop()
        await output.stop()

    return 0


def main() -> None:
    """Main entry point."""
    args = parse_args()
    setup_logging(args.verbose)

    try:
        exit_code = asyncio.run(main_async(args))
        sys.exit(exit_code)
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
