# Data Model: Mark-Based App Identification

**Feature**: 076-mark-based-app-identification
**Created**: 2025-11-14
**Purpose**: Define data structures for mark injection, storage, and retrieval

## Core Entities

### MarkMetadata

**Purpose**: Represents a structured mark with key-value pairs for window classification

**Fields**:
- `app` (str, required): Application name from app-registry (e.g., "terminal", "code", "chatgpt-pwa")
- `project` (str, optional): Project context if app is scoped (e.g., "nixos", "dotfiles")
- `workspace` (str, optional): Workspace number for validation (e.g., "1", "23")
- `scope` (str, optional): "scoped" or "global" classification
- `custom` (dict[str, str], optional): Extensibility for future metadata

**Validation Rules**:
- `app` must match `^[a-z0-9][a-z0-9-]*$` (app-registry naming convention)
- `workspace` must match `^[1-9][0-9]{0,1}$` (1-70)
- `scope` must be "scoped" or "global" if present
- `custom` keys must match `^[a-z_][a-z0-9_]*$` (snake_case identifiers)

**Relationships**:
- One window can have one MarkMetadata instance
- MarkMetadata serializes to multiple Sway marks (one per key-value pair)

**Example**:
```python
mark_metadata = MarkMetadata(
    app="terminal",
    project="nixos",
    workspace="1",
    scope="scoped",
    custom={"session_id": "abc123"},
)

# Serializes to Sway marks:
# - i3pm_app:terminal
# - i3pm_project:nixos
# - i3pm_ws:1
# - i3pm_scope:scoped
# - i3pm_custom:session_id:abc123
```

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, field_validator
from typing import Optional

class MarkMetadata(BaseModel):
    """Structured mark metadata for window classification."""
    app: str = Field(..., pattern=r'^[a-z0-9][a-z0-9-]*$', description="App name from app-registry")
    project: Optional[str] = Field(default=None, description="Project context for scoped apps")
    workspace: Optional[str] = Field(default=None, pattern=r'^[1-9][0-9]{0,1}$', description="Workspace number (1-70)")
    scope: Optional[str] = Field(default=None, pattern=r'^(scoped|global)$', description="App scope classification")
    custom: Optional[dict[str, str]] = Field(default=None, description="Custom metadata for extensibility")

    @field_validator('custom')
    @classmethod
    def validate_custom_keys(cls, v):
        if v is not None:
            for key in v.keys():
                if not re.match(r'^[a-z_][a-z0-9_]*$', key):
                    raise ValueError(f"Custom key '{key}' must be snake_case identifier")
        return v

    def to_sway_marks(self) -> list[str]:
        """Convert to Sway mark strings (i3pm_<key>:<value>)."""
        marks = [f"i3pm_app:{self.app}"]

        if self.project:
            marks.append(f"i3pm_project:{self.project}")
        if self.workspace:
            marks.append(f"i3pm_ws:{self.workspace}")
        if self.scope:
            marks.append(f"i3pm_scope:{self.scope}")
        if self.custom:
            for key, value in self.custom.items():
                marks.append(f"i3pm_custom:{key}:{value}")

        return marks

    @classmethod
    def from_sway_marks(cls, marks: list[str]) -> "MarkMetadata":
        """Parse from Sway mark strings."""
        data = {}
        custom = {}

        for mark in marks:
            if not mark.startswith("i3pm_"):
                continue

            # Remove prefix and parse
            mark = mark[5:]  # Remove "i3pm_"

            if mark.startswith("custom:"):
                # Custom mark format: custom:key:value
                _, key, value = mark.split(":", 2)
                custom[key] = value
            elif ":" in mark:
                key, value = mark.split(":", 1)
                data[key] = value

        if custom:
            data["custom"] = custom

        return cls(**data)
```

---

### SavedWindowWithMarks

**Purpose**: Extended SavedWindow model from Feature 074 with mark metadata

**Fields** (extends existing SavedWindow):
- `app_registry_name` (str, required): Application name
- `workspace` (int, required): Workspace number
- `cwd` (Path, optional): Working directory for terminals
- `focused` (bool): Whether window was focused
- `geometry` (dict, optional): Window size/position
- `floating` (bool): Whether window is floating
- **`marks` (MarkMetadata, optional)**: Mark metadata (NEW)

**Validation Rules**:
- Same as SavedWindow (Feature 074)
- `marks` field is optional for backward compatibility
- If `marks` present, `marks.app` must match `app_registry_name`

**Relationships**:
- Stored in LayoutSnapshot.workspace_layouts[].windows[]
- One SavedWindowWithMarks per window in layout

**Example**:
```python
window = SavedWindowWithMarks(
    app_registry_name="terminal",
    workspace=1,
    cwd=Path("/etc/nixos"),
    focused=True,
    marks=MarkMetadata(
        app="terminal",
        project="nixos",
        workspace="1",
        scope="scoped",
    ),
)
```

**Pydantic Model**:
```python
from pydantic import BaseModel, field_validator
from pathlib import Path

