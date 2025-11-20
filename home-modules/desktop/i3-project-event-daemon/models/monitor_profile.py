"""Monitor profile models for Feature 083 and Feature 084.

This module defines Pydantic models for:
- Monitor profile configuration (single/dual/triple for headless)
- Hybrid mode profiles (local-only/local+1vnc/local+2vnc for M1)
- Profile events for observability
- Eww widget state for real-time updates

Version: 1.1.0 (2025-11-19)
- Added Feature 084: Hybrid mode models for M1 physical+virtual displays
"""

from enum import Enum
from datetime import datetime
from typing import Optional, List, Union, Any, Literal
from pydantic import BaseModel, Field, field_validator


class ProfileEventType(str, Enum):
    """Event types emitted during profile switch operations.

    Used for observability and debugging via i3pm diagnose events.
    """

    PROFILE_SWITCH_START = "profile_switch_start"
    OUTPUT_ENABLE = "output_enable"
    OUTPUT_DISABLE = "output_disable"
    WORKSPACE_REASSIGN = "workspace_reassign"
    PROFILE_SWITCH_COMPLETE = "profile_switch_complete"
    PROFILE_SWITCH_FAILED = "profile_switch_failed"
    PROFILE_SWITCH_ROLLBACK = "profile_switch_rollback"


class OutputPosition(BaseModel):
    """Position and dimensions for output alignment.

    Used in profile JSON files to define output layout.
    """

    x: int = Field(0, description="Horizontal position in pixels")
    y: int = Field(0, description="Vertical position in pixels")
    width: int = Field(1920, gt=0, description="Output width in pixels")
    height: int = Field(1080, gt=0, description="Output height in pixels")

    class Config:
        frozen = True


class ProfileOutput(BaseModel):
    """Configuration for a single output within a profile.

    Defines whether an output is enabled and its screen position.
    """

    name: str = Field(..., pattern=r"^HEADLESS-[1-9]$|^eDP-\d+$|^HDMI-A-\d+$|^DP-\d+$",
                      description="Output identifier (e.g., HEADLESS-1)")
    enabled: bool = Field(True, description="Whether output is active in this profile")
    position: OutputPosition = Field(default_factory=OutputPosition,
                                     description="Screen position for alignment")

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        """Validate output name is non-empty."""
        if not v or v.strip() == "":
            raise ValueError("Output name cannot be empty")
        return v

    class Config:
        frozen = True


class MonitorProfile(BaseModel):
    """Named monitor profile configuration.

    Defines which headless outputs to enable and their positions.
    Stored in ~/.config/sway/monitor-profiles/{name}.json

    Supports two output formats:
    - Simple: ["HEADLESS-1", "HEADLESS-2"] (strings are enabled outputs)
    - Full: [{"name": "HEADLESS-1", "enabled": true, ...}] (ProfileOutput objects)
    """

    name: str = Field(..., description="Profile identifier (e.g., single, dual, triple)")
    description: str = Field("", description="Human-readable description")
    outputs: List[Union[str, ProfileOutput]] = Field(..., min_length=1,
                                         description="Output configurations (strings or ProfileOutput)")
    default: bool = Field(False, description="Whether this is the default profile")
    workspace_roles: Optional[dict] = Field(None, description="Workspace role assignments")

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        """Validate profile name format."""
        if not v or v.strip() == "":
            raise ValueError("Profile name cannot be empty")
        return v.lower()

    @field_validator("outputs", mode="before")
    @classmethod
    def convert_string_outputs(cls, v: Any) -> List[ProfileOutput]:
        """Convert string outputs to ProfileOutput objects."""
        if not v:
            return v
        result = []
        for item in v:
            if isinstance(item, str):
                # Simple format: just output name means it's enabled
                result.append(ProfileOutput(name=item, enabled=True))
            elif isinstance(item, dict):
                # Full format: convert dict to ProfileOutput
                result.append(ProfileOutput(**item))
            else:
                result.append(item)
        return result

    def get_enabled_outputs(self) -> List[str]:
        """Return list of output names that are enabled in this profile."""
        return [o.name for o in self.outputs if isinstance(o, ProfileOutput) and o.enabled]

    def get_disabled_outputs(self) -> List[str]:
        """Return list of output names that are disabled in this profile."""
        return [o.name for o in self.outputs if isinstance(o, ProfileOutput) and not o.enabled]


