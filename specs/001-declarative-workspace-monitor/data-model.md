# Data Model: Declarative Workspace-to-Monitor Assignment with Floating Window Configuration

**Feature**: 001-declarative-workspace-monitor
**Date**: 2025-11-10

## Overview

This document defines the data models for declarative workspace-to-monitor assignment. All models are designed for validation, type safety, and integration with existing i3pm daemon architecture.

---

## Core Entities

### 1. MonitorRole (Enum)

Logical monitor position independent of physical output names.

**Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| value | `"primary" \| "secondary" \| "tertiary"` | Yes | Monitor role identifier |

**Validation Rules**:
- Must be one of three valid roles (case-insensitive)
- Normalized to lowercase on parsing

**Python Implementation**:
```python
from enum import Enum

class MonitorRole(str, Enum):
    """Logical monitor positions for workspace assignment."""
    PRIMARY = "primary"
    SECONDARY = "secondary"
    TERTIARY = "tertiary"

    @classmethod
    def from_str(cls, value: str) -> "MonitorRole":
        """Parse role from string (case-insensitive)."""
        return cls(value.lower())
```

**Nix Validation**:
```nix
# In app-registry-data.nix
validateMonitorRole = role:
  if !builtins.elem (lib.toLower role) ["primary" "secondary" "tertiary"]
  then throw "Invalid monitor role '${role}': must be primary, secondary, or tertiary"
  else lib.toLower role;
```

**State Transitions**: None (immutable enum)

---

### 2. MonitorRoleConfig

Application/PWA configuration for monitor role preference.

**Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| app_name | string | Yes | Application identifier (from registry) |
| preferred_workspace | integer | Yes | Workspace number (1-70) |
| preferred_monitor_role | MonitorRole \| null | No | Desired monitor role (nullable) |
| source | `"app-registry" \| "pwa-sites"` | Yes | Configuration source |

**Validation Rules**:
- `preferred_workspace` must be between 1 and 70
- `preferred_monitor_role` validated against MonitorRole enum if present
- `app_name` must exist in application registry

**Python Implementation**:
```python
from pydantic import BaseModel, Field, validator
from typing import Optional, Literal

class MonitorRoleConfig(BaseModel):
    """Application monitor role preference configuration."""
    app_name: str = Field(..., description="Application identifier")
    preferred_workspace: int = Field(..., ge=1, le=70, description="Workspace number")
    preferred_monitor_role: Optional[MonitorRole] = Field(None, description="Monitor role")
    source: Literal["app-registry", "pwa-sites"] = Field(..., description="Config source")

    @validator("app_name")
    def validate_app_name(cls, v):
        if not v or v.strip() == "":
            raise ValueError("app_name cannot be empty")
        return v
```

**Relationships**:
- References: ApplicationConfig (app-registry), PWAConfig (pwa-sites)
- Used by: MonitorRoleResolver for workspace-to-output assignment

---

### 3. OutputInfo

Physical monitor/output information from Sway IPC.

**Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | Yes | Output identifier (HDMI-A-1, eDP-1, etc.) |
| active | boolean | Yes | Whether output is currently active |
| width | integer | Yes | Output width in pixels |
| height | integer | Yes | Output height in pixels |
| scale | float | No | DPI scale factor (default: 1.0) |

**Validation Rules**:
- `name` must be non-empty
- `width` and `height` must be positive integers
- `scale` must be positive float

**Python Implementation**:
```python
class OutputInfo(BaseModel):
    """Physical monitor/output from Sway IPC GET_OUTPUTS."""
    name: str = Field(..., description="Output identifier")
    active: bool = Field(..., description="Active status")
    width: int = Field(..., gt=0, description="Width in pixels")
    height: int = Field(..., gt=0, description="Height in pixels")
    scale: float = Field(1.0, gt=0.0, description="DPI scale factor")

    class Config:
        frozen = True  # Immutable after creation
```

**State Source**: Sway IPC GET_OUTPUTS (authoritative)

---

### 4. MonitorRoleAssignment

