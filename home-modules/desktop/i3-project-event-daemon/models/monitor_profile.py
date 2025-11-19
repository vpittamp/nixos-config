"""Monitor profile models for Feature 083.

This module defines Pydantic models for:
- Monitor profile configuration (single/dual/triple)
- Profile events for observability
- Eww widget state for real-time updates

Version: 1.0.0 (2025-11-19)
"""

from enum import Enum
from datetime import datetime
from typing import Optional, List, Union, Any
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
    short_name: str = Field(..., description="Display abbreviation (e.g., H1)")
    active: bool = Field(..., description="Output is enabled and connected")
    workspace_count: int = Field(0, ge=0, description="Number of workspaces on this output")

    @classmethod
    def from_output_name(cls, name: str, active: bool, workspace_count: int = 0) -> "OutputDisplayState":
        """Create from output name with auto-generated short name."""
        # Generate short name: HEADLESS-1 -> H1, eDP-1 -> eDP1
        if name.startswith("HEADLESS-"):
            short_name = f"H{name[-1]}"
        else:
            short_name = name.replace("-", "")

        return cls(
            name=name,
            short_name=short_name,
            active=active,
            workspace_count=workspace_count
        )


class MonitorState(BaseModel):
    """Monitor state pushed to Eww for top bar display.

    Contains profile name and output status for real-time updates.
    """

    profile_name: str = Field(..., description="Current active profile name")
    outputs: List[OutputDisplayState] = Field(..., description="Per-output display state")

    def to_eww_json(self) -> str:
        """Serialize to JSON string for eww update command."""
        if hasattr(self, 'model_dump_json'):
            return self.model_dump_json()
        else:
            return self.json()
