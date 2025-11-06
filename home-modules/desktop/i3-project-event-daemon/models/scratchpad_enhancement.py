"""
Scratchpad Enhancement Models (Feature 051)

Pydantic models for i3run-inspired scratchpad terminal enhancements:
- Mouse-cursor positioning with boundary detection
- Configurable screen edge gaps
- Workspace summoning modes
- State persistence via Sway marks
"""

from pydantic import BaseModel, Field, field_validator, computed_field
from enum import Enum
from typing import Optional
import os
import time


# ============================================================================
# Domain 1: Screen Geometry & Configuration
# ============================================================================

class GapConfig(BaseModel):
    """Screen edge gap configuration in pixels."""

    top: int = Field(default=10, ge=0, le=500, description="Top edge gap (pixels)")
    bottom: int = Field(default=10, ge=0, le=500, description="Bottom edge gap (pixels)")
    left: int = Field(default=10, ge=0, le=500, description="Left edge gap (pixels)")
    right: int = Field(default=10, ge=0, le=500, description="Right edge gap (pixels)")

    @classmethod
    def from_environment(cls) -> "GapConfig":
        """Load gap configuration from environment variables."""
        return cls(
            top=int(os.getenv("I3RUN_TOP_GAP", "10")),
            bottom=int(os.getenv("I3RUN_BOTTOM_GAP", "10")),
            left=int(os.getenv("I3RUN_LEFT_GAP", "10")),
            right=int(os.getenv("I3RUN_RIGHT_GAP", "10")),
        )

    @field_validator("*")
    @classmethod
    def validate_reasonable_gaps(cls, v: int) -> int:
        """Ensure gaps are reasonable (0-500px)."""
        if v < 0:
            raise ValueError("Gap cannot be negative")
        if v > 500:
            raise ValueError("Gap exceeds reasonable maximum (500px)")
        return v

    def total_horizontal(self) -> int:
        """Total horizontal gap (left + right)."""
        return self.left + self.right

    def total_vertical(self) -> int:
        """Total vertical gap (top + bottom)."""
        return self.top + self.bottom


