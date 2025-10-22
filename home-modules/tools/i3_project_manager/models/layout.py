"""
Data models for layout save/restore and window state management.

These models use Pydantic for validation and are based on the i3 IPC data structures
with extensions for i3pm-specific functionality.
"""

import re
import shlex
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel, Field, field_validator, model_validator


class WindowGeometry(BaseModel):
    """Window geometry (size and position)."""

    x: int
    y: int
    width: int
    height: int

    @field_validator("width", "height")
    @classmethod
    def validate_positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("Width and height must be positive")
        return v


class SwallowCriteria(BaseModel):
    """Swallow criteria for window matching during restore."""

    window_class: Optional[str] = Field(default=None, description="Window class regex")
    instance: Optional[str] = Field(default=None, description="Instance regex")
    title: Optional[str] = Field(default=None, description="Title regex")
    window_role: Optional[str] = Field(default=None, description="Window role regex")

    @model_validator(mode="after")
    def validate_at_least_one_criteria(self):
        """At least one criteria must be specified."""
        if not any(
            [self.window_class, self.instance, self.title, self.window_role]
        ):
            raise ValueError("At least one swallow criteria must be specified")
        return self

    @model_validator(mode="after")
    def validate_regex_patterns(self):
        """All specified patterns must be valid regex."""
        for field_name in ["window_class", "instance", "title", "window_role"]:
            pattern = getattr(self, field_name)
            if pattern:
                try:
                    re.compile(pattern)
                except re.error as e:
                    raise ValueError(f"Invalid regex in {field_name}: {e}")
        return self

    def matches(self, window: "WindowState") -> bool:
        """Check if window matches these criteria."""
        if self.window_class and not re.match(
            self.window_class, window.window_class
        ):
            return False
        if self.instance and not re.match(self.instance, window.instance):
            return False
        if self.title and not re.match(self.title, window.title):
            return False
        if (
            self.window_role
            and window.window_role
            and not re.match(self.window_role, window.window_role)
        ):
            return False
        return True

    def to_i3_swallow(self) -> Dict[str, str]:
        """Convert to i3 swallow JSON format."""
        swallow = {}
        if self.window_class:
            swallow["class"] = self.window_class
        if self.instance:
            swallow["instance"] = self.instance
        if self.title:
            swallow["title"] = self.title
        if self.window_role:
            swallow["window_role"] = self.window_role
        return swallow


class WindowState(BaseModel):
    """Current state of a window from i3 IPC."""

    id: int = Field(..., gt=0, description="i3 window ID")
    window_class: str = Field(..., min_length=1, description="X11 window class")
    instance: str = Field(..., min_length=1, description="X11 window instance")
    title: str = Field(default="", description="Window title")
    window_role: Optional[str] = Field(default=None, description="X11 window role")
    workspace: int = Field(..., ge=1, le=10, description="Workspace number")
    workspace_name: str = Field(..., description="Workspace name")
    output: str = Field(..., min_length=1, description="Monitor output name")
    marks: List[str] = Field(default_factory=list, description="i3 marks")
    floating: bool = Field(default=False, description="Floating state")
    focused: bool = Field(default=False, description="Focus state")
    geometry: WindowGeometry = Field(..., description="Window geometry")
    pid: Optional[int] = Field(default=None, description="Process ID")
    project: Optional[str] = Field(default=None, description="Associated project")
    classification: str = Field(default="global", description="Scoped or global")
    hidden: bool = Field(default=False, description="Hidden by project scope")
    app_identifier: Optional[str] = Field(default=None, description="App identifier")

    @field_validator("classification")
    @classmethod
    def validate_classification(cls, v: str) -> str:
        if v not in ["scoped", "global"]:
            raise ValueError("Classification must be 'scoped' or 'global'")
        return v

    @field_validator("project")
    @classmethod
    def validate_project_mark(cls, v: Optional[str], info) -> Optional[str]:
        """Ensure project matches mark if present."""
        if v:
            marks = info.data.get("marks", [])
            expected_mark = f"project:{v}"
            if expected_mark not in marks:
                raise ValueError(
                    f"Project '{v}' must have corresponding mark '{expected_mark}'"
                )
        return v


class MonitorInfo(BaseModel):
    """Monitor configuration snapshot."""

    name: str = Field(..., description="Output name")
    active: bool = Field(..., description="Active status")
    width: int = Field(..., gt=0, description="Width in pixels")
    height: int = Field(..., gt=0, description="Height in pixels")
    x: int = Field(default=0, description="X position")
    y: int = Field(default=0, description="Y position")


