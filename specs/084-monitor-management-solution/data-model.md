# Data Model: M1 Hybrid Multi-Monitor Management

**Feature**: 084-monitor-management-solution
**Date**: 2025-11-19

## Overview

This document defines the data models for M1 hybrid multi-monitor management, extending the existing Feature 083 models with hybrid mode support.

---

## Core Entities

### HybridMonitorProfile

Extends the base MonitorProfile to support M1's physical + virtual display configuration.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `name` | string | Profile identifier | `^(local-only|local\+[12]vnc)$` |
| `description` | string | Human-readable description | Max 200 chars |
| `outputs` | OutputConfig[] | List of output configurations | Min 1, max 3 |
| `default` | boolean | Whether this is the default profile | Only one per system |
| `workspace_assignments` | WorkspaceAssignment[] | Workspace-to-output mappings | Non-overlapping ranges |

**Example**:
```json
{
  "name": "local+1vnc",
  "description": "Physical display plus one VNC output",
  "outputs": [
    {
      "name": "eDP-1",
      "type": "physical",
      "enabled": true,
      "position": {"x": 0, "y": 0, "width": 2560, "height": 1600},
      "scale": 2.0
    },
    {
      "name": "HEADLESS-1",
      "type": "virtual",
      "enabled": true,
      "position": {"x": 1280, "y": 0, "width": 1920, "height": 1080},
      "scale": 1.0,
      "vnc_port": 5900
    }
  ],
  "default": false,
  "workspace_assignments": [
    {"output": "eDP-1", "workspaces": [1, 2, 3, 4]},
    {"output": "HEADLESS-1", "workspaces": [5, 6, 7, 8, 9]}
  ]
}
```

---

### OutputConfig

Configuration for a single display output.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `name` | string | Output identifier | `^(eDP-1|HEADLESS-[12])$` |
| `type` | enum | Output type | `physical`, `virtual` |
| `enabled` | boolean | Whether output is active | Required |
| `position` | OutputPosition | Screen coordinates | x,y >= 0 |
| `scale` | float | Display scaling factor | 1.0 or 2.0 |
| `vnc_port` | int? | VNC port (virtual only) | 5900-5901, null for physical |

**State Transitions**:
```
Virtual Output: disabled → created → configured → enabled → disabled → destroyed
Physical Output: enabled (always active)
```

---

### OutputPosition

Represents the position and dimensions of an output.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `x` | int | Horizontal position | >= 0 |
| `y` | int | Vertical position | >= 0 |
| `width` | int | Pixel width | > 0 |
| `height` | int | Pixel height | > 0 |

---

### WorkspaceAssignment

Maps workspaces to their target output.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `output` | string | Target output name | Must exist in profile |
| `workspaces` | int[] | Workspace numbers | 1-100+, non-overlapping |

---

### HybridOutputState

Runtime state for the M1 hybrid monitor system.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `version` | string | State format version | Semver |
| `mode` | enum | System mode | `headless`, `hybrid` |
| `current_profile` | string | Active profile name | Must match profile |
| `outputs` | OutputRuntimeState[] | Current output states | |
| `last_updated` | datetime | Last state change | ISO 8601 |

**Example**:
```json
{
  "version": "1.0",
  "mode": "hybrid",
  "current_profile": "local+1vnc",
  "outputs": {
    "eDP-1": {"enabled": true, "type": "physical"},
    "HEADLESS-1": {"enabled": true, "type": "virtual", "vnc_port": 5900}
  },
  "last_updated": "2025-11-19T14:30:00Z"
}
```

---

### OutputRuntimeState

Runtime state for a single output.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `enabled` | boolean | Currently enabled | Required |
| `type` | enum | Output type | `physical`, `virtual` |
| `vnc_port` | int? | VNC port if virtual | 5900-5901 |
| `workspace_count` | int | Workspaces on this output | >= 0 |

---

### M1MonitorState

Published state for Eww top bar display (extends MonitorState from Feature 083).

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `profile_name` | string | Current profile | Required |
| `mode` | enum | System mode | `headless`, `hybrid` |
| `outputs` | OutputDisplayState[] | Display-ready states | |

