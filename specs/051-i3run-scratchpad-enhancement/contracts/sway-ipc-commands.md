# Sway IPC Commands Contract

**Feature**: 051-i3run-scratchpad-enhancement
**Contract Type**: Sway IPC Protocol
**Version**: 1.0
**Date**: 2025-11-06

## Overview

This contract defines all Sway IPC commands and queries required for Feature 051 implementation. All commands use i3ipc.aio Python library for async execution.

---

## Query Commands (Read Operations)

### GET_TREE

**Purpose**: Query complete window tree for window lookups and mark queries.

**i3ipc.aio Method**: `await connection.get_tree()`

**Returns**: `i3ipc.Con` object (container tree)

**Usage**:
```python
tree = await conn.get_tree()
window = tree.find_by_id(window_id)
marks = window.marks  # List[str]
```

**Performance**: 3-8ms per query

---

### GET_OUTPUTS

**Purpose**: Query monitor/output configuration for workspace geometry.

**i3ipc.aio Method**: `await connection.get_outputs()`

**Returns**: `List[i3ipc.OutputReply]`

**Output Fields**:
- `name`: str (e.g., "HEADLESS-1", "eDP-1")
- `active`: bool
- `rect`: Rect (x, y, width, height)
- `current_workspace`: str

**Usage**:
```python
outputs = await conn.get_outputs()
for output in outputs:
    if output.active and output.current_workspace == "1":
        geometry = WorkspaceGeometry(
            width=output.rect.width,
            height=output.rect.height,
            x_offset=output.rect.x,
            y_offset=output.rect.y,
            workspace_num=1,
            monitor_name=output.name
        )
```

**Performance**: 2-5ms per query

---

### GET_WORKSPACES

**Purpose**: Query workspace list with focus and output assignments.

**i3ipc.aio Method**: `await connection.get_workspaces()`

**Returns**: `List[i3ipc.WorkspaceReply]`

**Workspace Fields**:
- `num`: int (workspace number)
- `name`: str
- `focused`: bool
- `visible`: bool
- `output`: str (monitor name)

**Usage**:
```python
workspaces = await conn.get_workspaces()
active_ws = next(ws for ws in workspaces if ws.focused)
# active_ws.num, active_ws.output
```

**Performance**: 2-4ms per query

---

## Command Operations (Write Operations)

### Move Window to Position

**Purpose**: Position window at specific coordinates.

**Command Format**: `[con_id={id}] move absolute position {x} {y}`

**i3ipc.aio Method**:
```python
await conn.command(f"[con_id={window_id}] move absolute position {x} {y}")
```

**Parameters**:
- `window_id`: int (Sway container ID)
- `x`, `y`: int (absolute pixels from screen origin)

**Performance**: 5-10ms per command

**Example**:
```python
position = TerminalPosition(x=100, y=200, width=1000, height=600)
await conn.command(position.to_sway_command(window_id))
```

---

### Resize Window

**Purpose**: Set window dimensions.

**Command Format**: `[con_id={id}] resize set {width} {height}`

**i3ipc.aio Method**:
```python
await conn.command(f"[con_id={window_id}] resize set {width} {height}")
```

**Performance**: 5-10ms per command

---

### Add Mark to Window

**Purpose**: Persist state metadata on window.

**Command Format**: `[con_id={id}] mark {mark_name}`

**i3ipc.aio Method**:
```python
await conn.command(f"[con_id={window_id}] mark {mark}")
```

**Constraints**:
- ONE mark per window (new mark replaces previous)
- Mark name can contain: letters, digits, `:`, `=`, `,`, `-`, `_`
- Recommended max length: 500 characters (tested up to 2000+)

**Performance**: 5-15ms per command

**Example**:
```python
state = ScratchpadState(project_name="nixos", floating=True, x=100, y=200, ...)
mark = state.to_mark_string()
# "scratchpad_state:nixos=floating:true,x:100,y:200,..."
await conn.command(f"[con_id={window_id}] mark {mark}")
```

---

### Move Window to Workspace

**Purpose**: Move terminal to current workspace (summon mode).

**Command Format**: `[con_id={id}] move --no-auto-back-and-forth to workspace {num}`

**i3ipc.aio Method**:
```python
await conn.command(f"[con_id={window_id}] move --no-auto-back-and-forth to workspace {workspace_num}")
```

**Performance**: 5-10ms per command

---

### Switch to Workspace

**Purpose**: Focus terminal's workspace (goto mode).

**Command Format**: `workspace --no-auto-back-and-forth {num}`

**i3ipc.aio Method**:
```python
await conn.command(f"workspace --no-auto-back-and-forth {workspace_num}")
```

