# Data Model: Python Backend Consolidation

**Feature**: 058-python-backend-consolidation
**Date**: 2025-11-03
**Purpose**: Define all data entities, relationships, and validation rules for layout and project management

## Overview

This feature introduces four primary entities for managing window layouts and project state:

1. **WindowSnapshot**: Individual window state within a layout
2. **Layout**: Complete layout snapshot containing multiple window snapshots
3. **Project**: Development project or workspace context
4. **ActiveProjectState**: Singleton representing currently active project

## Entity Definitions

### WindowSnapshot

**Purpose**: Represents the saved state of a single window for layout restoration.

**Attributes**:

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `window_id` | `int` | Yes | Positive integer | i3/Sway window ID |
| `app_id` | `str` | Yes | Non-empty | I3PM_APP_ID from environment (deterministic identifier) |
| `app_name` | `str` | Yes | Non-empty | I3PM_APP_NAME from environment (e.g., "vscode", "firefox") |
| `window_class` | `str` | No | - | X11 window class (for validation, not primary matching) |
| `title` | `str` | No | - | Window title (for informational display) |
| `workspace` | `int` | Yes | 1 ≤ n ≤ 70 | Workspace number to restore window to |
| `output` | `str` | Yes | Non-empty | Output/monitor name (e.g., "HEADLESS-1", "eDP-1") |
| `rect` | `dict[str, int]` | Yes | Contains x, y, width, height | Window geometry (position and size) |
| `floating` | `bool` | Yes | - | Whether window is floating (True) or tiled (False) |
| `focused` | `bool` | Yes | - | Whether window had focus when layout was captured |

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, field_validator

class WindowSnapshot(BaseModel):
    """Window state snapshot for layout restore."""
    window_id: int = Field(..., gt=0, description="i3/Sway window ID")
    app_id: str = Field(..., min_length=1, description="I3PM_APP_ID for deterministic matching")
    app_name: str = Field(..., min_length=1, description="Application name (e.g., vscode)")
    window_class: str = Field(default="", description="X11 window class (validation only)")
    title: str = Field(default="", description="Window title (display only)")
    workspace: int = Field(..., ge=1, le=70, description="Workspace number (1-70)")
    output: str = Field(..., min_length=1, description="Output name (e.g., HEADLESS-1)")
    rect: dict[str, int] = Field(..., description="Window geometry {x, y, width, height}")
    floating: bool = Field(..., description="Floating vs tiled state")
    focused: bool = Field(..., description="Had focus when captured")

    @field_validator('rect')
    @classmethod
    def validate_rect(cls, v: dict[str, int]) -> dict[str, int]:
        """Ensure rect contains required fields."""
        required = {'x', 'y', 'width', 'height'}
        if not required.issubset(v.keys()):
            raise ValueError(f"rect must contain fields: {required}")

        # Validate positive dimensions
        if v['width'] <= 0 or v['height'] <= 0:
            raise ValueError("width and height must be positive")

        return v

    def matches_window_id(self, window_env: dict) -> bool:
        """Check if this snapshot matches a window's environment."""
        return window_env.get('I3PM_APP_ID') == self.app_id