---

### OutputDisplayState

Display-ready state for a single output indicator.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `name` | string | Full output name | e.g., "HEADLESS-1" |
| `short_name` | string | Display indicator | L, V1, V2 (M1) or H1, H2, H3 (Hetzner) |
| `active` | boolean | Currently enabled | |
| `workspace_count` | int | Workspaces on output | >= 0 |

---

## File Storage Locations

| File | Path | Purpose |
|------|------|---------|
| Profile definitions | `~/.config/sway/monitor-profiles/*.json` | HybridMonitorProfile instances |
| Current profile | `~/.config/sway/monitor-profile.current` | Active profile name |
| Output states | `~/.config/sway/output-states.json` | HybridOutputState |
| Default profile | `~/.config/sway/monitor-profile.default` | Fallback profile name |

---

## Relationships

```
HybridMonitorProfile 1──* OutputConfig
                    1──* WorkspaceAssignment

HybridOutputState 1──* OutputRuntimeState

M1MonitorState 1──* OutputDisplayState

Profile files ──watchdog── MonitorProfileWatcher ──callback── MonitorProfileService
                                                            ↓
                                                    HybridOutputState (file)
                                                            ↓
                                                    OutputStatesWatcher
                                                            ↓
                                                    Workspace reassignment
```

---

## Pydantic Model Definitions

```python
from pydantic import BaseModel, Field, validator
from typing import Optional, Literal
from datetime import datetime

class OutputPosition(BaseModel):
    x: int = Field(ge=0, default=0)
    y: int = Field(ge=0, default=0)
    width: int = Field(gt=0, default=1920)
    height: int = Field(gt=0, default=1080)

class OutputConfig(BaseModel):
    name: str = Field(pattern=r"^(eDP-1|HEADLESS-[12])$")
    type: Literal["physical", "virtual"]
    enabled: bool = True
    position: OutputPosition = OutputPosition()
    scale: float = Field(ge=1.0, le=2.0, default=1.0)
    vnc_port: Optional[int] = Field(ge=5900, le=5901, default=None)

    @validator("vnc_port")
    def vnc_port_for_virtual_only(cls, v, values):
        if values.get("type") == "physical" and v is not None:
            raise ValueError("Physical outputs cannot have VNC port")
        if values.get("type") == "virtual" and v is None:
            raise ValueError("Virtual outputs must have VNC port")
        return v

class WorkspaceAssignment(BaseModel):
    output: str
    workspaces: list[int] = Field(min_items=1)

class HybridMonitorProfile(BaseModel):
    name: str = Field(pattern=r"^(local-only|local\+[12]vnc)$")
    description: str = Field(max_length=200, default="")
    outputs: list[OutputConfig] = Field(min_items=1, max_items=3)
    default: bool = False
    workspace_assignments: list[WorkspaceAssignment] = []

class OutputRuntimeState(BaseModel):
    enabled: bool
    type: Literal["physical", "virtual"]
    vnc_port: Optional[int] = None
    workspace_count: int = 0

class HybridOutputState(BaseModel):
    version: str = "1.0"
    mode: Literal["headless", "hybrid"]
    current_profile: str
    outputs: dict[str, OutputRuntimeState]
    last_updated: datetime = Field(default_factory=datetime.utcnow)

class OutputDisplayState(BaseModel):
    name: str
    short_name: str  # L, V1, V2 for M1
    active: bool
    workspace_count: int = 0

class M1MonitorState(BaseModel):
    profile_name: str
    mode: Literal["headless", "hybrid"]
    outputs: list[OutputDisplayState]
```

---

## Migration Notes

### From Feature 083

The existing `MonitorProfile` and `MonitorState` models are extended, not replaced:

1. **MonitorProfile** → **HybridMonitorProfile**: Adds `type` field to outputs, `vnc_port` for virtual
2. **OutputState** → **OutputRuntimeState**: Adds `type` field
3. **MonitorState** → **M1MonitorState**: Adds `mode` field

### Backward Compatibility

- Existing Hetzner profiles continue to work unchanged
- `mode: "headless"` uses existing model behavior
- `mode: "hybrid"` enables M1-specific features
