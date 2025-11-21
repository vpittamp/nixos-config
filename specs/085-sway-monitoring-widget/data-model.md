# Data Model: Live Window/Project Monitoring Panel

**Feature**: 085-sway-monitoring-widget
**Date**: 2025-11-20
**Status**: Design Complete

## Overview

This document defines the data structures and JSON schemas used for communication between:
1. **i3pm daemon** → **Python backend script** (via DaemonClient)
2. **Python backend script** → **Eww widget** (via defpoll/defvar)

All entities are designed to be serializable to JSON for Eww consumption and follow existing patterns from Feature 025 (Window State Visualization).

---

## Entity Definitions

### 1. MonitoringPanelState

**Purpose**: Root data structure returned to Eww for rendering

**Fields**:
- `status`: `"ok" | "error"` - Indicates query success or failure
- `monitors`: `MonitorInfo[]` - List of physical/virtual displays
- `monitor_count`: `number` - Total number of monitors
- `workspace_count`: `number` - Total number of workspaces across all monitors
- `window_count`: `number` - Total number of windows across all workspaces
- `timestamp`: `number` - Unix timestamp (seconds since epoch)
- `error`: `string | null` - Error message if status is "error"

**JSON Schema**:
```typescript
interface MonitoringPanelState {
  status: "ok" | "error";
  monitors: MonitorInfo[];
  monitor_count: number;
  workspace_count: number;
  window_count: number;
  timestamp: number;
  error?: string;
}
```

**Example** (success):
```json
{
  "status": "ok",
  "monitors": [...],
  "monitor_count": 2,
  "workspace_count": 8,
  "window_count": 25,
  "timestamp": 1700000000.123,
  "error": null
}
```

**Example** (error):
```json
{
  "status": "error",
  "monitors": [],
  "monitor_count": 0,
  "workspace_count": 0,
  "window_count": 0,
  "timestamp": 1700000000.456,
  "error": "Daemon socket not found: /run/user/1000/i3-project-daemon/ipc.sock"
}
```

---

### 2. MonitorInfo

**Purpose**: Represents a physical or virtual display output

**Fields**:
- `name`: `string` - Output name (e.g., "eDP-1", "HDMI-A-1", "HEADLESS-1")
- `active`: `boolean` - Whether monitor is currently active
- `focused`: `boolean` - Whether this monitor has focused workspace
- `workspaces`: `WorkspaceInfo[]` - List of workspaces on this monitor

**JSON Schema**:
```typescript
interface MonitorInfo {
  name: string;
  active: boolean;
  focused: boolean;
  workspaces: WorkspaceInfo[];
}
```

**Example**:
```json
{
  "name": "eDP-1",
  "active": true,
  "focused": true,
  "workspaces": [
    { "number": 1, "name": "1: Terminal", "focused": true, "windows": [...] },
    { "number": 2, "name": "2: Code", "focused": false, "windows": [...] }
  ]
}
```

---

### 3. WorkspaceInfo

**Purpose**: Represents a Sway workspace containing windows

**Fields**:
- `number`: `number` - Workspace number (1-70)
- `name`: `string` - Workspace name (may include application labels from i3wsr)
- `visible`: `boolean` - Whether workspace is currently visible on any monitor
- `focused`: `boolean` - Whether workspace currently has keyboard focus
- `monitor`: `string` - Output name where workspace is assigned
- `window_count`: `number` - Number of windows in this workspace
- `windows`: `WindowInfo[]` - List of windows in this workspace

**JSON Schema**:
```typescript
interface WorkspaceInfo {
  number: number;
  name: string;
  visible: boolean;
  focused: boolean;
  monitor: string;
  window_count: number;
  windows: WindowInfo[];
}
```

**Example**:
```json
{
  "number": 1,
  "name": "1: Terminal",
  "visible": true,
  "focused": true,
  "monitor": "eDP-1",
  "window_count": 3,
  "windows": [...]
}
```

---

### 4. WindowInfo

**Purpose**: Represents a Sway window with project association and state metadata

**Fields**:
- `id`: `number` - Sway container ID (unique per window)
- `app_name`: `string` - Application name from app registry or window class
- `title`: `string` - Window title (truncated to 50 chars for display)
- `project`: `string` - Project name if scoped window, empty string if global
- `scope`: `"scoped" | "global"` - Window scope classification
- `icon_path`: `string` - Absolute path to application icon (for display)
- `workspace`: `number` - Workspace number where window resides
- `floating`: `boolean` - Whether window is floating (not tiled)
- `hidden`: `boolean` - Whether window is hidden in scratchpad
- `focused`: `boolean` - Whether window currently has keyboard focus

**JSON Schema**:
```typescript
interface WindowInfo {
  id: number;
  app_name: string;
  title: string;
  project: string;
  scope: "scoped" | "global";
  icon_path: string;
  workspace: number;
  floating: boolean;
  hidden: boolean;
  focused: boolean;
}
```

