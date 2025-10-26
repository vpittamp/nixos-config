# Data Model: i3 Window Management System Diagnostic & Optimization

**Feature**: 039-create-a-new
**Date**: 2025-10-26
**Status**: Complete

## Overview

This document defines the data structures used in the i3 window management diagnostic and optimization system. All models use Pydantic for validation and serialization.

---

## Core Entities

### 1. WindowIdentity

Represents the complete identity of an i3 window, including both X11 properties and I3PM environment context.

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class WindowIdentity(BaseModel):
    """Complete window identification and context."""

    # X11/i3 Properties
    window_id: int = Field(..., description="i3 window container ID")
    window_class: str = Field(..., description="WM_CLASS class field (full)")
    window_class_normalized: str = Field(..., description="Normalized class for matching")
    window_instance: Optional[str] = Field(None, description="WM_CLASS instance field")
    window_title: str = Field(..., description="Window title/name")
    window_pid: int = Field(..., description="Process ID of window")

    # Workspace Context
    workspace_number: int = Field(..., description="Current workspace number")
    workspace_name: str = Field(..., description="Current workspace name")
    output_name: str = Field(..., description="Monitor/output name (e.g., 'HDMI-1')")

    # Window State
    is_floating: bool = Field(False, description="Floating vs tiled")
    is_focused: bool = Field(False, description="Currently focused")
    is_hidden: bool = Field(False, description="In scratchpad")

    # I3PM Context
    i3pm_env: Optional["I3PMEnvironment"] = Field(None, description="I3PM environment variables")
    i3pm_marks: list[str] = Field(default_factory=list, description="i3 marks on window")

    # Matching Info (diagnostic)
    matched_app: Optional[str] = Field(None, description="Matched app name from registry")
    match_type: Optional[str] = Field(None, description="Match type: exact, instance, normalized, none")

    # Timestamps
    created_at: datetime = Field(default_factory=datetime.now, description="Window creation time")
    last_seen_at: datetime = Field(default_factory=datetime.now, description="Last state update time")

    class Config:
        json_schema_extra = {
            "example": {
                "window_id": 14680068,
                "window_class": "com.mitchellh.ghostty",
                "window_class_normalized": "ghostty",
                "window_instance": "ghostty",
                "window_title": "vpittamp@hetzner: ~",
                "window_pid": 823199,
                "workspace_number": 2,
                "workspace_name": "2:code",
                "output_name": "HDMI-1",
                "is_floating": False,
                "is_focused": True,
                "is_hidden": False,
                "i3pm_env": {...},
                "i3pm_marks": ["project:stacks", "app:terminal"],
                "matched_app": "terminal",
                "match_type": "instance"
            }
        }
```

---

### 2. I3PMEnvironment

I3PM-specific environment variables set by the app-launcher-wrapper.

```python
class I3PMEnvironment(BaseModel):
    """I3PM environment variables from /proc/{pid}/environ."""

    # Application Identity
    app_id: str = Field(..., description="Unique instance ID: {app}-{project}-{pid}-{timestamp}")
    app_name: str = Field(..., description="Registry application name (e.g., 'vscode', 'terminal')")

    # Workspace Assignment (NEW in Feature 039)
    target_workspace: Optional[int] = Field(None, description="Direct workspace assignment from launcher (1-10)")

    # Project Context
    project_name: Optional[str] = Field(None, description="Active project name (e.g., 'nixos', 'stacks')")
    project_dir: Optional[str] = Field(None, description="Project directory path")
    project_display_name: Optional[str] = Field(None, description="Human-readable project name")
    project_icon: Optional[str] = Field(None, description="Project icon emoji")

    # Scope
    scope: str = Field(..., description="Application scope: 'scoped' or 'global'")
    active: bool = Field(True, description="True if project was active at launch")

    # Launch Context
    launch_time: int = Field(..., description="Unix timestamp of launch")
    launcher_pid: int = Field(..., description="Wrapper script PID")

    class Config:
        json_schema_extra = {
            "example": {
                "app_id": "terminal-stacks-823199-1730000000",
                "app_name": "terminal",
                "project_name": "stacks",
                "project_dir": "/home/vpittamp/projects/stacks",
                "project_display_name": "Stacks",
                "project_icon": "📚",
                "scope": "scoped",
                "active": True,
                "launch_time": 1730000000,
                "launcher_pid": 823150
            }
        }