class SavedWindowWithMarks(BaseModel):
    """Window entry in saved layout with mark metadata."""
    app_registry_name: str = Field(..., description="App name from app-registry")
    workspace: int = Field(..., ge=1, le=70, description="Workspace number")
    cwd: Optional[Path] = Field(default=None, description="Working directory for terminals")
    focused: bool = Field(default=False, description="Was window focused")
    geometry: Optional[dict] = Field(default=None, description="Window size/position")
    floating: bool = Field(default=False, description="Is window floating")
    marks: Optional[MarkMetadata] = Field(default=None, description="Mark metadata for restoration")

    @field_validator('marks')
    @classmethod
    def validate_marks_match_app(cls, v, values):
        if v and 'app_registry_name' in values:
            if v.app != values['app_registry_name']:
                raise ValueError(f"Mark app '{v.app}' must match app_registry_name '{values['app_registry_name']}'")
        return v
```

---

### WindowMarkQuery

**Purpose**: Query parameters for finding windows by marks

**Fields**:
- `app` (str, optional): Filter by app name
- `project` (str, optional): Filter by project
- `workspace` (int, optional): Filter by workspace number
- `scope` (str, optional): Filter by scope ("scoped" or "global")
- `custom_key` (str, optional): Filter by custom metadata key
- `custom_value` (str, optional): Filter by custom metadata value (requires custom_key)

**Validation Rules**:
- At least one filter field must be provided
- `custom_value` requires `custom_key` to be set
- `workspace` must be 1-70

**Relationships**:
- Used by MarkManager.find_windows() query method
- Returns list of window IDs matching criteria

**Example**:
```python
# Find all terminals in nixos project
query = WindowMarkQuery(app="terminal", project="nixos")
windows = await mark_manager.find_windows(query)

# Find all windows on workspace 5
query = WindowMarkQuery(workspace=5)
windows = await mark_manager.find_windows(query)
```

**Pydantic Model**:
```python
class WindowMarkQuery(BaseModel):
    """Query parameters for finding windows by marks."""
    app: Optional[str] = None
    project: Optional[str] = None
    workspace: Optional[int] = Field(default=None, ge=1, le=70)
    scope: Optional[str] = Field(default=None, pattern=r'^(scoped|global)$')
    custom_key: Optional[str] = None
    custom_value: Optional[str] = None

    @field_validator('custom_value')
    @classmethod
    def validate_custom_value_requires_key(cls, v, values):
        if v and not values.get('custom_key'):
            raise ValueError("custom_value requires custom_key to be set")
        return v

    @property
    def is_empty(self) -> bool:
        """Check if query has any filters."""
        return not any([self.app, self.project, self.workspace, self.scope, self.custom_key])

    def to_sway_marks(self) -> list[str]:
        """Convert to Sway mark strings for querying."""
        marks = []
        if self.app:
            marks.append(f"i3pm_app:{self.app}")
        if self.project:
            marks.append(f"i3pm_project:{self.project}")
        if self.workspace:
            marks.append(f"i3pm_ws:{self.workspace}")
        if self.scope:
            marks.append(f"i3pm_scope:{self.scope}")
        if self.custom_key:
            if self.custom_value:
                marks.append(f"i3pm_custom:{self.custom_key}:{self.custom_value}")
            else:
                # Match any value for this key
                marks.append(f"i3pm_custom:{self.custom_key}:")
        return marks
```

---

## State Transitions

### Mark Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│                    MARK LIFECYCLE                           │
└─────────────────────────────────────────────────────────────┘

1. APP LAUNCH (via AppLauncher)
   ┌──────────────┐
   │  No Marks    │
   └──────┬───────┘
          │ app_launcher.launch_app()
          │ → Wait for window appearance
          │ → mark_manager.inject_marks()
          ▼
   ┌──────────────┐
   │ Marks Injected│
   └──────┬───────┘
          │
          │ Window exists with marks:
          │ - i3pm_app:terminal
          │ - i3pm_project:nixos
          │ - i3pm_ws:1
          │ - i3pm_scope:scoped
          │

2. LAYOUT SAVE
   ┌──────────────┐
   │ Marks Injected│
   └──────┬───────┘
          │ layout_persistence.save_layout()
          │ → Query GET_TREE for windows
          │ → Read marks from tree nodes
          │ → Serialize to MarkMetadata
          ▼
   ┌──────────────┐
   │ Marks Persisted│ (in layout file)
   └──────────────┘

3. WINDOW CLOSE
   ┌──────────────┐
   │ Marks Injected│
   └──────┬───────┘
          │ daemon window::close event
          │ → mark_manager.cleanup_marks(window_id)
          │ → swaymsg unmark <each_mark>
          ▼
   ┌──────────────┐
   │ Marks Removed │
   └──────────────┘

4. LAYOUT RESTORE
   ┌──────────────┐
   │ Marks Persisted│ (in layout file)
   └──────┬───────┘
          │ layout_restore.restore_workflow()
          │ → Read MarkMetadata from layout
          │ → Query running windows by marks
          │ → Count instances per app
          │ → Launch missing apps
          │ → Marks re-injected at launch
          ▼
   ┌──────────────┐
   │ Marks Injected│ (restored windows)
   └──────────────┘
```