class ProfileEvent(BaseModel):
    """Event emitted during profile switch operations.

    Used for observability via structured logging and event buffer.
    """

    event_type: ProfileEventType = Field(..., description="Type of profile event")
    timestamp: float = Field(..., description="Unix timestamp")
    profile_name: str = Field(..., description="Profile being switched to")
    previous_profile: Optional[str] = Field(None, description="Previous profile (for rollback)")
    outputs_changed: List[str] = Field(default_factory=list,
                                       description="Outputs that changed state")
    duration_ms: Optional[float] = Field(None, description="Operation duration in ms")
    error: Optional[str] = Field(None, description="Error message on failure")

    @classmethod
    def start(cls, profile_name: str, previous_profile: Optional[str] = None,
              outputs_changed: Optional[List[str]] = None) -> "ProfileEvent":
        """Create a profile switch start event."""
        return cls(
            event_type=ProfileEventType.PROFILE_SWITCH_START,
            timestamp=datetime.now().timestamp(),
            profile_name=profile_name,
            previous_profile=previous_profile,
            outputs_changed=outputs_changed or []
        )

    @classmethod
    def complete(cls, profile_name: str, previous_profile: Optional[str] = None,
                 outputs_changed: Optional[List[str]] = None,
                 duration_ms: Optional[float] = None) -> "ProfileEvent":
        """Create a profile switch complete event."""
        return cls(
            event_type=ProfileEventType.PROFILE_SWITCH_COMPLETE,
            timestamp=datetime.now().timestamp(),
            profile_name=profile_name,
            previous_profile=previous_profile,
            outputs_changed=outputs_changed or [],
            duration_ms=duration_ms
        )

    @classmethod
    def failed(cls, profile_name: str, error: str,
               outputs_changed: Optional[List[str]] = None) -> "ProfileEvent":
        """Create a profile switch failed event."""
        return cls(
            event_type=ProfileEventType.PROFILE_SWITCH_FAILED,
            timestamp=datetime.now().timestamp(),
            profile_name=profile_name,
            outputs_changed=outputs_changed or [],
            error=error
        )


class OutputDisplayState(BaseModel):
    """Display state for a single output in Eww widget.

    Pushed to Eww for top bar display of monitor status.
    """

    name: str = Field(..., description="Output name (e.g., HEADLESS-1)")
    short_name: str = Field(..., description="Display abbreviation (e.g., H1, L, V1)")
    active: bool = Field(..., description="Output is enabled and connected")
    workspace_count: int = Field(0, ge=0, description="Number of workspaces on this output")

    @classmethod
    def from_output_name(
        cls,
        name: str,
        active: bool,
        workspace_count: int = 0,
        is_hybrid_mode: bool = False
    ) -> "OutputDisplayState":
        """Create from output name with auto-generated short name.

        Feature 084 T026: Generate L/V1/V2 for hybrid mode, H1/H2/H3 for headless.

        Args:
            name: Output name (e.g., HEADLESS-1, eDP-1)
            active: Whether output is enabled
            workspace_count: Number of workspaces on output
            is_hybrid_mode: If True, use L/V1/V2 naming convention
        """
        short_name = get_short_name(name, is_hybrid_mode)

        return cls(
            name=name,
            short_name=short_name,
            active=active,
            workspace_count=workspace_count
        )


def get_short_name(output_name: str, is_hybrid_mode: bool = False) -> str:
    """Get short display name for an output.

    Feature 084 T026: Visual indicators for hybrid mode.

    Args:
        output_name: Full output name (e.g., HEADLESS-1, eDP-1)
        is_hybrid_mode: If True, use hybrid naming (L/V1/V2)

    Returns:
        Short display name for top bar
    """
    if is_hybrid_mode:
        # Hybrid mode: eDP-1 -> L (Local), HEADLESS-N -> VN (Virtual N)
        if output_name == "eDP-1":
            return "L"
        elif output_name.startswith("HEADLESS-"):
            return f"V{output_name[-1]}"
        else:
            return output_name.replace("-", "")
    else:
        # Headless mode: HEADLESS-N -> HN
        if output_name.startswith("HEADLESS-"):
            return f"H{output_name[-1]}"
        else:
            return output_name.replace("-", "")


class MonitorState(BaseModel):
    """Monitor state pushed to Eww for top bar display.

    Contains profile name and output status for real-time updates.
    Feature 084 T027: Added mode field for hybrid mode detection.
    """

    profile_name: str = Field(..., description="Current active profile name")
    outputs: List[OutputDisplayState] = Field(..., description="Per-output display state")
    mode: Literal["headless", "hybrid"] = Field("headless", description="Display mode")

    def to_eww_json(self) -> str:
        """Serialize to JSON string for eww update command."""
        if hasattr(self, 'model_dump_json'):
            return self.model_dump_json()
        else:
            return self.json()


# =============================================================================
# Feature 084: Hybrid Mode Models (M1 physical + virtual displays)
# =============================================================================


class OutputType(str, Enum):
    """Type of display output.

    Feature 084: Distinguishes physical displays from virtual VNC outputs.
    """
    PHYSICAL = "physical"
    VIRTUAL = "virtual"


