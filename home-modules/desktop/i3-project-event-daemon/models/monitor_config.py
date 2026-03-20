"""Monitor role configuration models for Feature 001.

This module defines Pydantic models for workspace-to-monitor assignment
based on logical monitor roles (primary/secondary/tertiary/quaternary).
"""

from enum import Enum
from datetime import datetime
from typing import Optional, Dict, Literal
from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator


class MonitorRole(str, Enum):
    """Logical monitor positions for workspace assignment.

    Four-tier role system independent of physical output names:
    - PRIMARY: Main monitor (fallback for all workspaces)
    - SECONDARY: Second monitor (fallback for tertiary/quaternary)
    - TERTIARY: Third monitor (fallback for quaternary)
    - QUATERNARY: Fourth monitor (no fallback source)

    Fallback chain: quaternary → tertiary → secondary → primary
    """

    PRIMARY = "primary"
    SECONDARY = "secondary"
    TERTIARY = "tertiary"
    QUATERNARY = "quaternary"

    @classmethod
    def from_str(cls, value: str) -> "MonitorRole":
        """Parse role from string (case-insensitive).

        Args:
            value: Role name string

        Returns:
            MonitorRole: Parsed enum value

        Raises:
            ValueError: If value is not a valid role
        """
        try:
            return cls(value.lower())
        except ValueError:
            valid_roles = ", ".join([r.value for r in cls])
            raise ValueError(
                f"Invalid monitor role '{value}': must be one of {valid_roles}"
            )


class OutputInfo(BaseModel):
    """Physical monitor/output information from Sway IPC GET_OUTPUTS.

    Represents a physical display connected to the system. This is the
    authoritative source for output names and properties.

    Immutable after creation (frozen).
    """

    model_config = ConfigDict(frozen=True)

    name: str = Field(..., description="Output identifier (HDMI-A-1, eDP-1, etc.)")
    active: bool = Field(..., description="Whether output is currently active")
    width: int = Field(..., gt=0, description="Output width in pixels")
    height: int = Field(..., gt=0, description="Output height in pixels")
    scale: float = Field(1.0, gt=0.0, description="DPI scale factor")

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        """Validate output name is non-empty."""
        if not v or v.strip() == "":
            raise ValueError("Output name cannot be empty")
        return v


class MonitorRoleConfig(BaseModel):
    """Application monitor role preference configuration.

    Represents an application's desired monitor role from Nix configuration
    (app-registry-data.nix or pwa-sites.nix).
    """

    app_name: str = Field(..., description="Application identifier")
    preferred_workspace: int = Field(
        ..., ge=1, description="Workspace number (1+)"
    )
    preferred_monitor_role: Optional[MonitorRole] = Field(
        None, description="Desired monitor role (nullable)"
    )
    source: Literal["app-registry", "pwa-sites", "nix"] = Field(
        ..., description="Configuration source (nix for Nix-generated configs)"
    )

    @field_validator("app_name")
    @classmethod
    def validate_app_name(cls, v: str) -> str:
        """Validate app name is non-empty."""
        if not v or v.strip() == "":
            raise ValueError("app_name cannot be empty")
        return v


class MonitorRoleAssignment(BaseModel):
    """Resolved monitor role to output mapping.

    Represents the result of monitor role resolution, mapping a logical
    role (primary/secondary/tertiary) to a physical output name.

    Immutable after creation (frozen).
    """

    model_config = ConfigDict(frozen=True)

    role: MonitorRole = Field(..., description="Logical monitor role")
    output: str = Field(..., description="Physical output name")
    fallback_applied: bool = Field(
        False, description="Whether fallback logic was used"
    )
    preferred_output: Optional[str] = Field(
        None, description="User-configured preferred output (Feature US5)"
    )

    @field_validator("output")
    @classmethod
    def validate_output(cls, v: str) -> str:
        """Validate output name is non-empty."""
        if not v or v.strip() == "":
            raise ValueError("Output name cannot be empty")
        return v


