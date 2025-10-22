# Data Model: Visual Window State Management

**Feature Branch**: `025-visual-window-state`
**Created**: 2025-10-22
**Purpose**: Define all entities, relationships, and validation rules

## Entity Relationship Diagram

```
┌──────────────┐
│   Project    │
└──────┬───────┘
       │ 1
       │
       │ 0..*
┌──────┴───────────┐
│  SavedLayout     │◄──────────────┐
└──────┬───────────┘               │
       │ 1                          │ extends
       │                            │
       │ 1..*                  ┌────┴────────┐
┌──────┴──────────────┐        │  i3 JSON    │
│ WorkspaceLayout     │        │  Format     │
└──────┬──────────────┘        └─────────────┘
       │ 1
       │
       │ 0..*
┌──────┴─────────┐
│ LayoutWindow   │
└──────┬─────────┘
       │ 1
       │
       │ 1..*
┌──────┴────────────┐
│ SwallowCriteria   │
└───────────────────┘

┌──────────────────┐
│  WindowState     │  (real-time from i3 IPC)
└──────────────────┘

┌──────────────┐
│  WindowDiff  │  (computed)
└──────────────┘
```

## Core Entities

### WindowState

**Purpose**: Represents current state of a single window as reported by i3 IPC GET_TREE

**Source**: i3 window manager via i3 IPC API (authoritative)

**Fields**:

| Field | Type | Required | Description | Source |
|-------|------|----------|-------------|--------|
| id | int | Yes | Unique i3 window ID | i3 IPC |
| window_class | str | Yes | X11 window class | i3 IPC |
| instance | str | Yes | X11 window instance | i3 IPC |
| title | str | Yes | Window title | i3 IPC |
| window_role | Optional[str] | No | X11 window role | i3 IPC |
| workspace | int | Yes | Workspace number (1-10) | i3 IPC |
| workspace_name | str | Yes | Workspace name | i3 IPC |
| output | str | Yes | Monitor/output name | i3 IPC |
| marks | List[str] | Yes | i3 marks on window | i3 IPC |
| floating | bool | Yes | Floating vs tiled | i3 IPC |
| focused | bool | Yes | Has keyboard focus | i3 IPC |
| geometry | WindowGeometry | Yes | Size and position | i3 IPC |
| pid | Optional[int] | No | Process ID | i3 IPC |
| project | Optional[str] | No | Associated project name | daemon mark |
| classification | str | No | "scoped" or "global" | daemon logic |
| hidden | bool | Yes | Hidden due to project scope | daemon logic |
| app_identifier | Optional[str] | No | Friendly app name | daemon logic |

**Validation Rules**:
- `id` must be positive integer
- `window_class` and `instance` cannot be empty strings
- `workspace` must be 1-10
- `output` must exist in GET_OUTPUTS response
- `marks` format: `project:<name>` for project association
- `classification` must be "scoped" or "global"

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, field_validator

class WindowGeometry(BaseModel):
    """Window geometry (size and position)."""
    x: int
    y: int
    width: int
    height: int

    @field_validator('width', 'height')
    @classmethod
    def validate_positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("Width and height must be positive")
        return v

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

    @field_validator('classification')
    @classmethod
    def validate_classification(cls, v: str) -> str:
        if v not in ['scoped', 'global']:
            raise ValueError("Classification must be 'scoped' or 'global'")
        return v

    @field_validator('project')
    @classmethod
    def validate_project_mark(cls, v: Optional[str], info) -> Optional[str]:
        """Ensure project matches mark if present."""
        if v:
            marks = info.data.get('marks', [])
            expected_mark = f"project:{v}"
            if expected_mark not in marks:
                raise ValueError(f"Project '{v}' must have corresponding mark '{expected_mark}'")
        return v
```

**State Transitions**: None (read-only view of i3 state)

**Relationships**:
- None (WindowState is a read-only snapshot from i3 IPC)

---

### SwallowCriteria

**Purpose**: Defines which window properties to match during layout restore

**Source**: Configuration file + per-app overrides

**Fields**:

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|------------|
| window_class | Optional[str] | No | Match window class (regex) | Valid regex |
| instance | Optional[str] | No | Match instance (regex) | Valid regex |
| title | Optional[str] | No | Match title (regex) | Valid regex |
| window_role | Optional[str] | No | Match window role (regex) | Valid regex |

**Validation Rules**:
- At least one field must be specified
- All specified fields must be valid regex patterns
- Empty strings are not allowed (use None for unmatched fields)

**Pydantic Model**:
```python
import re
from pydantic import BaseModel, Field, model_validator