Resolved mapping of monitor roles to physical outputs.

**Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| role | MonitorRole | Yes | Logical monitor role |
| output | string | Yes | Physical output name |
| fallback_applied | boolean | Yes | Whether fallback logic was used |
| preferred_output | string \| null | No | User-configured preferred output |

**Validation Rules**:
- `output` must correspond to an active OutputInfo
- `role` must be unique within assignment set (one role per output)

**Python Implementation**:
```python
class MonitorRoleAssignment(BaseModel):
    """Resolved monitor role to output mapping."""
    role: MonitorRole = Field(..., description="Logical monitor role")
    output: str = Field(..., description="Physical output name")
    fallback_applied: bool = Field(False, description="Fallback logic used")
    preferred_output: Optional[str] = Field(None, description="User-preferred output")

    class Config:
        frozen = True
```

**State Transitions**:
- Recomputed on monitor connect/disconnect events
- Persisted to `monitor-state.json`

---

### 5. WorkspaceAssignment

Complete workspace-to-output assignment with metadata.

**Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| workspace_num | integer | Yes | Workspace number (1-70) |
| output | string | Yes | Assigned output name |
| monitor_role | MonitorRole | Yes | Resolved monitor role |
| app_name | string \| null | No | Application owning workspace |
| source | string | Yes | Config source (app-registry, pwa-sites, default) |

**Validation Rules**:
- `workspace_num` must be unique (no duplicate assignments)
- `output` must be active OutputInfo
- `monitor_role` must have valid MonitorRoleAssignment

**Python Implementation**:
```python
class WorkspaceAssignment(BaseModel):
    """Complete workspace-to-output assignment."""
    workspace_num: int = Field(..., ge=1, le=70, description="Workspace number")
    output: str = Field(..., description="Assigned output")
    monitor_role: MonitorRole = Field(..., description="Monitor role")
    app_name: Optional[str] = Field(None, description="Application identifier")
    source: str = Field(..., description="Assignment source")

    class Config:
        frozen = True
```

**Relationships**:
- Composed from: MonitorRoleConfig + MonitorRoleAssignment
- Persisted in: `monitor-state.json` (version 2.0)
- Queried by: Workspace assignment manager

---

### 6. FloatingWindowConfig

Floating window size and behavior configuration.

**Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| app_name | string | Yes | Application identifier |
| floating | boolean | Yes | Enable floating mode |
| floating_size | FloatingSize \| null | No | Size preset (null = natural size) |
| scope | Scope | Yes | Project filtering scope |

**Validation Rules**:
- `floating` must be true for floating_size to be used
- `floating_size` validated against FloatingSize enum if present
- `scope` validated against Scope enum

**Python Implementation**:
```python
from enum import Enum

class FloatingSize(str, Enum):
    """Floating window size presets."""
    SCRATCHPAD = "scratchpad"  # 1200×600
    SMALL = "small"            # 800×500
    MEDIUM = "medium"          # 1200×800
    LARGE = "large"            # 1600×1000

class Scope(str, Enum):
    """Application project scope."""
    SCOPED = "scoped"
    GLOBAL = "global"

class FloatingWindowConfig(BaseModel):
    """Floating window configuration."""
    app_name: str = Field(..., description="Application identifier")
    floating: bool = Field(..., description="Enable floating")
    floating_size: Optional[FloatingSize] = Field(None, description="Size preset")
    scope: Scope = Field(..., description="Project scope")

    @validator("floating_size")
    def validate_floating_size(cls, v, values):
        if v is not None and not values.get("floating", False):
            raise ValueError("floating_size requires floating=true")
        return v
```

**Size Preset Mapping**:
```python
FLOATING_SIZE_DIMENSIONS = {
    FloatingSize.SCRATCHPAD: (1200, 600),
    FloatingSize.SMALL: (800, 500),
    FloatingSize.MEDIUM: (1200, 800),
    FloatingSize.LARGE: (1600, 1000),
}
```

---

### 7. MonitorStateV2

Extended state file format for monitor role assignments.

**Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| version | string | Yes | State file format version ("2.0") |
| monitor_roles | dict[MonitorRole, string] | Yes | Role to output mapping |
| workspaces | dict[int, WorkspaceAssignment] | Yes | Workspace assignments |
| last_updated | datetime | Yes | Timestamp of last update |

**Validation Rules**:
- `version` must be "2.0"
- `monitor_roles` keys must cover all assigned roles
- `workspaces` keys must match workspace_num in values

**Python Implementation**:
```python
from datetime import datetime
from typing import Dict

class MonitorStateV2(BaseModel):
    """Extended state file for monitor role assignments."""
    version: str = Field("2.0", const=True, description="State format version")
    monitor_roles: Dict[MonitorRole, str] = Field(..., description="Role→output mapping")
    workspaces: Dict[int, WorkspaceAssignment] = Field(..., description="Workspace assignments")
    last_updated: datetime = Field(default_factory=datetime.now, description="Update timestamp")

    @validator("workspaces")
    def validate_workspace_keys(cls, v):
        for key, assignment in v.items():
            if key != assignment.workspace_num:
                raise ValueError(f"Workspace key {key} doesn't match assignment {assignment.workspace_num}")
        return v

    class Config:
        json_encoders = {datetime: lambda dt: dt.isoformat()}
```

**Migration from V1**:
```python
def migrate_v1_to_v2(v1_state: dict) -> MonitorStateV2:
    """Migrate Feature 049 state (v1.0) to v2.0 format."""
    # Infer monitor roles from workspace numbers
    workspaces = {}
    for ws_num_str, output in v1_state["workspaces"].items():
        ws_num = int(ws_num_str)
        role = infer_role_from_workspace(ws_num)
        workspaces[ws_num] = WorkspaceAssignment(
            workspace_num=ws_num,
            output=output,
            monitor_role=role,
            app_name=None,
            source="migrated-v1"
        )

    return MonitorStateV2(
        monitor_roles={role: output for role, output in compute_role_assignments(v1_state)},
        workspaces=workspaces
    )
```

---

## Data Flow Diagram

```
[Nix Config]                    [Sway IPC]
app-registry-data.nix      →    GET_OUTPUTS (active monitors)
pwa-sites.nix                    GET_WORKSPACES (current assignments)
     ↓                                ↓
[Parsing Layer]                [Monitor Detection]
MonitorRoleConfig[]                OutputInfo[]
     ↓                                ↓
[Resolution Layer]
MonitorRoleResolver:
  - resolve_role() → MonitorRoleAssignment[]
  - apply_fallback() → fallback chain
     ↓
[Assignment Layer]
WorkspaceAssignment[] = combine(MonitorRoleConfig, MonitorRoleAssignment)
     ↓
[Persistence]
monitor-state.json (MonitorStateV2)
     ↓
[Sway IPC Commands]
`workspace N output X` for each WorkspaceAssignment
```

---

## Validation Summary

**Nix-level validation** (build-time):
- Monitor role enum values
- Workspace number range (1-70)
- Floating size preset values
- App name existence in registry

**Python-level validation** (runtime):
- Pydantic model constraints
- Output availability checks
- Role uniqueness constraints
- State file schema validation

**Sway IPC validation** (authoritative):
- Output names from GET_OUTPUTS
- Current workspace assignments from GET_WORKSPACES
- Window properties from GET_TREE

---

## Performance Considerations

**Model instantiation**:
- Pydantic validation overhead: ~0.1ms per model
- Target: <10ms for full configuration parse

**State file I/O**:
- JSON serialization: ~1ms for 70 workspaces
- File write (atomic): ~5ms
- Git commit: ~50ms (background, non-blocking)

**Memory footprint**:
- MonitorRoleConfig: ~100 bytes each (~3KB for 30 apps)
- WorkspaceAssignment: ~150 bytes each (~10.5KB for 70 workspaces)
- MonitorStateV2: ~15KB total in-memory representation

---

**Status**: Data model complete. Ready for contract generation (Phase 1).