```

---

### 3. WorkspaceRule

Configuration rule for workspace assignment.

```python
class WorkspaceRule(BaseModel):
    """Workspace assignment rule for an application."""

    # Application Matching
    app_identifier: str = Field(..., description="App name or window class pattern")
    matching_strategy: str = Field("normalized", description="Match strategy: exact, instance, normalized, regex")
    aliases: list[str] = Field(default_factory=list, description="Alternative class names that match")

    # Assignment
    target_workspace: int = Field(..., description="Workspace number to assign (1-10)")
    fallback_behavior: str = Field("current", description="Fallback if workspace unavailable: current, create, error")

    # Metadata
    app_name: str = Field(..., description="Application name from registry")
    description: Optional[str] = Field(None, description="Human-readable description")

    class Config:
        json_schema_extra = {
            "example": {
                "app_identifier": "ghostty",
                "matching_strategy": "normalized",
                "aliases": ["com.mitchellh.ghostty", "Ghostty"],
                "target_workspace": 3,
                "fallback_behavior": "current",
                "app_name": "lazygit",
                "description": "Git TUI in terminal on workspace 3"
            }
        }
```

---

### 4. EventSubscription

Status of i3 IPC event subscription.

```python
class EventSubscription(BaseModel):
    """i3 IPC event subscription status."""

    subscription_type: str = Field(..., description="Event type: window, workspace, output, tick, binding")
    is_active: bool = Field(..., description="True if subscription is currently active")
    event_count: int = Field(0, description="Total events received since daemon start")
    last_event_time: Optional[datetime] = Field(None, description="Timestamp of most recent event")
    last_event_change: Optional[str] = Field(None, description="Last event change type (e.g., 'new', 'focus')")

    class Config:
        json_schema_extra = {
            "example": {
                "subscription_type": "window",
                "is_active": True,
                "event_count": 1234,
                "last_event_time": "2025-10-26T12:34:56",
                "last_event_change": "new"
            }
        }
```

---

### 5. WindowEvent

Represents a captured i3 window event for diagnostic purposes.

```python
class WindowEvent(BaseModel):
    """Captured i3 window event for diagnostics."""

    # Event Metadata
    event_type: str = Field(..., description="Event type: window, workspace, output, tick")
    event_change: str = Field(..., description="Change type: new, close, focus, move, etc.")
    timestamp: datetime = Field(default_factory=datetime.now, description="Event capture time")

    # Window Context
    window_id: Optional[int] = Field(None, description="Window container ID (if window event)")
    window_class: Optional[str] = Field(None, description="Window class at event time")
    window_title: Optional[str] = Field(None, description="Window title at event time")

    # Processing Info
    handler_duration_ms: Optional[float] = Field(None, description="Handler execution time in milliseconds")
    workspace_assigned: Optional[int] = Field(None, description="Workspace assigned (if applicable)")
    marks_applied: list[str] = Field(default_factory=list, description="Marks applied to window")

    # Error Tracking
    error: Optional[str] = Field(None, description="Error message if processing failed")
    stack_trace: Optional[str] = Field(None, description="Stack trace for debugging")

    class Config:
        json_schema_extra = {
            "example": {
                "event_type": "window",
                "event_change": "new",
                "timestamp": "2025-10-26T12:34:56.789",
                "window_id": 14680068,
                "window_class": "com.mitchellh.ghostty",
                "window_title": "vpittamp@hetzner: ~",
                "handler_duration_ms": 45.2,
                "workspace_assigned": 3,
                "marks_applied": ["project:stacks", "app:terminal"],
                "error": None
            }
        }
```

---

### 6. StateValidation

Results of daemon state consistency check against i3 IPC.

```python
class StateValidation(BaseModel):
    """State consistency validation results."""

    # Validation Metadata
    validated_at: datetime = Field(default_factory=datetime.now, description="Validation timestamp")
    total_windows_checked: int = Field(0, description="Total windows validated")

    # Consistency Metrics
    windows_consistent: int = Field(0, description="Windows matching i3 state")
    windows_inconsistent: int = Field(0, description="Windows with state drift")
    mismatches: list["StateMismatch"] = Field(default_factory=list, description="Detailed mismatches")

    # Overall Status
    is_consistent: bool = Field(True, description="True if all state matches")
    consistency_percentage: float = Field(100.0, description="Percentage of windows consistent")

    class Config:
        json_schema_extra = {
            "example": {
                "validated_at": "2025-10-26T12:34:56",
                "total_windows_checked": 23,
                "windows_consistent": 21,
                "windows_inconsistent": 2,
                "mismatches": [{...}],
                "is_consistent": False,
                "consistency_percentage": 91.3
            }
        }


