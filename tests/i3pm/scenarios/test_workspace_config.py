"""Test scenario: Workspace configuration workflow.

Tests workspace-to-monitor assignment configuration:
- View current monitor configuration
- Assign workspaces to monitor roles
- Validate assignments against current monitor count
- Manually trigger workspace redistribution
"""

import pytest
from pathlib import Path
import sys
import json

# Add paths
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools" / "i3_project_manager"))
specs_path = Path(__file__).parent.parent.parent.parent / "specs" / "022-create-a-new"
if str(specs_path) not in sys.path:
    sys.path.insert(0, str(specs_path))

from testing.framework import TestFramework
from contracts.test_framework import (
    TestScenario,
    TestAction,
    TestAssertion
)


def create_workspace_config_scenario(config_dir: Path) -> TestScenario:
    """Create test scenario for workspace configuration.

    Args:
        config_dir: Test configuration directory

    Returns:
        TestScenario: Complete test scenario
    """
    project_file = config_dir / "projects" / "test-project.json"

    return TestScenario(
        name="workspace_config_workflow",
        description="User configures workspace-to-monitor assignments for a project",
        preconditions=[
            "Project 'test-project' exists",
            "2 monitors connected (primary + secondary)",
            "Default workspace distribution active"
        ],
        actions=[
            # Navigate to workspace configuration
            TestAction.press_key("w", "Open workspace configuration"),
            TestAction.wait(0.5, "Wait for screen transition"),

            # Assign workspaces to monitors
            # WS 1-2 -> primary
            # WS 3-4 -> secondary
            TestAction.type_text("1:primary", "Assign WS1 to primary"),
            TestAction.press_key("enter"),
            TestAction.wait(0.2),

            TestAction.type_text("2:primary", "Assign WS2 to primary"),
            TestAction.press_key("enter"),
            TestAction.wait(0.2),

            TestAction.type_text("3:secondary", "Assign WS3 to secondary"),
            TestAction.press_key("enter"),
            TestAction.wait(0.2),

            TestAction.type_text("4:secondary", "Assign WS4 to secondary"),
            TestAction.press_key("enter"),
            TestAction.wait(0.2),

            # Save configuration
            TestAction.press_key("s", "Save workspace configuration"),
            TestAction.wait(1.0, "Wait for save operation"),

            # Return to browser
            TestAction.press_key("escape", "Return to browser"),
        ],
        assertions=[
            # Project file updated with workspace preferences
            TestAssertion.file_exists(
                str(project_file),
                "Project file exists"
            ),

            # Configuration save completed quickly
            TestAssertion.timing(
                "workspace_config_save",
                2.0,
                "Workspace config save completed within 2 seconds"
            ),

            # Additional assertions would verify:
            # - workspace_preferences in project JSON
            # - Correct assignments stored
            # These require file content inspection
        ],
        timeout=10.0,
        cleanup=[
            TestAction.press_key("escape", "Ensure returned to browser"),
        ],
        tags=["workspace", "config", "priority-p1", "us2"]
    )


@pytest.mark.tui
@pytest.mark.asyncio
async def test_workspace_config_workflow(isolated_test_env):
    """Test workspace configuration workflow."""
    env = isolated_test_env
    config_dir = env["config_dir"]

    scenario = create_workspace_config_scenario(config_dir)

    framework = TestFramework()
    result = await framework.execute_scenario(scenario)

    print(f"\nScenario: {result.scenario_name}")
    print(f"  Actions executed: {result.actions_executed}")
    print(f"  Assertions: {result.assertions_passed} passed, {result.assertions_failed} failed")
    print(f"  Duration: {result.duration:.2f}s")

    if not result.passed:
        print("  Failed assertions:")
        for assertion_result in result.assertion_results:
            if not assertion_result.passed:
                print(f"    - {assertion_result.assertion.description}")

    # Verify project file was updated (in isolated test env)
    project_file = config_dir / "projects" / "test-project.json"
    if project_file.exists():
        with open(project_file) as f:
            project_data = json.load(f)
            print(f"  Project workspace_preferences: {project_data.get('workspace_preferences', {})}")


