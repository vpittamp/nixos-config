# Data Model: Event-Driven Workspace Mode Navigation

**Feature**: Event-Driven Workspace Mode Navigation
**Branch**: 042-event-driven-workspace-mode
**Date**: 2025-10-31

## Overview

This document defines the data models (entities, relationships, and state) for the workspace mode navigation feature. All models use Pydantic for runtime validation and type safety.

## Core Entities

### 1. WorkspaceModeState

**Purpose**: Represents the current workspace mode session state (in-memory only)

**Location**: `home-modules/tools/i3pm/models/workspace_mode.py`

**Schema**:
```python
from pydantic import BaseModel, Field
from typing import Literal, Optional, Dict
from datetime import datetime

class WorkspaceModeState(BaseModel):
    """Current workspace mode session state."""

    active: bool = Field(
        default=False,
        description="Whether workspace mode is currently active"
    )

    mode_type: Optional[Literal["goto", "move"]] = Field(
        default=None,
        description="Type of workspace mode: 'goto' (navigate) or 'move' (move window)"
    )

    accumulated_digits: str = Field(
        default="",
        description="Digits typed by user so far (e.g., '23' for workspace 23)"
    )

    entered_at: Optional[float] = Field(
        default=None,
        description="Unix timestamp when mode was entered"
    )

    output_cache: Dict[str, str] = Field(
        default_factory=dict,
        description="Mapping of output roles to physical output names: PRIMARY/SECONDARY/TERTIARY -> eDP-1/HEADLESS-1/etc."
    )

    class Config:
        json_schema_extra = {
            "example": {
                "active": True,
                "mode_type": "goto",
                "accumulated_digits": "23",
                "entered_at": 1698768000.0,
                "output_cache": {
                    "PRIMARY": "eDP-1",
                    "SECONDARY": "eDP-1",
                    "TERTIARY": "eDP-1"
                }
            }
        }
```

**Validation Rules**:
- `mode_type` must be "goto" or "move" when `active` is True
- `accumulated_digits` must contain only digits 0-9
- `output_cache` keys must be PRIMARY, SECONDARY, TERTIARY
- `entered_at` must be set when `active` is True

**State Transitions**:
```
INACTIVE (default)
  → on_mode_enter → ACTIVE (mode_type set, accumulated_digits = "")
    → on_digit_add → ACTIVE (accumulated_digits updated)
    → on_execute → INACTIVE (mode_type = None, accumulated_digits = "")
    → on_cancel → INACTIVE (mode_type = None, accumulated_digits = "")
```

**Lifecycle**:
- Created once per daemon startup
- Mutated in-place during mode sessions
- Reset to default on mode exit or daemon restart
- Never persisted to disk

---

### 2. WorkspaceSwitch

**Purpose**: Historical record of a single workspace navigation event

**Location**: `home-modules/tools/i3pm/models/workspace_mode.py`

**Schema**:
```python
from pydantic import BaseModel, Field

class WorkspaceSwitch(BaseModel):
    """Record of a workspace navigation event."""

    workspace: int = Field(
        description="Workspace number that was switched to",
        ge=1,
        le=70
    )

    output: str = Field(
        description="Physical output name that was focused (e.g., eDP-1, HEADLESS-1)"
    )

    timestamp: float = Field(
        description="Unix timestamp when switch occurred"
    )

    mode_type: Literal["goto", "move"] = Field(
        description="How user navigated: 'goto' (focus workspace) or 'move' (move window + follow)"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "workspace": 23,
                "output": "HEADLESS-2",
                "timestamp": 1698768123.456,
                "mode_type": "goto"
            }
        }
```

**Validation Rules**:
- `workspace` must be 1-70 (reasonable workspace range)
- `output` must be non-empty string
- `timestamp` must be positive float
- `mode_type` must be "goto" or "move"

**Storage**:
- Stored in circular buffer (max 100 entries)
- In-memory only (cleared on daemon restart)
- Accessed via `workspace_mode.history` IPC method

**Usage**:
- Future enhancement: "recent workspace" shortcuts
- Analytics: Understand user workspace navigation patterns
- Diagnostics: Verify output focusing is correct

---

### 3. WorkspaceModeEvent

