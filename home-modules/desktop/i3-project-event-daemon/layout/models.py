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
    """Window placeholder for layout restoration"""
    window_class: Optional[str] = None
    instance: Optional[str] = None
    title_pattern: Optional[str] = None
    launch_command: str = Field(..., min_length=1)
    geometry: WindowGeometry
    floating: bool = False
    marks: list[str] = Field(default_factory=list)

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
    """A saved workspace configuration for session persistence"""
    name: str = Field(..., pattern=r'^[a-z0-9-]+$', min_length=1, max_length=50)
    project: str = Field(..., pattern=r'^[a-z0-9-]+$')
    created_at: datetime = Field(default_factory=datetime.now)
    monitor_config: MonitorConfiguration
    workspace_layouts: list[WorkspaceLayout] = Field(min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)

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
