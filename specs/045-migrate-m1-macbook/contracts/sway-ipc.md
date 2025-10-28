# Sway IPC Protocol Contract

**Feature**: 045-migrate-m1-macbook
**Purpose**: Document Sway IPC messages used by i3pm daemon

## Overview

Sway implements the i3 IPC protocol for 100% backward compatibility. This contract documents the IPC messages used by the i3pm daemon and any Sway-specific extensions.

---

## IPC Message Types

### GET_TREE

**Purpose**: Query complete window tree including containers, marks, properties.

**Request**:
```python
tree = await conn.get_tree()
```

**Response Structure**:
```python
{
    "id": int,              # Container ID
    "pid": int,             # Process ID (Sway includes directly)
    "app_id": str | None,   # Wayland app identifier (Sway-specific)
    "window_properties": {  # XWayland only
        "class": str,
        "instance": str,
        "title": str
    },
    "name": str,            # Window title
    "marks": [str],         # List of marks
    "geometry": {
        "x": int,
        "y": int,
        "width": int,
        "height": int
    },
    "floating": "auto_on" | "auto_off" | "user_on" | "user_off",
    "visible": bool,
    "nodes": [Container],   # Child containers
    "floating_nodes": [Container]
}
```

**Sway-Specific Fields**:
- `app_id`: Wayland application identifier (not present in i3)
- `pid`: Always present (i3 may not include PID)

**Usage in Daemon**:
```python
# Get window properties
pid = container.ipc_data.get('pid')  # Direct access
app_id = container.app_id  # Wayland app
window_class = container.window_properties.get('class')  # XWayland fallback
```

---

### GET_WORKSPACES

**Purpose**: Query list of workspaces with visibility and output assignments.

**Request**:
```python
workspaces = await conn.get_workspaces()
```

**Response Structure**:
```python
[{
    "num": int,             # Workspace number (1-70)
    "name": str,            # Workspace name
    "visible": bool,        # Is workspace visible on any output?
    "focused": bool,        # Is workspace focused?
    "output": str,          # Output name (e.g., "eDP-1", "HDMI-A-1")
    "urgent": bool,         # Has urgent window?
    "rect": {
        "x": int,
        "y": int,
        "width": int,
        "height": int
    }
}]
```

**Compatibility**: Identical response structure in i3 and Sway.

**Usage in Daemon**:
- Validate workspace-to-output assignments
- Detect active workspace for project switching

---

### GET_OUTPUTS

**Purpose**: Query monitor/display configuration.

**Request**:
```python
outputs = await conn.get_outputs()
```

**Response Structure**:
```python
[{
    "name": str,            # Output identifier (e.g., "eDP-1")
    "active": bool,         # Is output enabled?
    "current_workspace": str | None,  # Focused workspace name
    "rect": {
        "x": int,
        "y": int,
        "width": int,         # Logical width (after scaling)
        "height": int         # Logical height (after scaling)
    },
    "scale": float,         # Scaling factor (Sway-specific)
    "transform": str,       # Rotation (Sway-specific)
    "make": str,            # Manufacturer
    "model": str,           # Model name
    "serial": str           # Serial number
}]
```

**Sway-Specific Fields**:
- `scale`: HiDPI scaling factor (not in i3)
- `transform`: Rotation transform (not in i3)

**Output Name Differences**:

| Display Type | i3 (X11) | Sway (DRM) |
|--------------|----------|------------|
| Built-in laptop | eDP-1 or LVDS-1 | eDP-1 |
| HDMI | HDMI-1 | HDMI-A-1 or HDMI-A-2 |
| DisplayPort | DP-1 | DP-1 or DP-2 |
| USB-C (DP Alt Mode) | DP-2 | DP-3 or DP-4 |

**Usage in Daemon**:
- Monitor hotplug detection (output events)
- Workspace distribution across monitors

---

### GET_MARKS

**Purpose**: Query all window marks in current session.

**Request**:
```python
marks = await conn.get_marks()
```

**Response**:
```python
["project:nixos:12345", "project:stacks:67890", "urgent", "visible"]
```

**Compatibility**: Identical in i3 and Sway.

**Usage in Daemon**:
- Verify project marks are applied
- Diagnostic validation

---

### COMMAND

**Purpose**: Execute Sway/i3 commands.

**Request**:
```python
result = await conn.command("workspace 1 output eDP-1")
result = await conn.command("mark project:nixos:12345")
result = await conn.command("move scratchpad")
```

**Response Structure**:
```python
[{
    "success": bool,
    "error": str | None     # Error message if success=false
}]
```

