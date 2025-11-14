"""
Data models for i3pm production readiness

Feature 030: Production Readiness
Task T006: Pydantic data models

All models use Pydantic v2 for data validation and serialization.
"""

from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Optional
from uuid import UUID, uuid4
import re
import shlex
import shutil

from pydantic import BaseModel, Field, field_validator, model_validator


# ============================================================================
# Enums
# ============================================================================

class LayoutMode(str, Enum):
    """Container layout modes in i3"""
    SPLITH = "splith"
    SPLITV = "splitv"
    TABBED = "tabbed"
    STACKED = "stacked"


class EventSource(str, Enum):
    """Event origin sources"""
    I3 = "i3"
    SYSTEMD = "systemd"
    PROC = "proc"


class ScopeType(str, Enum):
    """Application scope classification"""
    SCOPED = "scoped"
    GLOBAL = "global"


class PatternType(str, Enum):
    """Window property to match against"""
    CLASS = "class"
    INSTANCE = "instance"
    TITLE = "title"


class RuleSource(str, Enum):
    """Classification rule source"""
    SYSTEM = "system"
    USER = "user"


class CorrelationStatus(str, Enum):
    """Status of window correlation attempt (Feature 074: T043, US3)"""
    PENDING = "pending"      # Waiting for window to appear
    MATCHED = "matched"      # Window successfully matched
    TIMEOUT = "timeout"      # Window did not appear within timeout
    FAILED = "failed"        # Matching failed due to error


# ============================================================================
# Geometry and Position
# ============================================================================

class WindowGeometry(BaseModel):
    """Window position and size"""
    x: int
    y: int
    width: int = Field(gt=0)
    height: int = Field(gt=0)


class Resolution(BaseModel):
    """Display resolution"""
    width: int = Field(gt=0)
    height: int = Field(gt=0)


class Position(BaseModel):
    """Display position in multi-monitor setup"""
    x: int
    y: int


# ============================================================================
# Core Entities
# ============================================================================

class Project(BaseModel):
    """A named development context with associated directory and applications"""
    name: str = Field(..., pattern=r'^[a-z0-9-]+$', min_length=1, max_length=50)
    display_name: str = Field(..., min_length=1, max_length=100)
    icon: str = Field(default="", max_length=10)
    directory: Path
    created_at: datetime = Field(default_factory=datetime.now)
    scoped_classes: list[str] = Field(default_factory=list)
    layout_snapshots: list['LayoutSnapshot'] = Field(default_factory=list)

    @field_validator('directory')
    @classmethod
    def directory_must_be_absolute(cls, v: Path) -> Path:
        """Ensure directory is absolute path"""
        return v.absolute()

    @field_validator('name')
    @classmethod
    def name_must_be_lowercase(cls, v: str) -> str:
        """Ensure project name is lowercase with hyphens only"""
        if not re.match(r'^[a-z0-9-]+$', v):
            raise ValueError(f"Project name must be lowercase alphanumeric with hyphens: {v}")
        return v


class Window(BaseModel):
    """An X11 window managed by i3 with project association"""
    id: int = Field(..., gt=0)
    window_class: Optional[str] = None
    instance: Optional[str] = None
    title: str
    workspace: str
    output: str
    marks: list[str] = Field(default_factory=list)
    floating: bool = False
    geometry: WindowGeometry
    pid: Optional[int] = Field(default=None, gt=0)
    visible: bool = True

    def get_project_mark(self) -> Optional[str]:
        """Extract project name from marks list"""
        for mark in self.marks:
            if mark.startswith("project:"):
                return mark.replace("project:", "")
        return None


