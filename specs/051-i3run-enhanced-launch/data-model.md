# Data Model: i3run-Inspired Application Launch UX

**Feature**: 051-i3run-enhanced-launch
**Date**: 2025-11-06
**Status**: Phase 1 Design

## Overview

This document defines the data models for Feature 051's run-raise-hide state machine, scratchpad state preservation, and CLI/daemon communication.

## Core Entities

### 1. WindowState (Enum)

**Purpose**: Represents the 5 possible states in the run-raise-hide state machine

**Definition**:
```python
from enum import Enum

class WindowState(Enum):
    """Five possible window states for run-raise-hide logic."""
    NOT_FOUND = "not_found"                    # Window doesn't exist
    DIFFERENT_WORKSPACE = "different_workspace"  # On another workspace
    SAME_WORKSPACE_UNFOCUSED = "same_workspace_unfocused"  # Same WS, not focused
    SAME_WORKSPACE_FOCUSED = "same_workspace_focused"      # Same WS, focused
    SCRATCHPAD = "scratchpad"                  # Hidden in scratchpad
```

**State Transitions**:
- `NOT_FOUND` → Launch new instance via app-launcher-wrapper.sh
- `DIFFERENT_WORKSPACE` → Switch to workspace (goto) or move window (summon)
- `SAME_WORKSPACE_UNFOCUSED` → Focus window
- `SAME_WORKSPACE_FOCUSED` → Hide to scratchpad (unless `--nohide`)
- `SCRATCHPAD` → Show from scratchpad on current workspace

**Validation Rules**:
- Enum values are immutable strings
- Only these 5 states are valid (enforced by Python enum)

---

### 2. WindowStateInfo (Data Class)

**Purpose**: Complete window state detection result from Sway IPC queries

**Definition**:
```python
from dataclasses import dataclass
from typing import Optional
from i3ipc.aio import Con

@dataclass
class WindowStateInfo:
    """Window state detection result for run-raise-hide logic."""
    state: WindowState
    window: Optional[Con]           # Sway window container (None if NOT_FOUND)
    current_workspace: str          # Current focused workspace name
    window_workspace: Optional[str] # Window's workspace name (None if NOT_FOUND)
    is_focused: bool                # True if window is currently focused

    @property
    def window_id(self) -> Optional[int]:
        """Sway container ID (convenience accessor)."""
        return self.window.id if self.window else None

    @property
    def is_floating(self) -> bool:
        """True if window is in floating mode."""
        return self.window.floating in ["user_on", "auto_on"] if self.window else False

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
```

**Field Descriptions**:
- `state`: One of 5 WindowState enum values
- `window`: Sway IPC container object (from `tree.find_by_id()`)
- `current_workspace`: Workspace name where user is currently focused
- `window_workspace`: Workspace name where window is located (or "__i3_scratch")
- `is_focused`: Whether window has keyboard focus

**Derived Properties**:
- `window_id`: Sway container ID (convenience for logging/RPC)
- `is_floating`: Computed from window.floating property
- `geometry`: Computed from window.rect (only if floating)

**Validation Rules**:
- If `state == NOT_FOUND`, then `window` must be `None`
- If `state == SCRATCHPAD`, then `window_workspace` must be "__i3_scratch"
- If `is_focused == True`, then `current_workspace == window_workspace`

---

### 3. WindowGeometry (Pydantic Model)

**Purpose**: Window position and size for scratchpad state preservation

**Definition**:
```python
from pydantic import BaseModel, Field

class WindowGeometry(BaseModel):
    """Window geometry for scratchpad state preservation."""
    x: int = Field(..., description="X position in pixels (from rect.x)")
    y: int = Field(..., description="Y position in pixels (from rect.y)")
    width: int = Field(..., ge=1, description="Width in pixels (minimum 1)")
    height: int = Field(..., ge=1, description="Height in pixels (minimum 1)")

    class Config:
        frozen = True  # Immutable after creation
```