class SwallowCriteria(BaseModel):
    """Swallow criteria for window matching during restore."""
    window_class: Optional[str] = Field(default=None, description="Window class regex")
    instance: Optional[str] = Field(default=None, description="Instance regex")
    title: Optional[str] = Field(default=None, description="Title regex")
    window_role: Optional[str] = Field(default=None, description="Window role regex")

    @model_validator(mode='after')
    def validate_at_least_one_criteria(self):
        """At least one criteria must be specified."""
        if not any([self.window_class, self.instance, self.title, self.window_role]):
            raise ValueError("At least one swallow criteria must be specified")
        return self

    @model_validator(mode='after')
    def validate_regex_patterns(self):
        """All specified patterns must be valid regex."""
        for field_name in ['window_class', 'instance', 'title', 'window_role']:
            pattern = getattr(self, field_name)
            if pattern:
                try:
                    re.compile(pattern)
                except re.error as e:
                    raise ValueError(f"Invalid regex in {field_name}: {e}")
        return self

    def matches(self, window: WindowState) -> bool:
        """Check if window matches these criteria."""
        if self.window_class and not re.match(self.window_class, window.window_class):
            return False
        if self.instance and not re.match(self.instance, window.instance):
            return False
        if self.title and not re.match(self.title, window.title):
            return False
        if self.window_role and window.window_role and not re.match(self.window_role, window.window_role):
            return False
        return True

    def to_i3_swallow(self) -> Dict[str, str]:
        """Convert to i3 swallow JSON format."""
        swallow = {}
        if self.window_class:
            swallow['class'] = self.window_class
        if self.instance:
            swallow['instance'] = self.instance
        if self.title:
            swallow['title'] = self.title
        if self.window_role:
            swallow['window_role'] = self.window_role
        return swallow
```

**State Transitions**: None (immutable once created)

**Relationships**:
- Used by LayoutWindow to define matching criteria

---

### LayoutWindow

**Purpose**: Represents a window in a saved layout with launch information

**Source**: Saved layout JSON file

**Fields**:

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|------------|
| swallows | List[SwallowCriteria] | Yes | Window matching criteria | Min 1 criteria |
| launch_command | Optional[str] | No | Shell command to launch app | Valid command |
| working_directory | Optional[Path] | No | Working directory for launch | Must exist |
| environment | Dict[str, str] | No | Environment variables | Filtered secrets |
| geometry | WindowGeometry | Yes | Target size/position | Positive dimensions |
| floating | bool | Yes | Floating vs tiled | - |
| border | str | Yes | Border style | Valid i3 border |
| layout | str | Yes | Container layout mode | Valid i3 layout |
| percent | Optional[float] | No | Size percentage (0.0-1.0) | 0.0 < percent <= 1.0 |

**Validation Rules**:
- `swallows` list must contain at least one SwallowCriteria
- `launch_command` must not contain shell injection characters
- `working_directory` must be an existing directory
- `environment` must not contain secret patterns (TOKEN, PASSWORD, KEY, AWS_*)
- `geometry` must have positive width/height
- `border` must be one of: "normal", "pixel", "none"
- `layout` must be one of: "splith", "splitv", "stacked", "tabbed"
- `percent` must be between 0.0 and 1.0

**Pydantic Model**:
```python
from pathlib import Path
from pydantic import BaseModel, Field, field_validator
import shlex