class WorkspaceAssignment(BaseModel):
    """Complete workspace-to-output assignment with metadata.

    Represents the final resolved assignment of a workspace to a physical
    output, including the application that owns it and the monitor role used.

    Immutable after creation (frozen).
    """

    model_config = ConfigDict(frozen=True)

    workspace_num: int = Field(..., ge=1, description="Workspace number (1+)")
    output: str = Field(..., description="Assigned output name")
    monitor_role: MonitorRole = Field(..., description="Resolved monitor role")
    app_name: Optional[str] = Field(None, description="Application owning workspace")
    source: str = Field(..., description="Assignment source")

    @field_validator("output")
    @classmethod
    def validate_output(cls, v: str) -> str:
        """Validate output name is non-empty."""
        if not v or v.strip() == "":
            raise ValueError("Output name cannot be empty")
        return v

    @field_validator("source")
    @classmethod
    def validate_source(cls, v: str) -> str:
        """Validate source is non-empty."""
        if not v or v.strip() == "":
            raise ValueError("Source cannot be empty")
        return v


class MonitorStateV2(BaseModel):
    """Extended state file for monitor role assignments (version 2.0).

    Persisted to ~/.config/sway/monitor-state.json. This extends Feature 049's
    state file (v1.0) with monitor role and application metadata.

    Migration from v1.0: See migrate_v1_to_v2() helper function.
    """

    version: Literal["2.0"] = Field(
        "2.0", description="State file format version"
    )
    monitor_roles: Dict[str, str] = Field(
        ..., description="Role→output mapping (role names as keys)"
    )
    workspaces: Dict[int, WorkspaceAssignment] = Field(
        ..., description="Workspace assignments (workspace number as key)"
    )
    last_updated: datetime = Field(
        default_factory=datetime.now, description="ISO 8601 timestamp of last update"
    )

    @field_validator("workspaces")
    @classmethod
    def validate_workspace_keys(
        cls, v: Dict[int, "WorkspaceAssignment"]
    ) -> Dict[int, "WorkspaceAssignment"]:
        """Validate workspace dict keys match assignment workspace numbers."""
        for key, assignment in v.items():
            if key != assignment.workspace_num:
                raise ValueError(
                    f"Workspace key {key} doesn't match assignment workspace_num {assignment.workspace_num}"
                )
        return v

    @field_validator("monitor_roles")
    @classmethod
    def validate_monitor_roles(cls, v: Dict[str, str]) -> Dict[str, str]:
        """Validate monitor role keys are valid role names."""
        valid_roles = {role.value for role in MonitorRole}
        for role_str in v.keys():
            if role_str not in valid_roles:
                raise ValueError(
                    f"Invalid monitor role key '{role_str}': must be one of {valid_roles}"
                )
        return v

    @field_serializer("last_updated", when_used="json")
    def serialize_last_updated(self, value: datetime) -> str:
        return value.isoformat()


class OutputState(BaseModel):
    """State for a single output (enabled/disabled for workspace distribution).

    This is used for headless/virtual outputs that can't be disabled via DPMS.
    """

    enabled: bool = Field(True, description="Whether output should receive workspaces")


class OutputStatesFile(BaseModel):
    """User-controlled output state file for dynamic workspace distribution.

    File: ~/.config/sway/output-states.json

    This allows users to toggle headless outputs as 'inactive' for workspace
    distribution purposes, since headless outputs can't be disabled via DPMS.
    """

    version: Literal["1.0"] = Field("1.0", description="State file format version")
    outputs: Dict[str, OutputState] = Field(
        default_factory=dict,
        description="Output states keyed by output name (e.g., HEADLESS-1)"
    )
    last_updated: datetime = Field(
        default_factory=datetime.now, description="ISO 8601 timestamp of last update"
    )

    @field_serializer("last_updated", when_used="json")
    def serialize_last_updated(self, value: datetime) -> str:
        return value.isoformat()

    def get_enabled_outputs(self) -> list[str]:
        """Return list of output names that are enabled."""
        return [name for name, state in self.outputs.items() if state.enabled]

    def is_output_enabled(self, output_name: str) -> bool:
        """Check if an output is enabled (defaults to True if not in file)."""
        if output_name not in self.outputs:
            return True  # Default to enabled for new outputs
        return self.outputs[output_name].enabled

    def toggle_output(self, output_name: str) -> bool:
        """Toggle output enabled state. Returns new state."""
        if output_name not in self.outputs:
            self.outputs[output_name] = OutputState(enabled=False)
        else:
            self.outputs[output_name].enabled = not self.outputs[output_name].enabled
        self.last_updated = datetime.now()
        return self.outputs[output_name].enabled

    def set_output_enabled(self, output_name: str, enabled: bool) -> None:
        """Set output enabled state explicitly."""
        if output_name not in self.outputs:
            self.outputs[output_name] = OutputState(enabled=enabled)
        else:
            self.outputs[output_name].enabled = enabled
        self.last_updated = datetime.now()
