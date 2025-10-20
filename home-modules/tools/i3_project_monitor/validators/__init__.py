"""State validators for i3 project monitoring.

This package provides validators for i3 IPC state data:
- workspace_validator: Validates workspace-to-output assignments
- output_validator: Validates monitor/output configuration

These validators use i3's native IPC message types (GET_OUTPUTS, GET_WORKSPACES)
as the source of truth for validation.
"""

from .workspace_validator import (
    WorkspaceValidationResult,
    validate_workspace_assignments,
    check_visible_workspaces_on_active_outputs,
    get_orphaned_workspaces,
    get_workspaces_for_output,
    get_focused_workspace,
)

from .output_validator import (
    OutputValidationResult,
    validate_output_configuration,
    check_primary_output_exists,
    check_active_outputs,
    get_primary_output,
    get_output_by_name,
    check_output_geometry_valid,
    get_total_display_area,
)

__all__ = [
    # Workspace validator
    'WorkspaceValidationResult',
    'validate_workspace_assignments',
    'check_visible_workspaces_on_active_outputs',
    'get_orphaned_workspaces',
    'get_workspaces_for_output',
    'get_focused_workspace',
    # Output validator
    'OutputValidationResult',
    'validate_output_configuration',
    'check_primary_output_exists',
    'check_active_outputs',
    'get_primary_output',
    'get_output_by_name',
    'check_output_geometry_valid',
    'get_total_display_area',
]