**Validation Rules**:
- All fields required (non-nullable)
- `width` and `height` must be >= 1 pixel
- Immutable after creation (frozen=True)
- Serializes to JSON as: `{"x": 100, "y": 200, "width": 1000, "height": 600}`

**Usage**:
```python
# Save geometry on scratchpad hide
geometry = WindowGeometry(
    x=window.rect.x,
    y=window.rect.y,
    width=window.rect.width,
    height=window.rect.height
)

# Restore on scratchpad show
await sway.command(
    f'[con_id={window_id}] floating enable, '
    f'resize set {geometry.width} {geometry.height}, '
    f'move position {geometry.x} {geometry.y}'
)
```

---

### 4. ScratchpadState (Pydantic Model)

**Purpose**: Persistent scratchpad state storage (extends Feature 038 schema)

**Definition**:
```python
from pydantic import BaseModel, Field
from typing import Optional

class ScratchpadState(BaseModel):
    """Scratchpad state for window hide/show operations."""
    window_id: int = Field(..., description="Sway container ID")
    app_name: str = Field(..., description="Application name from registry")
    floating: bool = Field(..., description="True if window was floating when hidden")
    geometry: Optional[WindowGeometry] = Field(
        None,
        description="Window geometry (None for tiled windows)"
    )
    hidden_at: float = Field(..., description="Unix timestamp when hidden")
    project_name: Optional[str] = Field(None, description="Project name (if scoped)")

    class Config:
        frozen = True
```

**Field Descriptions**:
- `window_id`: Sway container ID (unique identifier)
- `app_name`: Application name from registry (e.g., "firefox", "vscode")
- `floating`: Window's floating state before hiding
- `geometry`: Position/size if floating, `None` if tiled
- `hidden_at`: Timestamp for cleanup (remove stale entries)
- `project_name`: Optional project association (from I3PM_PROJECT_NAME)

**Validation Rules**:
- `window_id` must be positive integer
- `app_name` must be non-empty string
- If `floating == True`, `geometry` should be set (warning if None)
- If `floating == False`, `geometry` must be `None`
- `hidden_at` must be valid Unix timestamp

**Storage Format** (JSON):
```json
{
  "window_id": 123456,
  "app_name": "firefox",
  "floating": true,
  "geometry": {
    "x": 100,
    "y": 200,
    "width": 1600,
    "height": 900
  },
  "hidden_at": 1730000000.123,
  "project_name": "nixos"
}
```

---

### 5. RunMode (Enum)

**Purpose**: CLI command modes for run-raise-hide behavior

**Definition**:
```python
class RunMode(Enum):
    """CLI run command modes."""
    SUMMON = "summon"   # Default: show on current workspace
    HIDE = "hide"       # Toggle visibility (hide if visible, show if hidden)
    NOHIDE = "nohide"   # Never hide, only show (idempotent)
```

**Mode Behaviors**:

| Mode | Window State | Action |
|------|-------------|--------|
| SUMMON (default) | NOT_FOUND | Launch on current workspace |
| | DIFFERENT_WORKSPACE | Move to current workspace |
| | SAME_WORKSPACE_UNFOCUSED | Focus window |
| | SAME_WORKSPACE_FOCUSED | Focus window (no-op) |
| | SCRATCHPAD | Show on current workspace |
| HIDE | NOT_FOUND | Launch on current workspace |
| | DIFFERENT_WORKSPACE | Move to current workspace |
| | SAME_WORKSPACE_UNFOCUSED | Focus window |
| | SAME_WORKSPACE_FOCUSED | **Hide to scratchpad** |
| | SCRATCHPAD | Show on current workspace |
| NOHIDE | NOT_FOUND | Launch on current workspace |
| | DIFFERENT_WORKSPACE | Move to current workspace |
| | SAME_WORKSPACE_UNFOCUSED | Focus window |
| | SAME_WORKSPACE_FOCUSED | No-op (already visible) |
| | SCRATCHPAD | Show on current workspace |

