# Data Model: Intelligent Automatic Workspace-to-Monitor Assignment

**Feature**: 049-intelligent-automatic-workspace
**Date**: 2025-10-29
**Phase**: Phase 1 - Design

## Overview

This document defines the data models for automatic workspace redistribution. All models use Pydantic for validation and serialization, following Python Development Standards (Constitution Principle X).

---

## Core Entities

### 1. MonitorState

Represents the current monitor configuration including active monitors, their roles, and timestamp.

**Purpose**: Track monitor configuration changes and persist preferences for monitor reconnection scenarios.

**Attributes**:
- `version` (str): Schema version for compatibility (e.g., "1.0")
- `last_updated` (datetime): Timestamp of last monitor configuration change
- `active_monitors` (list[MonitorInfo]): List of currently active monitors with roles
- `workspace_assignments` (dict[int, str]): Mapping of workspace numbers to output names

**Validation Rules**:
- `version` must match expected schema version
- `last_updated` must be valid ISO 8601 datetime
- `active_monitors` must contain at least 1 monitor
- `workspace_assignments` must cover workspaces 1-70

**State Transitions**:
- **Initial State**: Empty or default configuration
- **Monitor Connect**: Add monitor to active_monitors, recalculate workspace_assignments
- **Monitor Disconnect**: Remove monitor from active_monitors, recalculate workspace_assignments
- **Persist**: Write to ~/.config/sway/monitor-state.json after any change

**Pydantic Model**:
```python
from pydantic import BaseModel, Field
from datetime import datetime

class MonitorInfo(BaseModel):
    name: str = Field(..., description="Output name from Sway (e.g., HEADLESS-1)")
    role: str = Field(..., description="Monitor role: primary, secondary, tertiary, overflow")
    active: bool = Field(default=True, description="Whether monitor is currently connected")

class MonitorState(BaseModel):
    version: str = Field(default="1.0", description="Schema version")
    last_updated: datetime = Field(..., description="Timestamp of last update")
    active_monitors: list[MonitorInfo] = Field(..., min_items=1, description="Active monitors with roles")
    workspace_assignments: dict[int, str] = Field(..., description="Workspace number -> output name mapping")

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }
```

**Example**:
```json
{
  "version": "1.0",
  "last_updated": "2025-10-29T12:34:56Z",
  "active_monitors": [
    {"name": "HEADLESS-1", "role": "primary", "active": true},
    {"name": "HEADLESS-2", "role": "secondary", "active": true},
    {"name": "HEADLESS-3", "role": "tertiary", "active": true}
  ],
  "workspace_assignments": {
    "1": "HEADLESS-1",
    "2": "HEADLESS-1",
    "3": "HEADLESS-2",
    "4": "HEADLESS-2",
    "5": "HEADLESS-2",
    "6": "HEADLESS-3"
  }
}
```

---

### 2. WorkspaceDistribution

Maps workspace numbers to monitor roles based on active monitor count.

**Purpose**: Calculate workspace-to-monitor distribution using built-in rules, independent of specific monitor names.

**Attributes**:
- `monitor_count` (int): Number of active monitors
- `workspace_to_role` (dict[int, str]): Mapping of workspace number to monitor role (primary/secondary/tertiary/overflow)

**Validation Rules**:
- `monitor_count` must be >= 1
- `workspace_to_role` must cover workspaces 1-70
- All workspace numbers must map to valid roles: primary, secondary, tertiary, overflow

**Distribution Algorithm**:
- **1 monitor**: All workspaces (1-70) → primary
- **2 monitors**: WS 1-2 → primary, WS 3-70 → secondary
- **3 monitors**: WS 1-2 → primary, WS 3-5 → secondary, WS 6-70 → tertiary
- **4+ monitors**: WS 1-2 → primary, WS 3-5 → secondary, WS 6-9 → tertiary, WS 10-70 → overflow (round-robin)

**Pydantic Model**:
```python
class WorkspaceDistribution(BaseModel):
    monitor_count: int = Field(..., ge=1, description="Number of active monitors")
    workspace_to_role: dict[int, str] = Field(..., description="Workspace number -> monitor role mapping")

    @validator("workspace_to_role")
    def validate_workspace_coverage(cls, v):
        """Ensure all workspaces 1-70 are assigned."""
        expected_workspaces = set(range(1, 71))
        actual_workspaces = set(v.keys())
        if not expected_workspaces.issubset(actual_workspaces):
            missing = expected_workspaces - actual_workspaces
            raise ValueError(f"Missing workspace assignments: {missing}")
        return v

    @validator("workspace_to_role")
    def validate_roles(cls, v):
        """Ensure all roles are valid."""
        valid_roles = {"primary", "secondary", "tertiary", "overflow"}
        for ws, role in v.items():
            if role not in valid_roles:
                raise ValueError(f"Invalid role '{role}' for workspace {ws}")
        return v

    @staticmethod
    def calculate(monitor_count: int) -> "WorkspaceDistribution":
        """Calculate distribution based on monitor count."""
        workspace_to_role = {}

        if monitor_count == 1:
            for ws in range(1, 71):
                workspace_to_role[ws] = "primary"
        elif monitor_count == 2:
            for ws in range(1, 3):
                workspace_to_role[ws] = "primary"
            for ws in range(3, 71):
                workspace_to_role[ws] = "secondary"
        elif monitor_count == 3:
            for ws in range(1, 3):
                workspace_to_role[ws] = "primary"
            for ws in range(3, 6):
                workspace_to_role[ws] = "secondary"
            for ws in range(6, 71):
                workspace_to_role[ws] = "tertiary"
        else:  # 4+ monitors
            for ws in range(1, 3):
                workspace_to_role[ws] = "primary"
            for ws in range(3, 6):
                workspace_to_role[ws] = "secondary"
            for ws in range(6, 10):
                workspace_to_role[ws] = "tertiary"
            for ws in range(10, 71):
                workspace_to_role[ws] = "overflow"

        return WorkspaceDistribution(
            monitor_count=monitor_count,
            workspace_to_role=workspace_to_role
        )
```

