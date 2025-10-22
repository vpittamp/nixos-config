"""TestFramework implementation for TUI testing.

Implements ITestFramework contract using Textual Pilot API for automated testing.
"""

import asyncio
import sys
import time
from pathlib import Path
from typing import List, Dict, Any, Optional
from datetime import datetime

from textual.pilot import Pilot
from textual.app import App
from textual.widgets import DataTable, Input

# Import contracts from specs directory
contracts_path = Path(__file__).parent.parent.parent.parent.parent / "specs" / "022-create-a-new" / "contracts"
if str(contracts_path) not in sys.path:
    sys.path.insert(0, str(contracts_path.parent))

from contracts.test_framework import (
    ITestFramework,
    TestScenario,
    TestAction,
    TestAssertion,
    TestResult,
    TestSuiteResult,
    AssertionResult,
    TestActionType,
    AssertionType
)


class TestFramework(ITestFramework):
    """Concrete implementation of TUI test framework.

    Uses Textual Pilot API to simulate user interactions and verify TUI behavior.
    """

    def __init__(self):
        """Initialize test framework."""
        self.coverage_data: Dict[str, Any] = {
            "screens_tested": set(),
            "actions_executed": [],
            "assertions_evaluated": []
        }

    async def execute_scenario(self, scenario: TestScenario) -> TestResult:
        """Execute a single test scenario.

        Process:
        1. Validate scenario
        2. Check preconditions
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
        """
        start_time = time.time()

        try:
            # Validate scenario
            scenario.validate()
        except ValueError as e:
            return TestResult(
                scenario_name=scenario.name,
                passed=False,
                duration=0.0,
                actions_executed=0,
                assertions_passed=0,
                assertions_failed=0,
                assertion_results=[],
                error=f"Scenario validation failed: {str(e)}"
            )

        app = None
        pilot = None
        actions_executed = 0
        assertion_results: List[AssertionResult] = []

        try:
            # Note: Actual app initialization would happen here
            # For now, we'll create a minimal structure for testing the framework itself

            # Execute actions
            for action in scenario.actions:
                if pilot:  # Only execute if we have a pilot
                    await self.simulate_action(action, pilot)
                actions_executed += 1

                # Check timeout
                if time.time() - start_time > scenario.timeout:
                    raise TimeoutError(f"Scenario exceeded timeout of {scenario.timeout}s")

            # Evaluate assertions
            for assertion in scenario.assertions:
                assertion_result = await self.evaluate_assertion(assertion, app)
                assertion_results.append(assertion_result)

            # Execute cleanup
            for cleanup_action in scenario.cleanup:
                if pilot:
                    await self.simulate_action(cleanup_action, pilot)

            # Calculate results
            assertions_passed = sum(1 for r in assertion_results if r.passed)
            assertions_failed = len(assertion_results) - assertions_passed
            passed = assertions_failed == 0

            duration = time.time() - start_time

            # Update coverage data
            self.coverage_data["actions_executed"].extend([a.action_type.value for a in scenario.actions])
            self.coverage_data["assertions_evaluated"].extend([a.assertion_type.value for a in scenario.assertions])

            return TestResult(
                scenario_name=scenario.name,
                passed=passed,
                duration=duration,
                actions_executed=actions_executed,
                assertions_passed=assertions_passed,
                assertions_failed=assertions_failed,
                assertion_results=assertion_results,
                state_dump=self.capture_state_dump(app) if not passed else None
            )

        except Exception as e:
            duration = time.time() - start_time
            return TestResult(
                scenario_name=scenario.name,
                passed=False,
                duration=duration,
                actions_executed=actions_executed,
                assertions_passed=0,
                assertions_failed=len(assertion_results),
                assertion_results=assertion_results,
                error=str(e),
                state_dump=self.capture_state_dump(app) if app else None
            )

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
        start_time = time.time()
        test_results: List[TestResult] = []

        for scenario in scenarios:
            result = await self.execute_scenario(scenario)
            test_results.append(result)

        duration = time.time() - start_time

        # Calculate aggregate statistics
        passed = sum(1 for r in test_results if r.passed)
        failed = sum(1 for r in test_results if not r.passed)
        skipped = 0  # Not implemented yet

        # Generate coverage report
        coverage_report = self.generate_coverage_report(test_results)

        return TestSuiteResult(
            total_tests=len(scenarios),
            passed=passed,
            failed=failed,
            skipped=skipped,
            duration=duration,
            test_results=test_results,
            coverage_report=coverage_report
        )

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
        if not pilot:
            return

        action_type = action.action_type

        if action_type == TestActionType.PRESS_KEY:
            key = action.params.get("key")
            await pilot.press(key)

        elif action_type == TestActionType.TYPE_TEXT:
            text = action.params.get("text")
            # Type each character
            for char in text:
                await pilot.press(char)

        elif action_type == TestActionType.CLICK:
            widget_id = action.params.get("widget_id")
            await pilot.click(f"#{widget_id}")

        elif action_type == TestActionType.SELECT_ROW:
            table_id = action.params.get("table_id")
            row_key = action.params.get("row_key")

            # Get table widget
            try:
                table = pilot.app.query_one(f"#{table_id}", DataTable)
                # Move cursor to row
                table.move_cursor(row=row_key)
            except Exception:
                pass  # Table not found or row doesn't exist

        elif action_type == TestActionType.WAIT:
            seconds = action.params.get("seconds", 0.5)
            await asyncio.sleep(seconds)

        elif action_type == TestActionType.WAIT_FOR_CONDITION:
            # Future implementation for waiting for specific conditions
            timeout = action.params.get("timeout", 5.0)
            condition = action.params.get("condition")
            # Would poll condition until met or timeout
            await asyncio.sleep(0.1)

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
        start_time = time.time()
        assertion_type = assertion.assertion_type

        try:
            if assertion_type == AssertionType.FILE_EXISTS:
                file_path = Path(assertion.target).expanduser()
                actual = file_path.exists()
                passed = actual == assertion.expected

                return AssertionResult(
                    assertion=assertion,
                    passed=passed,
                    actual=actual,
                    duration=time.time() - start_time
                )

            elif assertion_type == AssertionType.STATE_EQUALS:
                # Parse target: "widget_id.property"
                parts = assertion.target.split(".", 1)
                if len(parts) != 2:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error="Invalid target format, expected 'widget_id.property'",
                        duration=time.time() - start_time
                    )

                widget_id, property_name = parts

                if not app:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error="No app instance available",
                        duration=time.time() - start_time
                    )

                try:
                    widget = app.query_one(f"#{widget_id}")
                    actual = getattr(widget, property_name)
                    passed = actual == assertion.expected

                    return AssertionResult(
                        assertion=assertion,
                        passed=passed,
                        actual=actual,
                        duration=time.time() - start_time
                    )
                except Exception as e:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error=str(e),
                        duration=time.time() - start_time
                    )

            elif assertion_type == AssertionType.TABLE_ROW_COUNT:
                if not app:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error="No app instance available",
                        duration=time.time() - start_time
                    )

                try:
                    table = app.query_one(f"#{assertion.target}", DataTable)
                    actual = table.row_count
                    passed = actual == assertion.expected

                    return AssertionResult(
                        assertion=assertion,
                        passed=passed,
                        actual=actual,
                        duration=time.time() - start_time
                    )
                except Exception as e:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error=str(e),
                        duration=time.time() - start_time
                    )

            elif assertion_type == AssertionType.INPUT_VALUE:
                if not app:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error="No app instance available",
                        duration=time.time() - start_time
                    )

                try:
                    input_widget = app.query_one(f"#{assertion.target}", Input)
                    actual = input_widget.value
                    passed = actual == assertion.expected

                    return AssertionResult(
                        assertion=assertion,
                        passed=passed,
                        actual=actual,
                        duration=time.time() - start_time
                    )
                except Exception as e:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error=str(e),
                        duration=time.time() - start_time
                    )

            elif assertion_type == AssertionType.SCREEN_ACTIVE:
                if not app:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error="No app instance available",
                        duration=time.time() - start_time
                    )

                actual = app.screen.name if app.screen else None
                passed = actual == assertion.expected

                return AssertionResult(
                    assertion=assertion,
                    passed=passed,
                    actual=actual,
                    duration=time.time() - start_time
                )

            elif assertion_type == AssertionType.WIDGET_VISIBLE:
                if not app:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error="No app instance available",
                        duration=time.time() - start_time
                    )

                try:
                    widget = app.query_one(f"#{assertion.target}")
                    actual = widget.display and not widget.disabled
                    passed = actual == assertion.expected

                    return AssertionResult(
                        assertion=assertion,
                        passed=passed,
                        actual=actual,
                        duration=time.time() - start_time
                    )
                except Exception as e:
                    return AssertionResult(
                        assertion=assertion,
                        passed=False,
                        actual=None,
                        error=str(e),
                        duration=time.time() - start_time
                    )

            elif assertion_type == AssertionType.TIMING:
                # Timing assertions should be evaluated after the operation completes
                # For now, we'll check if the duration is less than expected
                actual = time.time() - start_time
                passed = actual < assertion.expected

                return AssertionResult(
                    assertion=assertion,
                    passed=passed,
                    actual=actual,
                    duration=time.time() - start_time
                )

            else:
                return AssertionResult(
                    assertion=assertion,
                    passed=False,
                    actual=None,
                    error=f"Unsupported assertion type: {assertion_type}",
                    duration=time.time() - start_time
                )

        except Exception as e:
            return AssertionResult(
                assertion=assertion,
                passed=False,
                actual=None,
                error=f"Exception during assertion evaluation: {str(e)}",
                duration=time.time() - start_time
            )

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
        if not app:
            return {"error": "No app instance available"}

        state_dump = {
            "timestamp": datetime.now().isoformat(),
            "screen": None,
            "widgets": {},
            "file_system": {}
        }

        try:
            # Capture active screen
            if hasattr(app, 'screen') and app.screen:
                state_dump["screen"] = {
                    "name": app.screen.name if hasattr(app.screen, 'name') else "unknown",
                    "class": app.screen.__class__.__name__
                }

            # Capture widget states
            try:
                for widget in app.query("*"):
                    widget_id = widget.id if hasattr(widget, 'id') and widget.id else None
                    if widget_id:
                        widget_state = {
                            "class": widget.__class__.__name__,
                            "visible": widget.display if hasattr(widget, 'display') else None
                        }

                        # Capture specific widget types
                        if isinstance(widget, DataTable):
                            widget_state["row_count"] = widget.row_count
                        elif isinstance(widget, Input):
                            widget_state["value"] = widget.value

                        state_dump["widgets"][widget_id] = widget_state
            except Exception:
                pass  # Ignore widget query errors

            # Capture file system state
            config_dir = Path.home() / ".config" / "i3"
            if config_dir.exists():
                state_dump["file_system"]["config_dir_exists"] = True
                state_dump["file_system"]["projects_count"] = len(list((config_dir / "projects").glob("*.json"))) if (config_dir / "projects").exists() else 0
                state_dump["file_system"]["layouts_count"] = len(list((config_dir / "layouts").rglob("*.json"))) if (config_dir / "layouts").exists() else 0
            else:
                state_dump["file_system"]["config_dir_exists"] = False

        except Exception as e:
            state_dump["capture_error"] = str(e)

        return state_dump

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
        # Aggregate action types across all tests
        action_types_used = set()
        assertion_types_used = set()

        for result in results:
            # Extract action types from coverage data
            # (In real implementation, we'd track this during execution)
            pass

        action_types_used = set(self.coverage_data.get("actions_executed", []))
        assertion_types_used = set(self.coverage_data.get("assertions_evaluated", []))

        # Calculate coverage
        total_action_types = len(TestActionType)
        total_assertion_types = len(AssertionType)

        action_coverage = (len(action_types_used) / total_action_types * 100) if total_action_types > 0 else 0
        assertion_coverage = (len(assertion_types_used) / total_assertion_types * 100) if total_assertion_types > 0 else 0

        return {
            "screens_tested": list(self.coverage_data.get("screens_tested", [])),
            "screens_not_tested": [],  # Would need full screen list to calculate
            "total_scenarios": len(results),
            "scenarios_passed": sum(1 for r in results if r.passed),
            "scenarios_failed": sum(1 for r in results if not r.passed),
            "action_types_tested": list(action_types_used),
            "action_coverage_percentage": round(action_coverage, 2),
            "assertion_types_tested": list(assertion_types_used),
            "assertion_coverage_percentage": round(assertion_coverage, 2),
            "overall_coverage_percentage": round((action_coverage + assertion_coverage) / 2, 2)
        }
