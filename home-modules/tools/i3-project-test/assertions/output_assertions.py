"""Output/workspace validation assertions for test scenarios.

This module provides assertions for validating monitor configuration and
workspace-to-output assignments, ensuring daemon state matches i3 state.
"""

import logging
from typing import Any, Dict, List

from .i3_assertions import I3Assertions
from .state_assertions import StateAssertions


logger = logging.getLogger(__name__)


class OutputAssertions:
    """Assertions for output/workspace validation."""

    def __init__(
        self,
        state_assertions: StateAssertions,
        i3_assertions: I3Assertions,
    ):
        """Initialize output assertions.

        Args:
            state_assertions: Daemon state assertions instance
            i3_assertions: i3 IPC assertions instance
        """
        self.state_assertions = state_assertions
        self.i3_assertions = i3_assertions

    async def assert_workspace_assignment_valid(self) -> None:
        """Assert all workspaces are assigned to active outputs.

        Validates that every visible workspace is assigned to an active output
        according to i3 IPC data.

        Raises:
            AssertionError: If any workspace is assigned to inactive output
        """
        workspaces = await self.i3_assertions.get_workspaces()
        outputs = await self.i3_assertions.get_outputs()

        # Build map of active outputs
        active_outputs = {o["name"] for o in outputs if o["active"]}

        # Check each visible workspace
        invalid_assignments = []
        for workspace in workspaces:
            if workspace["visible"]:
                output = workspace["output"]
                if output not in active_outputs:
                    invalid_assignments.append(
                        f"Workspace '{workspace['name']}' assigned to inactive output '{output}'"
                    )

        if invalid_assignments:
            raise AssertionError(
                f"Invalid workspace assignments:\n" +
                "\n".join(f"  - {a}" for a in invalid_assignments)
            )

        logger.info("✓ All workspace assignments are valid")

    async def assert_daemon_i3_state_match(self) -> None:
        """Assert that daemon state matches i3 IPC state.

        Validates consistency between daemon's view of the world and
        i3's authoritative state.

        Raises:
            AssertionError: If states don't match
        """
        # Get daemon state
        daemon_state = await self.state_assertions.get_state()

        # Get i3 state
        i3_workspaces = await self.i3_assertions.get_workspaces()
        i3_marks = await self.i3_assertions.get_marks()

        mismatches = []

        # Check active project mark exists in i3
        active_project = daemon_state["status"].get("active_project")
        if active_project:
            expected_mark = f"project:{active_project}"
            if expected_mark not in i3_marks:
                mismatches.append(
                    f"Active project '{active_project}' mark not found in i3 marks"
                )

        # Check window count consistency
        daemon_window_count = daemon_state["status"].get("window_count", 0)
        i3_tree = await self.i3_assertions.get_tree()
        i3_window_count = self._count_windows_in_tree(i3_tree)

        # Note: Daemon may track fewer windows (only project-scoped ones)
        # so we check daemon_count <= i3_count
        if daemon_window_count > i3_window_count:
            mismatches.append(
                f"Daemon tracking {daemon_window_count} windows, "
                f"but i3 only has {i3_window_count}"
            )

        if mismatches:
            raise AssertionError(
                f"Daemon and i3 state mismatch:\n" +
                "\n".join(f"  - {m}" for m in mismatches)
            )

        logger.info("✓ Daemon and i3 states match")

    async def assert_all_outputs_active(self, expected_outputs: List[str]) -> None:
        """Assert that all expected outputs are active.

        Args:
            expected_outputs: List of output names that should be active

        Raises:
            AssertionError: If any expected output is not active
        """
        outputs = await self.i3_assertions.get_outputs()
        active_outputs = {o["name"] for o in outputs if o["active"]}

        missing = set(expected_outputs) - active_outputs
        if missing:
            raise AssertionError(
                f"Expected outputs not active: {missing}. "
                f"Active outputs: {active_outputs}"
            )

        logger.info(f"✓ All expected outputs are active: {expected_outputs}")

    async def assert_output_count(self, expected: int) -> None:
        """Assert that the number of active outputs matches expected.

        Args:
            expected: Expected number of active outputs

        Raises:
            AssertionError: If output count doesn't match
        """
        outputs = await self.i3_assertions.get_outputs()
        active_outputs = [o for o in outputs if o["active"]]
        actual = len(active_outputs)

        if actual != expected:
            output_names = [o["name"] for o in active_outputs]
            raise AssertionError(
                f"Expected {expected} active outputs, got {actual}. "
                f"Active outputs: {output_names}"
            )

        logger.info(f"✓ Output count is {expected}")

    async def assert_workspace_on_correct_output(
        self,
        workspace_num: int,
        expected_output: str,
    ) -> None:
        """Assert that a workspace is on the correct output.

        Args:
            workspace_num: Workspace number
            expected_output: Expected output name

        Raises:
            AssertionError: If workspace is on wrong output
        """
        workspaces = await self.i3_assertions.get_workspaces()
        workspace = next((w for w in workspaces if w["num"] == workspace_num), None)

        if workspace is None:
            raise AssertionError(f"Workspace {workspace_num} not found")

        actual_output = workspace["output"]
        if actual_output != expected_output:
            raise AssertionError(
                f"Expected workspace {workspace_num} on output '{expected_output}', "
                f"but it's on '{actual_output}'"
            )

        logger.info(
            f"✓ Workspace {workspace_num} is on correct output '{expected_output}'"
        )

    async def get_output_summary(self) -> Dict[str, Any]:
        """Get summary of output configuration.

        Returns:
            Dictionary with output summary including workspaces per output

        Raises:
            RuntimeError: If unable to get output summary
        """
        try:
            outputs = await self.i3_assertions.get_outputs()
            workspaces = await self.i3_assertions.get_workspaces()

            # Group workspaces by output
            workspaces_by_output = {}
            for workspace in workspaces:
                output = workspace["output"]
                if output not in workspaces_by_output:
                    workspaces_by_output[output] = []
                workspaces_by_output[output].append(workspace["name"])

            summary = {
                "outputs": outputs,
                "active_output_count": sum(1 for o in outputs if o["active"]),
                "total_output_count": len(outputs),
                "workspaces_by_output": workspaces_by_output,
            }

            return summary

        except Exception as e:
            raise RuntimeError(f"Failed to get output summary: {e}")

    def _count_windows_in_tree(self, tree: Dict[str, Any]) -> int:
        """Count windows in i3 tree recursively.

        Args:
            tree: i3 tree dictionary

        Returns:
            Number of windows in tree
        """
        count = 0

        # Check if this node is a window
        if tree.get("type") == "con" and tree.get("window"):
            count += 1

        # Recursively count in child nodes
        for node in tree.get("nodes", []):
            count += self._count_windows_in_tree(node)

        for node in tree.get("floating_nodes", []):
            count += self._count_windows_in_tree(node)

        return count