**Example** (scoped window):
```json
{
  "id": 123456,
  "app_name": "ghostty",
  "title": "bash: ~/nixos-085-sway-monitoring-widget",
  "project": "nixos",
  "scope": "scoped",
  "icon_path": "/etc/nixos/assets/icons/terminal.svg",
  "workspace": 1,
  "floating": false,
  "hidden": false,
  "focused": true
}
```

**Example** (global window):
```json
{
  "id": 123457,
  "app_name": "firefox",
  "title": "GitHub - Pull Requests",
  "project": "",
  "scope": "global",
  "icon_path": "/nix/store/.../share/icons/hicolor/scalable/apps/firefox.svg",
  "workspace": 3,
  "floating": false,
  "hidden": false,
  "focused": false
}
```

**Example** (floating/hidden window):
```json
{
  "id": 123458,
  "app_name": "pavucontrol",
  "title": "Volume Control",
  "project": "",
  "scope": "global",
  "icon_path": "/usr/share/icons/hicolor/scalable/apps/multimedia-volume-control.svg",
  "workspace": 1,
  "floating": true,
  "hidden": false,
  "focused": false
}
```

---

## State Transitions

### Panel Visibility State

```
   [Closed]
      ↕ (Keybinding: Mod+m)
   [Open]
```

**Triggers**:
- User presses keybinding (`toggle-monitoring-panel` script)
- Script queries `eww list-windows`, determines state, calls `eww open/close`

**State Persistence**: Eww daemon tracks window state, no external state file needed

---

### Window Visibility State

```
   [Visible] → (Project switch, move to scratchpad) → [Hidden]
      ↑                                                   ↓
      └─────────── (Restore, project switch back) ────────┘
```

**Triggers**:
- i3pm daemon event handlers (`window::move`, `workspace::focus`)
- User actions (project switch, scratchpad toggle)

**State Authority**: Sway IPC `GET_TREE` query (daemon queries on each event)

---

### Monitor Active State

```
   [Active] → (Output disable, monitor disconnect) → [Inactive]
      ↑                                                  ↓
      └─────── (Output enable, monitor reconnect) ───────┘
```

**Triggers**:
- Sway output events (`output::enabled`, `output::disabled`)
- Monitor profile changes (Feature 083/084)

**State Authority**: Sway IPC `GET_OUTPUTS` query

---

## Data Flow Diagram

```
┌──────────────────┐
│  i3pm daemon     │
│  (authoritative) │
└────────┬─────────┘
         │ DaemonClient.get_window_tree()
         │ (async query, 2-5ms)
         ↓
┌──────────────────┐
│  Python backend  │
│  monitoring_data │
│      .py         │
└────────┬─────────┘
         │ JSON output (stdout)
         │ (MonitoringPanelState)
         ↓
┌──────────────────┐
│  Eww defpoll     │
│  monitoring_data │
└────────┬─────────┘
         │ Yuck expression evaluation
         │ (parse JSON, bind to widgets)
         ↓
┌──────────────────┐
│  GTK widgets     │
│  (rendered UI)   │
└──────────────────┘
```

**Update Flow** (event-driven):
```
Sway IPC Event (window::new)
    ↓
i3pm daemon event handler
    ↓
MonitoringPanelPublisher.publish()
    ↓
eww update panel_state='{"monitors":[...]}'
    ↓
Eww widget re-renders (<50ms)
```

---

## Validation Rules

### Field Constraints

| Field | Constraint | Validation |
|-------|-----------|------------|
| `workspace.number` | 1-70 | Must be positive integer in valid range |
| `window.title` | Max 50 chars | Truncate with "..." if longer |
| `window.id` | Unique | Sway container ID (guaranteed unique) |
| `monitor.name` | Non-empty | Must match Sway output name |
| `icon_path` | Valid path or fallback | Use default icon if path invalid |

### Data Integrity

**Empty States**:
- Empty monitors array: Valid (no outputs detected)
- Empty workspaces array: Valid (monitor has no workspaces assigned)
- Empty windows array: Valid (workspace has no windows)

**Null Handling**:
- All nullable fields: Use `null` or empty string `""` (not undefined)
- Missing fields: Use sensible defaults (e.g., `floating: false`, `hidden: false`)

**Error States**:
- Daemon unavailable: Return `status: "error"` with error message
- Timeout: Return `status: "error"` with timeout message
- Malformed response: Log error, return empty state with error status

---

## Performance Characteristics

### Data Sizes (Estimated)

| Windows | JSON Size | Parse Time | Memory |
|---------|-----------|------------|--------|
| 10      | ~5 KB     | <1ms       | ~50 KB |
| 30      | ~15 KB    | ~2ms       | ~150 KB |
| 50      | ~25 KB    | ~3ms       | ~250 KB |
| 100     | ~50 KB    | ~5ms       | ~500 KB |

**Conclusion**: Well under 100KB target for typical workload (20-30 windows)

### Query Performance