class LayoutWindow(BaseModel):
    """Window configuration in a saved layout."""
    swallows: List[SwallowCriteria] = Field(..., min_length=1, description="Matching criteria")
    launch_command: Optional[str] = Field(default=None, description="Launch command")
    working_directory: Optional[Path] = Field(default=None, description="Working directory")
    environment: Dict[str, str] = Field(default_factory=dict, description="Environment vars")
    geometry: WindowGeometry = Field(..., description="Target geometry")
    floating: bool = Field(default=False, description="Floating state")
    border: str = Field(default="pixel", description="Border style")
    layout: str = Field(default="splith", description="Container layout")
    percent: Optional[float] = Field(default=None, description="Size percentage")

    @field_validator('launch_command')
    @classmethod
    def validate_launch_command(cls, v: Optional[str]) -> Optional[str]:
        """Validate launch command for safety."""
        if not v:
            return v

        # Check for shell injection characters
        forbidden = ['|', '&', ';', '`', '\n', '$(']
        if any(char in v for char in forbidden):
            raise ValueError(f"Launch command contains forbidden characters: {v}")

        # Must be parseable as shell command
        try:
            shlex.split(v)
        except ValueError as e:
            raise ValueError(f"Invalid shell command syntax: {e}")

        return v

    @field_validator('working_directory')
    @classmethod
    def validate_working_directory(cls, v: Optional[Path]) -> Optional[Path]:
        """Validate working directory exists."""
        if v and not v.is_dir():
            raise ValueError(f"Working directory does not exist: {v}")
        return v

    @field_validator('environment')
    @classmethod
    def filter_secrets(cls, v: Dict[str, str]) -> Dict[str, str]:
        """Filter sensitive environment variables."""
        secret_patterns = ['TOKEN', 'SECRET', 'PASSWORD', 'KEY', 'AWS_', 'API_']
        filtered = {
            k: val for k, val in v.items()
            if not any(pattern in k.upper() for pattern in secret_patterns)
        }
        if len(filtered) < len(v):
            removed_keys = set(v.keys()) - set(filtered.keys())
            print(f"Warning: Filtered secrets from environment: {removed_keys}")
        return filtered

    @field_validator('border')
    @classmethod
    def validate_border(cls, v: str) -> str:
        """Validate border style."""
        valid_borders = ['normal', 'pixel', 'none']
        if v not in valid_borders:
            raise ValueError(f"Border must be one of {valid_borders}, got: {v}")
        return v

    @field_validator('layout')
    @classmethod
    def validate_layout(cls, v: str) -> str:
        """Validate layout mode."""
        valid_layouts = ['splith', 'splitv', 'stacked', 'tabbed']
        if v not in valid_layouts:
            raise ValueError(f"Layout must be one of {valid_layouts}, got: {v}")
        return v

    @field_validator('percent')
    @classmethod
    def validate_percent(cls, v: Optional[float]) -> Optional[float]:
        """Validate size percentage."""
        if v is not None and not (0.0 < v <= 1.0):
            raise ValueError(f"Percent must be between 0.0 and 1.0, got: {v}")
        return v
```

**State Transitions**:
- Created during layout save
- Restored during layout restore (may transition to running window)

**Relationships**:
- Belongs to WorkspaceLayout (many LayoutWindow to one WorkspaceLayout)
- Uses SwallowCriteria for matching (one LayoutWindow to many SwallowCriteria)

---

### WorkspaceLayout

**Purpose**: Represents saved layout for a single workspace

**Source**: Saved layout JSON file

**Fields**:

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|------------|
| number | int | Yes | Workspace number (1-10) | 1-10 range |
| output | str | Yes | Target monitor output | Valid output name |
| layout | str | Yes | Workspace layout mode | Valid i3 layout |
| windows | List[LayoutWindow] | Yes | Windows in workspace | Min 0 windows |
| saved_at | datetime | Yes | Timestamp of save | Valid datetime |
| window_count | int | Yes | Number of windows | >= 0 |

**Validation Rules**:
- `number` must be 1-10
- `output` must match a known output name (validated against i3 GET_OUTPUTS)
- `layout` must be valid i3 layout mode
- `window_count` must match length of `windows` list
- `saved_at` must be valid ISO 8601 datetime

**Pydantic Model**:
```python
from datetime import datetime
from pydantic import BaseModel, Field, field_validator

