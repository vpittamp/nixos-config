"""JSON reporter for test results.

This module provides machine-readable JSON output for test results,
suitable for CI/CD integration and automated processing.
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

from ..models import ResultStatus, TestResult, TestSuiteResult


logger = logging.getLogger(__name__)


class JSONReporter:
    """Machine-readable JSON reporter.

    Provides JSON and TAP (Test Anything Protocol) output formats
    for automated processing and CI/CD integration.

    Attributes:
        output_file: Optional output file path
        format_type: Output format (json or tap)
    """

    def __init__(
        self,
        output_file: Path | None = None,
        format_type: str = "json",
    ):
        """Initialize JSON reporter.

        Args:
            output_file: Optional output file path
            format_type: Output format (json or tap)
        """
        self.output_file = output_file
        self.format_type = format_type

    def report_suite(self, suite_result: TestSuiteResult) -> str:
        """Generate suite report.

        Args:
            suite_result: Suite result to report

        Returns:
            Report content as string
        """
        if self.format_type == "tap":
            content = self._generate_tap(suite_result)
        else:
            content = self._generate_json(suite_result)

        # Write to file if specified
        if self.output_file:
            self._write_to_file(content)

        return content

    def _generate_json(self, suite_result: TestSuiteResult) -> str:
        """Generate JSON report.

        Args:
            suite_result: Suite result

        Returns:
            JSON string
        """
        report = {
            "schema_version": "1.0.0",
            "timestamp": datetime.now().isoformat(),
            "summary": {
                "total": suite_result.total_tests,
                "passed": suite_result.passed_tests,
                "failed": suite_result.failed_tests,
                "skipped": suite_result.skipped_tests,
                "errors": suite_result.error_tests,
                "success_rate": suite_result.success_rate,
                "duration_seconds": suite_result.total_duration_seconds,
            },
            "tests": [
                self._test_result_to_dict(result)
                for result in suite_result.test_results
            ],
            "metadata": suite_result.metadata,
        }

        return json.dumps(report, indent=2)

    def _generate_tap(self, suite_result: TestSuiteResult) -> str:
        """Generate TAP (Test Anything Protocol) report.

        Args:
            suite_result: Suite result

        Returns:
            TAP format string
        """
        lines = [
            "TAP version 13",
            f"1..{suite_result.total_tests}",
        ]

        for i, result in enumerate(suite_result.test_results, start=1):
            if result.status == ResultStatus.PASSED:
                lines.append(f"ok {i} - {result.scenario_name}")
            elif result.status == ResultStatus.SKIPPED:
                lines.append(f"ok {i} - {result.scenario_name} # SKIP")
            else:
                lines.append(f"not ok {i} - {result.scenario_name}")
                if result.error_message:
                    lines.append(f"  # {result.error_message}")

        # Add summary
        lines.append("")
        lines.append(f"# tests {suite_result.total_tests}")
        lines.append(f"# pass {suite_result.passed_tests}")
        lines.append(f"# fail {suite_result.failed_tests}")
        lines.append(f"# skip {suite_result.skipped_tests}")

        return "\n".join(lines)

    def _test_result_to_dict(self, result: TestResult) -> Dict[str, Any]:
        """Convert TestResult to dictionary.

        Args:
            result: Test result

        Returns:
            Dictionary representation
        """
        return {
            "scenario_id": result.scenario_id,
            "name": result.scenario_name,
            "status": result.status.value,
            "duration_seconds": result.duration_seconds,
            "start_time": result.start_time.isoformat(),
            "end_time": result.end_time.isoformat(),
            "assertions": {
                "total": result.total_count,
                "passed": result.passed_count,
                "failed": result.failed_count,
                "results": [
                    {
                        "id": a.assertion_id,
                        "type": a.assertion_type.value,
                        "status": a.status.value,
                        "expected": str(a.expected),
                        "actual": str(a.actual),
                        "message": a.message,
                    }
                    for a in result.assertion_results
                ],
            },
            "error": result.error_message,
            "logs": [
                {
                    "timestamp": log.timestamp.isoformat(),
                    "level": log.level,
                    "message": log.message,
                }
                for log in result.logs
            ] if result.logs else [],
            "artifacts": result.artifacts,
        }

    def _write_to_file(self, content: str) -> None:
        """Write report content to file.

        Args:
            content: Report content

        Raises:
            IOError: If unable to write file
        """
        try:
            # Ensure parent directory exists
            if self.output_file.parent:
                self.output_file.parent.mkdir(parents=True, exist_ok=True)

            # Write content
            with open(self.output_file, "w") as f:
                f.write(content)

            logger.info(f"Report written to {self.output_file}")

        except Exception as e:
            logger.error(f"Failed to write report to {self.output_file}: {e}")
            raise IOError(f"Failed to write report: {e}")

    def print_to_stdout(self, content: str) -> None:
        """Print report to stdout.

        Args:
            content: Report content
        """
        print(content)


class CIReporter(JSONReporter):
    """Specialized reporter for CI/CD environments.

    Extends JSONReporter with CI-specific features like exit code
    determination and concise output.
    """

    def __init__(self, output_file: Path | None = None):
        """Initialize CI reporter.

        Args:
            output_file: Optional output file path
        """
        super().__init__(output_file=output_file, format_type="json")

    def get_exit_code(self, suite_result: TestSuiteResult) -> int:
        """Determine exit code based on results.

        Args:
            suite_result: Suite result

        Returns:
            Exit code (0 = success, 1 = failures, 2 = errors)
        """
        if suite_result.error_tests > 0:
            return 2  # Error exit code

        if suite_result.failed_tests > 0:
            return 1  # Failure exit code

        return 0  # Success exit code

    def print_ci_summary(self, suite_result: TestSuiteResult) -> None:
        """Print concise CI-friendly summary.

        Args:
            suite_result: Suite result
        """
        # Print single line summary
        summary = (
            f"TESTS: {suite_result.total_tests} total, "
            f"{suite_result.passed_tests} passed, "
            f"{suite_result.failed_tests} failed, "
            f"{suite_result.skipped_tests} skipped, "
            f"{suite_result.error_tests} errors "
            f"({suite_result.total_duration_seconds:.1f}s)"
        )
        print(summary)

        # Print status
        exit_code = self.get_exit_code(suite_result)
        if exit_code == 0:
            print("STATUS: PASSED")
        elif exit_code == 1:
            print("STATUS: FAILED")
        else:
            print("STATUS: ERROR")