**Backend script execution** (stateless):
- Daemon connection: 5-10ms
- `get_window_tree()` query: 2-5ms (20-30 windows)
- JSON formatting: 1-2ms
- **Total**: 9-18ms per invocation

**Eww defpoll overhead**:
- 10s interval: 0.09-0.18% avg CPU usage
- JSON parsing: <5ms per update
- Widget re-render: <50ms for 30 windows

---

## Type Definitions (Python)

### Pydantic Models (for validation)

```python
from pydantic import BaseModel, Field
from typing import List, Literal

class WindowInfo(BaseModel):
    id: int = Field(description="Sway container ID")
    app_name: str = Field(description="Application name")
    title: str = Field(max_length=50, description="Window title (truncated)")
    project: str = Field(default="", description="Project name or empty")
    scope: Literal["scoped", "global"] = Field(description="Window scope")
    icon_path: str = Field(description="Absolute path to icon")
    workspace: int = Field(ge=1, le=70, description="Workspace number")
    floating: bool = Field(default=False, description="Floating state")
    hidden: bool = Field(default=False, description="Hidden in scratchpad")
    focused: bool = Field(default=False, description="Has keyboard focus")

class WorkspaceInfo(BaseModel):
    number: int = Field(ge=1, le=70, description="Workspace number")
    name: str = Field(description="Workspace name")
    visible: bool = Field(description="Currently visible")
    focused: bool = Field(description="Has keyboard focus")
    monitor: str = Field(description="Output name")
    window_count: int = Field(ge=0, description="Number of windows")
    windows: List[WindowInfo] = Field(default_factory=list)

class MonitorInfo(BaseModel):
    name: str = Field(description="Output name")
    active: bool = Field(description="Monitor is active")
    focused: bool = Field(description="Monitor has focused workspace")
    workspaces: List[WorkspaceInfo] = Field(default_factory=list)

class MonitoringPanelState(BaseModel):
    status: Literal["ok", "error"] = Field(description="Query status")
    monitors: List[MonitorInfo] = Field(default_factory=list)
    monitor_count: int = Field(ge=0, description="Total monitors")
    workspace_count: int = Field(ge=0, description="Total workspaces")
    window_count: int = Field(ge=0, description="Total windows")
    timestamp: float = Field(description="Unix timestamp")
    error: str | None = Field(default=None, description="Error message if status=error")
```

---

## Example Payloads

### Complete State (Success)

```json
{
  "status": "ok",
  "monitors": [
    {
      "name": "eDP-1",
      "active": true,
      "focused": true,
      "workspaces": [
        {
          "number": 1,
          "name": "1: Terminal",
          "visible": true,
          "focused": true,
          "monitor": "eDP-1",
          "window_count": 2,
          "windows": [
            {
              "id": 123456,
              "app_name": "ghostty",
              "title": "bash: ~/nixos-085-sway-monitoring-widget",
              "project": "nixos",
              "scope": "scoped",
              "icon_path": "/etc/nixos/assets/icons/terminal.svg",
              "workspace": 1,
              "floating": false,
              "hidden": false,
              "focused": true
            },
            {
              "id": 123457,
              "app_name": "code",
              "title": "monitoring-data.py - VS Code",
              "project": "nixos",
              "scope": "scoped",
              "icon_path": "/nix/store/.../vscode.png",
              "workspace": 1,
              "floating": false,
              "hidden": false,
              "focused": false
            }
          ]
        },
        {
          "number": 3,
          "name": "3: Firefox",
          "visible": false,
          "focused": false,
          "monitor": "eDP-1",
          "window_count": 1,
          "windows": [
            {
              "id": 123458,
              "app_name": "firefox",
              "title": "GitHub - Pull Requests",
              "project": "",
              "scope": "global",
              "icon_path": "/nix/store/.../firefox.svg",
              "workspace": 3,
              "floating": false,
              "hidden": false,
              "focused": false
            }
          ]
        }
      ]
    },
    {
      "name": "HEADLESS-1",
      "active": false,
      "focused": false,
      "workspaces": []
    }
  ],
  "monitor_count": 2,
  "workspace_count": 2,
  "window_count": 3,
  "timestamp": 1700000000.123,
  "error": null
}
```

### Error State (Daemon Unavailable)

```json
{
  "status": "error",
  "monitors": [],
  "monitor_count": 0,
  "workspace_count": 0,
  "window_count": 0,
  "timestamp": 1700000000.456,
  "error": "Daemon socket not found: /run/user/1000/i3-project-daemon/ipc.sock\nIs the daemon running? Check: systemctl --user status i3-project-event-listener"
}
```

---

## References

- **Feature 025**: `i3pm windows --json` output format (source for window tree structure)
- **Feature 072**: Workspace preview JSON schema (monitors → workspaces → windows hierarchy)
- **Python Pydantic**: Data validation and serialization library
- **Eww Documentation**: JSON expression evaluation in Yuck (`{data.field}`)