class WorkspaceLayout(BaseModel):
    """Saved layout for a single workspace."""
    number: int = Field(..., ge=1, le=10, description="Workspace number")
    output: str = Field(..., min_length=1, description="Target output")
    layout: str = Field(..., description="Workspace layout mode")
    windows: List[LayoutWindow] = Field(default_factory=list, description="Windows")
    saved_at: datetime = Field(..., description="Save timestamp")
    window_count: int = Field(..., ge=0, description="Window count")

    @field_validator('layout')
    @classmethod
    def validate_layout(cls, v: str) -> str:
        """Validate layout mode."""
        valid_layouts = ['splith', 'splitv', 'stacked', 'tabbed', 'default']
        if v not in valid_layouts:
            raise ValueError(f"Layout must be one of {valid_layouts}, got: {v}")
        return v

    @model_validator(mode='after')
    def validate_window_count(self):
        """Ensure window_count matches windows list."""
        if self.window_count != len(self.windows):
            raise ValueError(f"window_count ({self.window_count}) does not match windows list length ({len(self.windows)})")
        return self
```

**State Transitions**:
- Created during layout save
- Loaded during layout restore

**Relationships**:
- Belongs to SavedLayout (many WorkspaceLayout to one SavedLayout)
- Contains LayoutWindow (one WorkspaceLayout to many LayoutWindow)

---

### SavedLayout

**Purpose**: Complete saved layout for a project including all workspaces

**Source**: Saved layout JSON file

**Fields**:

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|------------|
| version | str | Yes | Layout format version | "1.0" |
| project | str | Yes | Project name | Valid project name |
| layout_name | str | Yes | Layout identifier | Alphanumeric + - _ |
| saved_at | datetime | Yes | Save timestamp | ISO 8601 datetime |
| monitor_count | int | Yes | Number of monitors | > 0 |
| monitor_config | Dict[str, MonitorInfo] | Yes | Monitor details | Valid outputs |
| workspaces | List[WorkspaceLayout] | Yes | Workspace layouts | Min 1 workspace |
| total_windows | int | Yes | Total window count | >= 0 |
| metadata | Dict[str, Any] | No | Additional metadata | - |

**Validation Rules**:
- `version` must be "1.0" (current format version)
- `project` must match existing project configuration
- `layout_name` must be filesystem-safe (alphanumeric + - _)
- `monitor_count` must match length of `monitor_config`
- `workspaces` must contain at least one workspace
- `total_windows` must match sum of all workspace window counts

**Pydantic Model**:
```python
from datetime import datetime
from pydantic import BaseModel, Field, field_validator, model_validator

class MonitorInfo(BaseModel):
    """Monitor configuration snapshot."""
    name: str = Field(..., description="Output name")
    active: bool = Field(..., description="Active status")
    width: int = Field(..., gt=0, description="Width in pixels")
    height: int = Field(..., gt=0, description="Height in pixels")
    x: int = Field(default=0, description="X position")
    y: int = Field(default=0, description="Y position")

class SavedLayout(BaseModel):
    """Complete saved layout for a project."""
    version: str = Field(default="1.0", description="Format version")
    project: str = Field(..., min_length=1, description="Project name")
    layout_name: str = Field(..., min_length=1, description="Layout name")
    saved_at: datetime = Field(..., description="Save timestamp")
    monitor_count: int = Field(..., gt=0, description="Monitor count")
    monitor_config: Dict[str, MonitorInfo] = Field(..., description="Monitor details")
    workspaces: List[WorkspaceLayout] = Field(..., min_length=1, description="Workspaces")
    total_windows: int = Field(..., ge=0, description="Total windows")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Metadata")

    @field_validator('version')
    @classmethod
    def validate_version(cls, v: str) -> str:
        """Ensure version is supported."""
        if v != "1.0":
            raise ValueError(f"Unsupported layout version: {v}, expected 1.0")
        return v

    @field_validator('layout_name')
    @classmethod
    def validate_layout_name(cls, v: str) -> str:
        """Ensure layout name is filesystem-safe."""
        if not v.replace("-", "").replace("_", "").isalnum():
            raise ValueError(f"Layout name must be alphanumeric with - or _: {v}")
        return v

    @model_validator(mode='after')
    def validate_monitor_count(self):
        """Ensure monitor_count matches monitor_config."""
        if self.monitor_count != len(self.monitor_config):
            raise ValueError(f"monitor_count ({self.monitor_count}) does not match monitor_config length ({len(self.monitor_config)})")
        return self

    @model_validator(mode='after')
    def validate_total_windows(self):
        """Ensure total_windows matches sum of workspace windows."""
        calculated_total = sum(ws.window_count for ws in self.workspaces)
        if self.total_windows != calculated_total:
            raise ValueError(f"total_windows ({self.total_windows}) does not match calculated total ({calculated_total})")
        return self

    def get_workspace(self, number: int) -> Optional[WorkspaceLayout]:
        """Get workspace layout by number."""
        for ws in self.workspaces:
            if ws.number == number:
                return ws
        return None

    def export_i3_json(self) -> Dict[str, Any]:
        """Export as vanilla i3 JSON (strip i3pm extensions)."""
        # Implementation in layout.py
        pass