**Common Commands**:
- `mark <mark_name>`: Apply mark to focused window
- `[con_mark="<mark>"] move scratchpad`: Hide window
- `[con_mark="<mark>"] scratchpad show`: Show window
- `workspace <number> output <output>`: Assign workspace to output
- `workspace number <N>`: Switch to workspace N

**Compatibility**: 100% identical syntax in i3 and Sway.

---

## Event Subscriptions

### SUBSCRIBE

**Purpose**: Subscribe to i3/Sway events for real-time state updates.

**Request**:
```python
await conn.subscribe([
    Event.WINDOW,        # window::new, window::close, window::focus, etc.
    Event.WORKSPACE,     # workspace::focus, workspace::init, etc.
    Event.OUTPUT,        # output::added, output::removed (monitor hotplug)
    Event.TICK,          # tick events (custom triggers)
    Event.SHUTDOWN       # Compositor shutdown
])
```

**Event Types**:

#### window Events
- `window::new`: New window created
- `window::close`: Window closed
- `window::focus`: Window focused
- `window::move`: Window moved to different workspace/output
- `window::title`: Window title changed
- `window::mark`: Window mark added/removed

**Payload**:
```python
{
    "change": "new" | "close" | "focus" | "move" | "title" | "mark",
    "container": Container  # Same structure as GET_TREE response
}
```

#### workspace Events
- `workspace::focus`: Workspace focused
- `workspace::init`: New workspace created
- `workspace::empty`: Workspace became empty

**Payload**:
```python
{
    "change": "focus" | "init" | "empty",
    "current": Workspace,  # New workspace
    "old": Workspace | None  # Previous workspace (focus only)
}
```

#### output Events
- `output::added`: Monitor connected (Feature 033)
- `output::removed`: Monitor disconnected
- `output::changed`: Output configuration changed

**Payload**:
```python
{
    "change": "added" | "removed" | "changed"
}
```

**Usage**: Trigger workspace redistribution via `i3pm monitors reassign`.

#### tick Events
Custom events triggered via `swaymsg -t send_tick <payload>`.

**Usage**: Project switching trigger (`i3-project-switch` sends tick event).

---

## Sway vs i3 Differences

### Window Property Access

**i3 (X11)**:
```python
# Requires xprop for PID
result = subprocess.run(["xprop", "-id", str(window_id), "_NET_WM_PID"])
pid = parse_output(result.stdout)

# Window class from window_properties
window_class = container.window_properties.get('class')
```

**Sway (Wayland)**:
```python
# PID directly from IPC
pid = container.ipc_data.get('pid')

# Check app_id first (Wayland), then window_properties (XWayland)
window_class = container.app_id or container.window_properties.get('class')
```

### Output Names

i3 uses X11 output names (xrandr), Sway uses DRM output names. Update workspace-monitor-mapping.json with Sway names after testing.

---

## Code Changes Required

### connection.py
Replace xprop subprocess calls with IPC access:
```python
# OLD (X11):
window_xid = container.window
result = subprocess.run(["xprop", "-id", str(window_xid), "_NET_WM_PID"], ...)

# NEW (Wayland):
pid = container.ipc_data.get('pid')
```

### handlers.py
Update window class detection:
```python
# OLD (X11):
window_class = container.window_properties.get('class', 'unknown')

# NEW (Wayland-first):
window_class = container.app_id or container.window_properties.get('class', 'unknown')
```

### window_filter.py
Update environment variable reading (unchanged - OS-level):
```python
# Same on X11 and Wayland
def read_process_environ(pid: int) -> Dict[str, str]:
    with open(f"/proc/{pid}/environ", "rb") as f:
        data = f.read()
        # Parse null-terminated strings
        ...
```

---

## Testing Contract Compliance

### Validation Tests
```python
# Test PID access
async def test_window_pid():
    tree = await conn.get_tree()
    window = find_window(tree, window_id)
    pid = window.ipc_data.get('pid')
    assert pid is not None, "PID must be present in Sway tree"

# Test app_id vs window_properties
async def test_window_class():
    tree = await conn.get_tree()
    for window in get_all_windows(tree):
        # Wayland apps have app_id
        if window.app_id:
            assert isinstance(window.app_id, str)
        # XWayland apps have window_properties
        else:
            assert 'class' in window.window_properties
```

### Protocol Compatibility
Run existing i3pm test suite - all tests should pass without modification due to protocol compatibility.

---

## References

- [Sway IPC Documentation](https://github.com/swaywm/sway/blob/master/sway/sway-ipc.7.scd)
- [i3 IPC Documentation](https://i3wm.org/docs/ipc.html)
- [i3ipc-python Library](https://github.com/altdesktop/i3ipc-python)