class StateMismatch(BaseModel):
    """Specific state inconsistency between daemon and i3."""

    window_id: int = Field(..., description="Window with mismatch")
    property_name: str = Field(..., description="Property that doesn't match (e.g., 'workspace', 'marks')")
    daemon_value: str = Field(..., description="Value in daemon state")
    i3_value: str = Field(..., description="Value in i3 IPC state (authoritative)")
    severity: str = Field(..., description="Severity: critical, warning, info")

    class Config:
        json_schema_extra = {
            "example": {
                "window_id": 14680068,
                "property_name": "workspace",
                "daemon_value": "3",
                "i3_value": "5",
                "severity": "warning"
            }
        }
```

---

### 7. I3IPCState

Snapshot of i3's authoritative state via IPC.

```python
class I3IPCState(BaseModel):
    """i3 IPC authoritative state snapshot."""

    # Outputs/Monitors
    outputs: list["OutputInfo"] = Field(default_factory=list, description="Connected outputs")
    active_output_count: int = Field(0, description="Number of active monitors")

    # Workspaces
    workspaces: list["WorkspaceInfo"] = Field(default_factory=list, description="All workspaces")
    visible_workspace_count: int = Field(0, description="Number of visible workspaces")
    focused_workspace: Optional[str] = Field(None, description="Currently focused workspace name")

    # Windows
    total_windows: int = Field(0, description="Total window count from tree")
    marks: list[str] = Field(default_factory=list, description="All marks in current session")

    # Capture Time
    captured_at: datetime = Field(default_factory=datetime.now, description="State capture timestamp")


class OutputInfo(BaseModel):
    """Monitor/output information from i3 IPC."""
    name: str = Field(..., description="Output name (e.g., 'HDMI-1')")
    active: bool = Field(..., description="Output is active")
    current_workspace: Optional[str] = Field(None, description="Workspace currently on this output")


class WorkspaceInfo(BaseModel):
    """Workspace information from i3 IPC."""
    num: int = Field(..., description="Workspace number")
    name: str = Field(..., description="Workspace name with icon")
    visible: bool = Field(..., description="Currently visible on an output")
    focused: bool = Field(..., description="Currently focused")
    output: str = Field(..., description="Output name this workspace is on")
```

---

### 8. DiagnosticReport

Comprehensive diagnostic report combining all state information.

```python
class DiagnosticReport(BaseModel):
    """Comprehensive system diagnostic report."""

    # Report Metadata
    generated_at: datetime = Field(default_factory=datetime.now, description="Report generation time")
    daemon_version: str = Field(..., description="Daemon version string")
    uptime_seconds: float = Field(..., description="Daemon uptime in seconds")

    # Connection Status
    i3_ipc_connected: bool = Field(..., description="i3 IPC connection active")
    json_rpc_server_running: bool = Field(..., description="JSON-RPC IPC server active")

    # Event Subscriptions
    event_subscriptions: list[EventSubscription] = Field(default_factory=list, description="All event subscriptions")
    total_events_processed: int = Field(0, description="Sum of all event counts")

    # Window Tracking
    tracked_windows: list[WindowIdentity] = Field(default_factory=list, description="All tracked windows")
    total_windows: int = Field(0, description="Total window count")

    # Recent Events
    recent_events: list[WindowEvent] = Field(default_factory=list, description="Last N events (circular buffer)")
    event_buffer_size: int = Field(500, description="Max events in buffer")

    # State Validation
    state_validation: Optional[StateValidation] = Field(None, description="Consistency check results")

    # i3 IPC State
    i3_ipc_state: Optional[I3IPCState] = Field(None, description="i3 authoritative state snapshot")

    # Health Status
    overall_status: str = Field("unknown", description="Overall health: healthy, warning, critical, unknown")
    health_issues: list[str] = Field(default_factory=list, description="List of detected issues")

    class Config:
        json_schema_extra = {
            "example": {
                "generated_at": "2025-10-26T12:34:56",
                "daemon_version": "1.4.0",
                "uptime_seconds": 3600.5,
                "i3_ipc_connected": True,
                "json_rpc_server_running": True,
                "total_events_processed": 1350,
                "total_windows": 23,
                "overall_status": "warning",
                "health_issues": ["State drift detected for 2 windows"]
            }
        }
