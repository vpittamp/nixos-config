# Research: Multi-Monitor Window Management Enhancements

**Feature Branch**: `083-multi-monitor-window-management`
**Date**: 2025-11-19

## Research Questions

1. How can the daemon push real-time updates to Eww without polling?
2. How to subscribe to Sway output events for monitor state changes?
3. How to coordinate atomic profile switching to prevent race conditions?

---

## Decision 1: Eww Real-Time Updates via CLI

**Decision**: Use `eww update` CLI command for real-time widget updates

**Rationale**:
- Achieves <20ms latency (verified in workspace-preview-daemon)
- Eww has no socket/pipe listener API; CLI is the only push mechanism
- Proven pattern in Feature 072/073 with excellent results
- Non-blocking subprocess calls don't block daemon event loop

**Alternatives Considered**:
- **deflisten streaming**: Rejected - unreliable under rapid updates, 50-200ms latency, buffer issues
- **Socket/pipe IPC**: Not supported by Eww architecture
- **Polling with defpoll**: Rejected - 2s latency, CPU overhead

**Implementation**:
```python
import subprocess
import json

def update_eww(variable: str, value: dict) -> bool:
    """Push update to Eww widget."""
    try:
        result = subprocess.run(
            ["eww", "update", f"{variable}={json.dumps(value)}"],
            check=False,
            capture_output=True,
            timeout=2.0,
            text=True
        )
        return result.returncode == 0
    except Exception:
        return False
```

**Widget Variables to Update**:
- `monitor_state`: Active outputs (H1/H2/H3) and their status
- `current_profile`: Profile name (single/dual/triple)

---

## Decision 2: Sway Output Event Subscription

**Decision**: Use i3ipc.aio event subscription with `conn.on("output", handler)`

**Rationale**:
- Native async support integrates with existing daemon architecture
- Event-driven eliminates polling overhead
- Already proven in Feature 001/049 with reliable results
- 2-3ms IPC latency for output queries

**Alternatives Considered**:
- **Polling GET_OUTPUTS**: Rejected - CPU intensive, 100-500ms latency
- **File watcher for output-states.json**: Partial complement, less timely
- **Raw socket IPC**: Rejected - complexity, maintenance burden

**Event Payload Structure**:
```python
class OutputEvent:
    change: str   # "connected", "disconnected", "unknown"

# Handler receives full output info via get_outputs():
output.name              # "HEADLESS-1"
output.active            # True/False
output.current_workspace # Current workspace number
```

**Implementation Pattern** (from handlers.py):
```python
# Subscribe to output events
conn.on("output", partial(
    on_output,
    state_manager=self.state_manager,
    event_buffer=self.event_buffer
))

async def on_output(conn, event, state_manager, event_buffer):
    """Handle output event from Sway."""
    outputs = await conn.get_outputs()
    active_outputs = [o for o in outputs if o.active]
    # Process state change...
```

---

## Decision 3: Atomic Profile Switching with Debouncing

**Decision**: Event-driven debounce + state-file transaction pattern with intermediate state suppression

**Rationale**:
- Existing 500ms debounce pattern prevents cascading reassignments
- Global task cancellation ensures only one pending reassignment
- Pydantic models validate state before persistence
- asyncio.Lock protects concurrent state modifications

**Alternatives Considered**:
- **Direct IPC transaction batching**: Not supported by Sway
- **File-based checkpointing**: Too heavyweight for monitor changes
- **Workspace freezing**: Loses user input during transition

**Pattern 1: Debounce Task Cancellation** (handlers.py:2326-2376):
```python
global _output_debounce_task

async def on_output_event(conn, event):
    # Cancel existing pending task
    if _output_debounce_task and not _output_debounce_task.done():
        _output_debounce_task.cancel()
        try:
            await _output_debounce_task
        except asyncio.CancelledError:
            pass

    # Schedule new debounced task (500ms)
    _output_debounce_task = asyncio.create_task(
        _debounced_reassignment(conn)
    )
```

**Pattern 2: Atomic State Update**:
```python
# Update all output states in single operation
states = load_output_states()
for output in profile.outputs:
    states.set_output_enabled(output.name, output.enabled)
save_output_states(states)  # Single filesystem write
```

**Pattern 3: Batch Workspace Reassignment**:
```python
# All workspace moves in one async batch
results = await asyncio.gather(*[
    conn.command(f'workspace number {ws} move to output {output}')
    for ws, output in assignments
])
```

**Rollback Strategy**:
```python
async def rollback_profile_change(previous_profile: str, conn):
    """Revert to previous profile on failure."""
    prev_states = load_profile_states(previous_profile)
    save_output_states(prev_states)
    await _perform_workspace_reassignment(conn, prev_states)
    # Notify user of rollback
```

---

## Decision 4: Daemon-Script Communication Protocol

**Decision**: Shell script notifies daemon via file update; daemon owns state files

**Rationale**:
- Daemon's OutputStatesWatcher already monitors file changes
- Eliminates duplicate Python logic in shell script
- Single source of truth for state management
- Consistent with existing file watcher pattern (200ms debounce)

**Communication Flow**:
1. User triggers `set-monitor-profile <name>`
2. Script executes Sway IPC commands (enable/disable outputs)
3. Script writes `monitor-profile.current` with profile name
4. Script sends minimal notification to daemon (or relies on file watch)
5. Daemon reads profile, updates `output-states.json`
6. Daemon reassigns workspaces to enabled outputs
7. Daemon publishes state to Eww

**Script Simplification**:
```bash
# Current: Script writes output-states.json with embedded Python
# New: Script only writes monitor-profile.current

# set-monitor-profile.sh (simplified)
set_monitor_profile() {
    local profile_name="$1"

    # 1. Execute Sway output commands
    active-monitors --profile "$profile_name"

    # 2. Record profile selection (daemon will read this)
    printf "%s\n" "$profile_name" > "$CURRENT_FILE"

    # 3. Daemon detects change via file watcher and handles the rest
}
```

---

## Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Top bar update latency | <100ms | Eww update CLI achieves <20ms |
| Output event subscription | <5ms | i3ipc.aio native support |
| Debounce timer | 500ms | Prevents cascading reassignments |
| Workspace reassignment | <100ms | Batched IPC commands |
| Total profile switch | <600ms | debounce + reassignment |

---

## File References

- **Existing Output Handler**: `home-modules/desktop/i3-project-event-daemon/handlers.py:2342-2486`
- **State Manager**: `home-modules/desktop/i3-project-event-daemon/state.py`
- **Output State Manager**: `home-modules/desktop/i3-project-event-daemon/output_state_manager.py`
- **Profile Script**: `home-modules/desktop/scripts/set-monitor-profile.sh`
- **Eww Update Pattern**: `home-modules/tools/sway-workspace-panel/workspace-preview-daemon:624-656`
