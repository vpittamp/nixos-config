# Contract: Sway IPC Protocol

**Feature**: Feature 046 - Hetzner Cloud Sway with Headless Wayland
**Created**: 2025-10-28
**Purpose**: Define Sway IPC contract used by i3pm daemon for headless window management

## Overview

Sway implements the i3 IPC protocol with 100% compatibility. The daemon connects to Sway via Unix socket (SWAYSOCK) and uses identical commands and events as i3, ensuring zero code changes required.

## IPC Connection

### Socket Discovery

**Environment Variables** (Sway sets both for compatibility):
- `SWAYSOCK`: Native Sway socket path (primary)
- `I3SOCK`: Compatibility alias for i3 tools

**Default Path**: `/run/user/<UID>/sway-ipc.<PID>.sock`

**Connection Sequence**:
1. Daemon reads `SWAYSOCK` from environment
2. Opens Unix socket connection
3. Sends magic string: `i3-ipc` (6 bytes)
4. Receives protocol confirmation
5. Ready for message exchange

**i3ipc-python Behavior**:
```python
import i3ipc

# Auto-detects SWAYSOCK or I3SOCK
conn = i3ipc.Connection()  # Works with both Sway and i3
```

## Message Format

All IPC messages use identical format to i3:

```
┌─────────────┬─────────────┬─────────────┬─────────────┐
│ Magic (6B)  │ Length (4B) │ Type (4B)   │ Payload     │
├─────────────┼─────────────┼─────────────┼─────────────┤
│ "i3-ipc"    │ uint32 LE   │ uint32 LE   │ JSON string │
└─────────────┴─────────────┴─────────────┴─────────────┘
```

## Commands Used by i3pm Daemon

### 1. GET_TREE (Type: 4)

**Purpose**: Query window hierarchy for window properties and marks

**Request**:
```json
{
  "type": "GET_TREE"
}
```

**Response**:
```json
{
  "id": 94532735639728,
  "type": "con",
  "name": "Visual Studio Code",
  "app_id": "Code",  // Wayland native (NEW in Sway vs i3)
  "window_properties": {
    "class": "Code",  // XWayland fallback
    "instance": "code",
    "title": "Visual Studio Code"
  },
  "pid": 12345,
  "marks": ["project:nixos:94532735639728"],
  "workspace": 2,
  "output": "HEADLESS-1",
  "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
  "floating": "auto_off",
  "scratchpad_state": "none",
  "nodes": [],
  "floating_nodes": []
}
```

**Key Differences from i3**:
- ✅ `app_id` field: Native Wayland application identifier (primary for Sway)
- ✅ `window_properties.class`: XWayland compatibility (fallback)
- ✅ `output`: Shows "HEADLESS-1" instead of physical monitor name

**Daemon Usage**:
- Read `app_id` first for window class (Wayland native apps)
- Fallback to `window_properties.class` for XWayland apps
- Extract `marks` to check existing project associations
- Query `scratchpad_state` to determine visibility

**Functional Requirements**: FR-013, FR-014, FR-015

---

### 2. GET_WORKSPACES (Type: 1)

**Purpose**: Query workspace-to-output assignments

**Request**:
```json
{
  "type": "GET_WORKSPACES"
}
```

**Response**:
```json
[
  {
    "num": 1,
    "name": "1",
    "visible": true,
    "focused": true,
    "urgent": false,
    "output": "HEADLESS-1",
    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}
  },
  {
    "num": 2,
    "name": "2",
    "visible": false,
    "focused": false,
    "urgent": false,
    "output": "HEADLESS-1",
    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}
  }
]
```

**Key Differences from i3**:
- ✅ `output`: "HEADLESS-1" for virtual outputs (instead of physical monitor names like "eDP-1")

**Daemon Usage**:
- Monitor workspace distribution across virtual outputs
- Validate workspace-to-monitor mapping configuration
- Support multi-virtual-output configurations (Feature 046 FR-029)

**Functional Requirements**: FR-029, FR-030, FR-031

---

### 3. GET_OUTPUTS (Type: 3)

**Purpose**: Query virtual output configuration

**Request**:
```json
{
  "type": "GET_OUTPUTS"
}
```

**Response**:
```json
[
  {
    "name": "HEADLESS-1",
    "make": "headless",
    "model": "headless",
    "serial": "0x00000000",
    "active": true,
    "primary": false,
    "current_workspace": "1",
    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
    "modes": [
      {
        "width": 1920,
        "height": 1080,
        "refresh": 60000
      }
    ],
    "current_mode": {
      "width": 1920,
      "height": 1080,
      "refresh": 60000
    },
    "scale": 1.0,
    "transform": "normal"
  }
]
```