**Purpose**: Event broadcast payload for real-time status bar updates

**Location**: `home-modules/tools/i3pm/models/workspace_mode.py`

**Schema**:
```python
from pydantic import BaseModel, Field
from typing import Optional, Literal

class WorkspaceModeEvent(BaseModel):
    """Event broadcast payload for workspace mode state changes."""

    event_type: Literal["workspace_mode"] = Field(
        default="workspace_mode",
        description="Event type identifier (always 'workspace_mode')"
    )

    mode_active: bool = Field(
        description="Whether workspace mode is currently active"
    )

    mode_type: Optional[Literal["goto", "move"]] = Field(
        description="Type of workspace mode, or None if inactive"
    )

    accumulated_digits: str = Field(
        description="Digits accumulated so far (empty string if none)"
    )

    timestamp: float = Field(
        description="Unix timestamp when event was generated"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "event_type": "workspace_mode",
                "mode_active": True,
                "mode_type": "goto",
                "accumulated_digits": "23",
                "timestamp": 1698768123.456
            }
        }
```

**Validation Rules**:
- `event_type` is constant "workspace_mode"
- `mode_type` must be None when `mode_active` is False
- `accumulated_digits` must be empty string when `mode_active` is False
- `timestamp` must be positive float

**Transmission**:
- Broadcast to all subscribed IPC clients (status bar scripts)
- Sent on: mode entry, digit accumulation, mode exit
- Delivery latency target: <5ms from state change

**Consumer**:
- i3bar status block script (`workspace_mode_block.py`)
- Converts event to i3bar protocol JSON (full_text, color, urgent)

---

## Supporting Data Structures

### 4. OutputCache

**Purpose**: In-memory cache of output role → physical output name mapping

**Location**: Embedded in WorkspaceModeState as `output_cache` dict

**Schema**:
```python
# Dict[str, str] with keys:
{
    "PRIMARY": "eDP-1",      # Workspaces 1-2
    "SECONDARY": "eDP-1",    # Workspaces 3-5
    "TERTIARY": "eDP-1"      # Workspaces 6+
}
```

**Population Logic**:
```python
async def _refresh_output_cache(self) -> None:
    """Refresh output cache from i3 IPC."""
    outputs = await self._i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    if len(active_outputs) == 1:
        # Single monitor - all outputs map to same display
        self.output_cache = {
            "PRIMARY": active_outputs[0].name,
            "SECONDARY": active_outputs[0].name,
            "TERTIARY": active_outputs[0].name
        }
    elif len(active_outputs) == 2:
        # Two monitors
        self.output_cache = {
            "PRIMARY": active_outputs[0].name,
            "SECONDARY": active_outputs[1].name,
            "TERTIARY": active_outputs[1].name
        }
    elif len(active_outputs) >= 3:
        # Three or more monitors
        self.output_cache = {
            "PRIMARY": active_outputs[0].name,
            "SECONDARY": active_outputs[1].name,
            "TERTIARY": active_outputs[2].name
        }
```

**Refresh Triggers**:
- Mode entry (on_mode_enter)
- Output event (on_output from i3 IPC subscription)
- Workspace switch execution (fallback to ensure cache is never stale)

**Usage**:
```python
def _get_output_for_workspace(self, workspace: int) -> str:
    """Get output name for workspace number."""
    if workspace in (1, 2):
        return self.output_cache.get("PRIMARY", "eDP-1")
    elif workspace in (3, 4, 5):
        return self.output_cache.get("SECONDARY", "eDP-1")
    else:
        return self.output_cache.get("TERTIARY", "eDP-1")
```

---

### 5. WorkspaceHistory

**Purpose**: Circular buffer of recent workspace switches

**Location**: Embedded in WorkspaceModeManager as `_history` list

**Schema**:
```python
# List[WorkspaceSwitch] with max length 100
_history: List[WorkspaceSwitch] = []
```

**Management**:
```python
def _record_switch(self, workspace: int, output: str, mode_type: str) -> None:
    """Record workspace switch in history."""
    self._history.append(WorkspaceSwitch(
        workspace=workspace,
        output=output,
        timestamp=time.time(),
        mode_type=mode_type
    ))

    # Maintain max 100 entries (circular buffer)
    if len(self._history) > 100:
        self._history.pop(0)
```

