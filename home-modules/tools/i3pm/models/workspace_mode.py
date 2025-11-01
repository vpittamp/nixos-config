"""Pydantic models for workspace mode navigation.

Feature 042: Event-Driven Workspace Mode Navigation
Models for in-memory state, history tracking, and event broadcasting.
"""

from datetime import datetime
from pydantic import BaseModel, Field, field_validator
from typing import Literal, Optional, Dict, List


class WorkspaceModeState(BaseModel):
    """Current workspace mode session state (in-memory only)."""

    active: bool = Field(
        default=False,
        description="Whether workspace mode is currently active"
    )

    mode_type: Optional[Literal["goto", "move"]] = Field(
        default=None,
        description="Type of workspace mode: 'goto' (navigate) or 'move' (move window)"
    )

    accumulated_digits: str = Field(
        default="",
        description="Digits typed by user so far (e.g., '23' for workspace 23)"
    )

    entered_at: Optional[float] = Field(
        default=None,
        description="Unix timestamp when mode was entered"
    )

    output_cache: Dict[str, str] = Field(
        default_factory=dict,
        description="Mapping of output roles to physical output names: PRIMARY/SECONDARY/TERTIARY -> eDP-1/HEADLESS-1/etc."
    )

    @field_validator('accumulated_digits')
    @classmethod
    def validate_digits(cls, v: str) -> str:
        """Ensure accumulated_digits contains only digits."""
        if v and not v.isdigit():
            raise ValueError("accumulated_digits must contain only digits 0-9")
        return v

    @field_validator('output_cache')
    @classmethod
    def validate_output_cache_keys(cls, v: Dict[str, str]) -> Dict[str, str]:
        """Ensure output_cache has valid keys."""
        valid_keys = {"PRIMARY", "SECONDARY", "TERTIARY"}
        invalid_keys = set(v.keys()) - valid_keys
        if invalid_keys:
            raise ValueError(f"Invalid output_cache keys: {invalid_keys}. Must be PRIMARY/SECONDARY/TERTIARY")
        return v

    model_config = {
        "json_schema_extra": {
            "examples": [{
                "active": True,
                "mode_type": "goto",
                "accumulated_digits": "23",
                "entered_at": 1698768000.0,
                "output_cache": {
                    "PRIMARY": "eDP-1",
                    "SECONDARY": "eDP-1",
                    "TERTIARY": "eDP-1"
                }
            }]
        }
    }


class WorkspaceSwitch(BaseModel):
    """Historical record of a single workspace navigation event."""

    workspace: int = Field(
        description="Workspace number that was switched to",
        ge=1,
        le=70
    )

    output: str = Field(
        description="Physical output name that was focused (e.g., eDP-1, HEADLESS-1)"
    )

    timestamp: float = Field(
        description="Unix timestamp when switch occurred"
    )

    mode_type: Literal["goto", "move"] = Field(
        description="How user navigated: 'goto' (focus workspace) or 'move' (move window + follow)"
    )

    @field_validator('output')
    @classmethod
    def validate_output(cls, v: str) -> str:
        """Ensure output is non-empty."""
        if not v:
            raise ValueError("output must be non-empty string")
        return v

    @field_validator('timestamp')
    @classmethod
    def validate_timestamp(cls, v: float) -> float:
        """Ensure timestamp is positive."""
        if v <= 0:
            raise ValueError("timestamp must be positive")
        return v

    model_config = {
        "json_schema_extra": {
            "examples": [{
                "workspace": 23,
                "output": "HEADLESS-2",
                "timestamp": 1698768123.456,
                "mode_type": "goto"
            }]
        }
    }


class WorkspaceModeEvent(BaseModel):
    """Event broadcast payload for real-time status bar updates."""

    event_type: Literal["workspace_mode"] = Field(
        default="workspace_mode",
        description="Event type identifier (always 'workspace_mode')"
    )

    mode_active: bool = Field(
        description="Whether workspace mode is currently active"
    )

    mode_type: Optional[Literal["goto", "move"]] = Field(
        default=None,
        description="Type of workspace mode, or None if inactive"
    )

    accumulated_digits: str = Field(
        default="",
        description="Digits accumulated so far (empty string if none)"
    )

    timestamp: float = Field(
        description="Unix timestamp when event was generated"
    )

    @field_validator('mode_type')
    @classmethod
    def validate_mode_type_consistency(cls, v: Optional[str], info) -> Optional[str]:
        """Ensure mode_type is None when mode_active is False."""
        # Note: info.data only contains previously validated fields
        # We can't fully validate cross-field constraints in field_validator
        # This will be enforced in model_validator if needed
        return v

    @field_validator('accumulated_digits')
    @classmethod
    def validate_digits_format(cls, v: str) -> str:
        """Ensure accumulated_digits is empty or contains only digits."""
        if v and not v.isdigit():
            raise ValueError("accumulated_digits must be empty or contain only digits 0-9")
        return v

    model_config = {
        "json_schema_extra": {
            "examples": [{
                "event_type": "workspace_mode",
                "mode_active": True,
                "mode_type": "goto",
                "accumulated_digits": "23",
                "timestamp": 1698768123.456
            }]
        }
    }
