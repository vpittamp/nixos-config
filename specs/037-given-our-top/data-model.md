# Data Model: Unified Project-Scoped Window Management

**Feature**: 037-given-our-top | **Date**: 2025-10-25

## Overview

This document defines the data structures and relationships for project-scoped window filtering and workspace persistence in the i3pm system.

---

## Core Entities

### WindowState

Represents a window's persistent state for restoration after hiding.

**Attributes**:
```python
@dataclass
class WindowState:
    window_id: int              # i3 container ID
    workspace_number: int       # Workspace where window was/should be
    floating: bool              # True if floating, False if tiled
    project_name: str           # Project this window belongs to
    app_name: str               # Application name from registry (e.g., "vscode")
    window_class: str           # X11 window class (e.g., "Code")
    last_seen: float            # Unix timestamp of last state update
```

**Relationships**:
- Belongs to **Project** (via `project_name`)
- Resides on **Workspace** (via `workspace_number`)
- Instantiates **Application** (via `app_name`)

**State Transitions**:
```
visible (on workspace) → hidden (in scratchpad) → visible (restored to workspace)
                       ↓
                    cleanup (window closed)
```

**Validation Rules**:
- `workspace_number` must be in range 1-70
- `project_name` must exist in projects registry or be empty string (global)
- `window_id` must be valid i3 container ID
- `last_seen` updated on every state change

**Persistence**: Stored in `~/.config/i3/window-workspace-map.json`

---

### Project

Represents a named workspace context with associated windows (from Feature 035).

**Attributes**:
```python
@dataclass
class Project:
    name: str                   # Unique project identifier (e.g., "nixos")
    directory: str              # Project root directory
    display_name: str           # Human-readable name
    icon: str                   # Icon emoji for display
```

**Relationships**:
- Has many **WindowState** objects (windows belonging to this project)
- Windows associated via `I3PM_PROJECT_NAME` environment variable

**Operations**:
- `get_visible_windows()`: Query i3 tree for windows with matching project
- `get_hidden_windows()`: Query scratchpad for windows with matching project
- `hide_windows()`: Move all project windows to scratchpad
- `restore_windows()`: Move project windows back to tracked workspaces

---

### Application

Application definition from registry (from Feature 035).

**Attributes**:
```python
@dataclass
class Application:
    name: str                   # Unique app identifier (e.g., "vscode")
    display_name: str           # Human-readable name
    scope: str                  # "scoped" or "global"
    preferred_workspace: int    # Default workspace assignment
    expected_class: str         # Window class for matching
```

**Relationships**:
- Launched instances become **WindowState** objects
- `scope` determines filtering behavior:
  - **scoped**: Hidden when project inactive
  - **global**: Always visible across all projects

**Filtering Rules**:
- If `scope == "global"`: Never hide, always visible
- If `scope == "scoped"`: Hide when `I3PM_PROJECT_NAME != active_project`

---

### Workspace

i3 workspace container (queried from i3 IPC).

**Attributes**:
```python
@dataclass
class Workspace:
    number: int                 # Workspace number (1-70)
    name: str                   # Display name (e.g., "1:Code")
    visible: bool               # Currently visible on any output
    focused: bool               # Has focus
    output: str                 # Monitor name (e.g., "eDP-1", "HDMI-1")
```

**Relationships**:
- Assigned to **Monitor** (via `output`)
- Contains **WindowState** objects (via `workspace_number`)

**Authority**: i3 IPC GET_WORKSPACES is authoritative source

---

### Monitor

Physical display output (queried from i3 IPC).

**Attributes**:
```python
@dataclass
class Monitor:
    name: str                   # Output name (e.g., "eDP-1")
    active: bool                # Currently connected
    primary: bool               # Primary output
    current_workspace: str      # Currently visible workspace name
    rect: Rect                  # Dimensions (x, y, width, height)
```

**Relationships**:
- Hosts **Workspace** objects
- Configuration from Feature 033's workspace-monitor-mapping.json

**Events**:
- `output::connected`: Monitor plugged in
- `output::disconnected`: Monitor removed

---

## Derived Entities

### ProjectWindows

Collection of windows grouped by visibility state for a specific project.

**Attributes**:
```python
@dataclass
class ProjectWindows:
    project_name: str
    visible: list[WindowState]    # Windows currently on workspaces
    hidden: list[WindowState]     # Windows in scratchpad
    total_count: int              # len(visible) + len(hidden)
```