class WindowPlaceholder(BaseModel):
    """Window placeholder for layout restoration

    Feature 074: Session Management
    Extended with terminal cwd tracking, focused state, and mark-based correlation

    ⚠️ BREAKING CHANGE: All Feature 074 fields are REQUIRED (no Optional)
    """
    window_class: Optional[str] = None
    instance: Optional[str] = None
    title_pattern: Optional[str] = None
    launch_command: str = Field(..., min_length=1)
    geometry: WindowGeometry
    floating: bool = False
    marks: list[str] = Field(default_factory=list)

    # Feature 074: Session Management extensions - ALL REQUIRED
    cwd: Path  # Terminal working directory (T007, US2) - Path() for non-terminals
    focused: bool  # Window focus state (T007, US4) - exactly one per workspace
    restoration_mark: str  # Temporary mark for Sway correlation (T007, US3) - generated during restore
    app_registry_name: str  # App registry name for wrapper-based restoration (T015A) - "unknown" for manual launches

    @field_validator('launch_command')
    @classmethod
    def validate_command_executable(cls, v: str) -> str:
        """Ensure command executable exists"""
        try:
            executable = shlex.split(v)[0]
            if not shutil.which(executable):
                raise ValueError(f"Command not found: {executable}")
        except Exception as e:
            raise ValueError(f"Invalid command: {e}")
        return v

    @field_validator('cwd')
    @classmethod
    def validate_cwd_absolute(cls, v: Path) -> Path:
        """Ensure cwd is absolute path or empty (T008, US2)"""
        if v != Path() and not v.is_absolute():
            raise ValueError(f"Working directory must be absolute or empty: {v}")
        return v

    @field_validator('app_registry_name')
    @classmethod
    def validate_app_name_not_empty(cls, v: str) -> str:
        """Ensure app name is not empty string"""
        if not v or not v.strip():
            raise ValueError("app_registry_name cannot be empty")
        return v

    @field_validator('restoration_mark')
    @classmethod
    def validate_restoration_mark_format(cls, v: str) -> str:
        """Ensure restoration mark follows expected format"""
        if not v.startswith("i3pm-restore-") or len(v) != 21:  # i3pm-restore- + 8 hex chars
            raise ValueError(f"Invalid restoration mark format: {v}")
        return v

    def to_swallow_criteria(self) -> dict[str, str]:
        """Generate i3 swallow criteria"""
        criteria = {}
        if self.window_class:
            criteria["class"] = f"^{re.escape(self.window_class)}$"
        if self.instance:
            criteria["instance"] = f"^{re.escape(self.instance)}$"
        if self.title_pattern:
            criteria["title"] = self.title_pattern
        return criteria

    def is_terminal(self) -> bool:
        """Check if this placeholder represents a terminal application (T009, US2)"""
        TERMINAL_CLASSES = {"ghostty", "Alacritty", "kitty", "foot", "WezTerm"}
        return self.window_class in TERMINAL_CLASSES

    def get_launch_env(self, project: str) -> dict[str, str]:
        """Generate environment variables for window launch with correlation mark (T010, US3)

        Note: restoration_mark must be set before calling this method
        """
        import os

        env = {
            **os.environ,
            "I3PM_RESTORE_MARK": self.restoration_mark,
            "I3PM_PROJECT": project,
        }

        return env


class Container(BaseModel):
    """Container in i3 window tree (placeholder for future implementation)"""
    layout: LayoutMode = LayoutMode.SPLITH
    percent: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    nodes: list['Container'] = Field(default_factory=list)


class WorkspaceLayout(BaseModel):
    """Layout definition for a single workspace"""
    workspace_num: int = Field(..., ge=1, le=99)
    workspace_name: str = ""
    output: str
    layout_mode: LayoutMode
    containers: list[Container] = Field(default_factory=list)
    windows: list[WindowPlaceholder] = Field(default_factory=list)


class Monitor(BaseModel):
    """A physical or virtual display output"""
    name: str = Field(..., min_length=1)
    active: bool
    primary: bool = False
    current_workspace: Optional[str] = None
    resolution: Optional[Resolution] = None
    position: Position

    @classmethod
    def from_i3_output(cls, output_data: dict) -> 'Monitor':
        """Create Monitor from i3 GET_OUTPUTS response"""
        rect = output_data.get("rect")
        return cls(
            name=output_data["name"],
            active=output_data["active"],
            primary=output_data.get("primary", False),
            current_workspace=output_data.get("current_workspace"),
            resolution=Resolution(
                width=rect["width"],
                height=rect["height"]
            ) if rect else None,
            position=Position(
                x=rect["x"],
                y=rect["y"]
            ) if rect else Position(x=0, y=0)
        )


class MonitorConfiguration(BaseModel):
    """A named set of monitor arrangements and workspace assignments"""
    name: str = Field(..., pattern=r'^[a-z0-9-]+$', min_length=1)
    monitors: list[Monitor] = Field(min_length=1)
    workspace_assignments: dict[int, str]  # workspace_num → output_name
    created_at: datetime = Field(default_factory=datetime.now)

    @model_validator(mode='after')
    def validate_assignments(self) -> 'MonitorConfiguration':
        """Ensure all assigned outputs exist in monitors"""
        monitor_names = {m.name for m in self.monitors}
        for workspace, output in self.workspace_assignments.items():
            if output not in monitor_names:
                raise ValueError(f"Workspace {workspace} assigned to unknown output: {output}")
        return self


