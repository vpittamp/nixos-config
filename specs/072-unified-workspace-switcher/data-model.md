# Data Model: Unified Workspace/Window/Project Switcher

**Feature**: 072-unified-workspace-switcher
**Date**: 2025-11-12
**Status**: Phase 1 Design

## Overview

This document defines the data entities, relationships, and validation rules for the unified workspace switcher feature. The feature extends the existing workspace-preview-daemon (Feature 057) to display all windows grouped by workspace when entering workspace mode.

## Entities

### 1. AllWindowsPreview

**Purpose**: Represents the preview card state when showing ALL windows across all workspaces (mode entry, before filtering).

**Schema**:
```python
from typing import List, Optional
from pydantic import BaseModel, Field

class WindowPreviewEntry(BaseModel):
    """Individual window entry in the all-windows preview."""
    name: str                      # Window title or app name
    icon_path: str                 # Path to icon SVG/PNG (empty string if not found)
    app_id: Optional[str]          # Wayland app_id (e.g., "firefox", "Code")
    window_class: Optional[str]    # X11 window class (fallback)
    focused: bool                  # Is this window currently focused?
    workspace_num: int             # Which workspace this window belongs to

class WorkspaceGroup(BaseModel):
    """Group of windows on a single workspace."""
    workspace_num: int             # Workspace number (1-70)
    workspace_name: Optional[str]  # Workspace name (if named)
    window_count: int              # Number of windows on this workspace
    windows: List[WindowPreviewEntry]  # Windows on this workspace
    monitor_output: str            # Which monitor this workspace is on (e.g., "HEADLESS-1")

class AllWindowsPreview(BaseModel):
    """Complete preview card state showing all windows grouped by workspace."""
    visible: bool = True                  # Preview card is visible
    type: str = "all_windows"             # Preview type discriminator
    workspace_groups: List[WorkspaceGroup] = Field(default_factory=list)
    total_window_count: int = 0           # Total windows across all workspaces
    total_workspace_count: int = 0        # Number of workspaces with windows
    instructional: bool = False           # Show "Type workspace number..." message
    empty: bool = False                   # No windows open at all
```

**Validation Rules**:
- `workspace_num` MUST be 1-70 (Sway workspace limit)
- `workspace_groups` MUST be sorted by `workspace_num` ascending
- `total_window_count` MUST equal sum of all `window_count` in groups
- `total_workspace_count` MUST equal length of `workspace_groups`
- `instructional` MUST be True when mode entered but no digits typed yet
- `empty` MUST be True when `total_window_count == 0`
- Maximum 20 workspace groups shown initially (others collapsed with "... and N more workspaces")

**State Transitions**:
1. **Mode entry** (CapsLock pressed): `instructional=True`, no workspace_groups yet
2. **Initial load** (Sway IPC query complete): `workspace_groups` populated, `instructional=False`
3. **Filter applied** (digit typed): Transition to `FilteredWorkspacePreview` (existing entity from Feature 057)
4. **Project mode** (`:` typed): Transition to `ProjectModePreview` (existing entity from Feature 057)
5. **Mode exit** (Escape/Enter pressed): `visible=False`

### 2. FilteredWorkspacePreview

**Purpose**: Represents the preview card state when showing ONLY a specific workspace's windows (after typing digits).

**Schema**:
```python
class FilteredWorkspacePreview(BaseModel):
    """Preview card state showing single workspace (existing from Feature 057)."""
    visible: bool = True
    type: str = "workspace"
    workspace_num: int                     # Filtered workspace number
    workspace_name: Optional[str]          # Workspace name
    monitor_output: str                    # Target monitor
    mode: str                              # "goto" or "move"
    accumulated_digits: str                # User-typed digits (e.g., "23")
    apps: List[WindowPreviewEntry]         # Windows on this workspace
    window_count: int                      # Number of windows
    empty: bool                            # Workspace has no windows
    invalid: bool                          # Invalid workspace number (>70)
    instructional: bool = False
    icon_path: Optional[str] = None        # Primary app icon
```

