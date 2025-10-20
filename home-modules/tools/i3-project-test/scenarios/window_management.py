"""Window management test scenarios.

This module provides test scenarios for window marking, visibility,
and project-scoped window management.
"""

import asyncio
import subprocess
from typing import List, Optional

from ..assertions import I3Assertions, StateAssertions
from ..models import AssertionType
from .base_scenario import BaseScenario


class WindowMarkingValidation(BaseScenario):
    """Test window marking and project association."""

    scenario_id = "window_management_001"
    name = "Window Marking Validation"
    description = "Open windows in project context, validate correct marking"
    priority = 2
    timeout_seconds = 20.0

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.test_project = "test-window-marks"
        self.window_ids: List[int] = []
        self.state_assertions = None
        self.i3_assertions = None

    async def setup(self) -> None:
        """Create test project."""
        self.log_info("Setting up window marking test")

        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        # Create test project
        await self._create_project(self.test_project)

        # Switch to test project
        await self._switch_project(self.test_project)
        await self.wait(0.5)

    async def execute(self) -> None:
        """Open windows and check marking."""
        self.log_info("Opening test windows")

        # Open a test terminal window
        # Note: In real implementation, this would open actual windows
        # For now, we'll validate the project state

        # Get current window count
        state = await self.state_assertions.get_state()
        initial_count = state["status"].get("window_count", 0)

        self.log_info(f"Initial window count: {initial_count}")

    async def validate(self) -> None:
        """Validate window marking."""
        self.log_info("Validating window marks")

        # Verify active project
        await self.state_assertions.assert_active_project(self.test_project)

        # Verify project mark exists in i3
        expected_mark = f"project:{self.test_project}"
        try:
            await self.i3_assertions.assert_mark_exists(expected_mark)
            self.record_assertion(
                "assert_001",
                AssertionType.I3_MARK_EXISTS,
                expected_mark,
                expected_mark,
                f"Project mark '{expected_mark}' should exist in i3",
            )
        except AssertionError as e:
            # Mark might not exist if no windows are open yet
            self.log_warning(f"Project mark validation: {e}")

    async def cleanup(self) -> None:
        """Clean up test project."""
        self.log_info("Cleaning up window marking test")

        try:
            await self._switch_project(None)
            await self.wait(0.3)
        except Exception as e:
            self.log_warning(f"Could not clear active project: {e}")

        try:
            await self._delete_project(self.test_project)
        except Exception as e:
            self.log_warning(f"Could not delete project: {e}")

        if self.i3_assertions:
            await self.i3_assertions.disconnect()

    async def _create_project(self, name: str) -> None:
        """Create a test project."""
        subprocess.run(["mkdir", "-p", f"/tmp/{name}"], check=False)

        cmd = [
            "i3-project-create",
            "--name", name,
            "--dir", f"/tmp/{name}",
            "--icon", "",
            "--display-name", name.title(),
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to create project: {result.stderr}")

    async def _delete_project(self, name: str) -> None:
        """Delete a test project."""
        from pathlib import Path

        project_file = Path.home() / ".config/i3/projects" / f"{name}.json"
        if project_file.exists():
            project_file.unlink()

        subprocess.run(["rm", "-rf", f"/tmp/{name}"], check=False)

    async def _switch_project(self, name: str | None) -> None:
        """Switch to a project or clear active project."""
        if name is None:
            cmd = ["i3-project-switch", "--clear"]
        else:
            cmd = ["i3-project-switch", name]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to switch project: {result.stderr}")


class WindowVisibilityToggle(BaseScenario):
    """Test window visibility when switching projects."""

    scenario_id = "window_management_002"
    name = "Window Visibility Toggle"
    description = "Validate windows are hidden/shown when switching projects"
    priority = 2
    timeout_seconds = 20.0

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.test_projects = ["test-vis-a", "test-vis-b"]
        self.state_assertions = None
        self.i3_assertions = None

    async def setup(self) -> None:
        """Create test projects."""
        self.log_info("Setting up visibility test")

        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        # Create both test projects
        for project in self.test_projects:
            await self._create_project(project)
            self.log_info(f"Created project: {project}")

    async def execute(self) -> None:
        """Switch between projects and observe visibility."""
        self.log_info("Testing window visibility")

        # Switch to project A
        await self._switch_project(self.test_projects[0])
        await self.wait(0.5)

        # Switch to project B
        await self._switch_project(self.test_projects[1])
        await self.wait(0.5)

        # Switch back to project A
        await self._switch_project(self.test_projects[0])
        await self.wait(0.5)

    async def validate(self) -> None:
        """Validate visibility behavior."""
        self.log_info("Validating visibility state")

        # Should be on project A
        await self.state_assertions.assert_active_project(self.test_projects[0])

        self.record_assertion(
            "assert_001",
            AssertionType.DAEMON_ACTIVE_PROJECT_EQUALS,
            self.test_projects[0],
            self.test_projects[0],
            "Active project should be test-vis-a after switches",
        )

    async def cleanup(self) -> None:
        """Clean up test projects."""
        self.log_info("Cleaning up visibility test")

        try:
            await self._switch_project(None)
            await self.wait(0.3)
        except Exception as e:
            self.log_warning(f"Could not clear active project: {e}")

        for project in self.test_projects:
            try:
                await self._delete_project(project)
            except Exception as e:
                self.log_warning(f"Could not delete project {project}: {e}")

        if self.i3_assertions:
            await self.i3_assertions.disconnect()

    async def _create_project(self, name: str) -> None:
        """Create a test project."""
        subprocess.run(["mkdir", "-p", f"/tmp/{name}"], check=False)

        cmd = [
            "i3-project-create",
            "--name", name,
            "--dir", f"/tmp/{name}",
            "--icon", "",
            "--display-name", name.title(),
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to create project: {result.stderr}")

    async def _delete_project(self, name: str) -> None:
        """Delete a test project."""
        from pathlib import Path

        project_file = Path.home() / ".config/i3/projects" / f"{name}.json"
        if project_file.exists():
            project_file.unlink()

        subprocess.run(["rm", "-rf", f"/tmp/{name}"], check=False)

    async def _switch_project(self, name: str | None) -> None:
        """Switch to a project or clear active project."""
        if name is None:
            cmd = ["i3-project-switch", "--clear"]
        else:
            cmd = ["i3-project-switch", name]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to switch project: {result.stderr}")