```

**State Transitions**:
- Created during layout save
- Loaded during layout restore, diff computation

**Relationships**:
- Belongs to Project (many SavedLayout to one Project)
- Contains WorkspaceLayout (one SavedLayout to many WorkspaceLayout)

---

### WindowDiff

**Purpose**: Comparison result between current window state and saved layout

**Source**: Computed by diff algorithm

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| layout_name | str | Yes | Name of compared layout |
| current_windows | int | Yes | Number of current windows |
| saved_windows | int | Yes | Number of saved windows |
| added | List[WindowState] | Yes | Windows in current, not in saved |
| removed | List[LayoutWindow] | Yes | Windows in saved, not in current |
| moved | List[Tuple[WindowState, LayoutWindow]] | Yes | Windows changed workspace/output |
| kept | List[Tuple[WindowState, LayoutWindow]] | Yes | Windows unchanged |
| computed_at | datetime | Yes | Diff computation timestamp |

**Validation Rules**:
- `added`, `removed`, `moved`, `kept` must be mutually exclusive
- Sum of category lengths must equal `current_windows + removed length`
- `current_windows` must match total of `added + moved + kept`
- `saved_windows` must match total of `removed + moved + kept`

**Pydantic Model**:
```python
from datetime import datetime
from pydantic import BaseModel, Field, model_validator
from typing import Tuple

class WindowDiff(BaseModel):
    """Diff between current state and saved layout."""
    layout_name: str = Field(..., description="Layout name")
    current_windows: int = Field(..., ge=0, description="Current window count")
    saved_windows: int = Field(..., ge=0, description="Saved window count")
    added: List[WindowState] = Field(default_factory=list, description="Added windows")
    removed: List[LayoutWindow] = Field(default_factory=list, description="Removed windows")
    moved: List[Tuple[WindowState, LayoutWindow]] = Field(default_factory=list, description="Moved windows")
    kept: List[Tuple[WindowState, LayoutWindow]] = Field(default_factory=list, description="Unchanged windows")
    computed_at: datetime = Field(default_factory=datetime.now, description="Computation time")

    @model_validator(mode='after')
    def validate_counts(self):
        """Validate window counts match categories."""
        total_current = len(self.added) + len(self.moved) + len(self.kept)
        if total_current != self.current_windows:
            raise ValueError(f"Current window count mismatch: {total_current} != {self.current_windows}")

        total_saved = len(self.removed) + len(self.moved) + len(self.kept)
        if total_saved != self.saved_windows:
            raise ValueError(f"Saved window count mismatch: {total_saved} != {self.saved_windows}")

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
```

**State Transitions**:
- Computed on-demand (not persisted)
- Recomputed when current state or saved layout changes

**Relationships**:
- References WindowState (current state from i3 IPC)
- References LayoutWindow (saved layout from file)
- Not persisted (computed value)

---

## Supporting Data Structures

### LaunchCommand

**Purpose**: Discovered or configured launch command for window restoration

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| command | str | Yes | Shell command to execute |
| working_directory | Path | No | CWD for command execution |
| environment | Dict[str, str] | No | Environment variables |
| source | str | Yes | "discovered" or "configured" |

**Pydantic Model**:
```python
from pathlib import Path
from pydantic import BaseModel, Field

class LaunchCommand(BaseModel):
    """Launch command for window restoration."""
    command: str = Field(..., min_length=1, description="Shell command")
    working_directory: Optional[Path] = Field(default=None, description="Working directory")
    environment: Dict[str, str] = Field(default_factory=dict, description="Environment")
    source: str = Field(..., description="Command source")

    @field_validator('source')
    @classmethod
    def validate_source(cls, v: str) -> str:
        """Validate source."""
        if v not in ['discovered', 'configured']:
            raise ValueError(f"Source must be 'discovered' or 'configured', got: {v}")
        return v
