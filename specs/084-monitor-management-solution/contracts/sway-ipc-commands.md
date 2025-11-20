# Sway IPC Commands: M1 Hybrid Monitor Management

**Feature**: 084-monitor-management-solution
**Date**: 2025-11-19

## Overview

This document specifies the Sway IPC commands used for M1 hybrid monitor management. All commands are executed via `swaymsg` or the i3ipc-python async client.

---

## Output Management Commands

### Create Virtual Output

```bash
swaymsg create_output
```

**Response**: Creates `HEADLESS-N` where N is the next available number.

**Usage**: Called when switching to local+1vnc or local+2vnc profile.

---

### Configure Output

```bash
swaymsg "output HEADLESS-1 mode 1920x1080@60Hz position 1280,0 scale 1.0"
```

**Parameters**:
- `mode`: Resolution and refresh rate
- `position`: X,Y coordinates (logical pixels)
- `scale`: Scaling factor (1.0 for VNC, 2.0 for Retina)

**Note**: Position 1280,0 accounts for eDP-1's logical width (2560/2=1280 at scale 2.0).

---

### Enable/Disable Output

```bash
# Enable
swaymsg "output HEADLESS-1 enable"

# Disable
swaymsg "output HEADLESS-1 disable"
```

**State Change**: Output transitions to active/inactive in Sway tree.

---

### Query Outputs

```bash
swaymsg -t get_outputs
```

**Response Schema**:
```json
[
  {
    "name": "eDP-1",
    "active": true,
    "current_mode": {
      "width": 2560,
      "height": 1600,
      "refresh": 60000
    },
    "rect": {"x": 0, "y": 0, "width": 1280, "height": 800},
    "scale": 2.0
  },
  {
    "name": "HEADLESS-1",
    "active": true,
    "current_mode": {
      "width": 1920,
      "height": 1080,
      "refresh": 60000
    },
    "rect": {"x": 1280, "y": 0, "width": 1920, "height": 1080},
    "scale": 1.0
  }
]
```

---

## Workspace Commands

### Move Workspace to Output

```bash
swaymsg "[workspace=5] move workspace to output HEADLESS-1"
```

**Usage**: Reassign workspaces during profile switch.

---

### Query Workspaces

```bash
swaymsg -t get_workspaces
```

**Response Schema**:
```json
[
  {
    "num": 1,
    "name": "1:code",
    "visible": true,
    "focused": true,
    "output": "eDP-1"
  },
  {
    "num": 5,
    "name": "5:browser",
    "visible": true,
    "focused": false,
    "output": "HEADLESS-1"
  }
]
```

---

## Profile Switch Sequence

### Switch to local+1vnc

```bash
# 1. Create virtual output (if not exists)
swaymsg create_output

# 2. Configure output
swaymsg "output HEADLESS-1 mode 1920x1080@60Hz position 1280,0 scale 1.0"

# 3. Enable output
swaymsg "output HEADLESS-1 enable"

# 4. Start WayVNC service
systemctl --user start wayvnc@HEADLESS-1.service

# 5. Reassign workspaces
swaymsg "[workspace=5] move workspace to output HEADLESS-1"
swaymsg "[workspace=6] move workspace to output HEADLESS-1"
swaymsg "[workspace=7] move workspace to output HEADLESS-1"
swaymsg "[workspace=8] move workspace to output HEADLESS-1"
swaymsg "[workspace=9] move workspace to output HEADLESS-1"

# 6. Write profile state
echo "local+1vnc" > ~/.config/sway/monitor-profile.current
```

### Switch to local-only

```bash
# 1. Move workspaces back to eDP-1
swaymsg "[workspace=5] move workspace to output eDP-1"
swaymsg "[workspace=6] move workspace to output eDP-1"
# ... etc

# 2. Stop WayVNC service
systemctl --user stop wayvnc@HEADLESS-1.service

# 3. Disable output
swaymsg "output HEADLESS-1 disable"

# 4. Write profile state
echo "local-only" > ~/.config/sway/monitor-profile.current
```

---

## Python IPC Client Usage

### Create Output

```python
async def create_virtual_output(conn):
    """Create a new virtual output."""
    await conn.command("create_output")

    # Query to get new output name
    outputs = await conn.get_outputs()
    headless_outputs = [o for o in outputs if o.name.startswith("HEADLESS-")]
    return headless_outputs[-1].name  # Return newest
```

### Configure and Enable Output

```python
async def configure_output(conn, name: str, width: int, height: int, x: int, y: int, scale: float):
    """Configure output resolution, position, and scale."""
    await conn.command(f"output {name} mode {width}x{height}@60Hz position {x},{y} scale {scale}")
    await conn.command(f"output {name} enable")
```

### Reassign Workspaces

```python
async def reassign_workspaces(conn, assignments: dict[str, list[int]]):
    """Reassign workspaces to outputs.

    Args:
        assignments: Dict mapping output names to workspace lists
                    e.g., {"eDP-1": [1,2,3,4], "HEADLESS-1": [5,6,7,8,9]}
    """
    for output, workspaces in assignments.items():
        for ws in workspaces:
            await conn.command(f"[workspace={ws}] move workspace to output {output}")
```

---

## Event Subscriptions

### Output Events

```python
async def subscribe_to_output_events(conn):
    """Subscribe to output change events."""
    conn.on(i3ipc.Event.OUTPUT, handle_output_event)

async def handle_output_event(conn, event):
    """Handle output connect/disconnect events.

    event.change values:
    - "connected": New output available
    - "disconnected": Output removed
    """
    if event.change == "connected":
        # New virtual output created
        await update_eww_state(conn)
    elif event.change == "disconnected":
        # Output removed
        await update_eww_state(conn)
```

---

## Error Handling

### Command Failures

```python
async def safe_command(conn, cmd: str) -> tuple[bool, str]:
    """Execute command with error handling."""
    try:
        result = await conn.command(cmd)
        if result[0].success:
            return True, ""
        else:
            return False, result[0].error
    except Exception as e:
        return False, str(e)
```

### Validation

```python
async def validate_output_exists(conn, name: str) -> bool:
    """Check if output exists before configuration."""
    outputs = await conn.get_outputs()
    return any(o.name == name for o in outputs)
```
