# Ghost Container Contract

**Feature**: 051-i3run-scratchpad-enhancement
**Contract Type**: Component Specification
**Version**: 1.0
**Date**: 2025-11-06

## Purpose

Ghost container is a minimal invisible window that persists metadata for multiple projects via Sway marks. Used for project-wide state that isn't tied to specific terminal windows.

## Specification

### Creation

**Process**:
1. Launch long-running background process: `swaymsg 'exec --no-startup-id "sleep 100000"'`
2. Wait for window creation (poll tree for new window)
3. Apply properties:
   - Floating: `swaymsg '[con_id=N] floating enable'`
   - Size: `swaymsg '[con_id=N] resize set 1 1'`
   - Opacity: `swaymsg '[con_id=N] opacity 0'`
   - Hide: `swaymsg '[con_id=N] move scratchpad'`
4. Mark: `swaymsg '[con_id=N] mark i3pm_ghost'`

**Python Code**:
```python
async def create_ghost_container(conn: i3ipc.aio.Connection) -> int:
    """Create invisible ghost container, return window ID."""
    # Launch background process
    await conn.command('exec --no-startup-id "sleep 100000"')

    # Wait for window (with timeout)
    for attempt in range(10):
        await asyncio.sleep(0.1)
        tree = await conn.get_tree()
        # Find newest window without mark
        windows = [c for c in tree if c.type == "con" and not c.marks]
        if windows:
            window_id = windows[-1].id
            break
    else:
        raise TimeoutError("Ghost container creation timeout")

    # Configure
    commands = [
        f"[con_id={window_id}] floating enable",
        f"[con_id={window_id}] resize set 1 1",
        f"[con_id={window_id}] opacity 0",
        f"[con_id={window_id}] move scratchpad",
        f"[con_id={window_id}] mark i3pm_ghost"
    ]
    for cmd in commands:
        await conn.command(cmd)

    return window_id
```

### Query

**Method**: Search tree for mark `i3pm_ghost`

**Python Code**:
```python
async def find_ghost_container(conn: i3ipc.aio.Connection) -> Optional[int]:
    """Find existing ghost container by mark."""
    tree = await conn.get_tree()
    for con in tree:
        if "i3pm_ghost" in con.marks:
            return con.id
    return None
```

### Lifecycle Management

**Strategy**: "Create Once, Never Destroy"

1. **Daemon Start**:
   - Query for existing ghost (`find_ghost_container()`)
   - If found: Reuse (store window ID in daemon state)
   - If not found: Create new (`create_ghost_container()`)

2. **During Operation**:
   - Ghost persists in scratchpad (invisible, minimal resource usage)
   - Project state marks added/updated as needed

3. **Daemon Shutdown**:
   - Do NOT destroy ghost (let it persist for next daemon start)

4. **Sway Restart**:
   - Ghost survives IF sleep process still running
   - Window ID changes but mark persists
   - Daemon must re-query by mark (not cached ID)

5. **Process Death**:
   - Ghost disappears, marks lost
   - Next daemon start recreates ghost

### State Storage on Ghost

**Multiple Project Marks**:
```
Ghost window marks:
- i3pm_ghost (primary identity mark)
- scratchpad_state:nixos=floating:true,x:100,y:200,...
- scratchpad_state:dotfiles=floating:true,x:500,y:400,...
- scratchpad_state:work=floating:true,x:900,y:100,...
```

**NOTE**: Research shows ONE mark per window limit. **This contract is INVALID**. Ghost container approach must be REVISED or ABANDONED.

### Revised Approach (Per Terminal Marks)

Given ONE mark per window limit, state must be stored on terminal windows themselves:

**Terminal Window Marks**:
```
Terminal 1 (nixos project):
- scratchpad_state:nixos=floating:true,x:100,y:200,...

Terminal 2 (dotfiles project):
- scratchpad_state:dotfiles=floating:true,x:500,y:400,...
```

**Ghost container is NOT NEEDED** for state persistence.

### Alternative: Identity + State in Single Mark

Combine identity and state in one mark:

**Format**: `scratchpad:{project}|{state_fields}`

**Example**: `scratchpad:nixos|floating:true,x:100,y:200,w:1000,h:600,ts:1730934000`

This eliminates need for ghost container while preserving all functionality.

## Decision

**ABANDON ghost container approach**

**Rationale**:
- Research confirmed ONE mark per window in Sway
- Ghost container added complexity without benefit
- State can be stored on terminal windows directly
- Single mark format with delimited state is cleaner

**Revised Architecture**:
- Each terminal has ONE mark: `scratchpad:{project}|{state}`
- Parse mark to extract both identity and state
- No ghost container needed

## Impact on design

- Remove `GhostContainerManager` class from implementation
- Update `ScratchpadState` to include project identity in single mark
- Simplify lifecycle (no ghost creation/query logic)
- Reduce complexity and potential failure modes

**Status**: Ghost container contract DEPRECATED ❌

**Replacement**: See mark-serialization-format.md for revised single-mark approach.
