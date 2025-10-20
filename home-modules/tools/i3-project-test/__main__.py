"""CLI entry point for i3 project test framework.

This module provides the command-line interface for running test scenarios,
listing available tests, and generating reports.
"""

import argparse
import asyncio
import logging
import sys
from pathlib import Path
from typing import List, Optional

from .reporters import CIReporter, JSONReporter, TerminalReporter
from .scenarios import ALL_SCENARIOS
from .test_runner import TestRunner, TestRunnerConfig


# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="i3 Project Test Framework - Test automation for i3 project management",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List all available test scenarios
  i3-project-test list

  # Run all test scenarios
  i3-project-test run --all

  # Run specific test scenario
  i3-project-test run project_lifecycle_001

  # Run multiple specific scenarios
  i3-project-test run project_lifecycle_001 window_management_001

  # Run with JSON output for CI/CD
  i3-project-test run --all --no-ui --format=json --output=results.json

  # Run with verbose logging
  i3-project-test run --all --verbose --show-logs
        """,
    )

    # Subcommands
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # List command
    list_parser = subparsers.add_parser("list", help="List available test scenarios")
    list_parser.add_argument(
        "--format",
        choices=["table", "json"],
        default="table",
        help="Output format",
    )

    # Run command
    run_parser = subparsers.add_parser("run", help="Run test scenarios")
    run_parser.add_argument(
        "scenarios",
        nargs="*",
        help="Scenario IDs to run (if not using --all)",
    )
    run_parser.add_argument(
        "--all",
        action="store_true",
        help="Run all registered scenarios",
    )
    run_parser.add_argument(
        "--parallel",
        action="store_true",
        help="Run scenarios in parallel",
    )
    run_parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Verbose output",
    )
    run_parser.add_argument(
        "--show-logs",
        action="store_true",
        help="Show test execution logs",
    )
    run_parser.add_argument(
        "--no-ui",
        action="store_true",
        help="Disable rich terminal UI (plain text)",
    )
    run_parser.add_argument(
        "--format",
        choices=["terminal", "json", "tap"],
        default="terminal",
        help="Output format",
    )
    run_parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Output file path (for json/tap formats)",
    )
    run_parser.add_argument(
        "--ci",
        action="store_true",
        help="CI mode: headless, JSON output, strict validation",
    )
    run_parser.add_argument(
        "--capture-on-failure",
        action="store_true",
        help="Capture diagnostic snapshot when test fails",
    )

    # Version
    parser.add_argument(
        "--version",
        action="version",
        version="i3-project-test v1.0.0",
    )

    return parser.parse_args()


def list_scenarios(args: argparse.Namespace) -> int:
    """List available test scenarios.

    Args:
        args: Parsed arguments

    Returns:
        Exit code
    """
    runner = TestRunner()

    # Register all scenarios
    runner.register_scenarios(ALL_SCENARIOS)

    scenarios = runner.list_scenarios()

    if args.format == "json":
        import json
        print(json.dumps(scenarios, indent=2))
    else:
        # Table format
        print(f"\nAvailable Test Scenarios ({len(scenarios)} total):\n")
        print(f"{'ID':<30} {'Priority':<10} {'Timeout':<10} {'Name'}")
        print("-" * 90)

        for scenario in scenarios:
            print(
                f"{scenario['id']:<30} "
                f"{scenario['priority']:<10} "
                f"{scenario['timeout']:<10} "
                f"{scenario['name']}"
            )

        print("")

    return 0


async def run_scenarios(args: argparse.Namespace) -> int:
    """Run test scenarios.

    Args:
        args: Parsed arguments

    Returns:
        Exit code (0 = success, non-zero = failure)
    """
    # Create test runner
    runner = TestRunner()

    # Register all scenarios
    runner.register_scenarios(ALL_SCENARIOS)

    # Determine which scenarios to run
    if args.all:
        scenario_ids = None  # Run all
    elif args.scenarios:
        scenario_ids = args.scenarios
    else:
        print("Error: Must specify scenario IDs or use --all")
        return 1

    # CI mode overrides
    if args.ci:
        args.no_ui = True
        args.format = "json"
        if not args.output:
            args.output = Path("test-results.json")

    # Create reporter
    if args.format == "terminal":
        reporter = TerminalReporter(
            verbose=args.verbose,
            show_logs=args.show_logs,
            no_ui=args.no_ui,
        )
    elif args.format == "json":
        reporter = JSONReporter(
            output_file=args.output,
            format_type="json",
        )
    elif args.format == "tap":
        reporter = JSONReporter(
            output_file=args.output,
            format_type="tap",
        )
    else:
        reporter = TerminalReporter()

    # Print header for terminal output
    if isinstance(reporter, TerminalReporter):
        reporter.print_header()

        # Print start message
        total = len(scenario_ids) if scenario_ids else len(ALL_SCENARIOS)
        reporter.print_start(total)

    # Run scenarios
    try:
        suite_result = await runner.run_scenarios(
            scenario_ids=scenario_ids,
            parallel=args.parallel,
        )

        # Print individual results for terminal output
        if isinstance(reporter, TerminalReporter):
            for result in suite_result.test_results:
                reporter.print_scenario_result(result)

        # Generate report
        if isinstance(reporter, JSONReporter):
            content = reporter.report_suite(suite_result)
            if not args.output:
                reporter.print_to_stdout(content)
        else:
            reporter.report_suite(suite_result)

        # CI mode exit code
        if args.ci:
            ci_reporter = CIReporter()
            ci_reporter.print_ci_summary(suite_result)
            return ci_reporter.get_exit_code(suite_result)

        # Regular exit code
        if suite_result.failed_tests > 0 or suite_result.error_tests > 0:
            return 1

        return 0

    except KeyboardInterrupt:
        print("\n\nTest execution interrupted by user")
        return 130  # Standard SIGINT exit code

    except Exception as e:
        logger.error(f"Test execution failed: {e}", exc_info=True)
        print(f"\nError: {e}")
        return 2


def main() -> int:
    """Main entry point.

    Returns:
        Exit code
    """
    args = parse_args()

    if not args.command:
        print("Error: No command specified. Use -h for help.")
        return 1

    if args.command == "list":
        return list_scenarios(args)

    elif args.command == "run":
        return asyncio.run(run_scenarios(args))

    else:
        print(f"Error: Unknown command '{args.command}'")
        return 1


if __name__ == "__main__":
    sys.exit(main())
