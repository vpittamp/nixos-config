"""Base test scenario abstract class.

This module provides the abstract base class for all test scenarios,
defining the lifecycle methods and common utilities.
"""

import asyncio
import logging
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Any, Dict, List, Optional

from ..models import (
    AssertionResult,
    AssertionType,
    LogEntry,
    ResultStatus,
    TestResult,
)


logger = logging.getLogger(__name__)


class BaseScenario(ABC):
    """Abstract base class for test scenarios.

    All test scenarios must inherit from this class and implement
    the required abstract methods.

    Attributes:
        scenario_id: Unique identifier for this scenario
        name: Human-readable test name
        description: Test purpose and expected outcome
        priority: Execution priority (1 = highest)
        timeout_seconds: Maximum execution time
        requires_xrandr: Whether test needs X11/xrandr
        requires_tmux: Whether test needs tmux isolation
    """

    scenario_id: str = ""
    name: str = ""
    description: str = ""
    priority: int = 3
    timeout_seconds: float = 30.0
    requires_xrandr: bool = False
    requires_tmux: bool = True

    def __init__(self):
        """Initialize test scenario."""
        self._start_time: Optional[datetime] = None
        self._end_time: Optional[datetime] = None
        self._logs: List[LogEntry] = []
        self._assertion_results: List[AssertionResult] = []
        self._artifacts: Dict[str, str] = {}

        # Validate required attributes
        if not self.scenario_id:
            raise ValueError(f"{self.__class__.__name__} must define scenario_id")
        if not self.name:
            raise ValueError(f"{self.__class__.__name__} must define name")

    @abstractmethod
    async def setup(self) -> None:
        """Setup phase: prepare test environment.

        This method should create test projects, set up initial state,
        and prepare any required resources.

        Raises:
            Exception: If setup fails
        """
        pass

    @abstractmethod
    async def execute(self) -> None:
        """Execute phase: run test actions.

        This method should perform the main test actions such as
        switching projects, opening windows, or triggering events.

        Raises:
            Exception: If execution fails
        """
        pass

    @abstractmethod
    async def validate(self) -> None:
        """Validate phase: check expected outcomes.

        This method should run assertions to validate that the
        system state matches expectations.

        Raises:
            AssertionError: If validation fails
        """
        pass

    @abstractmethod
    async def cleanup(self) -> None:
        """Cleanup phase: clean up test artifacts.

        This method should delete test projects, close windows,
        and restore the system to its pre-test state.

        This method MUST NOT raise exceptions - it should handle
        all errors gracefully to ensure cleanup always completes.
        """
        pass

    async def run(self) -> TestResult:
        """Run the complete test scenario lifecycle.

        Executes setup, test actions, validation, and cleanup in sequence.
        Captures timing, logs, and assertion results.

        Returns:
            TestResult with complete execution details

        Raises:
            asyncio.TimeoutError: If test exceeds timeout_seconds
        """
        self._start_time = datetime.now()
        status = ResultStatus.PASSED
        error_message = None

        try:
            # Execute with timeout
            async with asyncio.timeout(self.timeout_seconds):
                self.log_info(f"Starting scenario: {self.name}")

                try:
                    # Setup phase
                    self.log_info("Running setup phase")
                    await self.setup()

                    # Execute phase
                    self.log_info("Running execute phase")
                    await self.execute()

                    # Validate phase
                    self.log_info("Running validate phase")
                    await self.validate()

                    # Check if any assertions failed
                    if any(r.status == ResultStatus.FAILED for r in self._assertion_results):
                        status = ResultStatus.FAILED
                        error_message = "One or more assertions failed"

                    self.log_info(f"Scenario completed: {status.value}")

                except AssertionError as e:
                    status = ResultStatus.FAILED
                    error_message = str(e)
                    self.log_error(f"Assertion failed: {e}")

                except Exception as e:
                    status = ResultStatus.ERROR
                    error_message = f"Test execution error: {e}"
                    self.log_error(f"Execution error: {e}")

        except asyncio.TimeoutError:
            status = ResultStatus.ERROR
            error_message = f"Test exceeded timeout of {self.timeout_seconds}s"
            self.log_error(error_message)

        finally:
            # Always run cleanup
            try:
                self.log_info("Running cleanup phase")
                await self.cleanup()
            except Exception as e:
                self.log_error(f"Cleanup error (suppressed): {e}")

            self._end_time = datetime.now()
            duration = (self._end_time - self._start_time).total_seconds()

            return TestResult(
                scenario_id=self.scenario_id,
                scenario_name=self.name,
                status=status,
                start_time=self._start_time,
                end_time=self._end_time,
                duration_seconds=duration,
                assertion_results=self._assertion_results,
                error_message=error_message,
                logs=self._logs,
                artifacts=self._artifacts,
            )

    # Logging helpers

    def log_info(self, message: str, context: Optional[Dict[str, Any]] = None) -> None:
        """Log info level message."""
        self._log("INFO", message, context)
        logger.info(message)

    def log_warning(self, message: str, context: Optional[Dict[str, Any]] = None) -> None:
        """Log warning level message."""
        self._log("WARNING", message, context)
        logger.warning(message)

    def log_error(self, message: str, context: Optional[Dict[str, Any]] = None) -> None:
        """Log error level message."""
        self._log("ERROR", message, context)
        logger.error(message)

    def log_debug(self, message: str, context: Optional[Dict[str, Any]] = None) -> None:
        """Log debug level message."""
        self._log("DEBUG", message, context)
        logger.debug(message)

    def _log(self, level: str, message: str, context: Optional[Dict[str, Any]] = None) -> None:
        """Internal logging method."""
        entry = LogEntry(
            timestamp=datetime.now(),
            level=level,
            message=message,
            context=context or {},
        )
        self._logs.append(entry)

    # Assertion helpers

    def record_assertion(
        self,
        assertion_id: str,
        assertion_type: AssertionType,
        expected: Any,
        actual: Any,
        message: Optional[str] = None,
    ) -> None:
        """Record assertion result.

        Args:
            assertion_id: Unique assertion identifier
            assertion_type: Type of assertion
            expected: Expected value
            actual: Actual value
            message: Optional custom message
        """
        status = ResultStatus.PASSED if expected == actual else ResultStatus.FAILED

        result = AssertionResult(
            assertion_id=assertion_id,
            assertion_type=assertion_type,
            status=status,
            expected=expected,
            actual=actual,
            message=message,
        )

        self._assertion_results.append(result)
        self.log_info(f"Assertion: {result}")

    def add_artifact(self, name: str, path: str) -> None:
        """Add test artifact (screenshot, log, diagnostic snapshot).

        Args:
            name: Artifact name/type
            path: File path to artifact
        """
        self._artifacts[name] = path
        self.log_debug(f"Added artifact: {name} -> {path}")

    # Helper methods for common operations

    async def wait(self, seconds: float) -> None:
        """Wait for specified duration.

        Args:
            seconds: Duration to wait
        """
        self.log_debug(f"Waiting {seconds}s")
        await asyncio.sleep(seconds)

    def assert_equals(
        self,
        assertion_id: str,
        assertion_type: AssertionType,
        expected: Any,
        actual: Any,
        message: Optional[str] = None,
    ) -> None:
        """Assert that expected equals actual.

        Args:
            assertion_id: Unique assertion identifier
            assertion_type: Type of assertion
            expected: Expected value
            actual: Actual value
            message: Optional custom message

        Raises:
            AssertionError: If expected != actual
        """
        self.record_assertion(assertion_id, assertion_type, expected, actual, message)

        if expected != actual:
            error_msg = message or f"Expected {expected}, got {actual}"
            raise AssertionError(error_msg)

    def assert_contains(
        self,
        assertion_id: str,
        assertion_type: AssertionType,
        collection: List[Any],
        item: Any,
        message: Optional[str] = None,
    ) -> None:
        """Assert that collection contains item.

        Args:
            assertion_id: Unique assertion identifier
            assertion_type: Type of assertion
            collection: Collection to search
            item: Item to find
            message: Optional custom message

        Raises:
            AssertionError: If item not in collection
        """
        expected = True
        actual = item in collection

        self.record_assertion(assertion_id, assertion_type, expected, actual, message)

        if not actual:
            error_msg = message or f"Expected {item} to be in {collection}"
            raise AssertionError(error_msg)