**Operations**:
- `hide_all()`: Move all visible windows to scratchpad
- `restore_all()`: Move all hidden windows back to tracked workspaces
- `filter_by_scope(scope)`: Get only scoped or global windows

**Usage**: Status display, bulk operations during project switches

---

### WindowFilterResult

Result of a window filtering operation.

**Attributes**:
```python
@dataclass
class WindowFilterResult:
    windows_hidden: int           # Count of windows moved to scratchpad
    windows_restored: int         # Count of windows restored to workspaces
    errors: list[WindowError]     # Errors during operation
    duration_ms: float            # Time taken for operation
```

**Error Types**:
```python
@dataclass
class WindowError:
    window_id: int
    operation: str                # "hide" or "restore"
    error_message: str
    recoverable: bool             # Can retry or needs manual intervention
```

---

## State Files

### window-workspace-map.json

Persistent storage for window workspace tracking.

**Schema**:
```json
{
  "version": "1.0",
  "last_updated": 1730000000.123,
  "windows": {
    "123456": {
      "workspace_number": 2,
      "floating": false,
      "project_name": "nixos",
      "app_name": "vscode",
      "window_class": "Code",
      "last_seen": 1730000000.123
    },
    "789012": {
      "workspace_number": 1,
      "floating": false,
      "project_name": "stacks",
      "app_name": "terminal",
      "window_class": "Ghostty",
      "last_seen": 1729999000.456
    }
  }
}
```

**Operations**:
- **Load**: Read on daemon start, parse JSON, validate schema
- **Save**: Atomic write (temp file + rename) on state changes
- **Update**: Modify entry when window moves or changes workspace
- **Cleanup**: Remove entry when window closes (window::close event)
- **Garbage Collection**: Remove entries for windows not in i3 tree (on daemon start)

**Size Limits**: Max 1000 entries, evict oldest by `last_seen` timestamp

---

## Environment Variables (from Feature 035)

### I3PM_* Variables

Injected by app-launcher-wrapper.sh, read from `/proc/<pid>/environ`.

**Schema**:
```
I3PM_APP_ID=vscode-nixos-12345-1730000000
I3PM_APP_NAME=vscode
I3PM_PROJECT_NAME=nixos
I3PM_PROJECT_DIR=/etc/nixos
I3PM_PROJECT_DISPLAY_NAME=NixOS
I3PM_PROJECT_ICON=
I3PM_SCOPE=scoped
I3PM_ACTIVE=true
I3PM_LAUNCH_TIME=1730000000
I3PM_LAUNCHER_PID=12344
```

**Usage**:
- **Window Association**: `I3PM_PROJECT_NAME` determines project ownership
- **Scope Filtering**: `I3PM_SCOPE` determines if window should hide
- **Fallback**: Missing variables → treat as global scope (always visible)

**Extraction**:
```python
async def get_window_project(window: i3ipc.Con) -> str:
    """Extract project name from window's process environment."""
    pid = window.pid or await get_pid_from_xprop(window.window)
    environ_path = f"/proc/{pid}/environ"

    try:
        with open(environ_path, "rb") as f:
            environ = f.read().decode("utf-8", errors="ignore")
            env_vars = dict(item.split("=", 1) for item in environ.split("\0") if "=" in item)
            return env_vars.get("I3PM_PROJECT_NAME", "")  # Empty string = global
    except FileNotFoundError:
        return ""  # Process died, treat as global
```

---

## Data Flow

### Project Switch Flow

```
1. User executes: i3pm project switch <name>
   ↓
2. CLI sends tick event to i3: i3-msg "nop i3pm-project-switch <name>"
   ↓
3. Daemon receives tick event in handle_tick()
   ↓
4. Daemon reads active_project from active-project.json
   ↓
5. Query i3 tree for all windows (GET_TREE)
   ↓
6. For each window:
   - Extract PID from window object
   - Read /proc/<pid>/environ for I3PM_* variables
   - Parse I3PM_PROJECT_NAME and I3PM_SCOPE
   ↓
7. Filter windows:
   - Old project scoped windows → hide_list
   - New project scoped windows → restore_list
   - Global windows → ignore (stay visible)
   ↓
8. Save current workspace positions to window-workspace-map.json
   ↓
9. Execute batch hide: [con_id="A"] move scratchpad; [con_id="B"] move scratchpad; ...
   ↓
10. Execute batch restore: [con_id="C"] move to workspace 2; [con_id="D"] move to workspace 1; ...
   ↓
11. Update window-workspace-map.json with new window positions
   ↓
12. Return WindowFilterResult to CLI
```

