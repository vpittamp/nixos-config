"""Window state models for run-raise-hide state machine - Feature 051."""

from dataclasses import dataclass
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field

try:
    from i3ipc.aio import Con
except ImportError:
    Con = None  # For type hints when i3ipc not available


class WindowState(Enum):
    """Five possible window states for run-raise-hide logic."""
    NOT_FOUND = "not_found"
    DIFFERENT_WORKSPACE = "different_workspace"
    SAME_WORKSPACE_UNFOCUSED = "same_workspace_unfocused"
    SAME_WORKSPACE_FOCUSED = "same_workspace_focused"
    SCRATCHPAD = "scratchpad"


@dataclass
class WindowStateInfo:
    """Window state detection result for run-raise-hide logic."""
    state: WindowState
    window: Optional[Con]  # Sway window container (None if NOT_FOUND)
    current_workspace: str  # Current focused workspace name
    window_workspace: Optional[str]  # Window's workspace name (None if NOT_FOUND)
    is_focused: bool  # True if window is currently focused

    @property
    def window_id(self) -> Optional[int]:
        """Sway container ID (convenience accessor)."""
        return self.window.id if self.window else None

    @property
    def is_floating(self) -> bool:
        """True if window is in floating mode."""
        if not self.window:
            return False
        return self.window.floating in ["user_on", "auto_on"]

    @property
    def geometry(self) -> Optional[dict]:
        """Window geometry (x, y, width, height) if floating, else None."""
        if not self.window or not self.is_floating:
            return None
        rect = self.window.rect
        return {
            "x": rect.x,
            "y": rect.y,
            "width": rect.width,
            "height": rect.height
        }


class RunMode(Enum):
    """CLI run command modes."""
    SUMMON = "summon"  # Default: show on current workspace
    HIDE = "hide"  # Toggle visibility (hide if visible, show if hidden)
    NOHIDE = "nohide"  # Never hide, only show (idempotent)


class RunRequest(BaseModel):
    """RPC request for app.run method."""
    app_name: str = Field(..., description="Application name from registry")
    mode: str = Field("summon", description="Run mode: summon|hide|nohide")
    force_launch: bool = Field(False, description="Always launch new instance")

    class Config:
        json_schema_extra = {
            "example": {
                "app_name": "firefox",
                "mode": "summon",
                "force_launch": False
            }
        }


class RunResponse(BaseModel):
    """RPC response for app.run method."""
    action: str = Field(..., description="Action taken: launched|focused|moved|hidden|shown|none")
    window_id: Optional[int] = Field(None, description="Sway container ID (if window exists)")
    focused: bool = Field(..., description="True if window is now focused")
    message: str = Field(..., description="Human-readable result message")

    class Config:
        json_schema_extra = {
            "example": {
                "action": "focused",
                "window_id": 123456,
                "focused": True,
                "message": "Focused Firefox on workspace 3"
            }
        }