**Key Differences from i3**:
- ✅ `name`: "HEADLESS-1" (virtual output naming convention)
- ✅ `make`/`model`: "headless" (not physical monitor vendor)
- ✅ `modes`: Single synthetic mode (not physical display capabilities)

**Daemon Usage**:
- Detect virtual output creation/removal (hotplug simulation)
- Support multi-monitor workspace distribution (FR-029)
- Validate output configuration for workspace reassignment

**Functional Requirements**: FR-003, FR-029, FR-030

---

### 4. COMMAND (Type: 0)

**Purpose**: Execute Sway commands for window management

**Mark Window**:
```json
{
  "type": "COMMAND",
  "payload": "[con_id=94532735639728] mark project:nixos:94532735639728"
}
```

**Response**:
```json
[
  {
    "success": true
  }
]
```

**Move Window to Workspace**:
```json
{
  "type": "COMMAND",
  "payload": "[con_id=94532735639728] move container to workspace number 2"
}
```

**Move Window to Scratchpad (Hide)**:
```json
{
  "type": "COMMAND",
  "payload": "[con_id=94532735639728] move scratchpad"
}
```

**Restore Window from Scratchpad**:
```json
{
  "type": "COMMAND",
  "payload": "[con_id=94532735639728] scratchpad show, move container to workspace number 2"
}
```

**Daemon Usage**:
- Apply project marks to windows (FR-017)
- Move windows to correct workspaces (FR-018)
- Hide windows on project switch (move to scratchpad)
- Restore windows when switching back to project

**Functional Requirements**: FR-017, FR-018, FR-037 (window filtering)

---

## Event Subscriptions

The daemon subscribes to identical events as i3 implementation:

### Event Types

```python
conn.on('window::new', handle_window_new)
conn.on('window::close', handle_window_close)
conn.on('window::focus', handle_window_focus)
conn.on('window::title', handle_window_title)
conn.on('window::move', handle_window_move)
conn.on('workspace::focus', handle_workspace_focus)
conn.on('output', handle_output)
conn.on('tick', handle_tick)
conn.on('shutdown', handle_shutdown)
```

### window::new Event

**Trigger**: New window created

**Payload**:
```json
{
  "change": "new",
  "container": {
    "id": 94532735639728,
    "type": "con",
    "app_id": "Code",
    "window_properties": {
      "class": "Code",
      "instance": "code",
      "title": "Visual Studio Code"
    },
    "pid": 12345,
    "marks": [],
    "workspace": 2,
    "output": "HEADLESS-1"
  }
}
```

**Daemon Workflow**:
1. Extract `pid` from container
2. Read `/proc/<pid>/environ` for `I3PM_PROJECT_NAME`
3. Generate unique window ID
4. Apply mark: `project:{PROJECT_NAME}:{WINDOW_ID}`
5. Move to workspace from registry if configured

**Functional Requirements**: FR-013, FR-014, FR-016, FR-017, FR-018

---

### tick Event

**Trigger**: Custom event sent via `swaymsg -t send_tick`

**Payload**:
```json
{
  "change": "tick",
  "first": true,
  "payload": "project_switch:nixos"
}
```

**Daemon Workflow** (Project Switch):
1. Parse tick payload for new project name
2. Query all windows via GET_TREE
3. Filter windows by project marks
4. Move non-matching scoped windows to scratchpad
5. Keep matching + global windows visible

**Functional Requirements**: FR-037 (window filtering)

---

### output Event

**Trigger**: Virtual output added/removed

**Payload**:
```json
{
  "change": "added",
  "output": {
    "name": "HEADLESS-2",
    "make": "headless",
    "model": "headless",
    "active": true,
    "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1080}
  }
}
```

**Daemon Workflow** (Multi-Monitor Support):
1. Detect output change (added/removed)
2. Read workspace-monitor-mapping.json
3. Reassign workspaces to outputs per configuration
4. Apply with debounce (1 second)

**Functional Requirements**: FR-029, FR-030, FR-031

---

## Headless-Specific Considerations

### Window Class Detection

**Priority Order** (Feature 045 implementation):
1. `app_id` (native Wayland apps - primary for Sway)
2. `window_properties.class` (XWayland fallback)
3. `window_class` property (legacy i3ipc attribute)

