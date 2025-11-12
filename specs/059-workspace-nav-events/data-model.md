# Data Model: Workspace Navigation Event Broadcasting

**Feature**: 059-workspace-nav-events
**Date**: 2025-11-12
**Purpose**: Define event payloads and state structures for navigation event broadcasting

## Overview

This feature introduces navigation events that flow from the i3pm daemon to workspace-preview-daemon subscribers. The i3pm daemon acts as a stateless broadcaster, while the preview daemon manages navigation state.

## Key Entities

### 1. NavigationEvent

Event payload broadcast when user presses arrow keys (Up/Down/Left/Right) or Home/End keys during workspace mode.

**Fields**:
```python
class NavigationEvent(BaseModel):
    """Navigation event payload (Feature 059).

    Broadcast from i3pm daemon to workspace-preview-daemon when user navigates.
    """
    event_type: Literal["nav"] = Field(..., description="Event type (always 'nav' for navigation)")
    direction: Literal["up", "down", "left", "right", "home", "end"] = Field(
        ...,
        description="Navigation direction"
    )
    mode_type: Optional[Literal["goto", "move"]] = Field(
        None,
        description="Workspace mode type (goto=navigate, move=move workspace)"
    )
    timestamp: datetime = Field(
        default_factory=datetime.now,
        description="When navigation event occurred"
    )
```

**Validation Rules**:
- `direction` must be one of: "up", "down", "left", "right", "home", "end"
- `event_type` is always "nav" (distinguishes from "delete" events)
- `timestamp` auto-populated when event created

**Example**:
```json
{
  "event_type": "nav",
  "direction": "down",
  "mode_type": "goto",
  "timestamp": "2025-11-12T14:30:00.123Z"
}
```

---

### 2. DeleteEvent

Event payload broadcast when user presses Delete key to close the currently selected window.

**Fields**:
```python
class DeleteEvent(BaseModel):
    """Delete event payload (Feature 059).

    Broadcast from i3pm daemon to workspace-preview-daemon when user wants to close selected window.
    """
    event_type: Literal["delete"] = Field(..., description="Event type (always 'delete')")
    mode_type: Optional[Literal["goto", "move"]] = Field(
        None,
        description="Workspace mode type (for context)"
    )
    timestamp: datetime = Field(
        default_factory=datetime.now,
        description="When delete event occurred"
    )
```

**Validation Rules**:
- `event_type` is always "delete"
- No additional fields required (SelectionManager in preview daemon knows which item is selected)

**Example**:
```json
{
  "event_type": "delete",
  "mode_type": "goto",
  "timestamp": "2025-11-12T14:30:05.456Z"
}
```

---

### 3. WorkspaceModeEvent (Extended)

The complete event payload broadcast via JSON-RPC IPC to all subscribers. Extends existing structure from Features 042/058 with new event types.

**Fields**:
```python
class WorkspaceModeEvent(BaseModel):
    """Complete workspace mode event structure (Features 042/058/059).

    Broadcast via IPC server to all subscribers (workspace-preview-daemon, etc.).
    """
    type: Literal["workspace_mode"] = Field(..., description="Event category (always 'workspace_mode')")
    payload: WorkspaceModePayload = Field(..., description="Event-specific data")

class WorkspaceModePayload(BaseModel):
    """Payload within workspace mode event."""
    event_type: Literal["enter", "digit", "nav", "delete", "cancel", "execute"] = Field(
        ...,
        description="Specific event type"
    )
    mode_type: Optional[Literal["goto", "move"]] = Field(
        None,
        description="Workspace mode type"
    )
    accumulated_digits: str = Field(
        default="",
        description="Currently typed digits (Feature 042)"
    )
    pending_workspace: Optional[PendingWorkspaceState] = Field(
        None,
        description="Calculated workspace target (Feature 058)"
    )

    # Feature 059: Navigation-specific fields
    direction: Optional[Literal["up", "down", "left", "right", "home", "end"]] = Field(
        None,
        description="Navigation direction (present only for event_type='nav')"
    )
```

**Event Type Summary**:
- `"enter"`: Workspace mode activated (Feature 042)
- `"digit"`: User typed a digit 0-9 (Feature 042)
- `"nav"`: User pressed arrow/home/end key (Feature 059 - NEW)
- `"delete"`: User pressed Delete key (Feature 059 - NEW)
- `"cancel"`: User cancelled workspace mode (Feature 042)
- `"execute"`: User confirmed workspace switch (Feature 042)

