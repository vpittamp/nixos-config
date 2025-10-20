"""Data models for i3 project test framework.

This module defines the core data structures used for test execution,
results, and reporting.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional


class ResultStatus(str, Enum):
    """Test result status enumeration."""
    PASSED = "passed"
    FAILED = "failed"
    SKIPPED = "skipped"
    ERROR = "error"


class AssertionType(str, Enum):
    """Assertion type enumeration."""
    # Daemon state assertions
    DAEMON_ACTIVE_PROJECT_EQUALS = "daemon_active_project_equals"
    DAEMON_WINDOW_COUNT_EQUALS = "daemon_window_count_equals"
    DAEMON_PROJECT_EXISTS = "daemon_project_exists"
    DAEMON_WINDOW_MARKED = "daemon_window_marked"

    # i3 IPC assertions
    I3_WORKSPACE_VISIBLE = "i3_workspace_visible"
    I3_WORKSPACE_ON_OUTPUT = "i3_workspace_on_output"
    I3_OUTPUT_ACTIVE = "i3_output_active"
    I3_OUTPUT_EXISTS = "i3_output_exists"
    I3_WINDOW_EXISTS = "i3_window_exists"
    I3_MARK_EXISTS = "i3_mark_exists"

    # Event buffer assertions
    EVENT_BUFFER_CONTAINS = "event_buffer_contains"
    EVENT_BUFFER_COUNT_EQUALS = "event_buffer_count_equals"
    EVENT_ORDER_CORRECT = "event_order_correct"

    # Cross-validation assertions
    DAEMON_I3_STATE_MATCH = "daemon_i3_state_match"
    WORKSPACE_ASSIGNMENT_VALID = "workspace_assignment_valid"


@dataclass
class AssertionResult:
    """Result of a single assertion."""
    assertion_id: str
    assertion_type: AssertionType
    status: ResultStatus
    expected: Any
    actual: Any
    message: Optional[str] = None
    timestamp: datetime = field(default_factory=datetime.now)

    def __str__(self) -> str:
        """Human-readable string representation."""
        status_symbol = "✓" if self.status == ResultStatus.PASSED else "✗"
        msg = f"{status_symbol} {self.assertion_type.value}"
        if self.message:
            msg += f": {self.message}"
        return msg


@dataclass
class LogEntry:
    """Test execution log entry."""
    timestamp: datetime
    level: str
    message: str
    context: Optional[Dict[str, Any]] = None

    def __str__(self) -> str:
        """Human-readable string representation."""
        time_str = self.timestamp.strftime("%H:%M:%S.%f")[:-3]
        return f"[{time_str}] {self.level}: {self.message}"


@dataclass
class TestResult:
    """Result of test scenario execution."""
    scenario_id: str
    scenario_name: str
    status: ResultStatus
    start_time: datetime
    end_time: datetime
    duration_seconds: float
    assertion_results: List[AssertionResult] = field(default_factory=list)
    error_message: Optional[str] = None
    logs: List[LogEntry] = field(default_factory=list)
    artifacts: Dict[str, str] = field(default_factory=dict)

    def __post_init__(self):
        """Validate test result data."""
        if self.end_time < self.start_time:
            raise ValueError("end_time must be >= start_time")

        expected_duration = (self.end_time - self.start_time).total_seconds()
        if abs(self.duration_seconds - expected_duration) > 0.1:
            # Allow small floating point differences
            self.duration_seconds = expected_duration

    @property
    def passed_count(self) -> int:
        """Count of passed assertions."""
        return sum(1 for r in self.assertion_results if r.status == ResultStatus.PASSED)

    @property
    def failed_count(self) -> int:
        """Count of failed assertions."""
        return sum(1 for r in self.assertion_results if r.status == ResultStatus.FAILED)

    @property
    def total_count(self) -> int:
        """Total assertion count."""
        return len(self.assertion_results)

    def __str__(self) -> str:
        """Human-readable string representation."""
        status_symbol = {
            ResultStatus.PASSED: "✓",
            ResultStatus.FAILED: "✗",
            ResultStatus.SKIPPED: "⊘",
            ResultStatus.ERROR: "⚠"
        }[self.status]

        return (
            f"{status_symbol} {self.scenario_name} "
            f"({self.duration_seconds:.1f}s) "
            f"[{self.passed_count}/{self.total_count}]"
        )


@dataclass
class TestSuiteResult:
    """Aggregated results for a test suite run."""
    start_time: datetime
    end_time: datetime
    total_duration_seconds: float
    test_results: List[TestResult] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    @property
    def total_tests(self) -> int:
        """Total number of tests."""
        return len(self.test_results)

    @property
    def passed_tests(self) -> int:
        """Number of passed tests."""
        return sum(1 for r in self.test_results if r.status == ResultStatus.PASSED)

    @property
    def failed_tests(self) -> int:
        """Number of failed tests."""
        return sum(1 for r in self.test_results if r.status == ResultStatus.FAILED)

    @property
    def skipped_tests(self) -> int:
        """Number of skipped tests."""
        return sum(1 for r in self.test_results if r.status == ResultStatus.SKIPPED)

    @property
    def error_tests(self) -> int:
        """Number of tests with errors."""
        return sum(1 for r in self.test_results if r.status == ResultStatus.ERROR)

    @property
    def success_rate(self) -> float:
        """Percentage of tests that passed."""
        if self.total_tests == 0:
            return 0.0
        return (self.passed_tests / self.total_tests) * 100

    def __str__(self) -> str:
        """Human-readable string representation."""
        return (
            f"Tests: {self.passed_tests} passed, {self.failed_tests} failed, "
            f"{self.skipped_tests} skipped, {self.error_tests} errors "
            f"({self.total_duration_seconds:.1f}s total)"
        )