**Code** (from handlers.py):
```python
def get_window_class(container) -> str:
    """Get window class in a Sway/i3-compatible way (Feature 045).

    For Sway/Wayland: Checks app_id first (native Wayland), then window_properties.class (XWayland).
    For i3/X11: Uses window_class property (always from window_properties).
    """
    # Sway: Check app_id first (native Wayland apps)
    if hasattr(container, 'app_id') and container.app_id:
        return container.app_id

    # Fallback: Use window_class property (works on i3, and Sway for XWayland apps)
    if hasattr(container, 'window_class') and container.window_class:
        return container.window_class

    # Legacy fallback: Read from window_properties dict
    if hasattr(container, 'window_properties') and container.window_properties:
        if isinstance(container.window_properties, dict):
            return container.window_properties.get('class', 'unknown')

    return "unknown"
```

**No Changes Needed**: Feature 045 implementation already handles Sway correctly.

### Virtual Output Names

**Format**: `HEADLESS-{N}` where N starts at 1

**Detection**:
```python
def is_headless_output(output_name: str) -> bool:
    return output_name.startswith("HEADLESS-")
```

**Usage**: Workspace distribution treats headless outputs identically to physical outputs (no special handling needed).

---

## Testing Contract Compliance

### Validate IPC Connection

```bash
# Check socket exists
echo $SWAYSOCK
# Expected: /run/user/1000/sway-ipc.<PID>.sock

# Test connection with swaymsg
swaymsg -t get_version
# Expected: {"human_readable": "sway version 1.9", ...}
```

### Validate GET_TREE Response

```bash
# Query tree and check for app_id field (Sway-specific)
swaymsg -t get_tree | jq '.. | select(.app_id?) | {id, app_id, window_properties}'

# Expected output for Wayland native app:
# {
#   "id": 94532735639728,
#   "app_id": "Code",
#   "window_properties": {"class": "Code", "instance": "code", ...}
# }
```

### Validate Event Subscriptions

```bash
# Monitor window events
swaymsg -t subscribe -m '["window"]'

# Open new window (e.g., Meta+Return for terminal)
# Expected output:
# {
#   "change": "new",
#   "container": {
#     "id": ...,
#     "app_id": "ghostty",
#     "pid": ...
#   }
# }
```

### Validate Window Marks

```bash
# Apply mark via CLI
swaymsg '[con_id=94532735639728] mark test_mark'

# Query marks
swaymsg -t get_marks
# Expected: ["test_mark", "project:nixos:...", ...]

# Query tree for marked windows
swaymsg -t get_tree | jq '.. | select(.marks?) | select(.marks | contains(["test_mark"])) | {id, marks}'
```

---

## Error Handling

### Connection Failures

**Error**: `Failed to connect to socket`

**Causes**:
- Sway not running
- SWAYSOCK not set
- Socket permission denied

**Daemon Behavior**:
- Retry connection with exponential backoff (1s, 2s, 4s, 8s, max 30s)
- Log error to journalctl
- Exit with code 1 after 5 failed attempts

### Command Failures

**Error**: `Command failed: [con_id=123] mark project:nixos:123`

**Causes**:
- Window no longer exists
- Invalid con_id
- Permission denied

**Daemon Behavior**:
- Log warning to journalctl
- Continue processing (don't crash)
- Skip window in next scan

### Event Processing Failures

**Error**: Exception in event handler

**Daemon Behavior**:
- Catch exception
- Log traceback to journalctl
- Continue processing events (don't exit)
- Increment error counter in daemon status

---

## Performance Characteristics

| Operation | Target Latency | Measured (Feature 045) |
|-----------|---------------|------------------------|
| GET_TREE query | <50ms | 10-20ms typical |
| COMMAND execution | <20ms | 5-10ms typical |
| Event delivery | <10ms | 2-5ms typical |
| Window marking | <100ms | 20-50ms typical |

**Notes**:
- Headless backend is CPU-bound (software rendering), not GPU-bound
- Virtual output queries are faster than physical output queries (no EDID parsing)
- Network latency for VNC is separate from IPC latency

---

## References

- **Sway IPC Documentation**: https://man.archlinux.org/man/sway-ipc.7.en
- **i3 IPC Protocol Specification**: https://i3wm.org/docs/ipc.html
- **i3ipc-python Library**: https://github.com/altdesktop/i3ipc-python
- **Feature 045 Implementation**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/handlers.py`

**Validation Status**: ✅ Feature 045 implementation proves 100% Sway IPC compatibility (no code changes needed for Feature 046)