**Example**:
```json
{
  "monitor_count": 3,
  "workspace_to_role": {
    "1": "primary",
    "2": "primary",
    "3": "secondary",
    "4": "secondary",
    "5": "secondary",
    "6": "tertiary",
    "7": "tertiary"
  }
}
```

---

### 3. WindowMigrationRecord

Tracks windows that were moved from disconnected monitors during reassignment.

**Purpose**: Log window migrations for diagnostics and user feedback, ensure all windows are accounted for.

**Attributes**:
- `window_id` (int): Sway window ID
- `window_class` (str): Window class for identification
- `old_output` (str): Output name before migration
- `new_output` (str): Output name after migration
- `workspace_number` (int): Workspace number (preserved during migration)
- `timestamp` (datetime): When migration occurred

**Validation Rules**:
- `window_id` must be positive integer
- `old_output` and `new_output` must be non-empty strings
- `workspace_number` must be in range 1-70
- `timestamp` must be valid datetime

**Pydantic Model**:
```python
class WindowMigrationRecord(BaseModel):
    window_id: int = Field(..., gt=0, description="Sway window ID")
    window_class: str = Field(..., min_length=1, description="Window class for identification")
    old_output: str = Field(..., min_length=1, description="Output before migration")
    new_output: str = Field(..., min_length=1, description="Output after migration")
    workspace_number: int = Field(..., ge=1, le=70, description="Workspace number (preserved)")
    timestamp: datetime = Field(..., description="Migration timestamp")

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }
```

**Example**:
```json
{
  "window_id": 94532735639728,
  "window_class": "Alacritty",
  "old_output": "HEADLESS-2",
  "new_output": "HEADLESS-1",
  "workspace_number": 5,
  "timestamp": "2025-10-29T12:35:10Z"
}
```

---

### 4. ReassignmentResult

Contains outcome of workspace reassignment operation including performance metrics.

**Purpose**: Monitor reassignment performance, provide user feedback, track success/failure rates.

**Attributes**:
- `success` (bool): Whether reassignment completed successfully
- `workspaces_reassigned` (int): Number of workspaces reassigned
- `windows_migrated` (int): Number of windows moved from disconnected monitors
- `duration_ms` (int): Total duration in milliseconds
- `error_message` (str | None): Error message if failed
- `migration_records` (list[WindowMigrationRecord]): Detailed migration logs

**Validation Rules**:
- `workspaces_reassigned` must be >= 0
- `windows_migrated` must be >= 0
- `duration_ms` must be >= 0
- If `success` is False, `error_message` must be non-empty

**Pydantic Model**:
```python
class ReassignmentResult(BaseModel):
    success: bool = Field(..., description="Whether reassignment succeeded")
    workspaces_reassigned: int = Field(..., ge=0, description="Number of workspaces reassigned")
    windows_migrated: int = Field(..., ge=0, description="Number of windows migrated")
    duration_ms: int = Field(..., ge=0, description="Total duration in milliseconds")
    error_message: str | None = Field(default=None, description="Error message if failed")
    migration_records: list[WindowMigrationRecord] = Field(default_factory=list, description="Detailed migration logs")

    @validator("error_message")
    def validate_error_message(cls, v, values):
        """If not successful, error_message must be provided."""
        if not values.get("success") and not v:
            raise ValueError("error_message required when success=False")
        return v
```

**Example**:
```json
{
  "success": true,
  "workspaces_reassigned": 9,
  "windows_migrated": 12,
  "duration_ms": 850,
  "error_message": null,
  "migration_records": [
    {
      "window_id": 94532735639728,
      "window_class": "Alacritty",
      "old_output": "HEADLESS-2",
      "new_output": "HEADLESS-1",
      "workspace_number": 5,
      "timestamp": "2025-10-29T12:35:10Z"
    }
  ]
}
```

---

## Supporting Types

### OutputEvent

Sway output event received via i3 IPC subscription (provided by i3ipc-python library).

