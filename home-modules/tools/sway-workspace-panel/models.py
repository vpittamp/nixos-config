"""Pydantic models for sway-workspace-panel.

Feature 058: Workspace Mode Visual Feedback
Models for parsing workspace mode IPC events from i3pm daemon.
"""

from typing import Optional, Literal
from pydantic import BaseModel, Field


class PendingWorkspaceState(BaseModel):
    """Pending workspace state received from workspace mode events.

    This is a simplified version for the workspace panel to parse IPC events.
    The canonical model is in i3pm daemon's models/workspace_mode_feedback.py.
    """

    workspace_number: int = Field(..., description="Target workspace number (1-70)")
    accumulated_digits: str = Field(..., description="Raw digit string")
    mode_type: Literal["goto", "move"] = Field(..., description="Navigation mode")
    target_output: Optional[str] = Field(default=None, description="Monitor output name")


class WorkspaceModeEvent(BaseModel):
    """Workspace mode event received via IPC from i3pm daemon.

    Feature 058: User Story 1 (Workspace Button Pending Highlight)
    """

    event_type: Literal["enter", "digit", "cancel", "execute"] = Field(..., description="Type of workspace mode event")
    pending_workspace: Optional[PendingWorkspaceState] = Field(default=None, description="Current pending workspace (None when mode inactive)")
    timestamp: float = Field(..., gt=0, description="Unix timestamp when event was emitted")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "event_type": "digit",
                    "pending_workspace": {
                        "workspace_number": 23,
                        "accumulated_digits": "23",
                        "mode_type": "goto",
                        "target_output": "HEADLESS-2"
                    },
                    "timestamp": 1699727480.8765
                },
                {
                    "event_type": "cancel",
                    "pending_workspace": None,
                    "timestamp": 1699727481.5432
                }
            ]
        }