class LayoutSnapshot(BaseModel):
    """A saved workspace configuration for session persistence

    Feature 074: Session Management
    Extended with focused workspace tracking for session restoration

    ⚠️ BREAKING CHANGE: focused_workspace is REQUIRED (no Optional)
    """
    name: str = Field(..., pattern=r'^[a-z0-9-]+$', min_length=1, max_length=50)
    project: str = Field(..., pattern=r'^[a-z0-9-]+$')
    created_at: datetime = Field(default_factory=datetime.now)
    monitor_config: MonitorConfiguration
    workspace_layouts: list[WorkspaceLayout] = Field(min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)

    # Feature 074: Session Management extension - REQUIRED
    focused_workspace: int = Field(..., ge=1, le=70)  # T011, US1 - always captured, fallback to 1

    @model_validator(mode='after')
    def validate_focused_workspace_exists(self) -> 'LayoutSnapshot':
        """Ensure focused workspace exists in workspace_layouts (T012, US1)"""
        workspace_nums = {wl.workspace_num for wl in self.workspace_layouts}
        if self.focused_workspace not in workspace_nums:
            raise ValueError(
                f"Focused workspace {self.focused_workspace} not in layout workspaces: {workspace_nums}"
            )
        return self

    def is_auto_save(self) -> bool:
        """Check if this is an auto-saved layout (name starts with 'auto-') (T013, US5)"""
        return self.name.startswith("auto-")

    def get_timestamp(self) -> Optional[str]:
        """Extract timestamp from auto-save name (format: auto-YYYYMMDD-HHMMSS) (T013, US5)"""
        if not self.is_auto_save():
            return None
        # Extract timestamp portion after "auto-"
        return self.name[5:] if len(self.name) > 5 else None

    def to_i3_json(self) -> dict[str, Any]:
        """Convert to i3's append_layout JSON format (placeholder)"""
        # TODO: Implement in Phase 4 (US2: Layout Persistence)
        raise NotImplementedError("Layout serialization implemented in Phase 4")

    @classmethod
    def from_i3_tree(cls, tree: dict, project: str, name: str) -> 'LayoutSnapshot':
        """Create snapshot from i3 tree structure (placeholder)"""
        # TODO: Implement in Phase 4 (US2: Layout Persistence)
        raise NotImplementedError("Layout capture implemented in Phase 4")


class Event(BaseModel):
    """A timestamped occurrence from i3, systemd, or /proc filesystem"""
    event_id: UUID = Field(default_factory=uuid4)
    source: EventSource
    event_type: str
    timestamp: datetime = Field(default_factory=datetime.now)
    data: dict[str, Any]
    correlation_id: Optional[UUID] = None
    confidence_score: Optional[float] = Field(default=None, ge=0.0, le=1.0)

    def correlate_with(self, other: 'Event', confidence: float) -> None:
        """Establish correlation with another event"""
        self.correlation_id = other.event_id
        self.confidence_score = confidence


class RestoreCorrelation(BaseModel):
    """Tracks correlation state for a single window restoration (Feature 074: T042, US3)

    Used by mark-based correlation to track window matching during layout restoration.
    Each window restoration gets a unique correlation ID and restoration mark.
    """
    correlation_id: UUID = Field(default_factory=uuid4)
    restoration_mark: str = Field(..., pattern=r'^i3pm-restore-[0-9a-f]{8}$')
    placeholder: WindowPlaceholder
    status: CorrelationStatus = CorrelationStatus.PENDING
    started_at: datetime = Field(default_factory=datetime.now)
    completed_at: Optional[datetime] = None
    matched_window_id: Optional[int] = None
    error_message: Optional[str] = None

    @property
    def elapsed_seconds(self) -> float:
        """Time elapsed since correlation started (T045, US3)"""
        end_time = self.completed_at or datetime.now()
        return (end_time - self.started_at).total_seconds()

    @property
    def is_complete(self) -> bool:
        """Check if correlation has finished - matched, timeout, or failed (T045, US3)"""
        return self.status != CorrelationStatus.PENDING

    def mark_matched(self, window_id: int) -> None:
        """Mark correlation as successfully matched (T044, US3)"""
        self.status = CorrelationStatus.MATCHED
        self.matched_window_id = window_id
        self.completed_at = datetime.now()

    def mark_timeout(self) -> None:
        """Mark correlation as timed out (T044, US3)"""
        self.status = CorrelationStatus.TIMEOUT
        self.completed_at = datetime.now()
        self.error_message = f"No window appeared with mark {self.restoration_mark} within timeout"

    def mark_failed(self, error: str) -> None:
        """Mark correlation as failed with error message (T044, US3)"""
        self.status = CorrelationStatus.FAILED
        self.completed_at = datetime.now()
        self.error_message = error


class ClassificationRule(BaseModel):
    """Defines whether an application is scoped or global"""
    pattern: str = Field(..., min_length=1)
    scope_type: ScopeType
    priority: int = Field(default=0, ge=0, le=100)
    pattern_type: PatternType = PatternType.CLASS
    source: RuleSource = RuleSource.USER

    @field_validator('pattern')
    @classmethod
    def validate_regex(cls, v: str) -> str:
        """Ensure pattern is valid regex"""
        try:
            re.compile(v)
        except re.error as e:
            raise ValueError(f"Invalid regex pattern: {e}")
        return v

    def matches(self, window: Window) -> bool:
        """Test if rule matches window"""
        if self.pattern_type == PatternType.CLASS:
            target = window.window_class or ""
        elif self.pattern_type == PatternType.INSTANCE:
            target = window.instance or ""
        else:  # TITLE
            target = window.title

        return bool(re.search(self.pattern, target, re.IGNORECASE))


# Forward references resolution
Container.model_rebuild()
Project.model_rebuild()
