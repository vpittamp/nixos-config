# Data Model: i3pm Production Readiness

**Feature**: 030-review-our-i3pm
**Date**: 2025-10-23
**Purpose**: Define data structures, relationships, and validation rules

## Overview

This document defines the data model for i3pm production readiness features. All entities use Pydantic for Python validation and TypeScript interfaces for Deno CLI type safety.

---

## Core Entities

### Project

A named development context with associated directory, applications, and workspace layouts.

**Attributes**:
- `name` (string, required): Unique project identifier (lowercase, alphanumeric + hyphens)
- `display_name` (string, required): Human-readable project name
- `icon` (string, optional): Unicode emoji or icon identifier
- `directory` (Path, required): Absolute path to project directory
- `created_at` (datetime, required): Project creation timestamp
- `scoped_classes` (list[string], optional): Application classes scoped to this project
- `layout_snapshots` (list[LayoutSnapshot], optional): Saved workspace layouts

**Validation**:
```python
from pydantic import BaseModel, Field, validator
from pathlib import Path
from datetime import datetime

class Project(BaseModel):
    name: str = Field(..., pattern=r'^[a-z0-9-]+$', min_length=1, max_length=50)
    display_name: str = Field(..., min_length=1, max_length=100)
    icon: str = Field(default="", max_length=10)
    directory: Path
    created_at: datetime = Field(default_factory=datetime.now)
    scoped_classes: list[str] = Field(default_factory=list)
    layout_snapshots: list['LayoutSnapshot'] = Field(default_factory=list)

    @validator('directory')
    def directory_must_exist(cls, v):
        if not v.exists():
            raise ValueError(f"Directory does not exist: {v}")
        return v.absolute()

    @validator('name')
    def name_must_be_unique(cls, v):
        # Check against existing projects
        pass
```

**TypeScript**:
```typescript
interface Project {
  name: string;           // Pattern: ^[a-z0-9-]+$
  displayName: string;
  icon?: string;
  directory: string;      // Absolute path
  createdAt: Date;
  scopedClasses?: string[];
  layoutSnapshots?: LayoutSnapshot[];
}
```

**Storage**: `~/.config/i3/projects/{project_name}.json`

---

### Window

An X11 window managed by i3 with project association and state tracking.

**Attributes**:
- `id` (integer, required): X11 window ID
- `window_class` (string, optional): WM_CLASS property
- `instance` (string, optional): WM_CLASS instance
- `title` (string, required): WM_NAME property
- `workspace` (string, required): Current workspace name/number
- `output` (string, required): Monitor/output name
- `marks` (list[string], required): i3 marks including project marks
- `floating` (bool, required): Window floating state
- `geometry` (WindowGeometry, required): Position and size
- `pid` (integer, optional): Process ID
- `visible` (bool, required): Current visibility state

**Validation**:
```python
class WindowGeometry(BaseModel):
    x: int
    y: int
    width: int = Field(gt=0)
    height: int = Field(gt=0)

class Window(BaseModel):
    id: int = Field(..., gt=0)
    window_class: str | None = None
    instance: str | None = None
    title: str
    workspace: str
    output: str
    marks: list[str] = Field(default_factory=list)
    floating: bool = False
    geometry: WindowGeometry
    pid: int | None = Field(default=None, gt=0)
    visible: bool = True

    def get_project_mark(self) -> str | None:
        """Extract project mark from marks list."""
        for mark in self.marks:
            if mark.startswith("project:"):
                return mark.replace("project:", "")
        return None

    @property
    def classification(self) -> ClassificationType:
        """Determine if window is scoped or global."""
        # Check classification rules
        pass
```

**TypeScript**:
```typescript
interface WindowGeometry {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface Window {
  id: number;
  windowClass?: string;
  instance?: string;
  title: string;
  workspace: string;
  output: string;
  marks: string[];
  floating: boolean;
  geometry: WindowGeometry;
  pid?: number;
  visible: boolean;
}
```

**Source**: Queried from i3 via `GET_TREE` IPC message

---

### LayoutSnapshot

A saved workspace configuration for session persistence and restoration.

