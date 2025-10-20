"""Terminal reporter for test results.

This module provides human-readable terminal output for test results
using the rich library for formatted display.
"""

import logging
from datetime import datetime
from typing import Optional

from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.table import Table
from rich.text import Text

from ..models import ResultStatus, TestResult, TestSuiteResult


logger = logging.getLogger(__name__)


class TerminalReporter:
    """Human-readable terminal reporter using rich library.

    Provides formatted, colorized output for test execution and results.

    Attributes:
        console: Rich console for output
        verbose: Whether to show verbose output
        show_logs: Whether to show test logs
    """

    def __init__(
        self,
        verbose: bool = False,
        show_logs: bool = False,
        no_ui: bool = False,
    ):
        """Initialize terminal reporter.

        Args:
            verbose: Show verbose output
            show_logs: Show test logs
            no_ui: Disable rich formatting (plain text)
        """
        self.console = Console(force_terminal=not no_ui, no_color=no_ui)
        self.verbose = verbose
        self.show_logs = show_logs
        self.no_ui = no_ui

    def print_header(self) -> None:
        """Print test runner header."""
        if self.no_ui:
            self.console.print("i3 Project Test Runner v1.0.0")
            self.console.print("=" * 60)
        else:
            title = Text("i3 Project Test Runner", style="bold cyan")
            version = Text("v1.0.0", style="dim")
            self.console.print(Panel(f"{title} {version}", border_style="cyan"))

    def print_start(self, total_scenarios: int) -> None:
        """Print test suite start message.

        Args:
            total_scenarios: Number of scenarios to run
        """
        msg = f"Running {total_scenarios} test scenario{'s' if total_scenarios != 1 else ''}..."
        if self.no_ui:
            self.console.print(msg)
        else:
            self.console.print(f"\n[bold]{msg}[/bold]\n")

    def print_scenario_start(self, scenario_name: str) -> None:
        """Print scenario start message.

        Args:
            scenario_name: Name of scenario starting
        """
        if self.verbose:
            self.console.print(f"  → {scenario_name}")

    def print_scenario_result(self, result: TestResult) -> None:
        """Print individual scenario result.

        Args:
            result: Test result to display
        """
        # Status symbol
        status_symbols = {
            ResultStatus.PASSED: "✓" if not self.no_ui else "[PASS]",
            ResultStatus.FAILED: "✗" if not self.no_ui else "[FAIL]",
            ResultStatus.SKIPPED: "⊘" if not self.no_ui else "[SKIP]",
            ResultStatus.ERROR: "⚠" if not self.no_ui else "[ERROR]",
        }

        # Status color
        status_colors = {
            ResultStatus.PASSED: "green",
            ResultStatus.FAILED: "red",
            ResultStatus.SKIPPED: "yellow",
            ResultStatus.ERROR: "magenta",
        }

        symbol = status_symbols[result.status]
        color = status_colors[result.status]

        # Format result line
        if self.no_ui:
            line = (
                f"{symbol} {result.scenario_name} "
                f"({result.duration_seconds:.1f}s) "
                f"[{result.passed_count}/{result.total_count}]"
            )
        else:
            line = (
                f"[{color}]{symbol}[/{color}] {result.scenario_name} "
                f"[dim]({result.duration_seconds:.1f}s)[/dim] "
                f"[{result.passed_count}/{result.total_count}]"
            )

        self.console.print(line)

        # Show error message if failed
        if result.status in [ResultStatus.FAILED, ResultStatus.ERROR] and result.error_message:
            indent = "    "
            if self.no_ui:
                self.console.print(f"{indent}Error: {result.error_message}")
            else:
                self.console.print(f"{indent}[red]Error:[/red] {result.error_message}")

        # Show failed assertions
        if result.status == ResultStatus.FAILED:
            failed_assertions = [a for a in result.assertion_results if a.status == ResultStatus.FAILED]
            if failed_assertions:
                for assertion in failed_assertions:
                    indent = "    "
                    msg = assertion.message or f"Expected {assertion.expected}, got {assertion.actual}"
                    if self.no_ui:
                        self.console.print(f"{indent}  - {msg}")
                    else:
                        self.console.print(f"{indent}  [dim]• {msg}[/dim]")

        # Show logs if requested
        if self.show_logs and result.logs:
            self.console.print(f"    Logs:")
            for log in result.logs:
                self.console.print(f"      {log}")

    def print_summary(self, suite_result: TestSuiteResult) -> None:
        """Print test suite summary.

        Args:
            suite_result: Suite result to summarize
        """
        self.console.print("")

        if self.no_ui:
            # Plain text summary
            self.console.print("=" * 60)
            self.console.print("Test Summary")
            self.console.print("-" * 60)
            self.console.print(f"Total:    {suite_result.total_tests}")
            self.console.print(f"Passed:   {suite_result.passed_tests}")
            self.console.print(f"Failed:   {suite_result.failed_tests}")
            self.console.print(f"Skipped:  {suite_result.skipped_tests}")
            self.console.print(f"Errors:   {suite_result.error_tests}")
            self.console.print(f"Duration: {suite_result.total_duration_seconds:.1f}s")
            self.console.print(f"Success Rate: {suite_result.success_rate:.1f}%")
            self.console.print("=" * 60)
        else:
            # Rich formatted summary
            table = Table(title="Test Summary", show_header=True, header_style="bold cyan")
            table.add_column("Metric", style="dim")
            table.add_column("Value", justify="right")

            table.add_row("Total Tests", str(suite_result.total_tests))
            table.add_row("Passed", f"[green]{suite_result.passed_tests}[/green]")

            if suite_result.failed_tests > 0:
                table.add_row("Failed", f"[red]{suite_result.failed_tests}[/red]")
            else:
                table.add_row("Failed", "0")

            if suite_result.skipped_tests > 0:
                table.add_row("Skipped", f"[yellow]{suite_result.skipped_tests}[/yellow]")

            if suite_result.error_tests > 0:
                table.add_row("Errors", f"[magenta]{suite_result.error_tests}[/magenta]")

            table.add_row("Duration", f"{suite_result.total_duration_seconds:.1f}s")

            # Success rate with color
            success_rate = suite_result.success_rate
            if success_rate == 100:
                rate_str = f"[green]{success_rate:.1f}%[/green]"
            elif success_rate >= 80:
                rate_str = f"[yellow]{success_rate:.1f}%[/yellow]"
            else:
                rate_str = f"[red]{success_rate:.1f}%[/red]"

            table.add_row("Success Rate", rate_str)

            self.console.print(table)

    def print_final_status(self, suite_result: TestSuiteResult) -> None:
        """Print final pass/fail status.

        Args:
            suite_result: Suite result
        """
        if suite_result.failed_tests == 0 and suite_result.error_tests == 0:
            if self.no_ui:
                self.console.print("\nAll tests PASSED")
            else:
                self.console.print("\n[bold green]✓ All tests PASSED[/bold green]")
        else:
            if self.no_ui:
                self.console.print("\nSome tests FAILED")
            else:
                self.console.print("\n[bold red]✗ Some tests FAILED[/bold red]")

    def report_suite(self, suite_result: TestSuiteResult) -> None:
        """Generate complete suite report.

        Args:
            suite_result: Suite result to report
        """
        self.print_summary(suite_result)
        self.print_final_status(suite_result)

    def create_progress(self) -> Optional[Progress]:
        """Create progress indicator for test execution.

        Returns:
            Progress instance or None if no_ui
        """
        if self.no_ui:
            return None

        return Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=self.console,
        )