**Example** (nav event):
```json
{
  "type": "workspace_mode",
  "payload": {
    "event_type": "nav",
    "mode_type": "goto",
    "accumulated_digits": "2",
    "pending_workspace": {
      "workspace_num": 2,
      "output_name": "HEADLESS-1",
      "monitor_role": "primary"
    },
    "direction": "down"
  }
}
```

**Example** (delete event):
```json
{
  "type": "workspace_mode",
  "payload": {
    "event_type": "delete",
    "mode_type": "goto",
    "accumulated_digits": "23",
    "pending_workspace": {
      "workspace_num": 23,
      "output_name": "HEADLESS-2",
      "monitor_role": "secondary"
    }
  }
}
```

---

### 4. SelectionState (Preview Daemon)

Navigation state managed by workspace-preview-daemon's SelectionManager. **Not stored in i3pm daemon** - this is for reference only.

**Fields**:
```python
class SelectionState(BaseModel):
    """Current navigation state (managed by workspace-preview-daemon).

    NOTE: This is NOT stored in i3pm daemon - it's owned by the preview daemon.
    """
    selected_index: int = Field(
        default=0,
        description="Index of currently highlighted item (0-based)"
    )
    item_type: Literal["workspace", "window"] = Field(
        default="workspace",
        description="Type of selected item"
    )
    workspace_num: Optional[int] = Field(
        None,
        description="Workspace number if item_type='workspace' or parent workspace if item_type='window'"
    )
    window_id: Optional[int] = Field(
        None,
        description="Sway container ID if item_type='window'"
    )
    total_items: int = Field(
        default=0,
        description="Total number of navigable items"
    )
```

**State Transitions**:
- `nav("down")`: `selected_index` increments (wraps to 0 at end)
- `nav("up")`: `selected_index` decrements (wraps to total_items-1 at start)
- `nav("home")`: `selected_index` = 0
- `nav("end")`: `selected_index` = total_items - 1
- `nav("left")` / `nav("right")`: Navigate into/out of workspace (workspace → windows → next workspace)
- `delete()`: Close selected window, update selected_index to next available item

---

## Entity Relationships

```
User Keyboard Input
  ↓
Sway Keybinding (sway-keybindings.nix)
  ↓
i3pm-workspace-mode CLI (nav <direction> / delete)
  ↓
WorkspaceModeManager.nav(direction) / .delete()
  ↓
_emit_workspace_mode_event("nav", direction=direction)
  ↓
IPC Server broadcasts WorkspaceModeEvent
  ↓
workspace-preview-daemon receives event
  ↓
NavigationHandler.handle_arrow_key_event(direction)
  ↓
SelectionManager updates SelectionState
  ↓
Preview UI re-renders with new highlight
```

**Data Flow**:
1. User presses Down arrow
2. Sway executes: `i3pm-workspace-mode nav down`
3. CLI calls JSON-RPC: `workspace_mode.nav("down")`
4. i3pm daemon emits: `{"type": "workspace_mode", "payload": {"event_type": "nav", "direction": "down"}}`
5. Preview daemon receives event
6. SelectionManager increments `selected_index`
7. Preview card re-renders with new highlight position

**Separation of Concerns**:
- **i3pm daemon**: Broadcasts raw navigation events (stateless)
- **Preview daemon**: Manages visual state and selection logic (stateful)
- **Sway IPC**: Authoritative source for workspace/window data
- **Eww UI**: Renders visual preview based on SelectionState

---

## State Transitions

### Navigation State Machine (Preview Daemon)

```
[Initial State]
  selected_index = 0
  item_type = "workspace"
  workspace_num = 1

  ↓ nav("down")

[Workspace 2 Selected]
  selected_index = 1
  item_type = "workspace"
  workspace_num = 2

  ↓ nav("right")  [enter workspace to see windows]

[First Window in WS 2 Selected]
  selected_index = 0  [reset to first window]
  item_type = "window"
  workspace_num = 2
  window_id = 12345

  ↓ nav("down")

[Second Window in WS 2 Selected]
  selected_index = 1
  item_type = "window"
  workspace_num = 2
  window_id = 12346

  ↓ delete()

[Window Closed, Next Window Selected]
  selected_index = 1  [or wrap if no more windows]
  item_type = "window"
  workspace_num = 2
  window_id = 12347

  ↓ nav("left")  [exit workspace back to workspace list]

[Workspace 2 Selected Again]
  selected_index = 1
  item_type = "workspace"
  workspace_num = 2
```

