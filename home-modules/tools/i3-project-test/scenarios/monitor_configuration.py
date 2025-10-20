"""Monitor configuration test scenarios.

This module provides test scenarios for validating monitor/output
configuration and workspace-to-output assignments.
"""

import asyncio
from typing import Dict, List

from ..assertions import I3Assertions, OutputAssertions, StateAssertions
from ..models import AssertionType
from .base_scenario import BaseScenario


class WorkspaceAssignmentValidation(BaseScenario):
    """Test workspace-to-output assignment validation."""

    scenario_id = "monitor_config_001"
    name = "Workspace Assignment Validation"
    description = "Validate all workspaces are assigned to active outputs"
    priority = 2
    timeout_seconds = 10.0

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.state_assertions = None
        self.i3_assertions = None
        self.output_assertions = None
        self.initial_outputs = None

    async def setup(self) -> None:
        """Set up assertions and capture initial state."""
        self.log_info("Setting up workspace assignment validation")

        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        self.output_assertions = OutputAssertions(
            self.state_assertions,
            self.i3_assertions,
        )

        # Capture initial output configuration
        self.initial_outputs = await self.i3_assertions.get_outputs()
        self.log_info(f"Found {len(self.initial_outputs)} outputs")

    async def execute(self) -> None:
        """Query current workspace assignments."""
        self.log_info("Querying workspace assignments")

        # Get workspace assignments
        workspaces = await self.i3_assertions.get_workspaces()
        self.log_info(f"Found {len(workspaces)} workspaces")

        for ws in workspaces:
            if ws["visible"]:
                self.log_debug(
                    f"Workspace {ws['name']} on output {ws['output']} (visible)"
                )

    async def validate(self) -> None:
        """Validate workspace assignments are correct."""
        self.log_info("Validating workspace assignments")

        # Assert all workspace assignments are valid
        try:
            await self.output_assertions.assert_workspace_assignment_valid()

            self.record_assertion(
                "assert_001",
                AssertionType.WORKSPACE_ASSIGNMENT_VALID,
                True,
                True,
                "All workspaces should be assigned to active outputs",
            )
        except AssertionError as e:
            self.record_assertion(
                "assert_001",
                AssertionType.WORKSPACE_ASSIGNMENT_VALID,
                True,
                False,
                str(e),
            )
            raise

        # Get output summary
        summary = await self.output_assertions.get_output_summary()
        self.log_info(
            f"Active outputs: {summary['active_output_count']}/{summary['total_output_count']}"
        )

    async def cleanup(self) -> None:
        """Disconnect from i3."""
        self.log_info("Cleaning up workspace assignment validation")

        if self.i3_assertions:
            await self.i3_assertions.disconnect()


class DaemonI3StateConsistency(BaseScenario):
    """Test consistency between daemon and i3 state."""

    scenario_id = "monitor_config_002"
    name = "Daemon/i3 State Consistency"
    description = "Validate daemon state matches i3 IPC state"
    priority = 2
    timeout_seconds = 10.0

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.state_assertions = None
        self.i3_assertions = None
        self.output_assertions = None

    async def setup(self) -> None:
        """Set up assertions."""
        self.log_info("Setting up state consistency test")

        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        self.output_assertions = OutputAssertions(
            self.state_assertions,
            self.i3_assertions,
        )

    async def execute(self) -> None:
        """Query both daemon and i3 state."""
        self.log_info("Querying daemon and i3 state")

        # Get daemon state
        daemon_state = await self.state_assertions.get_state()
        self.log_info(f"Daemon window count: {daemon_state['status'].get('window_count', 0)}")

        # Get i3 state
        i3_workspaces = await self.i3_assertions.get_workspaces()
        i3_outputs = await self.i3_assertions.get_outputs()
        self.log_info(f"i3 workspaces: {len(i3_workspaces)}, outputs: {len(i3_outputs)}")

    async def validate(self) -> None:
        """Validate state consistency."""
        self.log_info("Validating state consistency")

        # Assert daemon and i3 states match
        try:
            await self.output_assertions.assert_daemon_i3_state_match()

            self.record_assertion(
                "assert_001",
                AssertionType.DAEMON_I3_STATE_MATCH,
                True,
                True,
                "Daemon and i3 states should be consistent",
            )
        except AssertionError as e:
            self.record_assertion(
                "assert_001",
                AssertionType.DAEMON_I3_STATE_MATCH,
                True,
                False,
                str(e),
            )
            raise

    async def cleanup(self) -> None:
        """Disconnect from i3."""
        self.log_info("Cleaning up state consistency test")

        if self.i3_assertions:
            await self.i3_assertions.disconnect()


class OutputCountValidation(BaseScenario):
    """Test output count validation."""

    scenario_id = "monitor_config_003"
    name = "Output Count Validation"
    description = "Validate expected number of active outputs"
    priority = 3
    timeout_seconds = 10.0
    requires_xrandr = True

    def __init__(self):
        """Initialize scenario."""
        super().__init__()
        self.state_assertions = None
        self.i3_assertions = None
        self.output_assertions = None
        self.active_output_count = 0

    async def setup(self) -> None:
        """Set up assertions and detect outputs."""
        self.log_info("Setting up output count validation")

        from i3_project_monitor.daemon_client import DaemonClient
        daemon_client = DaemonClient()
        self.state_assertions = StateAssertions(daemon_client)
        self.i3_assertions = I3Assertions()
        await self.i3_assertions.connect()

        self.output_assertions = OutputAssertions(
            self.state_assertions,
            self.i3_assertions,
        )

        # Detect current active outputs
        outputs = await self.i3_assertions.get_outputs()
        self.active_output_count = sum(1 for o in outputs if o["active"])
        self.log_info(f"Detected {self.active_output_count} active outputs")

    async def execute(self) -> None:
        """Query output configuration."""
        self.log_info("Querying output configuration")

        outputs = await self.i3_assertions.get_outputs()
        for output in outputs:
            status = "active" if output["active"] else "inactive"
            self.log_debug(f"Output {output['name']}: {status}")

    async def validate(self) -> None:
        """Validate output count matches detected count."""
        self.log_info("Validating output count")

        # Assert output count matches what we detected in setup
        try:
            await self.output_assertions.assert_output_count(self.active_output_count)

            self.record_assertion(
                "assert_001",
                AssertionType.I3_OUTPUT_ACTIVE,
                self.active_output_count,
                self.active_output_count,
                f"Should have {self.active_output_count} active outputs",
            )
        except AssertionError as e:
            self.record_assertion(
                "assert_001",
                AssertionType.I3_OUTPUT_ACTIVE,
                self.active_output_count,
                0,  # Will be filled with actual
                str(e),
            )
            raise

    async def cleanup(self) -> None:
        """Disconnect from i3."""
        self.log_info("Cleaning up output count validation")

        if self.i3_assertions:
            await self.i3_assertions.disconnect()