**Attributes**:
- `name` (string, required): Unique layout name within project
- `project` (string, required): Associated project name
- `created_at` (datetime, required): Snapshot timestamp
- `monitor_config` (MonitorConfiguration, required): Monitor arrangement at capture time
- `workspace_layouts` (list[WorkspaceLayout], required): Layouts for each workspace
- `metadata` (dict, optional): Additional metadata (tags, description)

**Validation**:
```python
class LayoutSnapshot(BaseModel):
    name: str = Field(..., pattern=r'^[a-z0-9-]+$', min_length=1, max_length=50)
    project: str = Field(..., pattern=r'^[a-z0-9-]+$')
    created_at: datetime = Field(default_factory=datetime.now)
    monitor_config: 'MonitorConfiguration'
    workspace_layouts: list['WorkspaceLayout'] = Field(min_items=1)
    metadata: dict[str, Any] = Field(default_factory=dict)

    def to_i3_json(self) -> dict:
        """Convert to i3's append_layout JSON format."""
        # Transform to i3 layout format
        pass

    @classmethod
    def from_i3_tree(cls, tree: dict, project: str, name: str) -> 'LayoutSnapshot':
        """Create snapshot from i3 tree structure."""
        pass
```

**TypeScript**:
```typescript
interface LayoutSnapshot {
  name: string;           // Pattern: ^[a-z0-9-]+$
  project: string;
  createdAt: Date;
  monitorConfig: MonitorConfiguration;
  workspaceLayouts: WorkspaceLayout[];
  metadata?: Record<string, unknown>;
}
```

**Storage**: `~/.config/i3/layouts/{project_name}-{layout_name}.json`

---

### WorkspaceLayout

Layout definition for a single workspace within a layout snapshot.

**Attributes**:
- `workspace_num` (integer, required): Workspace number
- `workspace_name` (string, optional): Workspace name (if named)
- `output` (string, required): Assigned monitor/output
- `layout_mode` (string, required): Container layout (splith, splitv, tabbed, stacked)
- `containers` (list[Container], required): Container tree structure
- `windows` (list[WindowPlaceholder], required): Window placeholders for restoration

**Validation**:
```python
from enum import Enum

class LayoutMode(str, Enum):
    SPLITH = "splith"
    SPLITV = "splitv"
    TABBED = "tabbed"
    STACKED = "stacked"

class WorkspaceLayout(BaseModel):
    workspace_num: int = Field(..., ge=1, le=99)
    workspace_name: str = ""
    output: str
    layout_mode: LayoutMode
    containers: list['Container'] = Field(default_factory=list)
    windows: list['WindowPlaceholder'] = Field(min_items=0)

    @validator('workspace_num', 'workspace_name')
    def validate_workspace_identifier(cls, v, values):
        # At least one of workspace_num or workspace_name must be set
        pass
```

**TypeScript**:
```typescript
enum LayoutMode {
  SplitH = "splith",
  SplitV = "splitv",
  Tabbed = "tabbed",
  Stacked = "stacked",
}

interface WorkspaceLayout {
  workspaceNum: number;    // 1-99
  workspaceName?: string;
  output: string;
  layoutMode: LayoutMode;
  containers: Container[];
  windows: WindowPlaceholder[];
}
```

---

### WindowPlaceholder

Window placeholder for layout restoration with swallow criteria and launch command.

**Attributes**:
- `window_class` (string, optional): Expected WM_CLASS
- `instance` (string, optional): Expected WM_CLASS instance
- `title_pattern` (string, optional): Regex pattern for window title
- `launch_command` (string, required): Command to launch application
- `geometry` (WindowGeometry, required): Target position and size
- `floating` (bool, required): Target floating state
- `marks` (list[string], optional): Marks to apply after swallow