```

**JSON Serialization**:
```json
{
  "window_id": 94532735639728,
  "app_id": "vscode-nixos-20251103-123456",
  "app_name": "vscode",
  "window_class": "Code",
  "title": "plan.md - Visual Studio Code",
  "workspace": 2,
  "output": "HEADLESS-1",
  "rect": {
    "x": 0,
    "y": 30,
    "width": 1920,
    "height": 1050
  },
  "floating": false,
  "focused": true
}
```

**State Transitions**: None - WindowSnapshot is immutable once captured.

---

### Layout

**Purpose**: Complete snapshot of all windows in a workspace layout, associated with a project.

**Attributes**:

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `schema_version` | `str` | Yes | Semantic version | Layout file format version (e.g., "1.0") |
| `project_name` | `str` | Yes | Non-empty, alphanumeric + dash/underscore | Associated project name |
| `layout_name` | `str` | Yes | Non-empty | Human-readable layout name |
| `timestamp` | `datetime` | Yes | Valid ISO 8601 | When layout was captured |
| `windows` | `List[WindowSnapshot]` | Yes | - | All windows in the layout |

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, field_validator
from datetime import datetime
from typing import List
from pathlib import Path
import json

class Layout(BaseModel):
    """Complete layout snapshot with schema versioning."""
    schema_version: str = Field(default="1.0", description="Layout format version")
    project_name: str = Field(..., min_length=1, pattern=r'^[a-zA-Z0-9_-]+$')
    layout_name: str = Field(..., min_length=1)
    timestamp: datetime = Field(default_factory=datetime.now)
    windows: List[WindowSnapshot] = Field(default_factory=list)

    @field_validator('windows')
    @classmethod
    def validate_windows(cls, v: List[WindowSnapshot]) -> List[WindowSnapshot]:
        """Validate window list (can be empty for blank layouts)."""
        # Check for duplicate app_ids within same layout
        app_ids = [w.app_id for w in v]
        duplicates = [aid for aid in app_ids if app_ids.count(aid) > 1]
        if duplicates:
            raise ValueError(f"Duplicate app_ids in layout: {set(duplicates)}")
        return v

    def save_to_file(self, path: Path) -> None:
        """Save layout to JSON file."""
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'w') as f:
            json.dump(
                self.model_dump(mode='json'),
                f,
                indent=2,
                default=str  # Handle datetime serialization
            )

    @classmethod
    def load_from_file(cls, path: Path) -> "Layout":
        """Load layout from JSON file with automatic migration."""
        if not path.exists():
            raise FileNotFoundError(f"Layout file not found: {path}")

        with open(path) as f:
            data = json.load(f)

        # Auto-migrate old format
        if 'schema_version' not in data:
            logger.info(f"Migrating layout from v0 to v1.0: {path}")
            data = cls._migrate_v0_to_v1(data)

        return cls.model_validate(data)

    @classmethod
    def _migrate_v0_to_v1(cls, data: dict) -> dict:
        """Migrate pre-versioning layout to v1.0."""
        data['schema_version'] = '1.0'

        # Ensure all windows have app_id (old layouts may use class-based matching)
        for window in data.get('windows', []):
            if 'app_id' not in window:
                # Generate synthetic app_id from window_id
                window['app_id'] = f"migrated-{window['window_id']}"
                window['app_name'] = window.get('window_class', 'unknown')
                logger.warning(
                    f"Migrated window without app_id: {window.get('title', 'unknown')}"
                )

        return data
```

**JSON Serialization**:
```json
{
  "schema_version": "1.0",
  "project_name": "nixos",
  "layout_name": "default",
  "timestamp": "2025-11-03T14:30:00",
  "windows": [
    { /* WindowSnapshot 1 */ },
    { /* WindowSnapshot 2 */ },
    { /* WindowSnapshot 3 */ }
  ]
}
```

**State Transitions**:
- **Created**: Captured from current i3/Sway window tree
- **Persisted**: Saved to `~/.config/i3/layouts/{layout_name}.json`
- **Loaded**: Read from file with auto-migration
- **Applied**: Windows restored to saved positions

**File Location**: `~/.config/i3/layouts/{project_name}-{layout_name}.json`

---

### Project

**Purpose**: Represents a development project or workspace context with associated metadata.

**Attributes**:

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `name` | `str` | Yes | Non-empty, alphanumeric + dash/underscore | Unique project identifier |
| `directory` | `str` | Yes | Valid absolute path | Project root directory |
| `display_name` | `str` | Yes | Non-empty | Human-readable project name |
| `icon` | `str` | No | - | Project icon (emoji or text) |
| `created_at` | `datetime` | Yes | Valid ISO 8601 | Creation timestamp |
| `updated_at` | `datetime` | Yes | Valid ISO 8601 | Last modification timestamp |

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, field_validator
from datetime import datetime
from pathlib import Path
import json

class Project(BaseModel):
    """Project definition with metadata."""
    name: str = Field(..., min_length=1, pattern=r'^[a-zA-Z0-9_-]+$')
    directory: str = Field(..., min_length=1)
    display_name: str = Field(..., min_length=1)
    icon: str = Field(default="📁")
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: datetime = Field(default_factory=datetime.now)

    @field_validator('directory')
    @classmethod
    def validate_directory(cls, v: str) -> str:
        """Ensure directory exists and is absolute path."""
        path = Path(v).expanduser()

        if not path.is_absolute():
            raise ValueError("directory must be absolute path")

        if not path.exists():
            raise ValueError(f"directory does not exist: {v}")

        if not path.is_dir():
            raise ValueError(f"path is not a directory: {v}")

        return str(path)

    def save_to_file(self, config_dir: Path) -> None:
        """Save project to JSON file."""
        projects_dir = config_dir / "projects"
        projects_dir.mkdir(parents=True, exist_ok=True)

        project_file = projects_dir / f"{self.name}.json"
        with open(project_file, 'w') as f:
            json.dump(
                self.model_dump(mode='json'),
                f,
                indent=2,
                default=str
            )

    @classmethod
    def load_from_file(cls, config_dir: Path, name: str) -> "Project":
        """Load project from JSON file."""
        project_file = config_dir / "projects" / f"{name}.json"

        if not project_file.exists():
            raise FileNotFoundError(f"Project not found: {name}")

        with open(project_file) as f:
            data = json.load(f)

        return cls.model_validate(data)

    @classmethod
    def list_all(cls, config_dir: Path) -> List["Project"]:
        """List all projects in config directory."""
        projects_dir = config_dir / "projects"

        if not projects_dir.exists():
            return []

        projects = []
        for project_file in projects_dir.glob("*.json"):
            try:
                with open(project_file) as f:
                    data = json.load(f)
                projects.append(cls.model_validate(data))
            except Exception as e:
                logger.warning(f"Failed to load project {project_file}: {e}")

        return sorted(projects, key=lambda p: p.name)
