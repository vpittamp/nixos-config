#!/usr/bin/env python3
"""
Daemon startup validation for environment variable coverage.

This script is called during i3pm daemon initialization to validate that
all windows have I3PM_* environment variables. Logs coverage report summary.

Usage:
    python3 startup_validation.py
    python3 startup_validation.py --json

Exit codes:
    0 - Coverage validation passed (100%)
    1 - Coverage validation failed (<100%)
    2 - Error during validation
"""

import asyncio
import sys
import logging
from pathlib import Path

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

# Add daemon module to path
daemon_path = Path(__file__).parent
if str(daemon_path) not in sys.path:
    sys.path.insert(0, str(daemon_path))


async def validate_startup_coverage():
    """
    Validate environment variable coverage during daemon startup.

    Returns:
        int: Exit code (0 for success, 1 for failure, 2 for error)
    """
    try:
        from i3ipc.aio import Connection
        from window_environment import validate_environment_coverage

        # Connect to Sway IPC
        async with Connection() as i3:
            # Validate coverage
            report = await validate_environment_coverage(i3)

            # Log summary
            logger.info(
                f"Startup coverage validation: {report.coverage_percentage:.1f}% "
                f"({report.windows_with_env}/{report.total_windows} windows) - {report.status}"
            )

            # Warn if coverage < 100%
            if report.status != "PASS":
                logger.warning(
                    f"Found {report.windows_without_env} windows without I3PM_* variables"
                )

                # Log details of first few missing windows
                for i, missing in enumerate(report.missing_windows[:5]):
                    logger.warning(
                        f"  Missing [{i+1}]: {missing.window_class} "
                        f"(PID: {missing.pid}, reason: {missing.reason})"
                    )

                if len(report.missing_windows) > 5:
                    logger.warning(
                        f"  ... and {len(report.missing_windows) - 5} more"
                    )
            else:
                logger.info("✓ All windows have I3PM_* environment variables")

            # Return exit code based on status
            return 0 if report.status == "PASS" else 1

    except ImportError as e:
        logger.error(f"Failed to import required modules: {e}")
        logger.error("Ensure i3ipc-python and other dependencies are installed")
        return 2
    except Exception as e:
        logger.error(f"Error during coverage validation: {e}")
        return 2


def main():
    """Main entry point."""
    # Check for --json flag
    json_output = "--json" in sys.argv

    if json_output:
        # For JSON output, suppress INFO logs and output only JSON
        logging.getLogger().setLevel(logging.ERROR)

    # Run async validation
    exit_code = asyncio.run(validate_startup_coverage())
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