**Validation**:
```python
class WindowPlaceholder(BaseModel):
    window_class: str | None = None
    instance: str | None = None
    title_pattern: str | None = None
    launch_command: str = Field(..., min_length=1)
    geometry: WindowGeometry
    floating: bool = False
    marks: list[str] = Field(default_factory=list)

    @validator('launch_command')
    def validate_command_executable(cls, v):
        """Ensure command executable exists."""
        executable = shlex.split(v)[0]
        if not shutil.which(executable):
            raise ValueError(f"Command not found: {executable}")
        return v

    def to_swallow_criteria(self) -> dict:
        """Generate i3 swallow criteria."""
        criteria = {}
        if self.window_class:
            criteria["class"] = f"^{re.escape(self.window_class)}$"
        if self.instance:
            criteria["instance"] = f"^{re.escape(self.instance)}$"
        if self.title_pattern:
            criteria["title"] = self.title_pattern
        return criteria
```

**TypeScript**:
```typescript
interface WindowPlaceholder {
  windowClass?: string;
  instance?: string;
  titlePattern?: string;  // Regex
  launchCommand: string;
  geometry: WindowGeometry;
  floating: boolean;
  marks?: string[];
}
```

---

### Event

A timestamped occurrence from i3, systemd, or /proc filesystem.

**Attributes**:
- `event_id` (UUID, required): Unique event identifier
- `source` (EventSource, required): Event origin (i3, systemd, proc)
- `event_type` (string, required): Type of event (window, workspace, etc.)
- `timestamp` (datetime, required): Event occurrence time
- `data` (dict, required): Event-specific payload
- `correlation_id` (UUID, optional): Related event ID
- `confidence_score` (float, optional): Correlation confidence (0.0-1.0)

**Validation**:
```python
from uuid import UUID, uuid4

class EventSource(str, Enum):
    I3 = "i3"
    SYSTEMD = "systemd"
    PROC = "proc"

class Event(BaseModel):
    event_id: UUID = Field(default_factory=uuid4)
    source: EventSource
    event_type: str
    timestamp: datetime = Field(default_factory=datetime.now)
    data: dict[str, Any]
    correlation_id: UUID | None = None
    confidence_score: float = Field(default=None, ge=0.0, le=1.0)

    def correlate_with(self, other: 'Event', confidence: float) -> None:
        """Establish correlation with another event."""
        self.correlation_id = other.event_id
        self.confidence_score = confidence
```

**TypeScript**:
```typescript
enum EventSource {
  I3 = "i3",
  Systemd = "systemd",
  Proc = "proc",
}

interface Event {
  eventId: string;         // UUID
  source: EventSource;
  eventType: string;
  timestamp: Date;
  data: Record<string, unknown>;
  correlationId?: string;  // UUID
  confidenceScore?: number; // 0.0-1.0
}
```

**Storage**: In-memory circular buffer (500 events), persisted to `~/.local/share/i3pm/event-history/*.json`

---

### MonitorConfiguration

A named set of monitor arrangements and workspace assignments.

**Attributes**:
- `name` (string, required): Configuration name (e.g., "dual-monitor", "laptop-only")
- `monitors` (list[Monitor], required): Monitor definitions
- `workspace_assignments` (dict[int, string], required): Workspace → output mapping
- `created_at` (datetime, required): Configuration creation time

**Validation**:
```python
class MonitorConfiguration(BaseModel):
    name: str = Field(..., pattern=r'^[a-z0-9-]+$', min_length=1)
    monitors: list['Monitor'] = Field(min_items=1)
    workspace_assignments: dict[int, str]  # workspace_num → output_name
    created_at: datetime = Field(default_factory=datetime.now)

    @validator('workspace_assignments')
    def validate_assignments(cls, v, values):
        """Ensure all assigned outputs exist in monitors."""
        monitor_names = {m.name for m in values.get('monitors', [])}
        for workspace, output in v.items():
            if output not in monitor_names:
                raise ValueError(f"Workspace {workspace} assigned to unknown output: {output}")
        return v

    def detect_current() -> 'MonitorConfiguration':
        """Detect current monitor configuration from i3."""
        # Query i3 GET_OUTPUTS
        pass
```

**TypeScript**:
```typescript
interface MonitorConfiguration {
  name: string;            // Pattern: ^[a-z0-9-]+$
  monitors: Monitor[];
  workspaceAssignments: Record<number, string>; // workspace → output
  createdAt: Date;
}
```

**Storage**: `~/.config/i3/monitor-configs/{config_name}.json`

---

### Monitor