class LaunchCommand(BaseModel):
    """Launch command for window restoration."""

    command: str = Field(..., min_length=1, description="Shell command")
    working_directory: Optional[Path] = Field(
        default=None, description="Working directory"
    )
    environment: Dict[str, str] = Field(
        default_factory=dict, description="Environment"
    )
    source: str = Field(..., description="Command source")

    @field_validator("source")
    @classmethod
    def validate_source(cls, v: str) -> str:
        """Validate source."""
        if v not in ["discovered", "configured"]:
            raise ValueError(f"Source must be 'discovered' or 'configured', got: {v}")
        return v


class LayoutWindow(BaseModel):
    """Window configuration in a saved layout."""

    swallows: List[SwallowCriteria] = Field(
        ..., min_length=1, description="Matching criteria"
    )
    launch_command: Optional[str] = Field(default=None, description="Launch command")
    working_directory: Optional[Path] = Field(
        default=None, description="Working directory"
    )
    environment: Dict[str, str] = Field(
        default_factory=dict, description="Environment vars"
    )
    geometry: WindowGeometry = Field(..., description="Target geometry")
    floating: bool = Field(default=False, description="Floating state")
    border: str = Field(default="pixel", description="Border style")
    layout: str = Field(default="splith", description="Container layout")
    percent: Optional[float] = Field(default=None, description="Size percentage")

    @field_validator("launch_command")
    @classmethod
    def validate_launch_command(cls, v: Optional[str]) -> Optional[str]:
        """Validate launch command for safety."""
        if not v:
            return v

        # Check for shell injection characters
        forbidden = ["|", "&", ";", "`", "\n", "$(", ">", "<"]
        if any(char in v for char in forbidden):
            raise ValueError(f"Launch command contains forbidden characters: {v}")

        # Must be parseable as shell command
        try:
            shlex.split(v)
        except ValueError as e:
            raise ValueError(f"Invalid shell command syntax: {e}")

        return v

    @field_validator("working_directory")
    @classmethod
    def validate_working_directory(cls, v: Optional[Path]) -> Optional[Path]:
        """Validate working directory exists."""
        if v and not v.is_dir():
            raise ValueError(f"Working directory does not exist: {v}")
        return v

    @field_validator("environment")
    @classmethod
    def filter_secrets(cls, v: Dict[str, str]) -> Dict[str, str]:
        """Filter sensitive environment variables."""
        secret_patterns = ["TOKEN", "SECRET", "PASSWORD", "KEY", "AWS_", "API_"]
        filtered = {
            k: val
            for k, val in v.items()
            if not any(pattern in k.upper() for pattern in secret_patterns)
        }
        if len(filtered) < len(v):
            removed_keys = set(v.keys()) - set(filtered.keys())
            print(f"Warning: Filtered secrets from environment: {removed_keys}")
        return filtered

    @field_validator("border")
    @classmethod
    def validate_border(cls, v: str) -> str:
        """Validate border style."""
        valid_borders = ["normal", "pixel", "none"]
        if v not in valid_borders:
            raise ValueError(f"Border must be one of {valid_borders}, got: {v}")
        return v

    @field_validator("layout")
    @classmethod
    def validate_layout(cls, v: str) -> str:
        """Validate layout mode."""
        valid_layouts = ["splith", "splitv", "stacked", "tabbed"]
        if v not in valid_layouts:
            raise ValueError(f"Layout must be one of {valid_layouts}, got: {v}")
        return v

    @field_validator("percent")
    @classmethod
    def validate_percent(cls, v: Optional[float]) -> Optional[float]:
        """Validate size percentage."""
        if v is not None and not (0.0 < v <= 1.0):
            raise ValueError(f"Percent must be between 0.0 and 1.0, got: {v}")
        return v


class WorkspaceLayout(BaseModel):
    """Saved layout for a single workspace."""

    number: int = Field(..., ge=1, le=10, description="Workspace number")
    output: str = Field(..., min_length=1, description="Target output")
    layout: str = Field(..., description="Workspace layout mode")
    windows: List[LayoutWindow] = Field(default_factory=list, description="Windows")
    saved_at: datetime = Field(..., description="Save timestamp")
    window_count: int = Field(..., ge=0, description="Window count")

    @field_validator("layout")
    @classmethod
    def validate_layout(cls, v: str) -> str:
        """Validate layout mode."""
        valid_layouts = ["splith", "splitv", "stacked", "tabbed", "default"]
        if v not in valid_layouts:
            raise ValueError(f"Layout must be one of {valid_layouts}, got: {v}")
        return v

    @model_validator(mode="after")
    def validate_window_count(self):
        """Ensure window_count matches windows list."""
        if self.window_count != len(self.windows):
            raise ValueError(
                f"window_count ({self.window_count}) does not match windows list length ({len(self.windows)})"
            )
        return self