**Query Methods**:
```python
def get_history(self, limit: Optional[int] = None) -> List[WorkspaceSwitch]:
    """Get workspace switch history.

    Args:
        limit: Maximum number of entries to return (default: all)

    Returns:
        List of WorkspaceSwitch entries, most recent first
    """
    history = list(reversed(self._history))
    if limit:
        return history[:limit]
    return history
```

---

## IPC Protocol Data

### 6. IPC Method Request Schemas

**workspace_mode.digit**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.digit",
  "params": {
    "digit": "2"  // Single digit 0-9
  },
  "id": 1
}
```

**workspace_mode.execute**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.execute",
  "params": {},
  "id": 2
}
```

**workspace_mode.cancel**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.cancel",
  "params": {},
  "id": 3
}
```

**workspace_mode.state**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.state",
  "params": {},
  "id": 4
}
```

**workspace_mode.history**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.history",
  "params": {
    "limit": 10  // Optional: max entries to return
  },
  "id": 5
}
```

### 7. IPC Method Response Schemas

**workspace_mode.digit response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "accumulated_digits": "23"
  },
  "id": 1
}
```

**workspace_mode.execute response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "workspace": 23,
    "output": "HEADLESS-2",
    "success": true
  },
  "id": 2
}
```

**workspace_mode.cancel response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "cancelled": true
  },
  "id": 3
}
```

**workspace_mode.state response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "active": true,
    "mode_type": "goto",
    "accumulated_digits": "23",
    "entered_at": 1698768000.0,
    "output_cache": {
      "PRIMARY": "eDP-1",
      "SECONDARY": "eDP-1",
      "TERTIARY": "eDP-1"
    }
  },
  "id": 4
}
```

**workspace_mode.history response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "history": [
      {
        "workspace": 5,
        "output": "HEADLESS-1",
        "timestamp": 1698768123.456,
        "mode_type": "goto"
      },
      {
        "workspace": 23,
        "output": "HEADLESS-2",
        "timestamp": 1698768100.123,
        "mode_type": "move"
      }
    ],
    "total": 42
  },
  "id": 5
}
```

---

## Entity Relationships

```
WorkspaceModeState (singleton, in-memory)
  ├─ contains → OutputCache (dict)
  └─ managed by → WorkspaceModeManager

WorkspaceModeManager
  ├─ maintains → WorkspaceHistory (circular buffer of WorkspaceSwitch)
  ├─ broadcasts → WorkspaceModeEvent (on state changes)
  └─ exposes → IPC methods (digit, execute, cancel, state, history)

WorkspaceSwitch (historical record)
  └─ stored in → WorkspaceHistory

WorkspaceModeEvent (broadcast payload)
  ├─ derived from → WorkspaceModeState
  └─ consumed by → Status bar scripts (i3bar)

IPCServer
  ├─ handles → IPC method requests (JSON-RPC)
  ├─ delegates to → WorkspaceModeManager
  └─ broadcasts → WorkspaceModeEvent to subscribed clients
```

---

## Data Flow

### Mode Entry Flow
```
1. User presses CapsLock (M1) or Ctrl+0 (Hetzner)
2. Sway enters goto_workspace mode
3. Sway emits mode event (change="goto_workspace")
4. Daemon on_mode handler called
5. WorkspaceModeManager.enter_mode("goto") updates state:
   - active = True
   - mode_type = "goto"
   - accumulated_digits = ""
   - entered_at = current_timestamp
   - Refresh output_cache from i3 IPC
6. IPCServer broadcasts WorkspaceModeEvent (mode_active=True, accumulated_digits="")
7. Status bar receives event, displays "WS: _"
```

### Digit Accumulation Flow
```
1. User types "2" while in workspace mode
2. Sway bindsym calls: i3pm workspace-mode digit 2
3. CLI tool sends JSON-RPC: workspace_mode.digit {"digit": "2"}
4. IPCServer handles request, calls WorkspaceModeManager.add_digit("2")
5. WorkspaceModeManager updates state:
   - accumulated_digits = "2"
   - Validates digit (reject if not 0-9)
   - Handle leading zero (ignore if accumulated_digits is empty)
6. IPCServer broadcasts WorkspaceModeEvent (accumulated_digits="2")
7. Status bar receives event, displays "WS: 2"
8. Response sent to CLI: {"accumulated_digits": "2"}
```