---

## Storage Format

### Layout File with Marks (JSON)

```json
{
  "version": "2.0",
  "project": "nixos",
  "focused_workspace": 1,
  "saved_at": "2025-11-14T10:30:00Z",
  "workspace_layouts": [
    {
      "workspace_num": 1,
      "windows": [
        {
          "app_registry_name": "terminal",
          "workspace": 1,
          "cwd": "/etc/nixos",
          "focused": true,
          "floating": false,
          "marks": {
            "app": "terminal",
            "project": "nixos",
            "workspace": "1",
            "scope": "scoped"
          }
        },
        {
          "app_registry_name": "terminal",
          "workspace": 1,
          "cwd": "/home/user",
          "focused": false,
          "floating": false,
          "marks": {
            "app": "terminal",
            "project": "nixos",
            "workspace": "1",
            "scope": "scoped",
            "custom": {
              "session_id": "term-002"
            }
          }
        }
      ]
    },
    {
      "workspace_num": 2,
      "windows": [
        {
          "app_registry_name": "code",
          "workspace": 2,
          "cwd": "/etc/nixos",
          "focused": false,
          "floating": false,
          "marks": {
            "app": "code",
            "project": "nixos",
            "workspace": "2",
            "scope": "scoped"
          }
        }
      ]
    }
  ]
}
```

### Backward Compatibility (Missing Marks)

```json
{
  "version": "1.0",
  "project": "nixos",
  "focused_workspace": 1,
  "saved_at": "2025-11-10T10:30:00Z",
  "workspace_layouts": [
    {
      "workspace_num": 1,
      "windows": [
        {
          "app_registry_name": "terminal",
          "workspace": 1,
          "cwd": "/etc/nixos",
          "focused": true,
          "floating": false
          // No "marks" field - fallback to /proc detection
        }
      ]
    }
  ]
}
```

---

## Query Patterns

### Find All Terminals in Project

```python
query = WindowMarkQuery(app="terminal", project="nixos")
window_ids = await mark_manager.find_windows(query)
# Returns: [123, 456, 789]
```

### Count Running Instances of App

```python
query = WindowMarkQuery(app="terminal", workspace=1)
window_ids = await mark_manager.find_windows(query)
count = len(window_ids)
# Returns: 2 (two terminals on workspace 1)
```

### Find All Scoped Windows

```python
query = WindowMarkQuery(scope="scoped")
window_ids = await mark_manager.find_windows(query)
# Returns all windows with i3pm_scope:scoped mark
```

### Find Windows with Custom Metadata

```python
query = WindowMarkQuery(custom_key="session_id", custom_value="abc123")
window_ids = await mark_manager.find_windows(query)
# Returns windows with i3pm_custom:session_id:abc123 mark
```

---

## Performance Characteristics

### Mark Injection
- **Complexity**: O(1) per mark, O(m) per window (m = number of marks, typically 3-5)
- **Latency**: 2-5ms per mark (IPC round-trip)
- **Total**: 10-25ms per window for full mark set

### Mark Query
- **Complexity**: O(n) where n = total window count (Sway tree traversal)
- **Latency**: 5-10ms for 10 windows, 20-30ms for 50 windows
- **Optimization**: Single GET_TREE call returns all marks for all windows

### Mark Cleanup
- **Complexity**: O(m) where m = marks per window (typically 3-5)
- **Latency**: 2-5ms per mark
- **Total**: 10-25ms per window close

### Layout Save with Marks
- **Complexity**: O(n × m) where n = windows, m = marks per window
- **Latency**: Dominated by GET_TREE query (~10-30ms), mark serialization <1ms
- **Total**: 50-100ms for typical layout (10 windows)

---

## Summary

**3 Core Entities**:
1. **MarkMetadata** - Structured mark data with key-value pairs
2. **SavedWindowWithMarks** - Extended layout window entry with marks
3. **WindowMarkQuery** - Query parameters for finding windows

**Data Flow**:
1. Launch → Inject marks (AppLauncher + MarkManager)
2. Save → Serialize marks (LayoutPersistence)
3. Restore → Query by marks (LayoutRestore)
4. Close → Cleanup marks (Daemon event handler)

**Storage**:
- JSON layout files with nested `marks` objects
- Backward compatible (optional `marks` field)

**Performance**:
- <25ms mark injection per window
- <30ms mark query for typical session (10-20 windows)
- <25ms mark cleanup per window

**Ready for contracts definition (Phase 1.2)**
