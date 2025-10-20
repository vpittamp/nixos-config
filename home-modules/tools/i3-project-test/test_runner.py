"""Test runner for executing test scenarios.

This module provides the test execution engine that loads scenarios,
runs them with appropriate isolation, and collects results.
"""

import asyncio
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Type

from .models import ResultStatus, TestResult, TestSuiteResult
from .scenarios.base_scenario import BaseScenario


logger = logging.getLogger(__name__)


class TestRunner:
    """Test execution engine for i3 project test scenarios.

    The test runner loads test scenarios, executes them with proper
    isolation and timeout handling, and aggregates results.

    Attributes:
        scenarios: Registry of loaded test scenarios
        results: Collected test results
    """

    def __init__(self):
        """Initialize test runner."""
        self.scenarios: Dict[str, Type[BaseScenario]] = {}
        self.results: List[TestResult] = []

    def register_scenario(self, scenario_class: Type[BaseScenario]) -> None:
        """Register a test scenario class.

        Args:
            scenario_class: Test scenario class to register

        Raises:
            ValueError: If scenario_id already registered
        """
        # Create temporary instance to get scenario_id
        temp_instance = scenario_class()
        scenario_id = temp_instance.scenario_id

        if scenario_id in self.scenarios:
            raise ValueError(f"Scenario {scenario_id} already registered")

        self.scenarios[scenario_id] = scenario_class
        logger.info(f"Registered scenario: {scenario_id} ({temp_instance.name})")

    def register_scenarios(self, scenario_classes: List[Type[BaseScenario]]) -> None:
        """Register multiple test scenario classes.

        Args:
            scenario_classes: List of scenario classes to register
        """
        for scenario_class in scenario_classes:
            self.register_scenario(scenario_class)

    def list_scenarios(self) -> List[Dict[str, str]]:
        """List all registered scenarios.

        Returns:
            List of scenario metadata dictionaries
        """
        scenarios = []
        for scenario_class in self.scenarios.values():
            instance = scenario_class()
            scenarios.append({
                "id": instance.scenario_id,
                "name": instance.name,
                "description": instance.description,
                "priority": str(instance.priority),
                "timeout": f"{instance.timeout_seconds}s",
            })

        # Sort by priority (lowest number = highest priority)
        scenarios.sort(key=lambda s: int(s["priority"]))
        return scenarios

    async def run_scenario(self, scenario_id: str) -> TestResult:
        """Run a single test scenario.

        Args:
            scenario_id: ID of scenario to run

        Returns:
            Test result for the scenario

        Raises:
            ValueError: If scenario_id not found
        """
        if scenario_id not in self.scenarios:
            raise ValueError(f"Unknown scenario: {scenario_id}")

        scenario_class = self.scenarios[scenario_id]
        scenario = scenario_class()

        logger.info(f"Running scenario: {scenario_id} ({scenario.name})")

        try:
            result = await scenario.run()
            self.results.append(result)
            return result

        except Exception as e:
            logger.error(f"Unexpected error running scenario {scenario_id}: {e}")

            # Create error result
            now = datetime.now()
            result = TestResult(
                scenario_id=scenario_id,
                scenario_name=scenario.name,
                status=ResultStatus.ERROR,
                start_time=now,
                end_time=now,
                duration_seconds=0.0,
                error_message=f"Unexpected runner error: {e}",
            )
            self.results.append(result)
            return result

    async def run_scenarios(
        self,
        scenario_ids: Optional[List[str]] = None,
        parallel: bool = False,
    ) -> TestSuiteResult:
        """Run multiple test scenarios.

        Args:
            scenario_ids: List of scenario IDs to run (None = all scenarios)
            parallel: Whether to run scenarios in parallel

        Returns:
            Aggregated test suite results
        """
        start_time = datetime.now()

        # Determine which scenarios to run
        if scenario_ids is None:
            scenario_ids = list(self.scenarios.keys())

        # Sort by priority (lowest number = highest priority)
        sorted_ids = sorted(
            scenario_ids,
            key=lambda sid: self.scenarios[sid]().priority,
        )

        logger.info(f"Running {len(sorted_ids)} scenarios")

        # Run scenarios
        if parallel:
            # Run all scenarios concurrently
            tasks = [self.run_scenario(sid) for sid in sorted_ids]
            await asyncio.gather(*tasks, return_exceptions=True)
        else:
            # Run scenarios sequentially
            for scenario_id in sorted_ids:
                await self.run_scenario(scenario_id)

        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()

        # Create suite result
        suite_result = TestSuiteResult(
            start_time=start_time,
            end_time=end_time,
            total_duration_seconds=duration,
            test_results=self.results,
            metadata={
                "parallel": parallel,
                "total_scenarios": len(sorted_ids),
            },
        )

        logger.info(f"Test suite complete: {suite_result}")
        return suite_result

    async def run_all(self, parallel: bool = False) -> TestSuiteResult:
        """Run all registered scenarios.

        Args:
            parallel: Whether to run scenarios in parallel

        Returns:
            Aggregated test suite results
        """
        return await self.run_scenarios(scenario_ids=None, parallel=parallel)

    def clear_results(self) -> None:
        """Clear collected test results."""
        self.results = []
        logger.debug("Cleared test results")


