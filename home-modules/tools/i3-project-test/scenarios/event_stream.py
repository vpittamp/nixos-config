"""Event stream test scenarios.

This module provides test scenarios for validating event recording,
ordering, and buffer management.
"""

import asyncio
import subprocess

from ..assertions import I3Assertions, StateAssertions
from ..models import AssertionType
from .base_scenario import BaseScenario


class EventBufferValidation(BaseScenario):
    """Test event buffer recording and retrieval."""

    scenario_id = "event_stream_001"
    name = "Event Buffer Validation"
    description = "Validate events are recorded correctly in daemon buffer"
    priority = 2
    timeout_seconds = 15.0

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.test_project = "test-events"
        self.state_assertions = None
        self.i3_assertions = None
        self.initial_event_count = 0

    async def setup(self) -> None:
        """Set up assertions and capture initial state."""
        self.log_info("Setting up event buffer validation")

        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        # Get initial event count
        state = await self.state_assertions.get_state()
        self.initial_event_count = state["status"].get("event_count", 0)
        self.log_info(f"Initial event count: {self.initial_event_count}")

        # Create test project
        await self._create_project(self.test_project)

    async def execute(self) -> None:
        """Perform actions that generate events."""
        self.log_info("Generating events")

        # Switch to project (generates tick event)
        await self._switch_project(self.test_project)
        await self.wait(0.5)

        # Switch away (generates another tick event)
        await self._switch_project(None)
        await self.wait(0.5)

    async def validate(self) -> None:
        """Validate events were recorded."""
        self.log_info("Validating event recording")

        # Get current event count
        state = await self.state_assertions.get_state()
        current_event_count = state["status"].get("event_count", 0)

        self.log_info(f"Current event count: {current_event_count}")

        # Assert event count increased
        if current_event_count <= self.initial_event_count:
            self.record_assertion(
                "assert_001",
                AssertionType.EVENT_BUFFER_COUNT_EQUALS,
                f"> {self.initial_event_count}",
                current_event_count,
                "Event count should have increased",
            )
            raise AssertionError(
                f"Expected event count to increase from {self.initial_event_count}, "
                f"but got {current_event_count}"
            )

        self.record_assertion(
            "assert_001",
            AssertionType.EVENT_BUFFER_COUNT_EQUALS,
            f"> {self.initial_event_count}",
            current_event_count,
            "Event count increased as expected",
        )

    async def cleanup(self) -> None:
        """Clean up test project."""
        self.log_info("Cleaning up event buffer validation")

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


class EventOrderingValidation(BaseScenario):
    """Test event ordering and sequencing."""

    scenario_id = "event_stream_002"
    name = "Event Ordering Validation"
    description = "Validate events are recorded in correct chronological order"
    priority = 3
    timeout_seconds = 15.0

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.test_project = "test-event-order"
        self.state_assertions = None
        self.i3_assertions = None

    async def setup(self) -> None:
        """Set up test project."""
        self.log_info("Setting up event ordering validation")

        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        # Create test project
        await self._create_project(self.test_project)

    async def execute(self) -> None:
        """Perform ordered sequence of actions."""
        self.log_info("Performing ordered actions")

        # Action 1: Switch to project
        await self._switch_project(self.test_project)
        await self.wait(0.3)

        # Action 2: Switch away
        await self._switch_project(None)
        await self.wait(0.3)

        # Action 3: Switch back
        await self._switch_project(self.test_project)
        await self.wait(0.3)

    async def validate(self) -> None:
        """Validate event ordering."""
        self.log_info("Validating event ordering")

        # Verify final state is correct
        await self.state_assertions.assert_active_project(self.test_project)

        self.record_assertion(
            "assert_001",
            AssertionType.DAEMON_ACTIVE_PROJECT_EQUALS,
            self.test_project,
            self.test_project,
            "Final active project should match last switch action",
        )

    async def cleanup(self) -> None:
        """Clean up test project."""
        self.log_info("Cleaning up event ordering validation")

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