**CLI Flags**:
- `--summon` or no flag → `RunMode.SUMMON`
- `--hide` → `RunMode.HIDE`
- `--nohide` → `RunMode.NOHIDE`

**Validation Rules**:
- Flags are mutually exclusive (enforced in CLI)
- Only one mode can be active per command

---

### 6. RunRequest (RPC Request Model)

**Purpose**: JSON-RPC request payload for `app.run` daemon method

**Definition**:
```python
from pydantic import BaseModel

class RunRequest(BaseModel):
    """RPC request for app.run method."""
    app_name: str = Field(..., description="Application name from registry")
    mode: str = Field("summon", description="Run mode: summon|hide|nohide")
    force_launch: bool = Field(False, description="Always launch new instance")

    class Config:
        schema_extra = {
            "example": {
                "app_name": "firefox",
                "mode": "summon",
                "force_launch": False
            }
        }
```

**Validation Rules**:
- `app_name` must be non-empty string
- `mode` must be one of: "summon", "hide", "nohide"
- `force_launch` defaults to `False`

**JSON-RPC Format**:
```json
{
  "jsonrpc": "2.0",
  "method": "app.run",
  "params": {
    "app_name": "firefox",
    "mode": "summon",
    "force_launch": false
  },
  "id": 1
}
```

---

### 7. RunResponse (RPC Response Model)

**Purpose**: JSON-RPC response payload for `app.run` daemon method

**Definition**:
```python
class RunResponse(BaseModel):
    """RPC response for app.run method."""
    action: str = Field(..., description="Action taken: launched|focused|moved|hidden|shown|none")
    window_id: Optional[int] = Field(None, description="Sway container ID (if window exists)")
    focused: bool = Field(..., description="True if window is now focused")
    message: str = Field(..., description="Human-readable result message")

    class Config:
        schema_extra = {
            "example": {
                "action": "focused",
                "window_id": 123456,
                "focused": True,
                "message": "Focused Firefox on workspace 3"
            }
        }
```

**Action Values**:
- `"launched"`: New instance launched
- `"focused"`: Existing window focused
- `"moved"`: Window moved to current workspace (summon)
- `"hidden"`: Window hidden to scratchpad
- `"shown"`: Window shown from scratchpad
- `"none"`: No action taken (e.g., already visible with `--nohide`)

**JSON-RPC Format**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "action": "moved",
    "window_id": 123456,
    "focused": true,
    "message": "Moved Firefox to workspace 1"
  },
  "id": 1
}
```

---

## Relationships

### Entity Relationship Diagram

```
RunRequest (RPC)
    ↓
RunRaiseManager.detect_window_state()
    ↓
WindowStateInfo (contains WindowState enum + Sway window)
    ↓
RunRaiseManager.execute_transition()
    ↓ (if hiding to scratchpad)
ScratchpadState (with WindowGeometry if floating)
    ↓ (persisted to JSON)
window-workspace-map.json (Feature 038 schema v1.1)
    ↓ (on show from scratchpad)
Restore geometry via Sway IPC commands
    ↓
RunResponse (RPC)
```

### Data Flow

1. **CLI → Daemon**: `RunRequest` sent via JSON-RPC
2. **Daemon Query**: Lookup window_id from app_name (daemon state)
3. **Sway IPC Query**: `GET_TREE` → find window by ID → `WindowStateInfo`
4. **State Machine**: `WindowState` enum determines transition
5. **Scratchpad Hide**: Store `ScratchpadState` with `WindowGeometry`
6. **Persistence**: Write to `window-workspace-map.json` (Feature 038)
7. **Scratchpad Show**: Load `ScratchpadState` → restore geometry
8. **Daemon → CLI**: `RunResponse` with action/window_id/message

---

## Storage Schema

### window-workspace-map.json (Feature 038 Extension)

**Location**: `~/.config/i3/window-workspace-map.json`

**Schema Version**: v1.1 (existing, no migration needed)

**Format**:
```json
{
  "version": "1.1",
  "last_updated": 1730000000.123,
  "windows": {
    "123456": {
      "workspace_number": 2,
      "floating": true,
      "project_name": "nixos",
      "app_name": "firefox",
      "window_class": "firefox",
      "last_seen": 1730000000.123,
      "geometry": {
        "x": 100,
        "y": 200,
        "width": 1600,
        "height": 900
      },
      "original_scratchpad": false
    }
  }
}
```

**Feature 051 Fields** (already exist in v1.1):
- `geometry`: WindowGeometry dict (Feature 038 added for floating state)
- `original_scratchpad`: bool (Feature 038 added for scratchpad origin)

**No Schema Changes Required**: Feature 051 reuses existing schema!

---

## State Transitions

### State Machine Diagram

```
┌─────────────┐
│  NOT_FOUND  │ ──launch──> [New Window] ──> SAME_WORKSPACE_FOCUSED
└─────────────┘