class TestRunnerConfig:
    """Configuration for test runner behavior.

    Attributes:
        test_timeout_seconds: Default timeout for tests
        cleanup_on_failure: Whether to run cleanup even on test failure
        capture_diagnostics_on_failure: Capture diagnostic snapshot on failure
        diagnostics_dir: Directory for diagnostic snapshots
        log_level: Logging level
        tmux_session_prefix: Prefix for tmux test sessions
        test_project_prefix: Prefix for test projects
    """

    def __init__(
        self,
        test_timeout_seconds: float = 30.0,
        cleanup_on_failure: bool = True,
        capture_diagnostics_on_failure: bool = False,
        diagnostics_dir: Optional[Path] = None,
        log_level: str = "INFO",
        tmux_session_prefix: str = "i3-project-test-",
        test_project_prefix: str = "test-",
    ):
        """Initialize test runner configuration.

        Args:
            test_timeout_seconds: Default timeout for tests
            cleanup_on_failure: Whether to run cleanup on failure
            capture_diagnostics_on_failure: Capture diagnostics on failure
            diagnostics_dir: Directory for diagnostic snapshots
            log_level: Logging level
            tmux_session_prefix: Prefix for tmux sessions
            test_project_prefix: Prefix for test projects
        """
        self.test_timeout_seconds = test_timeout_seconds
        self.cleanup_on_failure = cleanup_on_failure
        self.capture_diagnostics_on_failure = capture_diagnostics_on_failure
        self.diagnostics_dir = diagnostics_dir or Path.home() / ".local/share/i3-project-test/diagnostics"
        self.log_level = log_level
        self.tmux_session_prefix = tmux_session_prefix
        self.test_project_prefix = test_project_prefix

    @classmethod
    def from_file(cls, config_path: Path) -> "TestRunnerConfig":
        """Load configuration from JSON file.

        Args:
            config_path: Path to configuration file

        Returns:
            TestRunnerConfig instance

        Raises:
            FileNotFoundError: If config file doesn't exist
            ValueError: If config file is invalid
        """
        import json

        if not config_path.exists():
            raise FileNotFoundError(f"Config file not found: {config_path}")

        try:
            with open(config_path) as f:
                data = json.load(f)

            return cls(
                test_timeout_seconds=data.get("test_timeout_seconds", 30.0),
                cleanup_on_failure=data.get("cleanup_on_failure", True),
                capture_diagnostics_on_failure=data.get("capture_diagnostics_on_failure", False),
                diagnostics_dir=Path(data["diagnostics_dir"]) if "diagnostics_dir" in data else None,
                log_level=data.get("log_level", "INFO"),
                tmux_session_prefix=data.get("tmux_session_prefix", "i3-project-test-"),
                test_project_prefix=data.get("test_project_prefix", "test-"),
            )

        except (json.JSONDecodeError, KeyError) as e:
            raise ValueError(f"Invalid config file: {e}")

    @classmethod
    def default(cls) -> "TestRunnerConfig":
        """Create default configuration.

        Returns:
            TestRunnerConfig with default values
        """
        return cls()