class SavedLayout(BaseModel):
    """Complete saved layout for a project."""

    version: str = Field(default="1.0", description="Format version")
    project: str = Field(..., min_length=1, description="Project name")
    layout_name: str = Field(..., min_length=1, description="Layout name")
    saved_at: datetime = Field(..., description="Save timestamp")
    monitor_count: int = Field(..., gt=0, description="Monitor count")
    monitor_config: Dict[str, MonitorInfo] = Field(
        ..., description="Monitor details"
    )
    workspaces: List[WorkspaceLayout] = Field(
        ..., min_length=1, description="Workspaces"
    )
    total_windows: int = Field(..., ge=0, description="Total windows")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Metadata")

    @field_validator("version")
    @classmethod
    def validate_version(cls, v: str) -> str:
        """Ensure version is supported."""
        if v != "1.0":
            raise ValueError(f"Unsupported layout version: {v}, expected 1.0")
        return v

    @field_validator("layout_name")
    @classmethod
    def validate_layout_name(cls, v: str) -> str:
        """Ensure layout name is filesystem-safe."""
        if not v.replace("-", "").replace("_", "").isalnum():
            raise ValueError(f"Layout name must be alphanumeric with - or _: {v}")
        return v

    @model_validator(mode="after")
    def validate_monitor_count(self):
        """Ensure monitor_count matches monitor_config."""
        if self.monitor_count != len(self.monitor_config):
            raise ValueError(
                f"monitor_count ({self.monitor_count}) does not match monitor_config length ({len(self.monitor_config)})"
            )
        return self

    @model_validator(mode="after")
    def validate_total_windows(self):
        """Ensure total_windows matches sum of workspace windows."""
        calculated_total = sum(ws.window_count for ws in self.workspaces)
        if self.total_windows != calculated_total:
            raise ValueError(
                f"total_windows ({self.total_windows}) does not match calculated total ({calculated_total})"
            )
        return self

    def get_workspace(self, number: int) -> Optional[WorkspaceLayout]:
        """Get workspace layout by number."""
        for ws in self.workspaces:
            if ws.number == number:
                return ws
        return None

    def export_i3_json(self) -> Dict[str, Any]:
        """Export as vanilla i3 JSON (strip i3pm extensions)."""
        # Implementation will be added in layout export tasks
        raise NotImplementedError("export_i3_json will be implemented in Phase 7")


class WindowDiff(BaseModel):
    """Diff between current state and saved layout."""

    layout_name: str = Field(..., description="Layout name")
    current_windows: int = Field(..., ge=0, description="Current window count")
    saved_windows: int = Field(..., ge=0, description="Saved window count")
    added: List[WindowState] = Field(default_factory=list, description="Added windows")
    removed: List[LayoutWindow] = Field(
        default_factory=list, description="Removed windows"
    )
    moved: List[Tuple[WindowState, LayoutWindow]] = Field(
        default_factory=list, description="Moved windows"
    )
    kept: List[Tuple[WindowState, LayoutWindow]] = Field(
        default_factory=list, description="Unchanged windows"
    )
    computed_at: datetime = Field(
        default_factory=datetime.now, description="Computation time"
    )

    @model_validator(mode="after")
    def validate_counts(self):
        """Validate window counts match categories."""
        total_current = len(self.added) + len(self.moved) + len(self.kept)
        if total_current != self.current_windows:
            raise ValueError(
                f"Current window count mismatch: {total_current} != {self.current_windows}"
            )

        total_saved = len(self.removed) + len(self.moved) + len(self.kept)
        if total_saved != self.saved_windows:
            raise ValueError(
                f"Saved window count mismatch: {total_saved} != {self.saved_windows}"
            )

        return self

    def has_changes(self) -> bool:
        """Check if there are any differences."""
        return len(self.added) > 0 or len(self.removed) > 0 or len(self.moved) > 0

    def summary(self) -> str:
        """Human-readable diff summary."""
        if not self.has_changes():
            return f"No changes vs '{self.layout_name}'"

        parts = []
        if self.added:
            parts.append(f"+{len(self.added)} added")
        if self.removed:
            parts.append(f"-{len(self.removed)} removed")
        if self.moved:
            parts.append(f"~{len(self.moved)} moved")

        return f"Changes vs '{self.layout_name}': {', '.join(parts)}"