**Validation Rules** (existing from Feature 057):
- `workspace_num` MUST be validated (1-70 valid, others mark `invalid=True`)
- `window_count` MUST equal length of `apps` list
- `empty` MUST be True when `window_count == 0`
- `accumulated_digits` MUST match `workspace_num` (e.g., "23" → 23)
- `mode` MUST be "goto" or "move"

### 3. ProjectModePreview

**Purpose**: Represents the preview card state when showing project search results (after typing `:` prefix).

**Schema**:
```python
class ProjectModePreview(BaseModel):
    """Preview card state showing project search (existing from Feature 057)."""
    visible: bool = True
    type: str = "project"
    accumulated_chars: str                 # User-typed characters after ":"
    matched_project: Optional[str]         # Best fuzzy match result (None if no match)
    project_icon: str = "📁"               # Project icon (emoji or path)
    no_match: bool = False                 # No projects matched the search
```

**Validation Rules** (existing from Feature 057):
- `accumulated_chars` MUST start with ":" prefix (stripped in daemon)
- `no_match` MUST be True when `matched_project is None and len(accumulated_chars) > 0`
- `project_icon` defaults to "📁" emoji if no project icon resolved

## Relationships

```
WorkspaceModeEvent (i3pm daemon)
  ↓ emits
  ├─→ AllWindowsPreview (mode entry, no digits)
  ├─→ FilteredWorkspacePreview (digits typed)
  └─→ ProjectModePreview (`:` prefix typed)

AllWindowsPreview
  ├─→ WorkspaceGroup [1..*]
  │     └─→ WindowPreviewEntry [0..*]
  └─→ FilteredWorkspacePreview (on digit input)

Sway IPC GET_TREE
  ↓ queries
  └─→ AllWindowsPreview (via PreviewRenderer.render_all_windows())
```

## Data Flow

1. **User enters workspace mode** → i3pm daemon emits `workspace_mode` event (`event_type="enter"`)
2. **workspace-preview-daemon receives event** → Calls `render_all_windows()` on `PreviewRenderer`
3. **PreviewRenderer queries Sway** → `GET_TREE` for all windows, `GET_WORKSPACES` for metadata
4. **PreviewRenderer builds AllWindowsPreview** → Groups windows by workspace, sorts by workspace number
5. **Daemon emits JSON** → `emit_preview(visible=True, preview_data=AllWindowsPreview)`
6. **Eww deflisten consumes JSON** → Updates preview card widget with grouped workspace list
7. **User types digit** → Event flow transitions to existing FilteredWorkspacePreview logic

## Performance Constraints

| Operation | Target | Measured |
|-----------|--------|----------|
| GET_TREE query (100 windows) | <50ms | ~15-30ms |
| AllWindowsPreview construction | <50ms | ~5-10ms |
| JSON serialization | <10ms | ~1-2ms |
| Eww widget render | <50ms | <20ms |
| **Total (mode entry → preview visible)** | **<150ms** | **~50-80ms** |

## Validation Logic

### Workspace Number Validation

```python
def validate_workspace_num(workspace_num: int) -> bool:
    """Validate workspace number is within Sway's 1-70 limit."""
    return 1 <= workspace_num <= 70
```

### Empty State Detection

```python
def is_empty_preview(preview: AllWindowsPreview) -> bool:
    """Check if preview has no windows across all workspaces."""
    return preview.total_window_count == 0
```

### Workspace Group Limit (Performance Optimization)

```python
MAX_INITIAL_GROUPS = 20

def limit_workspace_groups(groups: List[WorkspaceGroup]) -> tuple[List[WorkspaceGroup], int]:
    """Limit initial groups to 20, return remainder count."""
    if len(groups) <= MAX_INITIAL_GROUPS:
        return groups, 0

    visible_groups = groups[:MAX_INITIAL_GROUPS]
    remaining_count = len(groups) - MAX_INITIAL_GROUPS
    return visible_groups, remaining_count
```

## Edge Cases

### 1. Empty Workspaces (No Windows)

**Input**: User enters workspace mode, no windows open anywhere