```

**JSON Serialization**:
```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "display_name": "NixOS Configuration",
  "icon": "❄️",
  "created_at": "2025-11-01T10:00:00",
  "updated_at": "2025-11-03T14:30:00"
}
```

**State Transitions**:
- **Created**: User runs `i3pm project create`
- **Updated**: Metadata modified via `i3pm project update`
- **Activated**: Set as active project via `i3pm project switch`
- **Deleted**: Removed via `i3pm project delete`

**File Location**: `~/.config/i3/projects/{name}.json`

---

### ActiveProjectState

**Purpose**: Singleton representing which project is currently active.

**Attributes**:

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `name` | `str \| None` | Yes | Must match existing project or null | Active project name (null = global mode) |

**Pydantic Model**:
```python
from pydantic import BaseModel, Field
from pathlib import Path
from typing import Optional
import json

class ActiveProjectState(BaseModel):
    """Singleton state for active project."""
    name: Optional[str] = Field(default=None, description="Active project name (null = global)")

    @classmethod
    def load(cls, config_dir: Path) -> "ActiveProjectState":
        """Load active project state from file."""
        state_file = config_dir / "active-project.json"

        if not state_file.exists():
            return cls(name=None)

        with open(state_file) as f:
            data = json.load(f)

        return cls.model_validate(data)

    def save(self, config_dir: Path) -> None:
        """Save active project state to file."""
        state_file = config_dir / "active-project.json"
        state_file.parent.mkdir(parents=True, exist_ok=True)

        with open(state_file, 'w') as f:
            json.dump(self.model_dump(), f, indent=2)

    def is_active(self, project_name: str) -> bool:
        """Check if given project is active."""
        return self.name == project_name

    def is_global_mode(self) -> bool:
        """Check if in global mode (no active project)."""
        return self.name is None
```

**JSON Serialization**:
```json
{
  "name": "nixos"
}
```

Or global mode:
```json
{
  "name": null
}
```

**State Transitions**:
- **Global Mode**: `name` is `null`, no project filtering active
- **Project Active**: `name` is project name, window filtering enabled
- **Switch**: Change from one project to another triggers window filtering

**File Location**: `~/.config/i3/active-project.json`

## Relationships

### Layout ↔ Project

- **Type**: One-to-Many (Project → Layouts)
- **Description**: A project can have multiple layouts (e.g., "default", "coding", "review")
- **Constraint**: Layout's `project_name` field must reference an existing Project's `name`
- **Implementation**: Foreign key constraint enforced at IPC handler level

```python
async def handle_layout_save(self, params: dict) -> dict:
    """Save layout - validate project exists."""
    project_name = params["project_name"]

    # Validate project exists
    try:
        project = Project.load_from_file(self.config_dir, project_name)
    except FileNotFoundError:
        raise ValueError(f"Project not found: {project_name}")

    # Capture and save layout
    layout = await self.layout_engine.capture_layout(...)
    layout.save_to_file(...)
```

### Layout ↔ WindowSnapshot

- **Type**: One-to-Many (Layout → WindowSnapshots)
- **Description**: A layout contains multiple window snapshots
- **Constraint**: Each window snapshot must have unique `app_id` within a layout
- **Implementation**: Validated by Pydantic model `@field_validator`

### Project ↔ ActiveProjectState

- **Type**: One-to-One (Optional)
- **Description**: At most one project can be active at a time
- **Constraint**: ActiveProjectState's `name` must reference existing Project or be `null`
- **Implementation**: Validated at IPC handler level before setting active project

```python
async def handle_project_set_active(self, params: dict) -> dict:
    """Set active project - validate project exists."""
    project_name = params.get("project_name")

    if project_name is not None:
        # Validate project exists
        try:
            project = Project.load_from_file(self.config_dir, project_name)
        except FileNotFoundError:
            raise ValueError(f"Project not found: {project_name}")

    # Update active project state
    state = ActiveProjectState(name=project_name)
    state.save(self.config_dir)

    # Trigger window filtering
    await self.window_filter.apply_filtering(project_name)