┌──────────────────────┐
│ DIFFERENT_WORKSPACE  │ ──goto──> [Switch WS] ──> SAME_WORKSPACE_FOCUSED
└──────────────────────┘ ──summon──> [Move to current WS] ──> SAME_WORKSPACE_FOCUSED

┌────────────────────────────┐
│ SAME_WORKSPACE_UNFOCUSED   │ ──focus──> SAME_WORKSPACE_FOCUSED
└────────────────────────────┘

┌───────────────────────────┐
│ SAME_WORKSPACE_FOCUSED    │ ──hide (if mode=HIDE)──> SCRATCHPAD
└───────────────────────────┘ ──noop (if mode=NOHIDE)──> [No change]
                               ──noop (if mode=SUMMON)──> [No change]

┌─────────────┐
│ SCRATCHPAD  │ ──show──> SAME_WORKSPACE_FOCUSED (with geometry restore)
└─────────────┘
```

### Transition Table

| From State | To State | Trigger | Sway Commands | State Storage |
|-----------|----------|---------|---------------|---------------|
| NOT_FOUND | SAME_WS_FOCUSED | Any mode | Launch via app-launcher-wrapper.sh | None |
| DIFFERENT_WS | SAME_WS_FOCUSED | mode=summon | `move to workspace N; focus` | Update geometry if floating |
| DIFFERENT_WS | SAME_WS_FOCUSED | mode=hide/nohide | Same as summon | Same |
| SAME_WS_UNFOCUSED | SAME_WS_FOCUSED | Any mode | `[con_id=X] focus` | None |
| SAME_WS_FOCUSED | SCRATCHPAD | mode=hide | `move scratchpad` | Save floating + geometry |
| SAME_WS_FOCUSED | No change | mode=nohide/summon | None | None |
| SCRATCHPAD | SAME_WS_FOCUSED | Any mode | `scratchpad show` + restore geometry | Clear entry |

---

## Validation Rules Summary

### WindowState
- Must be one of 5 enum values
- Immutable (Python enum)

### WindowStateInfo
- If `state=NOT_FOUND`, `window` must be `None`
- If `state=SCRATCHPAD`, `window_workspace="__i3_scratch"`
- If `is_focused=True`, `current_workspace == window_workspace`

### WindowGeometry
- All fields required (x, y, width, height)
- width/height >= 1
- Immutable (frozen=True)

### ScratchpadState
- `window_id` > 0
- `app_name` non-empty
- If `floating=True`, `geometry` should exist
- If `floating=False`, `geometry` must be `None`
- `hidden_at` valid Unix timestamp

### RunRequest
- `app_name` non-empty
- `mode` ∈ {"summon", "hide", "nohide"}
- `force_launch` boolean

### RunResponse
- `action` ∈ {"launched", "focused", "moved", "hidden", "shown", "none"}
- `focused` boolean
- `message` non-empty

---

## Integration Points

### Feature 038 (Window State Preservation)
- **Reuses**: `window-workspace-map.json` schema v1.1
- **Extends**: Uses existing `geometry` and `original_scratchpad` fields
- **Method**: `WorkspaceTracker.track_window()` for state storage

### Feature 041 (Launch Notification)
- **Reuses**: Daemon's window_id tracking from launch events
- **Lookup**: `window_id = daemon.get_window_id_by_app_name(app_name)`
- **No Changes**: Launch notification flow unchanged

### Feature 057 (Unified Launcher)
- **Reuses**: `app-launcher-wrapper.sh` for launching
- **Environment**: I3PM_* variables automatically injected
- **No Changes**: Launcher script unchanged

### Feature 062 (Scratchpad Terminal)
- **Pattern**: Generalizes scratchpad state preservation logic
- **Difference**: Feature 062 stores in-memory, Feature 051 persists to JSON
- **Migration**: Feature 062 can adopt Feature 051 storage pattern

---

## Performance Characteristics

### Query Latency
- Daemon window_id lookup: <0.1ms (in-memory dict)
- Sway GET_TREE: ~15ms (network IPC)
- find_by_id: <0.1ms (tree traversal)
- State detection: ~20-22ms total

### Storage I/O
- JSON read: <5ms (small file, ~10KB typical)
- JSON write: <10ms (atomic write with temp file)
- Total hide operation: <50ms
- Total show operation: <30ms

### Memory
- WindowStateInfo: ~200 bytes per instance
- ScratchpadState: ~300 bytes per window
- JSON file: ~100 bytes per window entry
- Total daemon overhead: <1MB for 50 windows

---

## Testing Strategy

### Unit Tests (Data Models)
```python
def test_window_geometry_validation():
    """Test WindowGeometry validates width/height >= 1."""
    with pytest.raises(ValidationError):
        WindowGeometry(x=0, y=0, width=0, height=600)  # Invalid width

