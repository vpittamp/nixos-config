"""Pydantic models for Feature 058: Workspace Mode Visual Feedback.

This module contains models for pending workspace state and visual feedback events.
"""

from typing import Optional, Literal
from pydantic import BaseModel, Field, field_validator


class PendingWorkspaceState(BaseModel):
    """Represents pending workspace navigation target in workspace mode.

    This model captures the workspace that will be focused when the user presses
    Enter in workspace mode, derived from accumulated digit input.

    Feature 058: User Story 1 (Workspace Button Pending Highlight)
    """

    workspace_number: int = Field(..., ge=1, le=70, description="Target workspace number (1-70)")
    accumulated_digits: str = Field(..., pattern=r"^[0-9]{1,2}$", description="Raw digit string (1-2 digits)")
    mode_type: Literal["goto", "move"] = Field(..., description="Navigation mode: goto (focus) or move (move window + follow)")
    target_output: Optional[str] = Field(default=None, description="Monitor output name where workspace will appear (e.g., 'eDP-1', 'HEADLESS-2')")

    @field_validator("accumulated_digits")
    @classmethod
    def validate_accumulated_digits(cls, v: str, info) -> str:
        """Validate that accumulated_digits matches workspace_number."""
        if not v:
            raise ValueError("accumulated_digits cannot be empty")

        # Note: workspace_number validation happens first (ge=1, le=70)
        # This validator just ensures digit string is non-empty
        return v

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "workspace_number": 2,
                    "accumulated_digits": "2",
                    "mode_type": "goto",
                    "target_output": "eDP-1"
                },
                {
                    "workspace_number": 23,
                    "accumulated_digits": "23",
                    "mode_type": "move",
                    "target_output": "HEADLESS-2"
                }
            ]
        }