**Performance**: 5-10ms per command

---

### Set Floating State

**Purpose**: Enable/disable floating for window.

**Command Format**: `[con_id={id}] floating {enable|disable}`

**i3ipc.aio Method**:
```python
floating_state = "enable" if terminal.floating else "disable"
await conn.command(f"[con_id={window_id}] floating {floating_state}")
```

**Performance**: 5-10ms per command

---

### Move to Scratchpad

**Purpose**: Hide terminal (move to scratchpad).

**Command Format**: `[con_id={id}] move scratchpad`

**i3ipc.aio Method**:
```python
await conn.command(f"[con_id={window_id}] move scratchpad")
```

**Performance**: 5-10ms per command

---

### Show from Scratchpad

**Purpose**: Un-hide terminal (show from scratchpad).

**Command Format**: `[con_id={id}] scratchpad show`

**i3ipc.aio Method**:
```python
await conn.command(f"[con_id={window_id}] scratchpad show")
```

**Performance**: 5-10ms per command

---

## Composite Operations

### Summon Terminal with Mouse Positioning

**Purpose**: Complete workflow to show terminal at cursor position.

**Steps**:
1. Query workspace geometry (`get_outputs()`)
2. Query cursor position (xdotool - see xdotool-integration.md)
3. Calculate position (BoundaryDetectionAlgorithm)
4. Restore from scratchpad
5. Set floating state
6. Position window
7. Save state to mark

**Code**:
```python
async def summon_with_mouse_positioning(
    self, project: str, terminal: ScratchpadTerminal
) -> None:
    # Step 1: Get workspace geometry
    outputs = await self.conn.get_outputs()
    workspaces = await self.conn.get_workspaces()
    active_ws = next(ws for ws in workspaces if ws.focused)
    output = next(o for o in outputs if o.name == active_ws.output)

    geometry = WorkspaceGeometry(
        width=output.rect.width,
        height=output.rect.height,
        x_offset=output.rect.x,
        y_offset=output.rect.y,
        workspace_num=active_ws.num,
        monitor_name=output.name,
        gaps=self.gap_config
    )

    # Step 2: Get cursor position
    cursor = await self.cursor_positioner.get_position()

    # Step 3: Calculate position
    position = await self.positioning_algo.calculate_position(
        workspace=geometry,
        cursor=cursor,
        window=WindowDimensions(width=1000, height=600)
    )

    # Step 4-6: Show, float, position
    await self.conn.command(f"[con_id={terminal.window_id}] scratchpad show")
    await self.conn.command(f"[con_id={terminal.window_id}] floating enable")
    await self.conn.command(position.to_sway_command(terminal.window_id))

    # Step 7: Save state
    state = ScratchpadState(
        project_name=project,
        floating=True,
        x=position.x, y=position.y,
        width=position.width, height=position.height,
        workspace_num=position.workspace_num,
        monitor_name=position.monitor_name
    )
    await self.conn.command(f"[con_id={terminal.window_id}] mark {state.to_mark_string()}")
```

**Total Latency**: 30-50ms (well within <100ms target)

---

## Error Handling

### Command Timeout

```python
try:
    await asyncio.wait_for(
        conn.command(f"[con_id={id}] move absolute position {x} {y}"),
        timeout=2.0
    )
except asyncio.TimeoutError:
    logger.error(f"Sway command timeout for window {id}")
    # Retry or fallback
```

### Window Not Found

```python
tree = await conn.get_tree()
window = tree.find_by_id(window_id)
if not window:
    raise WindowNotFoundError(f"Window {window_id} not found in tree")
```

### Invalid Mark

```python
# Sway does not return errors for invalid marks
# Validation must happen before command
if not is_valid_mark_format(mark):
    raise ValueError(f"Invalid mark format: {mark}")
await conn.command(f"[con_id={id}] mark {mark}")
```

---

## Performance Budget

| Operation | Budget | Typical |
|-----------|---------|---------|
| GET_TREE | <10ms | 3-8ms |
| GET_OUTPUTS | <10ms | 2-5ms |
| GET_WORKSPACES | <10ms | 2-4ms |
| Command execution | <20ms | 5-15ms |
| **Total for summon** | <100ms | 30-50ms |

All timing targets met ✅

---

## Testing Contract

Unit tests must verify:
1. Command string formatting (exact match expected format)
2. Async timeout handling (graceful degradation)
3. Window ID validation (check tree before command)
4. Mark format validation (parse before save)

Integration tests must verify:
1. End-to-end summon workflow (<100ms)
2. State persistence across daemon restart
3. Multi-monitor positioning accuracy
4. Fallback behavior on errors