class HybridOutputConfig(BaseModel):
    """Configuration for a single output in hybrid mode.

    Feature 084: Extends ProfileOutput with output type and VNC port.
    """

    name: str = Field(..., pattern=r"^(eDP-1|HEADLESS-[12])$",
                      description="Output identifier")
    type: OutputType = Field(..., description="Physical or virtual output")
    enabled: bool = Field(True, description="Whether output is active")
    position: OutputPosition = Field(default_factory=OutputPosition,
                                     description="Screen position")
    scale: float = Field(1.0, ge=1.0, le=2.0, description="Display scaling factor")
    vnc_port: Optional[int] = Field(None, ge=5900, le=5901,
                                    description="VNC port for virtual outputs")

    @field_validator("vnc_port")
    @classmethod
    def validate_vnc_port(cls, v: Optional[int], info) -> Optional[int]:
        """Ensure VNC port is only set for virtual outputs."""
        # Get output_type from values if available
        values = info.data if hasattr(info, 'data') else {}
        output_type = values.get("type")

        if output_type == OutputType.PHYSICAL and v is not None:
            raise ValueError("Physical outputs cannot have VNC port")
        if output_type == OutputType.VIRTUAL and v is None:
            raise ValueError("Virtual outputs must have VNC port")
        return v


class WorkspaceAssignment(BaseModel):
    """Maps workspaces to an output.

    Feature 084: Defines workspace-to-output mapping for profile.
    """

    output: str = Field(..., description="Target output name")
    workspaces: List[int] = Field(..., min_length=1,
                                   description="Workspace numbers (1-100+)")

    @field_validator("workspaces")
    @classmethod
    def validate_workspaces(cls, v: List[int]) -> List[int]:
        """Ensure workspaces are positive integers."""
        for ws in v:
            if ws < 1:
                raise ValueError(f"Workspace number must be >= 1, got {ws}")
        return v


class HybridMonitorProfile(BaseModel):
    """Monitor profile for M1 hybrid mode.

    Feature 084: Defines physical + virtual display configuration.
    Stored in ~/.config/sway/monitor-profiles/{name}.json
    """

    name: str = Field(..., pattern=r"^(local-only|local\+[12]vnc)$",
                      description="Profile identifier")
    description: str = Field("", max_length=200,
                            description="Human-readable description")
    outputs: List[HybridOutputConfig] = Field(..., min_length=1, max_length=3,
                                              description="Output configurations")
    default: bool = Field(False, description="Whether this is the default profile")
    workspace_assignments: List[WorkspaceAssignment] = Field(
        default_factory=list,
        description="Workspace-to-output mappings"
    )

    def get_enabled_outputs(self) -> List[str]:
        """Return list of enabled output names."""
        return [o.name for o in self.outputs if o.enabled]

    def get_virtual_outputs(self) -> List[str]:
        """Return list of virtual (VNC) output names."""
        return [o.name for o in self.outputs
                if o.type == OutputType.VIRTUAL and o.enabled]

    def get_physical_output(self) -> Optional[str]:
        """Return the physical output name (eDP-1 for M1)."""
        for o in self.outputs:
            if o.type == OutputType.PHYSICAL:
                return o.name
        return None


class OutputRuntimeState(BaseModel):
    """Runtime state for a single output.

    Feature 084: Tracks enabled status and VNC port.
    """

    enabled: bool = Field(..., description="Currently enabled")
    type: OutputType = Field(..., description="Physical or virtual")
    vnc_port: Optional[int] = Field(None, description="VNC port if virtual")
    workspace_count: int = Field(0, ge=0, description="Workspaces on this output")


class HybridOutputState(BaseModel):
    """Runtime state for M1 hybrid monitor system.

    Feature 084: Persisted to ~/.config/sway/output-states.json
    """

    version: str = Field("1.0", description="State format version")
    mode: Literal["headless", "hybrid"] = Field(...,
                                                 description="System mode")
    current_profile: str = Field(..., description="Active profile name")
    outputs: dict[str, OutputRuntimeState] = Field(...,
                                                    description="Per-output state")
    last_updated: datetime = Field(default_factory=datetime.utcnow,
                                   description="Last state change")

    def to_json_file(self, path: str) -> None:
        """Save state to JSON file."""
        import json
        with open(path, 'w') as f:
            if hasattr(self, 'model_dump'):
                data = self.model_dump(mode='json')
            else:
                data = self.dict()
            # Convert datetime to ISO format
            data['last_updated'] = self.last_updated.isoformat()
            json.dump(data, f, indent=2)


class M1MonitorState(BaseModel):
    """Monitor state for M1 Eww top bar display.

    Feature 084: Extends MonitorState with hybrid mode.
    """

    profile_name: str = Field(..., description="Current active profile")
    mode: Literal["headless", "hybrid"] = Field(..., description="System mode")
    outputs: List[OutputDisplayState] = Field(..., description="Output states")

    def to_eww_json(self) -> str:
        """Serialize to JSON string for eww update command."""
        if hasattr(self, 'model_dump_json'):
            return self.model_dump_json()
        else:
            return self.json()