```

---

## Data Flow

### Window Creation Flow

```
1. i3 creates window
   └─> window::new event fired

2. Daemon receives event
   └─> Extract window_id, class, instance, title, PID from i3 container

3. Read environment
   └─> Read /proc/{pid}/environ for I3PM_* variables
   └─> Parse into I3PMEnvironment model

4. Normalize class
   └─> Apply normalize_class() transformation
   └─> Store both original and normalized

5. Match workspace rule
   └─> Query application-registry.json
   └─> Use tiered matching (exact → instance → normalized)
   └─> Get WorkspaceRule

6. Assign workspace
   └─> Execute i3 command: move to workspace number {target}
   └─> Apply marks: project:{name}, app:{name}

7. Create WindowIdentity
   └─> Populate all fields
   └─> Add to tracked_windows dict
   └─> Update state

8. Record event
   └─> Create WindowEvent with metrics
   └─> Add to circular event buffer
   └─> Log for diagnostics
```

### Diagnostic Query Flow

```
1. User runs: i3pm diagnose window <id>

2. CLI connects to daemon JSON-RPC

3. Daemon queries:
   └─> WindowIdentity from tracked_windows
   └─> Current i3 tree for live state
   └─> WorkspaceRule from registry

4. Build response:
   └─> Combine WindowIdentity + live i3 state
   └─> Include match information
   └─> Include any state mismatches

5. CLI formats output:
   └─> Rich table for human-readable
   └─> JSON if --json flag

6. User sees:
   ┌─────────────────────────────────────┐
   │ Window: 14680068                    │
   ├─────────────────────────────────────┤
   │ Class: com.mitchellh.ghostty        │
   │ Instance: ghostty                   │
   │ Normalized: ghostty                 │
   │ Matched App: terminal               │
   │ Match Type: instance                │
   │ Target WS: 3                        │
   │ Current WS: 5 ⚠️ MISMATCH           │
   └─────────────────────────────────────┘
```

---

## Validation Rules

### WindowIdentity Validation

- `window_id` must be positive integer
- `window_class` must be non-empty string
- `window_pid` must be positive integer
- `workspace_number` must be 1-10 (i3 default workspace range)
- `match_type` must be one of: "exact", "instance", "normalized", "none", or None

### I3PMEnvironment Validation

- `app_id` must match pattern: `{app}-{project}-{pid}-{timestamp}`
- `app_name` must be non-empty string
- `scope` must be either "scoped" or "global"
- `launch_time` must be Unix timestamp (positive integer)

### WorkspaceRule Validation

- `matching_strategy` must be one of: "exact", "instance", "normalized", "regex"
- `target_workspace` must be 1-10
- `fallback_behavior` must be one of: "current", "create", "error"

### DiagnosticReport Validation

- `overall_status` must be one of: "healthy", "warning", "critical", "unknown"
- `event_buffer_size` must be positive integer
- `uptime_seconds` must be non-negative

---

## Pydantic Configuration

All models use these Pydantic settings:

```python
class BaseConfig:
    # Allow extra fields during parsing (forward compatibility)
    extra = "ignore"

    # Use enum values, not names
    use_enum_values = True

    # Validate on assignment
    validate_assignment = True

    # JSON schema generation
    json_schema_extra = {...}  # Examples for documentation
```

---

## JSON Schema Export

Generate JSON schemas for contract documentation:

```python
# Generate schema files for contracts/
WindowIdentity.model_json_schema(mode='serialization')
I3PMEnvironment.model_json_schema(mode='serialization')
DiagnosticReport.model_json_schema(mode='serialization')
```

Output to: `contracts/window-identity-schema.json`, etc.

---

## Next Steps

1. Implement Pydantic models in `models.py`
2. Generate JSON schemas for contracts
3. Create API contracts using these models
4. Implement serialization/deserialization in IPC layer
