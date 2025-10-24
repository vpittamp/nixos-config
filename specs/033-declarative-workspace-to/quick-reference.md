# i3 Workspace-to-Output Assignment - Quick Reference

**For Feature 033**: Declarative workspace-to-monitor mapping implementation

---

## Command Syntax Quick Reference

### Configuration File (Declarative)

```i3config
# Basic assignment
workspace 1 output DP-1

# Named workspaces
workspace "1:terminal" output DP-1

# Multiple fallback outputs (i3 v4.16+)
workspace 1 output HDMI-1 DP-1 eDP-1

# Primary output
workspace 10 output primary
```

### Runtime Commands (Immediate)

```bash
# Switch to workspace, then move to output
i3-msg 'workspace 1; move workspace to output DP-1'

# Move currently focused workspace
i3-msg 'move workspace to output HDMI-1'
```

---

## Python i3ipc Quick Examples

### Immediate Workspace Assignment

```python
import i3ipc.aio

async def assign_workspace(ws_num: int, output: str):
    """Assign workspace to output immediately."""
    async with i3ipc.aio.Connection() as i3:
        # Switch to workspace (creates if needed)
        await i3.command(f"workspace {ws_num}")

        # Move to target output
        await i3.command(f"move workspace to output {output}")
```

### Query Current Assignments

```python
async def get_workspace_assignments():
    """Get current workspace-to-output assignments."""
    async with i3ipc.aio.Connection() as i3:
        workspaces = await i3.get_workspaces()

        return {
            ws.num: ws.output
            for ws in workspaces
            if ws.num is not None
        }
```

### Validate Output Exists

```python
async def validate_output(output: str) -> bool:
    """Check if output is active."""
    async with i3ipc.aio.Connection() as i3:
        outputs = await i3.get_outputs()
        active = {o.name for o in outputs if o.active}
        return output in active
```

---

## Key Behaviors

### Declarative vs Immediate

| Command | Type | Behavior |
|---------|------|----------|
| `workspace <num> output <output>` | Declarative | Sets preference, doesn't move immediately |
| `move workspace to output <output>` | Immediate | Moves workspace right now |

### Non-Existent Output Handling

- `workspace <num> output nonexistent`: Succeeds, workspace stays on current output
- `move workspace to output nonexistent`: Fails with error "No output matched"

### Workspace Reassignment

- Existing workspace with windows: **Can be reassigned**, all windows move
- Empty workspace: **Can be reassigned**, workspace moves
- Focused workspace: **Focus follows** to new output

---

## Distribution Patterns

### Single Monitor (1 output)

```python
# All workspaces on primary
for ws_num in range(1, 10):
    await i3.command(f"workspace {ws_num}")
    await i3.command(f"move workspace to output {primary}")
```

### Dual Monitor (2 outputs)

```python
# WS 1-2 on primary, WS 3-9 on secondary
for ws_num in range(1, 3):
    await i3.command(f"workspace {ws_num}")
    await i3.command(f"move workspace to output {primary}")

for ws_num in range(3, 10):
    await i3.command(f"workspace {ws_num}")
    await i3.command(f"move workspace to output {secondary}")
```

### Triple+ Monitor (3+ outputs)

```python
# WS 1-2 primary, 3-5 secondary, 6-9 tertiary
for ws_num in range(1, 3):
    await i3.command(f"workspace {ws_num}")
    await i3.command(f"move workspace to output {primary}")

for ws_num in range(3, 6):
    await i3.command(f"workspace {ws_num}")
    await i3.command(f"move workspace to output {secondary}")

for ws_num in range(6, 10):
    await i3.command(f"workspace {ws_num}")
    await i3.command(f"move workspace to output {tertiary}")
```

---

## Event-Driven Architecture

### Subscribe to Monitor Changes

```python
import i3ipc.aio

async def setup_monitor_listener():
    """Listen for monitor connect/disconnect events."""
    i3 = await i3ipc.aio.Connection().connect()

    async def on_output_change(i3, event):
        print("Monitor configuration changed")
        await redistribute_workspaces(i3)

    i3.on(i3ipc.Event.OUTPUT, on_output_change)
    await i3.main()
```

### Debounce Rapid Events

```python
import asyncio

class Debouncer:
    def __init__(self, delay: float = 1.0):
        self.delay = delay
        self.task = None

    async def schedule(self, callback):
        if self.task and not self.task.done():
            self.task.cancel()
        self.task = asyncio.create_task(self._delayed(callback))

    async def _delayed(self, callback):
        await asyncio.sleep(self.delay)
        await callback()

# Usage
debouncer = Debouncer(delay=1.0)

async def on_output_event(i3, event):
    await debouncer.schedule(lambda: redistribute_workspaces(i3))
```

