# Data Model: Multi-Monitor Window Management Enhancements

**Feature Branch**: `083-multi-monitor-window-management`
**Date**: 2025-11-19

## Entities

### MonitorProfile

Named configuration defining which headless outputs to enable.

**Fields**:
- `name: str` - Profile identifier (e.g., "single", "dual", "triple")
- `description: str` - Human-readable description
- `outputs: List[ProfileOutput]` - Output configurations
- `default: bool` - Whether this is the default profile

**Validation**:
- Name must be lowercase alphanumeric with hyphens
- At least one output must be enabled
- Output names must be valid HEADLESS-N format

**Storage**: `~/.config/sway/monitor-profiles/{name}.json`

### ProfileOutput

Configuration for a single output within a profile.

**Fields**:
- `name: str` - Output name (e.g., "HEADLESS-1")
- `enabled: bool` - Whether output is active in this profile
- `position: OutputPosition` - Screen position for alignment

### OutputPosition

Position and dimensions for output alignment.

**Fields**:
- `x: int` - Horizontal position in pixels
- `y: int` - Vertical position in pixels
- `width: int` - Output width in pixels
- `height: int` - Output height in pixels

### OutputState

Runtime state of each headless output.

**Fields**:
- `name: str` - Output name
- `enabled: bool` - Enabled for workspace distribution
- `active: bool` - Currently connected/active in Sway
- `vnc_connected: bool` - Has active VNC connection

**Storage**: `~/.config/sway/output-states.json`

### ProfileEvent

Event emitted during profile switch operations.

**Fields**:
- `event_type: ProfileEventType` - Type of event
- `timestamp: float` - Unix timestamp
- `profile_name: str` - Profile being switched to
- `previous_profile: Optional[str]` - Previous profile (for rollback)
- `outputs_changed: List[str]` - Outputs that changed state
- `duration_ms: Optional[float]` - Operation duration (on completion)
- `error: Optional[str]` - Error message (on failure)

**Event Types**:
- `PROFILE_SWITCH_START` - Profile switch initiated
- `OUTPUT_ENABLE` - Individual output enabled
- `OUTPUT_DISABLE` - Individual output disabled
- `WORKSPACE_REASSIGN` - Workspaces reassigned
- `PROFILE_SWITCH_COMPLETE` - Profile switch completed successfully
- `PROFILE_SWITCH_FAILED` - Profile switch failed
- `PROFILE_SWITCH_ROLLBACK` - Rolled back to previous profile

### MonitorState (Eww Widget Data)

Data structure pushed to Eww for top bar display.

**Fields**:
- `profile_name: str` - Current active profile name
- `outputs: List[OutputDisplayState]` - Per-output display state

### OutputDisplayState

Display state for a single output in Eww widget.

**Fields**:
- `name: str` - Output name (e.g., "HEADLESS-1")
- `short_name: str` - Display abbreviation (e.g., "H1")
- `active: bool` - Output is enabled and connected
- `workspace_count: int` - Number of workspaces on this output

---

## State Transitions

### Profile Switch State Machine

```
[IDLE]
  │
  ▼ (user selects profile)
[SWITCHING]
  │
  ├─► Enable new outputs
  ├─► Disable old outputs
  ├─► Stop/start WayVNC services
  │
  ▼ (all outputs configured)
[REASSIGNING]
  │
  ├─► Move workspaces to new outputs
  ├─► Update output-states.json
  │
  ▼ (success)                    ▼ (failure)
[IDLE]                        [ROLLING_BACK]
  │                              │
  └── Publish to Eww             ├─► Revert outputs
                                 ├─► Restore previous state
                                 └─► Notify user
```

### Output State Transitions

```
[DISABLED]
  │
  ▼ (profile enables)
[ENABLING]
  │
  ├─► Sway output enable
  ├─► Start wayvnc@{output}
  │
  ▼ (success)         ▼ (failure)
[ENABLED]          [ERROR]
  │                   │
  ▼ (profile disables) │
[DISABLING]           │
  │                   │
  ├─► Stop wayvnc@{output}
  ├─► Sway output disable
  │
  ▼
[DISABLED]
```

---

## Relationships

```
MonitorProfile 1 ─── * ProfileOutput
     │
     └─── outputs

OutputState * ─── 1 OutputStatesFile
     │
     └─── persisted in

ProfileEvent * ─── 1 EventBuffer
     │
     └─── stored in (circular buffer, max 500)

MonitorState 1 ─── * OutputDisplayState
     │
     └─── pushed to Eww widget
```

---

## Existing Entities (Extended)

### StateManager (from state.py)

Extended with profile tracking.

**New Fields**:
- `current_profile: Optional[str]` - Active profile name
- `profile_switch_in_progress: bool` - Atomic switch guard
- `previous_profile: Optional[str]` - For rollback support

### EventBuffer (from daemon.py)

Extended with profile events.

**Event Types Added**:
- Profile switch events (start, complete, failed, rollback)
- Output state change events

---

## File Schemas

### monitor-profiles/{name}.json

```json
{
  "name": "triple",
  "description": "Three-monitor configuration",
  "outputs": [
    {
      "name": "HEADLESS-1",
      "enabled": true,
      "position": { "x": 0, "y": 0, "width": 1920, "height": 1080 }
    },
    {
      "name": "HEADLESS-2",
      "enabled": true,
      "position": { "x": 1920, "y": 0, "width": 1920, "height": 1080 }
    },
    {
      "name": "HEADLESS-3",
      "enabled": true,
      "position": { "x": 3840, "y": 0, "width": 1920, "height": 1080 }
    }
  ],
  "default": false
}
```

### output-states.json (Extended)

```json
{
  "outputs": {
    "HEADLESS-1": "enabled",
    "HEADLESS-2": "enabled",
    "HEADLESS-3": "disabled"
  },
  "current_profile": "dual",
  "last_updated": "2025-11-19T10:30:00Z"
}
```

### monitor-profile.current

Plain text file containing profile name:
```
dual
```

---

## Pydantic Models

```python
from pydantic import BaseModel, Field
from typing import List, Optional
from enum import Enum

class ProfileEventType(str, Enum):
    PROFILE_SWITCH_START = "profile_switch_start"
    OUTPUT_ENABLE = "output_enable"
    OUTPUT_DISABLE = "output_disable"
    WORKSPACE_REASSIGN = "workspace_reassign"
    PROFILE_SWITCH_COMPLETE = "profile_switch_complete"
    PROFILE_SWITCH_FAILED = "profile_switch_failed"
    PROFILE_SWITCH_ROLLBACK = "profile_switch_rollback"

class OutputPosition(BaseModel):
    x: int = 0
    y: int = 0
    width: int = 1920
    height: int = 1080

class ProfileOutput(BaseModel):
    name: str = Field(..., pattern=r"^HEADLESS-[1-9]$")
    enabled: bool = True
    position: OutputPosition = Field(default_factory=OutputPosition)

class MonitorProfile(BaseModel):
    name: str = Field(..., pattern=r"^[a-z0-9-]+$")
    description: str = ""
    outputs: List[ProfileOutput] = Field(..., min_length=1)
    default: bool = False

class ProfileEvent(BaseModel):
    event_type: ProfileEventType
    timestamp: float
    profile_name: str
    previous_profile: Optional[str] = None
    outputs_changed: List[str] = Field(default_factory=list)
    duration_ms: Optional[float] = None
    error: Optional[str] = None

class OutputDisplayState(BaseModel):
    name: str
    short_name: str
    active: bool
    workspace_count: int = 0

class MonitorState(BaseModel):
    profile_name: str
    outputs: List[OutputDisplayState]
```