**Output**:
```json
{
  "visible": true,
  "type": "all_windows",
  "workspace_groups": [],
  "total_window_count": 0,
  "total_workspace_count": 0,
  "instructional": false,
  "empty": true
}
```

**Eww Behavior**: Display "No windows open" message

### 2. Instructional State (Mode Entered, No Query Yet)

**Input**: User presses CapsLock, daemon hasn't queried Sway yet

**Output**:
```json
{
  "visible": true,
  "type": "all_windows",
  "workspace_groups": [],
  "total_window_count": 0,
  "total_workspace_count": 0,
  "instructional": true,
  "empty": false
}
```

**Eww Behavior**: Display "Type workspace number to filter, or :project for project mode"

### 3. 100+ Windows Across 70 Workspaces

**Input**: User has windows on every workspace (70 workspaces, 100+ windows total)

**Output**: Show first 20 workspace groups, display "... and 50 more workspaces" footer

**Validation**: `total_workspace_count=70`, but only render 20 groups initially

### 4. Windows with Missing Icons

**Input**: Window has no identifiable app name or icon

**Output**: `icon_path=""`, `name` falls back to window title or workspace number

**Eww Behavior**: Display first character of name as fallback symbol (e.g., "F" for "Firefox")

### 5. Rapid Mode Transitions

**Input**: User types "2" (digit) then ":" (project mode) within 100ms

**Output**: Transition directly from `AllWindowsPreview` → `ProjectModePreview`, skip `FilteredWorkspacePreview`

**Validation**: Last event wins, accumulated_digits cleared on ":" detection

## Integration with Existing Models

### WorkspaceModeEvent (Feature 058)

**Existing Schema**:
```python
class WorkspaceModeEvent(BaseModel):
    event_type: str  # "enter", "digit", "execute", "cancel"
    pending_workspace: Optional[PendingWorkspaceState]
```

**Extension**: No schema changes needed. `event_type="enter"` triggers `AllWindowsPreview` rendering.

### PendingWorkspaceState (Feature 058)

**Existing Schema**:
```python
class PendingWorkspaceState(BaseModel):
    workspace_number: int
    mode_type: str  # "goto" or "move"
    target_output: str
    accumulated_digits: str
```

**Extension**: Used for `FilteredWorkspacePreview` (existing behavior), not `AllWindowsPreview`.

## JSON Schema Export

See [contracts/preview-card-all-windows.schema.json](contracts/preview-card-all-windows.schema.json) for full JSON Schema definition.

## Testing Strategy

### Unit Tests (pytest)

```python
def test_all_windows_preview_validation():
    """Test AllWindowsPreview Pydantic model validation."""
    preview = AllWindowsPreview(
        workspace_groups=[
            WorkspaceGroup(
                workspace_num=1,
                workspace_name="1",
                window_count=2,
                windows=[...],
                monitor_output="HEADLESS-1"
            )
        ],
        total_window_count=2,
        total_workspace_count=1
    )

    assert preview.visible is True
    assert preview.type == "all_windows"
    assert preview.total_window_count == 2
    assert not preview.empty
```

### Integration Tests (sway-test)

```json
{
  "name": "All windows preview shows grouped workspace list",
  "actions": [
    {"type": "launch_app_sync", "params": {"app_name": "firefox"}},
    {"type": "launch_app_sync", "params": {"app_name": "code"}},
    {"type": "send_ipc_sync", "params": {"ipc_command": "workspace 5"}},
    {"type": "launch_app_sync", "params": {"app_name": "alacritty"}},
    {"type": "trigger_workspace_mode"}
  ],
  "expectedState": {
    "preview_visible": true,
    "preview_type": "all_windows",
    "workspace_groups": [
      {"workspace_num": 1, "window_count": 1},
      {"workspace_num": 3, "window_count": 1},
      {"workspace_num": 5, "window_count": 1}
    ]
  }
}
```

## References

- **Feature 057**: Unified Bar System (existing workspace preview architecture)
- **Feature 058**: Workspace Mode Feedback (pending workspace highlighting)
- **Feature 069**: Sway Test Framework (test infrastructure)
- **Sway IPC**: GET_TREE message type for window queries