class WorkspaceGeometry(BaseModel):
    """Workspace dimensions and constraints."""

    # Raw dimensions from Sway
    width: int = Field(..., gt=0, description="Workspace width (pixels)")
    height: int = Field(..., gt=0, description="Workspace height (pixels)")
    x_offset: int = Field(default=0, description="X offset in multi-monitor (pixels)")
    y_offset: int = Field(default=0, description="Y offset in multi-monitor (pixels)")

    # Workspace metadata
    workspace_num: int = Field(..., ge=1, le=70, description="Workspace number")
    monitor_name: str = Field(..., description="Monitor name (e.g., HEADLESS-1, eDP-1)")

    # Gap configuration
    gaps: GapConfig = Field(default_factory=GapConfig, description="Screen edge gaps")

    @computed_field
    @property
    def available_width(self) -> int:
        """Available width after accounting for gaps."""
        return max(0, self.width - self.gaps.total_horizontal())

    @computed_field
    @property
    def available_height(self) -> int:
        """Available height after accounting for gaps."""
        return max(0, self.height - self.gaps.total_vertical())

    @computed_field
    @property
    def center_x(self) -> int:
        """Center X coordinate (absolute, including offset)."""
        return self.x_offset + (self.width // 2)

    @computed_field
    @property
    def center_y(self) -> int:
        """Center Y coordinate (absolute, including offset)."""
        return self.y_offset + (self.height // 2)

    def contains_point(self, x: int, y: int) -> bool:
        """Check if point is within this workspace's bounds."""
        return (self.x_offset <= x < self.x_offset + self.width and
                self.y_offset <= y < self.y_offset + self.height)


# ============================================================================
# Domain 2: Window Dimensions & Positioning
# ============================================================================

class WindowDimensions(BaseModel):
    """Floating window size."""

    width: int = Field(default=1000, gt=0, le=5000, description="Window width (pixels)")
    height: int = Field(default=600, gt=0, le=3000, description="Window height (pixels)")

    def fits_in_workspace(self, workspace: WorkspaceGeometry) -> bool:
        """Check if window fits within workspace's available space."""
        return (self.width <= workspace.available_width and
                self.height <= workspace.available_height)

    def scale_to_fit(self, workspace: WorkspaceGeometry) -> "WindowDimensions":
        """Scale window to fit within workspace if oversized."""
        if self.fits_in_workspace(workspace):
            return self

        # Calculate scale factor to fit within available space
        width_scale = workspace.available_width / self.width
        height_scale = workspace.available_height / self.height
        scale = min(width_scale, height_scale)

        return WindowDimensions(
            width=int(self.width * scale),
            height=int(self.height * scale)
        )


class CursorPosition(BaseModel):
    """Mouse cursor position."""

    x: int = Field(..., description="Cursor X coordinate (absolute, pixels)")
    y: int = Field(..., description="Cursor Y coordinate (absolute, pixels)")
    screen: int = Field(default=0, ge=0, description="Screen number from xdotool")
    window_id: Optional[int] = Field(default=None, description="Window under cursor")

    # Metadata
    valid: bool = Field(default=True, description="Is this a valid cursor position?")
    timestamp: float = Field(default_factory=time.time, description="Unix timestamp")
    source: str = Field(default="xdotool", description="Position source (xdotool|cache|center)")

    def is_stale(self, max_age_seconds: float = 2.0) -> bool:
        """Check if cached position is stale."""
        return time.time() - self.timestamp > max_age_seconds

    def is_in_workspace(self, workspace: WorkspaceGeometry) -> bool:
        """Check if cursor is within workspace bounds."""
        return workspace.contains_point(self.x, self.y)


class TerminalPosition(BaseModel):
    """Final calculated position for terminal window."""

    x: int = Field(..., description="Final X position (absolute, pixels)")
    y: int = Field(..., description="Final Y position (absolute, pixels)")
    width: int = Field(..., gt=0, description="Window width (pixels)")
    height: int = Field(..., gt=0, description="Window height (pixels)")

    # Metadata
    workspace_num: int = Field(..., ge=1, le=70, description="Target workspace")
    monitor_name: str = Field(..., description="Target monitor")
    constrained_by_gaps: bool = Field(default=False, description="Was position constrained?")
    cursor_position: Optional[CursorPosition] = Field(default=None, description="Original cursor")

    def to_sway_command(self, container_id: int) -> str:
        """Generate Sway command to position window."""
        return f"[con_id={container_id}] move absolute position {self.x} {self.y}"

    def to_sway_resize_command(self, container_id: int) -> str:
        """Generate Sway command to resize window."""
        return f"[con_id={container_id}] resize set {self.width} {self.height}"

    @property
    def geometry_dict(self) -> dict:
        """Return geometry as dict for mark serialization."""
        return {
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height
        }


# ============================================================================
# Domain 3: State Persistence
# ============================================================================

class ScratchpadState(BaseModel):
    """Persistent state stored in Sway marks."""

    # Window state
    floating: bool = Field(default=True, description="Is window floating?")
    x: int = Field(..., description="Last known X position (pixels)")
    y: int = Field(..., description="Last known Y position (pixels)")
    width: int = Field(default=1000, gt=0, description="Last known width (pixels)")
    height: int = Field(default=600, gt=0, description="Last known height (pixels)")

    # Context
    workspace_num: int = Field(..., ge=1, le=70, description="Last workspace")
    monitor_name: str = Field(..., description="Last monitor")
    timestamp: int = Field(default_factory=lambda: int(time.time()), description="Unix epoch")

    # Metadata
    project_name: str = Field(..., description="Project name (for mark prefix)")

    @classmethod
    def from_mark_string(cls, mark: str) -> Optional["ScratchpadState"]:
        """
        Parse mark string into ScratchpadState.

        Format: scratchpad:{project}|floating:true,x:100,y:200,w:1000,h:600,ts:1730934000,ws:1,mon:HEADLESS-1
        """
        try:
            if not mark.startswith("scratchpad:"):
                return None

            # Extract project and state string
            prefix, state_str = mark.split("|", 1)
            project_name = prefix.replace("scratchpad:", "")

            # Parse key:value pairs
            state_dict = {}
            for pair in state_str.split(","):
                key, value = pair.split(":", 1)
                state_dict[key] = value

            # Convert types
            return cls(
                project_name=project_name,
                floating=state_dict["floating"] == "true",
                x=int(state_dict["x"]),
                y=int(state_dict["y"]),
                width=int(state_dict.get("w", "1000")),
                height=int(state_dict.get("h", "600")),
                workspace_num=int(state_dict.get("ws", "1")),
                monitor_name=state_dict.get("mon", "unknown"),
                timestamp=int(state_dict.get("ts", str(int(time.time()))))
            )
        except (ValueError, KeyError, IndexError):
            return None

    def to_mark_string(self) -> str:
        """
        Serialize state to mark string.

        Format: scratchpad:{project}|floating:true,x:100,y:200,w:1000,h:600,ts:1730934000,ws:1,mon:HEADLESS-1
        """
        return (
            f"scratchpad:{self.project_name}|"
            f"floating:{'true' if self.floating else 'false'},"
            f"x:{self.x},y:{self.y},"
            f"w:{self.width},h:{self.height},"
            f"ts:{self.timestamp},"
            f"ws:{self.workspace_num},"
            f"mon:{self.monitor_name}"
        )

    def is_stale(self, max_age_hours: int = 24) -> bool:
        """Check if state is stale (not updated recently)."""
        age_hours = (time.time() - self.timestamp) / 3600
        return age_hours > max_age_hours

    def to_terminal_position(self) -> TerminalPosition:
        """Convert state to TerminalPosition for restoration."""
        return TerminalPosition(
            x=self.x, y=self.y,
            width=self.width, height=self.height,
            workspace_num=self.workspace_num,
            monitor_name=self.monitor_name
        )


# ============================================================================
# Domain 4: Summon Mode Configuration
# ============================================================================

class SummonBehavior(str, Enum):
    """Workspace summoning behavior."""
    GOTO = "goto"      # Switch to terminal's workspace (default, i3run default)
    SUMMON = "summon"  # Move terminal to current workspace


class SummonMode(BaseModel):
    """Summon mode configuration."""

    behavior: SummonBehavior = Field(
        default=SummonBehavior.GOTO,
        description="Workspace summoning behavior"
    )
    mouse_positioning_enabled: bool = Field(
        default=True,
        description="Enable mouse-cursor-based positioning"
    )

    @classmethod
    def from_environment(cls) -> "SummonMode":
        """Load summon mode from environment variables."""
        behavior_str = os.getenv("I3PM_SUMMON_MODE", "goto").lower()
        mouse_enabled = os.getenv("I3PM_MOUSE_POSITION", "true").lower() == "true"

        behavior = (SummonBehavior.SUMMON if behavior_str == "summon"
                    else SummonBehavior.GOTO)

        return cls(behavior=behavior, mouse_positioning_enabled=mouse_enabled)
