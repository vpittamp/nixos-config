"""Workspace-to-output assignment validator.

Validates workspace assignments using i3's GET_WORKSPACES data against
GET_OUTPUTS configuration. Ensures workspaces are assigned to active outputs
and detects orphaned workspaces.
"""

from dataclasses import dataclass, field
from typing import List, Optional

from ..models import WorkspaceAssignment, OutputState


@dataclass
class WorkspaceValidationResult:
    """Result of workspace validation."""

    valid: bool
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    orphaned_workspaces: List[WorkspaceAssignment] = field(default_factory=list)
    visible_on_inactive_outputs: List[WorkspaceAssignment] = field(default_factory=list)

    def __bool__(self) -> bool:
        """Allow using result in boolean context."""
        return self.valid


def validate_workspace_assignments(
    workspaces: List[WorkspaceAssignment],
    outputs: List[OutputState]
) -> WorkspaceValidationResult:
    """Validate workspace-to-output assignments.

    Checks:
    1. All workspaces are assigned to existing outputs
    2. Visible workspaces are on active outputs
    3. Only one workspace is focused
    4. Output consistency

    Args:
        workspaces: List of workspace assignments from GET_WORKSPACES
        outputs: List of output states from GET_OUTPUTS

    Returns:
        WorkspaceValidationResult with validation status and issues
    """
    result = WorkspaceValidationResult(valid=True)

    if not workspaces:
        result.warnings.append("No workspaces found")
        return result

    if not outputs:
        result.valid = False
        result.errors.append("No outputs found - cannot validate workspace assignments")
        return result

    # Build output name set for quick lookups
    active_output_names = {o.name for o in outputs if o.active}
    all_output_names = {o.name for o in outputs}

    # Track focused workspaces
    focused_workspaces = []

    for ws in workspaces:
        # Check 1: Workspace assigned to existing output
        if ws.output not in all_output_names:
            result.valid = False
            result.errors.append(
                f"Workspace '{ws.name}' (num={ws.num}) assigned to non-existent output '{ws.output}'"
            )
            result.orphaned_workspaces.append(ws)
            continue

        # Check 2: Visible workspaces must be on active outputs
        if ws.visible and ws.output not in active_output_names:
            result.valid = False
            result.errors.append(
                f"Workspace '{ws.name}' (num={ws.num}) is visible but assigned to inactive output '{ws.output}'"
            )
            result.visible_on_inactive_outputs.append(ws)

        # Track focused workspaces
        if ws.focused:
            focused_workspaces.append(ws)

    # Check 3: Only one workspace should be focused
    if len(focused_workspaces) > 1:
        result.valid = False
        focused_names = [f"'{ws.name}' (num={ws.num})" for ws in focused_workspaces]
        result.errors.append(
            f"Multiple workspaces are focused: {', '.join(focused_names)}"
        )
    elif len(focused_workspaces) == 0:
        result.warnings.append("No workspace is focused")

    # Detect orphaned workspaces (assigned to inactive outputs but not visible)
    for ws in workspaces:
        if not ws.visible and ws.output not in active_output_names:
            result.orphaned_workspaces.append(ws)
            result.warnings.append(
                f"Workspace '{ws.name}' (num={ws.num}) assigned to inactive output '{ws.output}'"
            )

    return result


def check_visible_workspaces_on_active_outputs(
    workspaces: List[WorkspaceAssignment],
    outputs: List[OutputState]
) -> bool:
    """Quick check: all visible workspaces on active outputs.

    Args:
        workspaces: List of workspace assignments
        outputs: List of output states

    Returns:
        True if all visible workspaces are on active outputs
    """
    active_output_names = {o.name for o in outputs if o.active}

    for ws in workspaces:
        if ws.visible and ws.output not in active_output_names:
            return False

    return True


def get_orphaned_workspaces(
    workspaces: List[WorkspaceAssignment],
    outputs: List[OutputState]
) -> List[WorkspaceAssignment]:
    """Get workspaces assigned to non-existent or inactive outputs.

    Args:
        workspaces: List of workspace assignments
        outputs: List of output states

    Returns:
        List of orphaned workspace assignments
    """
    all_output_names = {o.name for o in outputs}
    orphaned = []

    for ws in workspaces:
        if ws.output not in all_output_names:
            orphaned.append(ws)

    return orphaned


def get_workspaces_for_output(
    workspaces: List[WorkspaceAssignment],
    output_name: str
) -> List[WorkspaceAssignment]:
    """Get all workspaces assigned to a specific output.

    Args:
        workspaces: List of workspace assignments
        output_name: Output name to filter by

    Returns:
        List of workspaces assigned to the output
    """
    return [ws for ws in workspaces if ws.output == output_name]


def get_focused_workspace(
    workspaces: List[WorkspaceAssignment]
) -> Optional[WorkspaceAssignment]:
    """Get the currently focused workspace.

    Args:
        workspaces: List of workspace assignments

    Returns:
        The focused workspace, or None if no workspace is focused
    """
    focused = [ws for ws in workspaces if ws.focused]
    return focused[0] if focused else None