---

## Validation Patterns

### Validate Before Assignment

```python
async def safe_assign(i3, ws_num: int, output: str):
    """Assign workspace only if output exists."""
    outputs = await i3.get_outputs()
    active = {o.name for o in outputs if o.active}

    if output not in active:
        raise ValueError(f"Output '{output}' not active. "
                       f"Active: {', '.join(active)}")

    await i3.command(f"workspace {ws_num}")
    await i3.command(f"move workspace to output {output}")
```

### Rescue Orphaned Workspaces

```python
async def rescue_orphaned_workspaces(i3):
    """Move workspaces from inactive outputs to primary."""
    outputs = await i3.get_outputs()
    workspaces = await i3.get_workspaces()

    active = {o.name for o in outputs if o.active}
    primary = next((o.name for o in outputs if o.active and o.primary),
                   list(active)[0])

    for ws in workspaces:
        if ws.output not in active:
            await i3.command(f"workspace {ws.num}")
            await i3.command(f"move workspace to output {primary}")
```

---

## Best Practices Checklist

- [ ] **Always validate output exists** before assignment
- [ ] **Use `move workspace to output`** for immediate movement, not `workspace <num> output`
- [ ] **Subscribe to OUTPUT events** instead of polling
- [ ] **Debounce monitor changes** (1s delay recommended)
- [ ] **Handle disconnected monitors** (redistribute orphaned workspaces)
- [ ] **Switch to workspace before moving** it (`workspace <num>; move workspace to output`)
- [ ] **Query GET_WORKSPACES** to verify assignments after changes
- [ ] **Support arbitrary workspace numbers** (not just 1-10)
- [ ] **Use async context managers** for i3 connections
- [ ] **Batch commands** when possible (semicolon-separated)

---

## Common Pitfalls

### ❌ Assuming declarative command moves workspace

```python
# WRONG: This doesn't move the workspace immediately
await i3.command(f"workspace {ws_num} output {output}")
```

```python
# CORRECT: Switch to workspace, then move it
await i3.command(f"workspace {ws_num}")
await i3.command(f"move workspace to output {output}")
```

### ❌ Not validating output exists

```python
# WRONG: Command succeeds even if output doesn't exist
await i3.command(f"move workspace to output {output}")
```

```python
# CORRECT: Validate first
outputs = await i3.get_outputs()
if output not in {o.name for o in outputs if o.active}:
    raise ValueError(f"Output '{output}' not active")
```

### ❌ Polling for monitor changes

```python
# WRONG: Wasteful polling
while True:
    outputs = await i3.get_outputs()
    await redistribute_workspaces(outputs)
    await asyncio.sleep(5)
```

```python
# CORRECT: Event-driven
i3.on(i3ipc.Event.OUTPUT, on_output_change)
await i3.main()
```

---

## Performance Guidelines

| Operation | Latency | Frequency Recommendation |
|-----------|---------|--------------------------|
| GET_OUTPUTS | 2-3ms | Cache 500ms-1s or use events |
| GET_WORKSPACES | 2-3ms | Query on-demand or subscribe to events |
| RUN_COMMAND (single) | 5-10ms | Batch when possible |
| RUN_COMMAND (batch 10) | ~15ms | Better than 10x individual |

**Memory**: ~1MB per i3ipc.aio.Connection

---

## Testing Commands

```bash
# Query current outputs
i3-msg -t get_outputs | jq '.[] | {name, active, primary}'

# Query workspace assignments
i3-msg -t get_workspaces | jq '.[] | {num, name, output}'

# Test assignment
i3-msg 'workspace 99; move workspace to output rdp0'

# Test non-existent output
i3-msg 'workspace 99 output nonexistent'  # Succeeds but doesn't move

# Test immediate move to non-existent
i3-msg 'move workspace to output nonexistent'  # Fails with error
```

---

## References

- **Full Research Document**: `./i3-workspace-output-research.md`
- **i3 IPC Patterns**: `/etc/nixos/docs/I3_IPC_PATTERNS.md`
- **Existing Implementation**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/workspace_manager.py`
- **i3 User Guide**: https://i3wm.org/docs/userguide.html
- **i3ipc-python Docs**: https://i3ipc-python.readthedocs.io/

---

**Document Version**: 1.0
**Last Updated**: 2025-10-23
**i3 Version Tested**: 4.24