@pytest.mark.tui
@pytest.mark.asyncio
async def test_workspace_validation_workflow(isolated_test_env):
    """Test workspace configuration validation with insufficient monitors."""
    env = isolated_test_env

    scenario = TestScenario(
        name="workspace_validation",
        description="User assigns workspace to tertiary monitor but only has 2 monitors",
        preconditions=[
            "Project 'test-project' exists",
            "Only 2 monitors connected"
        ],
        actions=[
            TestAction.press_key("w", "Open workspace configuration"),
            TestAction.wait(0.5),

            # Try to assign to tertiary (should show warning)
            TestAction.type_text("6:tertiary", "Assign WS6 to tertiary"),
            TestAction.press_key("enter"),
            TestAction.wait(0.5),

            # Save (should show validation warning)
            TestAction.press_key("s", "Save with warning"),
            TestAction.wait(1.0),
        ],
        assertions=[
            # Would verify warning message displayed
            # Would verify configuration still saved with warning
            TestAssertion.timing(
                "workspace_validation",
                2.0,
                "Validation completed within 2 seconds"
            )
        ],
        timeout=10.0,
        tags=["workspace", "validation", "priority-p1", "us2"]
    )

    framework = TestFramework()
    result = await framework.execute_scenario(scenario)

    print(f"\nScenario: {result.scenario_name}")
    print(f"  Status: {'PASSED' if result.passed else 'FAILED'}")


@pytest.mark.tui
@pytest.mark.asyncio
async def test_workspace_redistribution_workflow(isolated_test_env):
    """Test manual workspace redistribution."""
    env = isolated_test_env

    scenario = TestScenario(
        name="workspace_redistribution",
        description="User manually triggers workspace redistribution after monitor change",
        preconditions=[
            "Project 'test-project' exists with workspace preferences",
            "Monitor configuration changed (connected/disconnected)"
        ],
        actions=[
            # Open monitor dashboard
            TestAction.press_key("m", "Open monitor dashboard"),
            TestAction.wait(0.5),

            # Trigger redistribution
            TestAction.press_key("r", "Trigger workspace redistribution"),
            TestAction.wait(0.5),

            # Choose "use project preferences"
            TestAction.press_key("enter", "Confirm use project preferences"),
            TestAction.wait(1.0, "Wait for redistribution"),
        ],
        assertions=[
            # Redistribution completed within 1 second (SC-010)
            TestAssertion.timing(
                "workspace_redistribution",
                1.0,
                "Workspace redistribution completed within 1 second"
            ),

            # Would verify:
            # - Workspaces moved to correct outputs
            # - Summary message shown
        ],
        timeout=10.0,
        tags=["workspace", "redistribution", "priority-p2", "us8"]
    )

    framework = TestFramework()
    result = await framework.execute_scenario(scenario)

    print(f"\nScenario: {result.scenario_name}")
    print(f"  Duration: {result.duration:.2f}s")
    print(f"  Status: {'PASSED' if result.passed else 'FAILED'}")


@pytest.mark.tui
@pytest.mark.asyncio
async def test_monitor_detection_workflow(isolated_test_env):
    """Test monitor detection and automatic redistribution."""
    env = isolated_test_env

    scenario = TestScenario(
        name="monitor_detection",
        description="System detects monitor change and offers redistribution",
        preconditions=[
            "2 monitors initially connected",
            "Mock i3 connection available"
        ],
        actions=[
            # Simulate monitor connection (in real test, would trigger i3 event)
            TestAction.wait(0.5, "Simulate monitor detection"),

            # Monitor dashboard should update automatically
            TestAction.press_key("m", "Open monitor dashboard"),
            TestAction.wait(0.5),

            # Verify new monitor shown
            # (In real test, would check DataTable row count)
        ],
        assertions=[
            # Monitor dashboard updates within 1 second (SC-010)
            TestAssertion.timing(
                "monitor_detection",
                1.0,
                "Monitor dashboard updated within 1 second"
            ),

            # Would verify:
            # - New monitor visible in table
            # - Redistribution preview shown
        ],
        timeout=10.0,
        tags=["monitor", "detection", "priority-p2", "us8"]
    )

    framework = TestFramework()
    result = await framework.execute_scenario(scenario)

    print(f"\nScenario: {result.scenario_name}")
    print(f"  Duration: {result.duration:.2f}s")
    print(f"  Status: {'PASSED' if result.passed else 'FAILED'}")