```

## Data Flow

### Layout Capture Flow

```
1. User: i3pm layout save nixos
2. TypeScript CLI → JSON-RPC request → Python Daemon
3. Daemon validates project "nixos" exists
4. Daemon queries i3 IPC for window tree (GET_TREE)
5. For each window:
   a. Read /proc/<pid>/environ (I3PM_APP_ID, I3PM_APP_NAME)
   b. Create WindowSnapshot with window state
6. Create Layout with all WindowSnapshots
7. Validate Layout (Pydantic)
8. Save Layout to ~/.config/i3/layouts/nixos-default.json
9. Return success response to CLI
10. CLI displays: "✓ Saved 10 windows to nixos-default layout"
```

### Layout Restore Flow

```
1. User: i3pm layout restore nixos
2. TypeScript CLI → JSON-RPC request → Python Daemon
3. Daemon loads Layout from ~/.config/i3/layouts/nixos-default.json
4. Daemon queries i3 IPC for current windows (GET_TREE)
5. For each current window:
   a. Read /proc/<pid>/environ to get I3PM_APP_ID
   b. Build map: app_id → window
6. For each WindowSnapshot in Layout:
   a. Match by app_id in current window map
   b. If matched: Move window to workspace, restore geometry
   c. If not matched: Add to "missing" list
7. Return restore result (restored count, missing windows)
8. CLI displays:
   "✓ Restored 8 windows
    ⚠ Could not restore 2 windows:
      - lazygit (workspace 5)
      - yazi (workspace 3)"
```

### Project Switch Flow

```
1. User: i3pm project switch nixos
2. TypeScript CLI → JSON-RPC request → Python Daemon
3. Daemon validates project "nixos" exists
4. Daemon updates ActiveProjectState:
   a. Load current state
   b. Set name = "nixos"
   c. Save state to active-project.json
5. Daemon triggers window filtering:
   a. Hide windows from previous project
   b. Show windows for "nixos" project
6. Return success response
7. CLI displays: "✓ Switched to project: nixos"
```

## Validation Rules

### Cross-Entity Validation

1. **Layout → Project Reference**:
   - Layout's `project_name` must match an existing Project's `name`
   - Enforced at: Layout save operation

2. **ActiveProjectState → Project Reference**:
   - ActiveProjectState's `name` (if not null) must match existing Project
   - Enforced at: Project switch operation

3. **WindowSnapshot → Application Registry**:
   - WindowSnapshot's `app_name` should match registry (warning if not)
   - Enforced at: Layout capture (informational warning)

### Business Rules

1. **Unique Project Names**: No two projects can have the same `name`
   - Enforced at: Project creation
   - Implementation: Check file existence before creating project

2. **Unique APP_IDs per Layout**: No duplicate `app_id` within same layout
   - Enforced at: Layout validation
   - Implementation: Pydantic `@field_validator`

3. **Active Project Constraint**: Only one project active at a time
   - Enforced at: Project switch
   - Implementation: ActiveProjectState singleton

## Error Handling

### Validation Errors

```python
from pydantic import ValidationError

try:
    layout = Layout.model_validate(data)
except ValidationError as e:
    # Return JSON-RPC error response
    return {
        "code": 1003,  # VALIDATION_ERROR
        "message": "Invalid layout data",
        "data": {"errors": e.errors()}
    }
```

### File Not Found Errors

```python
try:
    project = Project.load_from_file(config_dir, "nonexistent")
except FileNotFoundError as e:
    # Return JSON-RPC error response
    return {
        "code": 1001,  # PROJECT_NOT_FOUND
        "message": f"Project not found: {name}",
        "data": {"path": str(e.filename)}
    }
```

### Integrity Errors

```python
# Attempting to save layout for non-existent project
try:
    project = Project.load_from_file(config_dir, layout.project_name)
except FileNotFoundError:
    return {
        "code": 1003,  # VALIDATION_ERROR
        "message": f"Cannot save layout: project does not exist",
        "data": {"project_name": layout.project_name}
    }
```

## Summary

This data model provides:

1. **Strong typing** with Pydantic validation
2. **Clear relationships** between entities
3. **Backward compatibility** via schema versioning
4. **Deterministic window matching** via APP_ID
5. **Single source of truth** for project and layout state

**Next Steps**: Generate API contracts based on these entities.