### Workspace Switch Execution Flow
```
1. User presses Enter in workspace mode
2. Sway bindsym calls: i3pm workspace-mode execute
3. CLI tool sends JSON-RPC: workspace_mode.execute {}
4. IPCServer handles request, calls WorkspaceModeManager.execute()
5. WorkspaceModeManager:
   - Parse accumulated_digits ("23") → workspace = 23
   - Get output from cache: _get_output_for_workspace(23) → "HEADLESS-3"
   - Send i3 IPC command: "workspace number 23"
   - Send i3 IPC command: "focus output HEADLESS-3"
   - Record WorkspaceSwitch in history
   - Reset state: active=False, mode_type=None, accumulated_digits=""
6. Sway returns to default mode (emits mode event)
7. IPCServer broadcasts WorkspaceModeEvent (mode_active=False)
8. Status bar receives event, clears workspace mode display
9. Response sent to CLI: {"workspace": 23, "output": "HEADLESS-3", "success": true}
```

### Mode Cancel Flow
```
1. User presses Escape in workspace mode
2. Sway returns to default mode (emits mode event)
3. Daemon on_mode handler detects mode="default"
4. WorkspaceModeManager.cancel() resets state
5. IPCServer broadcasts WorkspaceModeEvent (mode_active=False)
6. Status bar clears display
```

---

## Persistence Strategy

**In-Memory Only**:
- WorkspaceModeState: Never persisted (ephemeral session state)
- WorkspaceHistory: Never persisted (cleared on daemon restart)
- OutputCache: Refreshed from i3 IPC on demand (never saved)

**Rationale**:
- Workspace mode sessions are short-lived (seconds)
- History is analytics-only (not critical to preserve)
- Output cache can be rebuilt quickly (<1ms i3 IPC query)
- No file I/O on hot path (critical for <10ms latency)

**Trade-offs**:
- ✅ Zero I/O overhead (fast)
- ✅ Simple state management (no corruption risk)
- ✅ Clean restarts (no stale state)
- ❌ History lost on daemon restart (acceptable)
- ❌ Mode state lost if daemon crashes during session (rare, user can re-enter)

---

## Validation & Error Handling

**Pydantic Validation**:
- All models use Pydantic for runtime validation
- Invalid data raises `ValidationError` (caught by IPC server)
- Error responses follow JSON-RPC error codes

**Error Response Example**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params: digit must be 0-9",
    "data": {
      "param": "digit",
      "value": "x"
    }
  },
  "id": 1
}
```

**Edge Cases**:
- Empty accumulated_digits on execute → No-op, return to default mode
- Leading zero → Ignored (first "0" discarded, next digit starts accumulation)
- Invalid digit → Reject with error response
- Daemon restart during mode → State lost, user must re-enter mode
- Output cache stale → Refreshed on next execute (fallback strategy)

---

## Schema Versioning

**Current Version**: 1.0.0

**Compatibility**:
- IPC protocol is versioned (follows JSON-RPC 2.0)
- Pydantic models include version in class metadata
- Breaking changes require major version bump

**Future Extensions** (potential):
- Add `recent_workspaces` to WorkspaceHistory (array of most visited)
- Add `switch_duration` to WorkspaceSwitch (time from mode entry to execute)
- Add `error_count` to WorkspaceModeState (track failed switches)

---

## Summary

The data model is designed for simplicity, performance, and consistency with existing i3pm daemon patterns:

1. **WorkspaceModeState**: Single source of truth for active mode session
2. **WorkspaceSwitch**: Historical record for analytics and future enhancements
3. **WorkspaceModeEvent**: Real-time broadcast payload for status bar
4. **OutputCache**: Fast lookup for workspace → output assignment
5. **WorkspaceHistory**: Circular buffer with bounded memory usage

All entities use Pydantic for validation, ensuring type safety and clear error messages. The in-memory-only strategy eliminates I/O overhead and simplifies state management.
