"""Project lifecycle test scenarios.

This module provides test scenarios for project creation, deletion,
and switching workflows.
"""

import asyncio
import subprocess
from typing import List

from ..assertions import I3Assertions, StateAssertions
from ..models import AssertionType
from .base_scenario import BaseScenario


class ProjectLifecycleBasic(BaseScenario):
    """Test basic project lifecycle: create, switch, delete."""

    scenario_id = "project_lifecycle_001"
    name = "Basic Project Lifecycle"
    description = "Create two test projects, switch between them, validate state changes"
    priority = 1
    timeout_seconds = 15.0

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.test_projects = ["test-proj-a", "test-proj-b"]
        self.state_assertions = None
        self.i3_assertions = None

    async def setup(self) -> None:
        """Create test projects."""
        self.log_info("Creating test projects")

        # Initialize assertion helpers
        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        # Create test projects
        for project in self.test_projects:
            await self._create_project(project)
            self.log_info(f"Created project: {project}")

    async def execute(self) -> None:
        """Switch between projects."""
        self.log_info("Switching between projects")

        # Switch to project A
        await self._switch_project(self.test_projects[0])
        await self.wait(0.5)  # Allow event processing

        # Switch to project B
        await self._switch_project(self.test_projects[1])
        await self.wait(0.5)  # Allow event processing

    async def validate(self) -> None:
        """Validate active project and state consistency."""
        self.log_info("Validating project state")

        # Assert active project is B
        await self.state_assertions.assert_active_project(self.test_projects[1])
        self.record_assertion(
            "assert_001",
            AssertionType.DAEMON_ACTIVE_PROJECT_EQUALS,
            self.test_projects[1],
            self.test_projects[1],
            "Active project should be test-proj-b",
        )

        # Assert both projects exist
        await self.state_assertions.assert_project_exists(self.test_projects[0])
        await self.state_assertions.assert_project_exists(self.test_projects[1])

        # Assert daemon is connected
        await self.state_assertions.assert_daemon_running()
        await self.state_assertions.assert_daemon_connected()

    async def cleanup(self) -> None:
        """Delete test projects."""
        self.log_info("Cleaning up test projects")

        # Clear active project first
        try:
            await self._switch_project(None)
            await self.wait(0.3)
        except Exception as e:
            self.log_warning(f"Could not clear active project: {e}")

        # Delete test projects
        for project in self.test_projects:
            try:
                await self._delete_project(project)
                self.log_info(f"Deleted project: {project}")
            except Exception as e:
                self.log_warning(f"Could not delete project {project}: {e}")

        # Disconnect from i3
        if self.i3_assertions:
            await self.i3_assertions.disconnect()

    # Helper methods

    async def _create_project(self, name: str) -> None:
        """Create a test project.

        Args:
            name: Project name
        """
        cmd = [
            "i3-project-create",
            "--name", name,
            "--dir", f"/tmp/{name}",
            "--icon", "",
            "--display-name", name.title(),
        ]

        # Create directory first
        subprocess.run(["mkdir", "-p", f"/tmp/{name}"], check=False)

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to create project: {result.stderr}")

    async def _delete_project(self, name: str) -> None:
        """Delete a test project.

        Args:
            name: Project name
        """
        # Delete project configuration
        import json
        from pathlib import Path

        project_dir = Path.home() / ".config/i3/projects"
        project_file = project_dir / f"{name}.json"

        if project_file.exists():
            project_file.unlink()

        # Clean up temp directory
        subprocess.run(["rm", "-rf", f"/tmp/{name}"], check=False)

    async def _switch_project(self, name: str | None) -> None:
        """Switch to a project or clear active project.

        Args:
            name: Project name or None to clear
        """
        if name is None:
            cmd = ["i3-project-switch", "--clear"]
        else:
            cmd = ["i3-project-switch", name]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to switch project: {result.stderr}")


class ProjectSwitchMultiple(BaseScenario):
    """Test switching between multiple projects rapidly."""

    scenario_id = "project_lifecycle_002"
    name = "Multiple Project Switches"
    description = "Rapidly switch between 3 projects and validate state consistency"
    priority = 2
    timeout_seconds = 20.0

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.test_projects = ["test-multi-1", "test-multi-2", "test-multi-3"]
        self.state_assertions = None
        self.i3_assertions = None

    async def setup(self) -> None:
        """Create test projects."""
        self.log_info("Creating test projects")

        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        # Create test projects
        for project in self.test_projects:
            await self._create_project(project)
            self.log_info(f"Created project: {project}")

    async def execute(self) -> None:
        """Perform multiple rapid switches."""
        self.log_info("Performing multiple switches")

        for i, project in enumerate(self.test_projects):
            self.log_debug(f"Switch {i+1}: {project}")
            await self._switch_project(project)
            await self.wait(0.2)  # Short delay between switches

    async def validate(self) -> None:
        """Validate final state."""
        self.log_info("Validating final state")

        # Should end on last project
        expected = self.test_projects[-1]
        await self.state_assertions.assert_active_project(expected)

        self.record_assertion(
            "assert_001",
            AssertionType.DAEMON_ACTIVE_PROJECT_EQUALS,
            expected,
            expected,
            f"Active project should be {expected}",
        )

        # All projects should exist
        for project in self.test_projects:
            await self.state_assertions.assert_project_exists(project)

    async def cleanup(self) -> None:
        """Delete test projects."""
        self.log_info("Cleaning up test projects")

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
