"""
Workspace assignment handler for Sway.

Manages workspace-to-output assignments with fallback behavior.
"""

import logging
from typing import List, Dict, Optional

from i3ipc.aio import Connection

from ..models import WorkspaceAssignment

logger = logging.getLogger(__name__)


class WorkspaceAssignmentHandler:
    """Handles workspace-to-output assignments via Sway IPC."""

    def __init__(self, sway_connection: Connection = None):
        """
        Initialize workspace assignment handler.

        Args:
            sway_connection: Async i3ipc Connection (created if None)
        """
        self.sway = sway_connection
        self.assignments = []

    async def load_assignments(self, assignments: List[WorkspaceAssignment]):
        """
        Load workspace assignments.

        Args:
            assignments: List of workspace assignments
        """
        self.assignments = assignments
        logger.info(f"Loaded {len(self.assignments)} workspace assignments")

    async def apply_assignments(self) -> bool:
        """
        Apply workspace assignments to Sway.

        Returns:
            True if assignments applied successfully, False otherwise
        """
        try:
            if self.sway is None:
                self.sway = await Connection(auto_reconnect=True).connect()

            # Get current outputs
            outputs = await self.sway.get_outputs()
            available_outputs = {output.name for output in outputs if output.active}

            logger.info(f"Available outputs: {available_outputs}")

            for assignment in self.assignments:
                output = self._select_output(assignment, available_outputs)
                if output:
                    await self._assign_workspace_to_output(assignment.workspace_number, output)
                else:
                    logger.warning(f"No available output for workspace {assignment.workspace_number}")

            return True

        except Exception as e:
            logger.error(f"Failed to apply workspace assignments: {e}")
            return False

    def _select_output(self, assignment: WorkspaceAssignment, available_outputs: set) -> Optional[str]:
        """
        Select output for workspace based on assignment and fallbacks.

        Args:
            assignment: Workspace assignment configuration
            available_outputs: Set of currently available output names

        Returns:
            Selected output name or None if no suitable output
        """
        # Try primary output first
        if assignment.primary_output in available_outputs:
            return assignment.primary_output

        # Try fallback outputs
        for fallback in assignment.fallback_outputs:
            if fallback in available_outputs:
                logger.info(f"Using fallback output '{fallback}' for workspace {assignment.workspace_number}")
                return fallback

        # No suitable output found
        return None

    async def _assign_workspace_to_output(self, workspace_number: int, output_name: str):
        """
        Assign workspace to output via Sway IPC.

        Args:
            workspace_number: Workspace number to assign
            output_name: Output name to assign workspace to
        """
        try:
            # Move workspace to output
            command = f"workspace number {workspace_number}; move workspace to output {output_name}"
            await self.sway.command(command)
            logger.info(f"Assigned workspace {workspace_number} to output {output_name}")

        except Exception as e:
            logger.error(f"Failed to assign workspace {workspace_number} to {output_name}: {e}")

    async def handle_output_change(self):
        """
        Handle output change events (monitor connect/disconnect).

        Re-applies assignments when outputs change.
        """
        # Check which assignments have auto_reassign enabled
        auto_reassign_assignments = [a for a in self.assignments if a.auto_reassign]

        if auto_reassign_assignments:
            logger.info(f"Reapplying {len(auto_reassign_assignments)} auto-reassign workspace assignments")
            # Reload only auto-reassign assignments
            await self.load_assignments(auto_reassign_assignments)
            await self.apply_assignments()