def test_scratchpad_state_floating_validation():
    """Test ScratchpadState requires geometry if floating."""
    state = ScratchpadState(
        window_id=123,
        app_name="firefox",
        floating=True,
        geometry=None,  # Should warn or error
        hidden_at=time.time()
    )
    # Validation logic TBD (warning vs error)
```

### Integration Tests (State Machine)
```python
@pytest.mark.asyncio
async def test_state_detection_not_found(manager):
    """Test state detection when window doesn't exist."""
    state_info = await manager.detect_window_state("nonexistent-app")
    assert state_info.state == WindowState.NOT_FOUND
    assert state_info.window is None

@pytest.mark.asyncio
async def test_transition_hide_saves_geometry(manager, tracker):
    """Test hiding to scratchpad saves floating geometry."""
    # Setup: floating window on workspace 1
    window = create_mock_window(floating=True, geometry=(100, 200, 1000, 600))

    await manager._transition_hide(window)

    # Verify geometry saved to tracker
    state = await tracker.get_window_workspace(window.id)
    assert state["geometry"] == {"x": 100, "y": 200, "width": 1000, "height": 600}
```

### End-to-End Tests (Full Workflow)
```python
@pytest.mark.asyncio
async def test_run_raise_hide_workflow(cli, daemon):
    """Test complete run-raise-hide workflow."""
    # Step 1: Launch (NOT_FOUND → launch)
    result = await cli.run("firefox", mode="summon")
    assert result["action"] == "launched"

    # Step 2: Focus (SAME_WS_UNFOCUSED → focus)
    await blur_window()
    result = await cli.run("firefox", mode="summon")
    assert result["action"] == "focused"

    # Step 3: Hide (SAME_WS_FOCUSED + mode=hide → scratchpad)
    result = await cli.run("firefox", mode="hide")
    assert result["action"] == "hidden"

    # Step 4: Show (SCRATCHPAD → show with geometry)
    result = await cli.run("firefox", mode="summon")
    assert result["action"] == "shown"
    # Verify geometry restored (within 10px tolerance)
```

---

This data model provides a complete, validated foundation for Feature 051 implementation, reusing proven patterns from Features 038, 041, 057, and 062.