```

---

## Data Flow Diagrams

### Layout Save Flow

```
[User Action: Save Layout]
         │
         ├─> [Query i3 IPC: GET_TREE, GET_WORKSPACES, GET_OUTPUTS]
         │
         ├─> [For each window:]
         │    ├─> Extract WindowState from i3 tree
         │    ├─> Discover LaunchCommand via psutil
         │    └─> Create LayoutWindow with SwallowCriteria
         │
         ├─> [Group LayoutWindows by workspace]
         │    └─> Create WorkspaceLayout for each workspace
         │
         ├─> [Create SavedLayout]
         │    ├─> Add WorkspaceLayouts
         │    ├─> Snapshot MonitorInfo
         │    └─> Calculate metadata
         │
         └─> [Write SavedLayout to JSON file]
              Location: ~/.config/i3pm/projects/<project>/layouts/<name>.json
```

### Layout Restore Flow

```
[User Action: Restore Layout]
         │
         ├─> [Load SavedLayout from JSON file]
         │
         ├─> [Validate monitor configuration]
         │    └─> Warn if monitor count differs
         │
         ├─> [For each WorkspaceLayout:]
         │    │
         │    ├─> [Unmap existing windows on workspace (xdotool)]
         │    │
         │    ├─> [Generate i3 append_layout JSON with placeholders]
         │    │
         │    ├─> [Execute i3: append_layout <file>]
         │    │
         │    ├─> [For each LayoutWindow:]
         │    │    ├─> Check if existing window matches SwallowCriteria
         │    │    ├─> If no match: Launch LaunchCommand
         │    │    └─> If match: Reposition existing window
         │    │
         │    ├─> [Wait for swallow (30s timeout)]
         │    │
         │    └─> [Remap all windows (try/finally)]
         │
         └─> [Report results: restored, launched, failed]
```

### Layout Diff Flow

```
[User Action: Diff Layout]
         │
         ├─> [Load SavedLayout from JSON file]
         │
         ├─> [Query i3 IPC: GET_TREE, GET_WORKSPACES]
         │    └─> Extract current WindowState list
         │
         ├─> [For each current WindowState:]
         │    └─> Try match against SavedLayout SwallowCriteria
         │         ├─> Match found: Check if workspace/output changed (moved)
         │         └─> No match: Categorize as added
         │
         ├─> [For each LayoutWindow in SavedLayout:]
         │    └─> If no matching WindowState: Categorize as removed
         │
         ├─> [Create WindowDiff with categories]
         │
         └─> [Display diff in TUI or CLI]
              ├─> Show added windows (green)
              ├─> Show removed windows (red)
              └─> Show moved windows (yellow)
```

---

## Schema Versioning Strategy

### Current Version: 1.0

**Compatibility Promise**:
- All 1.x versions are forwards-compatible (newer code reads older formats)
- Breaking changes require major version bump (2.0)
- Unknown fields are ignored (forward compatibility)

### Migration Path for Future Versions:

1. **Detect version** in JSON: `{"version": "1.0", ...}`
2. **Apply migrations** if older version:
   - 1.0 → 1.1: Add new optional fields with defaults
   - 1.0 → 2.0: Convert deprecated fields to new structure
3. **Validate** using Pydantic model for target version
4. **Save** in current version format

---

## Validation Summary

| Entity | Validation Method | Schema File |
|--------|-------------------|-------------|
| WindowState | Pydantic model + i3 IPC contract | N/A (runtime only) |
| SwallowCriteria | Pydantic model + regex validation | /contracts/swallow-criteria-schema.json |
| LayoutWindow | Pydantic model + command validation | /contracts/layout-window-schema.json |
| WorkspaceLayout | Pydantic model + count validation | /contracts/workspace-layout-schema.json |
| SavedLayout | Pydantic model + version check | /contracts/saved-layout-schema.json |
| WindowDiff | Pydantic model + count validation | N/A (computed value) |

---

**Next Steps**:
1. Generate JSON schemas in `/contracts/` directory
2. Implement Pydantic models in `i3_project_manager/models/`
3. Add validation tests in `tests/unit/test_models.py`