A physical or virtual display output.

**Attributes**:
- `name` (string, required): Output name (e.g., "eDP-1", "DP-1")
- `active` (bool, required): Output is currently active
- `primary` (bool, required): Primary display flag
- `current_workspace` (string, optional): Currently visible workspace
- `resolution` (Resolution, optional): Display resolution
- `position` (Position, required): Display position in multi-monitor setup

**Validation**:
```python
class Resolution(BaseModel):
    width: int = Field(gt=0)
    height: int = Field(gt=0)

class Position(BaseModel):
    x: int
    y: int

class Monitor(BaseModel):
    name: str = Field(..., min_length=1)
    active: bool
    primary: bool = False
    current_workspace: str | None = None
    resolution: Resolution | None = None
    position: Position

    @classmethod
    def from_i3_output(cls, output_data: dict) -> 'Monitor':
        """Create Monitor from i3 GET_OUTPUTS response."""
        return cls(
            name=output_data["name"],
            active=output_data["active"],
            primary=output_data.get("primary", False),
            current_workspace=output_data.get("current_workspace"),
            resolution=Resolution(
                width=output_data["rect"]["width"],
                height=output_data["rect"]["height"]
            ) if output_data.get("rect") else None,
            position=Position(
                x=output_data["rect"]["x"],
                y=output_data["rect"]["y"]
            ) if output_data.get("rect") else Position(x=0, y=0)
        )
```

**TypeScript**:
```typescript
interface Resolution {
  width: number;
  height: number;
}

interface Position {
  x: number;
  y: number;
}

interface Monitor {
  name: string;
  active: boolean;
  primary: boolean;
  currentWorkspace?: string;
  resolution?: Resolution;
  position: Position;
}
```

**Source**: Queried from i3 via `GET_OUTPUTS` IPC message

---

### ClassificationRule

Defines whether an application is scoped (project-specific) or global (always visible).

**Attributes**:
- `pattern` (string, required): Regex pattern matching window class, instance, or title
- `scope_type` (ScopeType, required): Scoped or global classification
- `priority` (integer, required): Rule precedence (higher wins)
- `pattern_type` (PatternType, required): What property to match (class, instance, title)
- `source` (RuleSource, required): System-wide or user-defined

**Validation**:
```python
class ScopeType(str, Enum):
    SCOPED = "scoped"
    GLOBAL = "global"

class PatternType(str, Enum):
    CLASS = "class"
    INSTANCE = "instance"
    TITLE = "title"

class RuleSource(str, Enum):
    SYSTEM = "system"
    USER = "user"

class ClassificationRule(BaseModel):
    pattern: str = Field(..., min_length=1)
    scope_type: ScopeType
    priority: int = Field(default=0, ge=0, le=100)
    pattern_type: PatternType = PatternType.CLASS
    source: RuleSource = RuleSource.USER

    @validator('pattern')
    def validate_regex(cls, v):
        """Ensure pattern is valid regex."""
        try:
            re.compile(v)
        except re.error as e:
            raise ValueError(f"Invalid regex pattern: {e}")
        return v

    def matches(self, window: Window) -> bool:
        """Test if rule matches window."""
        if self.pattern_type == PatternType.CLASS:
            target = window.window_class or ""
        elif self.pattern_type == PatternType.INSTANCE:
            target = window.instance or ""
        else:  # TITLE
            target = window.title

        return bool(re.search(self.pattern, target, re.IGNORECASE))
```

**TypeScript**:
```typescript
enum ScopeType {
  Scoped = "scoped",
  Global = "global",
}

enum PatternType {
  Class = "class",
  Instance = "instance",
  Title = "title",
}

enum RuleSource {
  System = "system",
  User = "user",
}

interface ClassificationRule {
  pattern: string;         // Regex
  scopeType: ScopeType;
  priority: number;        // 0-100
  patternType: PatternType;
  source: RuleSource;
}
```

**Storage**:
- System: `/etc/i3pm/rules.json`
- User: `~/.config/i3/app-classes.json`

---

## Relationships

