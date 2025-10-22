"""Test Framework Contract - FR-029 through FR-033

API contract for automated TUI testing using Textual Pilot API.

This contract defines interfaces for:
- Simulating user interactions (key presses, mouse events)
- Capturing state changes and daemon events
- Asserting expected outcomes with timing constraints
- Generating test coverage reports
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional, Callable
from datetime import datetime
from enum import Enum


class AssertionType(Enum):
    """Types of assertions supported by test framework."""
    FILE_EXISTS = "file_exists"
    STATE_EQUALS = "state_equals"
    EVENT_TRIGGERED = "event_triggered"
    TIMING = "timing"
    TABLE_ROW_COUNT = "table_row_count"
    INPUT_VALUE = "input_value"
    SCREEN_ACTIVE = "screen_active"
    WIDGET_VISIBLE = "widget_visible"


class TestActionType(Enum):
    """Types of test actions supported."""
    PRESS_KEY = "press_key"
    TYPE_TEXT = "type_text"
    CLICK = "click"
    SELECT_ROW = "select_row"
    WAIT = "wait"
    WAIT_FOR_CONDITION = "wait_for_condition"


@dataclass
class TestAction:
    """Base test action."""
    action_type: TestActionType
    description: str
    params: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def press_key(cls, key: str, description: str = "") -> "TestAction":
        """Create key press action."""
        return cls(
            action_type=TestActionType.PRESS_KEY,
            description=description or f"Press {key}",
            params={"key": key}
        )

    @classmethod
    def type_text(cls, text: str, description: str = "") -> "TestAction":
        """Create text typing action."""
        return cls(
            action_type=TestActionType.TYPE_TEXT,
            description=description or f"Type '{text}'",
            params={"text": text}
        )

    @classmethod
    def click(cls, widget_id: str, description: str = "") -> "TestAction":
        """Create click action."""
        return cls(
            action_type=TestActionType.CLICK,
            description=description or f"Click {widget_id}",
            params={"widget_id": widget_id}
        )

    @classmethod
    def select_row(cls, table_id: str, row_key: Any, description: str = "") -> "TestAction":
        """Create row selection action."""
        return cls(
            action_type=TestActionType.SELECT_ROW,
            description=description or f"Select row {row_key}",
            params={"table_id": table_id, "row_key": row_key}
        )

    @classmethod
    def wait(cls, seconds: float, description: str = "") -> "TestAction":
        """Create wait action."""
        return cls(
            action_type=TestActionType.WAIT,
            description=description or f"Wait {seconds}s",
            params={"seconds": seconds}
        )


@dataclass
class TestAssertion:
    """Test assertion definition."""
    assertion_type: AssertionType
    target: str                           # What to check (widget ID, file path, event name)
    expected: Any                         # Expected value
    operator: str = "equals"              # "equals", "contains", "less_than", "greater_than"
    timeout: Optional[float] = None       # Wait timeout for condition
    description: str = ""

    @classmethod
    def file_exists(cls, file_path: str, description: str = "") -> "TestAssertion":
        """Assert file exists."""
        return cls(
            assertion_type=AssertionType.FILE_EXISTS,
            target=file_path,
            expected=True,
            description=description or f"File exists: {file_path}"
        )

    @classmethod
    def state_equals(cls, widget_id: str, property: str, expected: Any, description: str = "") -> "TestAssertion":
        """Assert widget state equals expected."""
        return cls(
            assertion_type=AssertionType.STATE_EQUALS,
            target=f"{widget_id}.{property}",
            expected=expected,
            description=description or f"{widget_id}.{property} == {expected}"
        )

    @classmethod
    def timing(cls, operation: str, max_duration: float, description: str = "") -> "TestAssertion":
        """Assert operation completed within time limit."""
        return cls(
            assertion_type=AssertionType.TIMING,
            target=operation,
            expected=max_duration,
            operator="less_than",
            description=description or f"{operation} completed within {max_duration}s"
        )

    @classmethod
    def table_row_count(cls, table_id: str, expected_count: int, description: str = "") -> "TestAssertion":
        """Assert DataTable has expected row count."""
        return cls(
            assertion_type=AssertionType.TABLE_ROW_COUNT,
            target=table_id,
            expected=expected_count,
            description=description or f"{table_id} has {expected_count} rows"
        )


@dataclass
class AssertionResult:
    """Result of assertion evaluation."""
    assertion: TestAssertion
    passed: bool
    actual: Any                           # Actual value found
    error: Optional[str] = None
    duration: float = 0.0                 # Time taken to evaluate


@dataclass
class TestScenario:
    """Test scenario definition."""
    name: str
    description: str
    preconditions: List[str]
    actions: List[TestAction]
    assertions: List[TestAssertion]
    timeout: float = 30.0
    cleanup: List[TestAction] = field(default_factory=list)
    tags: List[str] = field(default_factory=list)

    def validate(self) -> None:
        """Validate scenario is well-formed."""
        if not self.name.replace("-", "").replace("_", "").isalnum():
            raise ValueError(f"Invalid scenario name: {self.name}")
        if not self.actions:
            raise ValueError("Scenario must have at least one action")
        if not self.assertions:
            raise ValueError("Scenario must have at least one assertion")
        if self.timeout <= 0:
            raise ValueError("Timeout must be positive")


@dataclass
class TestResult:
    """Test execution result."""
    scenario_name: str
    passed: bool
    duration: float
    actions_executed: int
    assertions_passed: int
    assertions_failed: int
    assertion_results: List[AssertionResult]
    error: Optional[str] = None
    state_dump: Optional[Dict[str, Any]] = None  # State dump if test failed
    executed_at: datetime = field(default_factory=datetime.now)


@dataclass
class TestSuiteResult:
    """Test suite execution result."""
    total_tests: int
    passed: int
    failed: int
    skipped: int
    duration: float
    test_results: List[TestResult]
    coverage_report: Optional[Dict[str, Any]] = None
    executed_at: datetime = field(default_factory=datetime.now)


class ITestFramework(ABC):
    """Abstract interface for TUI test framework.

    Implements:
    - FR-029: Simulate user interactions (key presses, mouse events, screen transitions)
    - FR-030: Capture state changes, daemon events, file modifications
    - FR-031: Provide assertions for state verification, timing, event sequences
    - FR-032: Execute tests in isolation preventing cross-test interference
    - FR-033: Generate test coverage reports showing tested UI paths
    """

    @abstractmethod
    async def execute_scenario(self, scenario: TestScenario) -> TestResult:
        """Execute a single test scenario.

        Process:
        1. Validate scenario
        2. Check preconditions (project exists, daemon running, etc.)
        3. Initialize Textual app with Pilot
        4. Execute each action in sequence
        5. Evaluate each assertion
        6. Execute cleanup actions
        7. Return test result with assertion outcomes

        Args:
            scenario: Test scenario to execute

        Returns:
            TestResult with pass/fail status and detailed results

        Raises:
            TimeoutError: If scenario exceeds timeout
            ValueError: If scenario validation fails

        Isolation:
            Each scenario runs in isolated environment (FR-032)
            - Separate config directory
            - Mock daemon connection
            - Clean slate for each test
        """
        pass

    @abstractmethod
    async def execute_suite(self, scenarios: List[TestScenario]) -> TestSuiteResult:
        """Execute multiple test scenarios.

        Runs each scenario in isolation and aggregates results.

        Args:
            scenarios: List of scenarios to execute

        Returns:
            TestSuiteResult with aggregate statistics and coverage

        Performance:
            Full suite should execute in under 5 minutes (SC-007)
        """
        pass

    @abstractmethod
    async def simulate_action(self, action: TestAction, pilot: Any) -> None:
        """Simulate a single user action using Textual Pilot.

        Args:
            action: Action to simulate
            pilot: Textual Pilot instance

        Supported actions:
            - PRESS_KEY: await pilot.press(key)
            - TYPE_TEXT: await pilot.press(*list(text))
            - CLICK: await pilot.click(selector=widget_id)
            - SELECT_ROW: Move cursor to row and select
            - WAIT: await asyncio.sleep(seconds)
            - WAIT_FOR_CONDITION: Poll until condition met
        """
        pass

    @abstractmethod
    async def evaluate_assertion(self, assertion: TestAssertion, app: Any) -> AssertionResult:
        """Evaluate a single assertion against current app state.

        Args:
            assertion: Assertion to evaluate
            app: Textual app instance

        Returns:
            AssertionResult with pass/fail status and actual value

        Assertion types:
            - FILE_EXISTS: Check file path exists
            - STATE_EQUALS: Check widget property equals expected
            - EVENT_TRIGGERED: Check daemon event was emitted
            - TIMING: Check operation completed within time limit
            - TABLE_ROW_COUNT: Check DataTable row count
            - INPUT_VALUE: Check Input widget value
            - SCREEN_ACTIVE: Check active screen name
            - WIDGET_VISIBLE: Check widget is visible
        """
        pass

    @abstractmethod
    def capture_state_dump(self, app: Any) -> Dict[str, Any]:
        """Capture complete app state for debugging.

        Returns state dump including:
        - Active screen name
        - All widget states (DataTable contents, Input values, etc.)
        - Current project configuration
        - Recent daemon events (if available)
        - File system state (saved layouts, projects)

        Used for debugging failed tests (User Story 7, Acceptance 3).

        Args:
            app: Textual app instance

        Returns:
            Dict with complete state snapshot
        """
        pass

    @abstractmethod
    def generate_coverage_report(self, results: List[TestResult]) -> Dict[str, Any]:
        """Generate test coverage report.

        Analyzes test results to determine which UI paths were tested.

        Returns report with:
        - Screens tested
        - Actions tested per screen
        - Assertion types used
        - Untested UI paths
        - Coverage percentage

        Args:
            results: List of test results

        Returns:
            Dict with coverage statistics (FR-033)

        Format:
        {
            "screens_tested": ["browser", "editor", "layout_manager"],
            "screens_not_tested": ["pattern_config"],
            "total_scenarios": 20,
            "ui_paths_tested": 45,
            "ui_paths_total": 52,
            "coverage_percentage": 86.5
        }
        """
        pass


class IMockDaemonClient(ABC):
    """Mock daemon client for testing.

    Provides mock implementations of daemon operations for isolated testing.
    Captures all IPC calls for verification in assertions.
    """

    @abstractmethod
    async def send_request(self, method: str, params: Dict[str, Any]) -> Any:
        """Mock daemon request.

        Records request for verification and returns mock response.

        Args:
            method: JSON-RPC method name
            params: Request parameters

        Returns:
            Mock response based on method
        """
        pass

    @abstractmethod
    def get_captured_requests(self) -> List[Dict[str, Any]]:
        """Get list of all captured requests for assertion verification.

        Returns:
            List of request dicts with method and params
        """
        pass

    @abstractmethod
    async def simulate_event(self, event_type: str, event_data: Dict[str, Any]) -> None:
        """Simulate daemon event for testing event handlers.

        Args:
            event_type: Event type (e.g., "layout::saved")
            event_data: Event payload
        """
        pass


# Example test scenario

def create_layout_save_restore_test() -> TestScenario:
    """Example test scenario for layout save/restore workflow."""
    return TestScenario(
        name="test_layout_save_restore",
        description="User saves current layout and restores it after making changes",
        preconditions=[
            "Project 'test-project' exists",
            "3 windows open (Ghostty on WS1, Code on WS1, Firefox on WS2)",
            "Daemon is running",
            "No saved layouts exist"
        ],
        actions=[
            # Navigate to layout manager
            TestAction.press_key("l", "Open layout manager"),
            TestAction.wait(0.5, "Wait for screen transition"),

            # Save layout
            TestAction.press_key("s", "Trigger save layout"),
            TestAction.type_text("coding-layout", "Enter layout name"),
            TestAction.press_key("enter", "Confirm save"),
            TestAction.wait(1.0, "Wait for save operation"),

            # Verify layout saved
            # (Layout now appears in table)

            # Close all windows
            TestAction.press_key("escape", "Return to browser"),
            TestAction.press_key("c", "Close all project windows"),
            TestAction.wait(1.0, "Wait for windows to close"),

            # Restore layout
            TestAction.press_key("l", "Open layout manager"),
            TestAction.select_row("layouts", "coding-layout", "Select saved layout"),
            TestAction.press_key("r", "Trigger restore"),
            TestAction.wait(3.0, "Wait for layout restoration with app launching"),
        ],
        assertions=[
            # Layout file exists
            TestAssertion.file_exists(
                "~/.config/i3/layouts/test-project/coding-layout.json",
                "Layout file was created"
            ),

            # All windows restored
            TestAssertion.state_equals(
                "monitor-dashboard", "window_count", 3,
                "All 3 windows restored"
            ),

            # Timing constraint
            TestAssertion.timing(
                "layout_restore", 2.0,
                "Layout restore completed within 2 seconds (FR-002 requirement)"
            ),

            # Windows on correct workspaces
            # (Would query i3 tree and verify window positions)
        ],
        timeout=15.0,
        cleanup=[
            TestAction.press_key("escape", "Return to browser"),
            # Delete test project and layouts
        ],
        tags=["layout", "save", "restore", "priority-p1"]
    )


# Example usage

async def run_test_example():
    """Example of running a test scenario."""
    from i3_project_manager.tui.app import I3ProjectManagerApp

    # Create test framework instance
    test_framework = TestFramework()  # Concrete implementation

    # Create test scenario
    scenario = create_layout_save_restore_test()

    # Execute scenario
    result = await test_framework.execute_scenario(scenario)

    # Check result
    if result.passed:
        print(f"✅ Test passed in {result.duration:.2f}s")
        print(f"   Assertions: {result.assertions_passed}/{result.assertions_passed + result.assertions_failed}")
    else:
        print(f"❌ Test failed after {result.duration:.2f}s")
        print(f"   Error: {result.error}")
        print(f"   Failed assertions:")
        for assertion_result in result.assertion_results:
            if not assertion_result.passed:
                print(f"      - {assertion_result.assertion.description}")
                print(f"        Expected: {assertion_result.assertion.expected}")
                print(f"        Actual: {assertion_result.actual}")

        # State dump available for debugging
        if result.state_dump:
            print(f"   State dump: {result.state_dump}")