**Attributes** (from i3ipc-python):
- `change` (str): Event type - "connected", "disconnected", "changed"
- `output` (Output): Output object with name, active status, dimensions

**Usage**:
```python
from i3ipc.aio import Connection
from i3ipc import OutputEvent

async def _on_output_event(self, i3: Connection, event: OutputEvent):
    if event.change == "connected":
        # Monitor connected
    elif event.change == "disconnected":
        # Monitor disconnected
```

---

### RoleAssignment

Temporary structure for assigning roles to monitors during reassignment.

**Attributes**:
- `monitor_name` (str): Output name
- `role` (str): Assigned role (primary/secondary/tertiary/overflow)

**Pydantic Model**:
```python
class RoleAssignment(BaseModel):
    monitor_name: str = Field(..., description="Output name")
    role: str = Field(..., description="Monitor role")

    @validator("role")
    def validate_role(cls, v):
        valid_roles = {"primary", "secondary", "tertiary", "overflow"}
        if v not in valid_roles:
            raise ValueError(f"Invalid role: {v}")
        return v
```

---

## Data Flow

```
1. Sway Output Event
   ↓
2. Debounce (500ms)
   ↓
3. Query Sway IPC (GET_OUTPUTS, GET_WORKSPACES, GET_TREE)
   ↓
4. Assign Monitor Roles (RoleAssignment[])
   ↓
5. Calculate Workspace Distribution (WorkspaceDistribution)
   ↓
6. Detect Windows on Disconnected Monitors (WindowMigrationRecord[])
   ↓
7. Apply Workspace Assignments via Sway IPC
   ↓
8. Persist Monitor State (MonitorState → monitor-state.json)
   ↓
9. Update Sway Config Manager (workspace-assignments.json)
   ↓
10. Return Reassignment Result (ReassignmentResult)
```

---

## File Schemas

### monitor-state.json

Persisted monitor configuration state.

**Location**: `~/.config/sway/monitor-state.json`

**Schema**: `MonitorState` model (JSON serialized)

**Example**:
```json
{
  "version": "1.0",
  "last_updated": "2025-10-29T12:34:56Z",
  "active_monitors": [
    {"name": "HEADLESS-1", "role": "primary", "active": true}
  ],
  "workspace_assignments": {
    "1": "HEADLESS-1",
    "2": "HEADLESS-1"
  }
}
```

---

### workspace-assignments.json

Sway Config Manager workspace assignments (updated by this feature).

**Location**: `~/.config/sway/workspace-assignments.json`

**Schema**: Array of `{"workspace": int, "output": str}` objects

**Example**:
```json
[
  {"workspace": 1, "output": "HEADLESS-1"},
  {"workspace": 2, "output": "HEADLESS-1"},
  {"workspace": 3, "output": "HEADLESS-2"}
]
```

---

## Relationships

```
MonitorState
├── has many → MonitorInfo (active_monitors)
└── contains → workspace_assignments (dict)

WorkspaceDistribution
└── maps to → MonitorInfo.role (via workspace_to_role)

ReassignmentResult
├── contains → migration_records (list[WindowMigrationRecord])
└── references → MonitorState (implicit via workspaces_reassigned)

WindowMigrationRecord
└── references → MonitorInfo (old_output, new_output)
```

---

## Performance Considerations

### Data Model Constraints:
- MonitorState: 1 active instance in memory, persisted on every change (~1KB file)
- WorkspaceDistribution: Calculated on-demand, not persisted (~2KB in memory)
- WindowMigrationRecord: Max ~100 records per reassignment (~10KB total)
- ReassignmentResult: Single instance per reassignment, logged and discarded

### Validation Overhead:
- Pydantic validation adds <1ms per model instantiation
- JSON serialization adds <5ms for MonitorState
- Total overhead <10ms per reassignment (within <2s budget)

---

## Migration from Legacy Models

### Deprecated Models (to be removed):
- `WorkspaceMonitorConfig` → Replaced by `MonitorState`
- `MonitorDistribution` → Replaced by `WorkspaceDistribution`
- `ConfigValidationResult` → No longer needed (Pydantic handles validation)

### Migration Path:
1. Delete `monitor_config_manager.py` (entire file)
2. Remove imports of deprecated models from `handlers.py`, `workspace_manager.py`, `ipc_server.py`
3. Replace legacy config file `~/.config/i3/workspace-monitor-mapping.json` with new `monitor-state.json`
4. No data migration required - fresh state generated on first reassignment

---

## Testing Strategy

### Unit Tests:
- Test WorkspaceDistribution.calculate() for all monitor counts (1, 2, 3, 4+)
- Test Pydantic validation for all models (invalid data, boundary conditions)
- Test JSON serialization/deserialization for MonitorState

### Integration Tests:
- Test MonitorState persistence to file
- Test workspace-assignments.json update
- Test data flow: OutputEvent → MonitorState → WorkspaceDistribution → ReassignmentResult

### Scenario Tests:
- Test 3 monitors → 2 monitors transition with window migration
- Test rapid connect/disconnect with debounce (only final state persisted)
- Test 100 windows across 9 workspaces (performance validation)