### Window Launch Flow

```
1. User launches app via Walker/Elephant
   ↓
2. app-launcher-wrapper.sh intercepts
   ↓
3. Wrapper queries daemon for active project
   ↓
4. Wrapper injects I3PM_* environment variables
   ↓
5. Application launches (variables persist in /proc)
   ↓
6. i3 creates window, fires window::new event
   ↓
7. Daemon receives window::new in handle_window_new()
   ↓
8. Daemon extracts I3PM_PROJECT_NAME from /proc/<pid>/environ
   ↓
9. Daemon assigns window to preferred_workspace from registry
   ↓
10. Daemon creates WindowState entry in window-workspace-map.json
   ↓
11. Window appears on correct workspace for active project
```

### Window Restoration Flow

```
1. Daemon executes restore_project_windows(project_name)
   ↓
2. Query i3 tree for scratchpad windows (GET_TREE)
   ↓
3. Filter scratchpad windows:
   - Extract I3PM_PROJECT_NAME from each window's /proc/<pid>/environ
   - Match against target project_name
   ↓
4. For each matching window:
   - Load workspace_number from window-workspace-map.json
   - Validate workspace exists via GET_WORKSPACES
   - Fallback to workspace 1 if invalid
   ↓
5. Build batch restore command:
   [con_id="A"] move to workspace number 2, floating disable;
   [con_id="B"] move to workspace number 1, floating disable;
   ↓
6. Execute batch command via i3 IPC COMMAND
   ↓
7. Update window-workspace-map.json with restored positions
   ↓
8. Return list of restored windows
```

---

## Validation Rules

### Window State Validation
- ✅ `workspace_number` in range 1-70
- ✅ `project_name` exists in projects registry or is empty (global)
- ✅ `window_id` present in i3 tree (via GET_TREE)
- ✅ `floating` is boolean value
- ✅ `last_seen` is valid Unix timestamp

### Project Validation
- ✅ `name` is unique, non-empty string
- ✅ `directory` is absolute path, exists on filesystem
- ✅ `display_name` is non-empty string
- ✅ `icon` is valid Unicode emoji or empty

### Scope Validation
- ✅ `scope` is either "scoped" or "global"
- ✅ Global windows never have project association
- ✅ Scoped windows always have valid I3PM_PROJECT_NAME

---

## Performance Considerations

### State File Access
- **Load**: Once on daemon start (~10ms)
- **Save**: After every batch operation (~5ms per write)
- **Size**: ~1KB per 10 windows, max ~100KB for 1000 windows

### /proc Filesystem Reads
- **Per-window cost**: ~5ms per /proc/<pid>/environ read
- **Optimization**: Parallel async reads with asyncio.gather()
- **30 windows**: 150ms sequential → 50ms parallel

### i3 IPC Operations
- **GET_TREE**: ~10ms for typical session (30 windows)
- **GET_WORKSPACES**: ~2ms
- **Batch COMMAND**: ~5ms for 30 window moves
- **Total switch latency**: ~100-200ms for 30 windows

---

## Error Handling

### Missing /proc Entry
- **Cause**: Process terminated before /proc read
- **Behavior**: Treat as global scope (always visible)
- **Log**: Warning level, include window class for debugging

### Corrupted State File
- **Cause**: Incomplete write, filesystem error
- **Behavior**: Reinitialize with current i3 state
- **Log**: Error level, backup corrupted file to .bak

### Invalid Workspace Assignment
- **Cause**: Workspace doesn't exist, monitor disconnected
- **Behavior**: Fall back to workspace 1 (always exists)
- **Log**: Warning level, include window and target workspace

### i3 IPC Connection Lost
- **Cause**: i3 restart, daemon crash recovery
- **Behavior**: Buffer operations, replay on reconnect
- **Log**: Error level, attempt reconnect every 5s

---

## References

- **Feature 035 Data Model**: I3PM_* environment variable schema
- **Feature 033 Data Model**: Workspace-monitor mapping schema
- **Feature 025 Data Model**: Window tree visualization structures
- **i3 IPC Reference**: https://i3wm.org/docs/ipc.html
- **Constitution Principle XI**: i3 IPC Alignment & State Authority

---

**Status**: ✅ Complete - Data model defined with validation and performance analysis
**Next**: Generate contracts/ for daemon IPC and CLI commands
