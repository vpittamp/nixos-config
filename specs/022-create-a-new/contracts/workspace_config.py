"""Workspace Configuration Contract - FR-009 through FR-013

API contract for workspace-to-monitor assignment and monitor management.

This contract defines interfaces for:
- Assigning workspaces to monitor roles (primary/secondary/tertiary)
- Displaying current monitor configuration
- Manual workspace redistribution triggers
- Validating assignments against monitor count
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import List, Dict, Optional
from datetime import datetime


@dataclass
class WorkspaceAssignment:
    """Workspace-to-monitor role assignment."""
    workspace_number: int                 # 1-10
    output_role: str                      # "primary", "secondary", "tertiary"

    def validate(self, available_monitors: int) -> None:
        """Validate assignment against available monitor count."""
        if not (1 <= self.workspace_number <= 10):
            raise ValueError(f"Workspace must be 1-10, got {self.workspace_number}")

        valid_roles = ["primary", "secondary", "tertiary"]
        if self.output_role not in valid_roles:
            raise ValueError(f"Invalid role: {self.output_role}")

        # Check if role is available given monitor count
        required_monitors = {"primary": 1, "secondary": 2, "tertiary": 3}
        if required_monitors[self.output_role] > available_monitors:
            raise ValueError(
                f"Cannot assign to {self.output_role} with only "
                f"{available_monitors} monitor(s)"
            )


@dataclass
class MonitorInfo:
    """Monitor/output information for display."""
    name: str                             # Output name (e.g., "DP-1", "HDMI-1")
    resolution: str                       # "1920x1080"
    role: str                             # "primary", "secondary", "tertiary"
    active: bool                          # Whether output is currently active
    assigned_workspaces: List[int]        # Workspaces assigned to this monitor
    position: str                         # "0,0" (x,y coordinates)


@dataclass
class MonitorConfiguration:
    """Current monitor configuration state."""
    monitor_count: int
    monitors: List[MonitorInfo]
    updated_at: datetime


@dataclass
class WorkspaceConfigUpdateRequest:
    """Request to update workspace-to-monitor assignments."""
    project_name: str
    assignments: List[WorkspaceAssignment]
    validate_against_current: bool = True  # Validate against current monitor count


@dataclass
class WorkspaceConfigUpdateResponse:
    """Response from workspace configuration update."""
    success: bool
    assignments_applied: int
    validation_warnings: List[str] = None  # Warnings about future incompatibilities
    error: Optional[str] = None


@dataclass
class WorkspaceRedistributionRequest:
    """Request to manually trigger workspace redistribution."""
    use_project_preferences: bool = True   # Use active project's workspace preferences
    force: bool = False                    # Force redistribution even if no changes detected


@dataclass
class WorkspaceRedistributionResponse:
    """Response from workspace redistribution."""
    success: bool
    workspaces_moved: int
    redistribution_summary: str            # Human-readable summary
    duration: float
    error: Optional[str] = None


class IWorkspaceConfigManager(ABC):
    """Abstract interface for workspace-to-monitor configuration management.

    Implements:
    - FR-009: Assign workspaces to monitor roles via TUI
    - FR-010: Validate assignments against current monitor count
    - FR-011: Persist workspace preferences in project JSON
    - FR-012: Display current monitor configuration
    - FR-013: Manual workspace redistribution trigger
    """

    @abstractmethod
    async def get_monitor_configuration(self) -> MonitorConfiguration:
        """Get current monitor configuration from i3.

        Queries i3 GET_OUTPUTS to retrieve active monitors with roles assigned
        based on position and count.

        Returns:
            MonitorConfiguration with all active monitors

        Performance:
            Must update within 1 second of monitor changes (SC-010)
        """
        pass

    @abstractmethod
    async def update_workspace_config(
        self,
        request: WorkspaceConfigUpdateRequest
    ) -> WorkspaceConfigUpdateResponse:
        """Update workspace-to-monitor assignments for a project.

        Process:
        1. Load project configuration
        2. Validate each assignment against current monitor count
        3. Update project.workspace_preferences dict
        4. Save project configuration to disk (atomic write)
        5. Return success with any validation warnings

        Args:
            request: Update request with assignments

        Returns:
            WorkspaceConfigUpdateResponse with validation results

        Raises:
            ValueError: If assignments invalid
            FileNotFoundError: If project not found
        """
        pass

    @abstractmethod
    async def get_workspace_config(self, project_name: str) -> List[WorkspaceAssignment]:
        """Get current workspace assignments for a project.

        Loads project configuration and returns workspace preferences
        as list of WorkspaceAssignment objects.

        Args:
            project_name: Project to get assignments for

        Returns:
            List of WorkspaceAssignment (empty if no preferences set)
        """
        pass

    @abstractmethod
    async def redistribute_workspaces(
        self,
        request: WorkspaceRedistributionRequest
    ) -> WorkspaceRedistributionResponse:
        """Manually trigger workspace redistribution across monitors.

        Process:
        1. Get current monitor configuration
        2. If use_project_preferences and active project:
           - Load project workspace preferences
           - Apply preferences (move workspaces to specified roles)
        3. Else:
           - Apply default distribution based on monitor count
        4. Send i3 commands to move workspaces to target outputs
        5. Return summary of changes

        Args:
            request: Redistribution request parameters

        Returns:
            WorkspaceRedistributionResponse with summary

        Distribution rules (default):
        - 1 monitor: All workspaces on primary
        - 2 monitors: WS 1-2 primary, WS 3-9 secondary
        - 3+ monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary
        """
        pass

    @abstractmethod
    async def validate_workspace_config(
        self,
        project_name: str,
        target_monitor_count: Optional[int] = None
    ) -> Dict[str, List[str]]:
        """Validate workspace configuration for compatibility.

        Checks if project's workspace preferences are compatible with
        current or target monitor count.

        Args:
            project_name: Project to validate
            target_monitor_count: Monitor count to validate against (None = current)

        Returns:
            Dict with 'errors' and 'warnings' keys containing validation messages

        Example return:
        {
            'errors': [],
            'warnings': [
                'WS6 assigned to tertiary but only 2 monitors available'
            ]
        }
        """
        pass


# Example usage in TUI screen

class WorkspaceConfigScreen:
    """Example TUI screen showing contract usage."""

    def __init__(self, config_manager: IWorkspaceConfigManager):
        self.config_manager = config_manager

    async def on_mount(self):
        """Load monitor configuration and workspace assignments on screen mount."""
        # Get current monitor configuration
        self.monitor_config = await self.config_manager.get_monitor_configuration()

        # Update monitor table
        await self.update_monitor_table(self.monitor_config)

        # Load workspace assignments for active project
        if self.active_project:
            self.assignments = await self.config_manager.get_workspace_config(
                self.active_project
            )
            await self.update_assignments_table(self.assignments)

    async def action_save_assignments(self):
        """Save workspace assignments from edit form."""
        # Collect assignments from form
        assignments = self.collect_assignments_from_form()

        request = WorkspaceConfigUpdateRequest(
            project_name=self.active_project,
            assignments=assignments,
            validate_against_current=True
        )

        response = await self.config_manager.update_workspace_config(request)

        if response.success:
            msg = f"Saved {response.assignments_applied} workspace assignments"
            if response.validation_warnings:
                msg += f"\nWarnings: {', '.join(response.validation_warnings)}"
            self.notify(msg, severity="success")
        else:
            self.notify(f"Failed to save: {response.error}", severity="error")

    async def action_redistribute(self):
        """Trigger workspace redistribution."""
        request = WorkspaceRedistributionRequest(
            use_project_preferences=True,
            force=False
        )

        response = await self.config_manager.redistribute_workspaces(request)

        if response.success:
            self.notify(
                f"Redistributed {response.workspaces_moved} workspaces\n"
                f"{response.redistribution_summary}",
                severity="success"
            )
        else:
            self.notify(f"Redistribution failed: {response.error}", severity="error")