```
Project (1) ─┬─→ (N) LayoutSnapshot
             │
             └─→ (N) ClassificationRule (via scoped_classes)

LayoutSnapshot (1) ─┬─→ (1) MonitorConfiguration
                    │
                    └─→ (N) WorkspaceLayout

WorkspaceLayout (1) ─┬─→ (N) Container
                     │
                     └─→ (N) WindowPlaceholder

MonitorConfiguration (1) ─→ (N) Monitor

Window (N) ─→ (1) Project (via project mark)
Window (N) ─→ (1) Monitor (via output)
Window (N) ─→ (N) ClassificationRule (via pattern matching)

Event (N) ─→ (1) Event (via correlation_id)
```

---

## State Transitions

### Window Lifecycle

```
Created → Classified → Marked → Visible/Hidden → Destroyed
```

1. **Created**: Window appears in i3 tree (window::new event)
2. **Classified**: Match against classification rules (scoped vs global)
3. **Marked**: Apply project mark if scoped and project is active
4. **Visible/Hidden**: Show/hide based on active project
5. **Destroyed**: Window closed (window::close event)

### Project Lifecycle

```
Defined → Inactive → Active → Inactive → Deleted
```

1. **Defined**: Project created via `i3pm project create`
2. **Inactive**: Project exists but not active (no windows visible)
3. **Active**: Project switched to via `i3pm project switch`
4. **Inactive**: Different project activated
5. **Deleted**: Project removed via `i3pm project delete`

### Layout Lifecycle

```
Captured → Saved → Loaded → Restored
```

1. **Captured**: Current workspace state captured via `i3pm layout save`
2. **Saved**: Layout snapshot written to disk
3. **Loaded**: Layout file read on restore request
4. **Restored**: Windows launched and swallowed into layout

---

## Validation Rules

### Global Constraints

1. **Unique Project Names**: No two projects can have the same name
2. **Unique Layout Names**: Within a project, layout names must be unique
3. **Valid Workspace Numbers**: Workspace numbers must be 1-99
4. **Valid Output Names**: Output names must match active monitor names
5. **Valid File Paths**: All directory paths must be absolute and exist

### Business Rules

1. **Project Directory Existence**: Project directories must exist before project creation
2. **Classification Precedence**: System rules override user rules unless explicit override
3. **Layout Compatibility**: Layouts can only be restored if monitor config is compatible
4. **Event Buffer Limit**: Circular buffer maintains max 500 most recent events
5. **Mark Format**: Project marks must follow `project:{project_name}` format

### Security Rules

1. **UID Validation**: IPC clients must match daemon UID
2. **Sensitive Data Sanitization**: Command lines and titles sanitized before logging
3. **File Permissions**: Configuration files must be readable only by owner (0600)
4. **Path Traversal Prevention**: All paths validated to prevent escaping project directory

---

## Data Migration

### Version Compatibility

**Current Version**: 2.0 (Deno CLI + Python daemon)
**Legacy Version**: 1.0 (Python TUI)

**Migration Strategy**:
```python
def migrate_legacy_project(legacy_path: Path) -> Project:
    """Migrate project from Python TUI format to new format."""
    with open(legacy_path) as f:
        legacy_data = json.load(f)

    return Project(
        name=legacy_data["name"],
        display_name=legacy_data.get("display_name", legacy_data["name"]),
        icon=legacy_data.get("icon", ""),
        directory=Path(legacy_data["directory"]),
        created_at=datetime.fromisoformat(legacy_data["created_at"]),
        scoped_classes=legacy_data.get("scoped_classes", []),
        layout_snapshots=[]  # Legacy doesn't have layouts
    )
```

**Breaking Changes**: None - schema is backwards compatible with Feature 015/025/029 data formats.

---

## Summary

This data model provides:
- **Type Safety**: Pydantic validation in Python, TypeScript interfaces in Deno
- **Consistency**: Shared entity definitions across daemon and CLI
- **Validation**: Comprehensive validation rules at model level
- **i3 Alignment**: Data structures mirror i3's IPC API where applicable
- **Extensibility**: Metadata fields allow future enhancements without schema changes

All entities are designed to align with Constitution Principle XI (i3 IPC Authority) by using i3's native data structures where possible.