### Event Emission State Machine (i3pm Daemon)

```
[Mode Inactive]
  active = false
  → nav("down") raises RuntimeError
  → delete() raises RuntimeError

  ↓ enter_mode("goto")

[Mode Active, No Digits]
  active = true
  mode_type = "goto"
  accumulated_digits = ""
  → nav("down") emits {"event_type": "nav", "direction": "down"}
  → nav("up") emits {"event_type": "nav", "direction": "up"}

  ↓ add_digit("2")

[Mode Active, Digit Typed]
  active = true
  accumulated_digits = "2"
  → nav("down") emits {"event_type": "nav", "direction": "down"}
  → delete() emits {"event_type": "delete"}

  ↓ execute()

[Mode Inactive Again]
  active = false
  accumulated_digits = ""
  → nav("down") raises RuntimeError again
```

---

## Validation Rules

### NavigationEvent Validation
1. `direction` must be in {"up", "down", "left", "right", "home", "end"}
2. `event_type` must be "nav"
3. Workspace mode must be active (enforced by WorkspaceModeManager.nav())

### DeleteEvent Validation
1. `event_type` must be "delete"
2. Workspace mode must be active (enforced by WorkspaceModeManager.delete())
3. SelectionManager must have a valid selection (enforced by preview daemon)

### WorkspaceModePayload Validation
1. If `event_type == "nav"`, then `direction` field must be present
2. If `event_type == "delete"`, then `direction` field must be absent
3. `mode_type` is optional but should match WorkspaceModeState.mode_type when active

---

## Performance Characteristics

### Event Payload Size
- **NavigationEvent**: ~100 bytes (small, fast to serialize)
- **DeleteEvent**: ~80 bytes
- **WorkspaceModeEvent** (complete): ~250-400 bytes (includes pending_workspace)

### Serialization Performance
- **orjson**: <1ms for event serialization (existing IPC infrastructure)
- **Network overhead**: <2ms for local Unix socket IPC
- **Total latency**: <5ms from emit to receive

### Memory Footprint
- **i3pm daemon**: No additional state tracking (+0 bytes)
- **Preview daemon**: SelectionState: ~64 bytes
- **Event history**: Not stored (stateless broadcasting)

---

## Technology Mapping

### Python (i3pm daemon)
```python
# workspace_mode.py
async def nav(self, direction: str) -> None:
    """Navigate in workspace preview (Feature 059)."""
    if not self._state.active:
        raise RuntimeError("Cannot navigate: workspace mode not active")

    valid_directions = {"up", "down", "left", "right", "home", "end"}
    if direction not in valid_directions:
        raise ValueError(f"Invalid direction: {direction}. Must be one of {valid_directions}")

    await self._emit_workspace_mode_event("nav", direction=direction)
    logger.info(f"Navigation event emitted: {direction}")
```

### Python (Preview Daemon)
```python
# workspace-preview-daemon
elif event_type == "nav":
    direction = payload.get("direction")
    navigation_handler.handle_arrow_key_event(direction, mode="all_windows")
```

### JSON-RPC (IPC Protocol)
```json
// Request from CLI
{"jsonrpc": "2.0", "method": "workspace_mode.nav", "params": ["down"], "id": 1}

// Event broadcast from daemon
{
  "type": "workspace_mode",
  "payload": {
    "event_type": "nav",
    "direction": "down",
    "mode_type": "goto",
    "accumulated_digits": "2"
  }
}
```

---

## References

- **Feature 042**: Event-Driven Workspace Mode Navigation (base event structure)
- **Feature 058**: Workspace Mode Visual Feedback (pending_workspace payload)
- **Feature 059**: Interactive Workspace Menu (SelectionManager, NavigationHandler)
- **Pydantic**: Data validation library (v2.x)
- **orjson**: Fast JSON serialization for IPC
