# Sway IPC Commands Contract

**Feature**: 049-intelligent-automatic-workspace
**Date**: 2025-10-29
**Phase**: Phase 1 - Design

## Overview

This document defines the Sway IPC commands used by the automatic workspace redistribution feature. All commands follow Sway's i3 IPC protocol specification.

---

## 1. Output Event Subscription

Subscribe to monitor connect/disconnect events.

**IPC Message Type**: `SUBSCRIBE`

**Event Type**: `output`

**Request** (via i3ipc-python):
```python
from i3ipc.aio import Connection

async with Connection() as i3:
    i3.on("output", on_output_event)
    await i3.main()
```

**Event Payload** (received):
```json
{
  "change": "connected" | "disconnected" | "changed",
  "output": {
    "name": "HEADLESS-1",
    "active": true,
    "current_mode": {
      "width": 1920,
      "height": 1080,
      "refresh": 60000
    }
  }
}
```

**Response Handling**:
- `change == "connected"`: Trigger debounced reassignment
- `change == "disconnected"`: Trigger debounced reassignment
- `change == "changed"`: Ignore (resolution/position changes don't require reassignment)

**Error Conditions**:
- Connection lost: Auto-reconnect with exponential backoff
- Invalid event payload: Log error, skip event

---

## 2. Get Active Outputs

Query all outputs (monitors) and their status.

**IPC Message Type**: `GET_OUTPUTS`

**Request** (via i3ipc-python):
```python
outputs = await i3.get_outputs()
```

**Response**:
```json
[
  {
    "name": "HEADLESS-1",
    "active": true,
    "primary": true,
    "current_mode": {
      "width": 1920,
      "height": 1080,
      "refresh": 60000
    },
    "rect": {
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1080
    }
  },
  {
    "name": "HEADLESS-2",
    "active": true,
    "primary": false,
    "current_mode": {
      "width": 1920,
      "height": 1080,
      "refresh": 60000
    },
    "rect": {
      "x": 1920,
      "y": 0,
      "width": 1920,
      "height": 1080
    }
  }
]
```

**Usage**:
- Filter `active == true` to get active monitors
- Use `primary` field for primary monitor detection (if set by user)
- Order of outputs determines role assignment if no explicit primary

**Error Conditions**:
- No active outputs: Should not occur (Sway always has at least one output)
- IPC timeout: Retry with exponential backoff

---

## 3. Get Workspace Status

Query all workspaces and their current output assignments.

**IPC Message Type**: `GET_WORKSPACES`

**Request** (via i3ipc-python):
```python
workspaces = await i3.get_workspaces()
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
    "rect": {
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1080
    }
  },
  {
    "num": 5,
    "name": "5",
    "visible": false,
    "focused": false,
    "urgent": false,
    "output": "HEADLESS-2",
    "rect": {
      "x": 1920,
      "y": 0,
      "width": 1920,
      "height": 1080
    }
  }
]
```

**Usage**:
- Identify workspaces on disconnected monitors (where `output` not in active outputs)
- Check if workspaces have windows before migration

**Error Conditions**:
- Empty workspace list: Should not occur (at least one workspace always exists)
- IPC timeout: Retry with exponential backoff

---

## 4. Get Window Tree

Query complete window hierarchy to detect windows on disconnected monitors.

**IPC Message Type**: `GET_TREE`

**Request** (via i3ipc-python):
```python
tree = await i3.get_tree()
```

**Response** (simplified):
```json
{
  "id": 1,
  "type": "root",
  "nodes": [
    {
      "type": "output",
      "name": "HEADLESS-1",
      "nodes": [
        {
          "type": "workspace",
          "num": 1,
          "nodes": [
            {
              "type": "con",
              "id": 94532735639728,
              "window": 12345678,
              "window_properties": {
                "class": "Alacritty",
                "title": "terminal"
              }
            }
          ]
        }
      ]
    }
  ]
}
```

**Usage**:
- Traverse tree to find workspaces on disconnected monitors
- Count windows on each workspace for migration logging
- Collect window IDs and classes for migration records

**Error Conditions**:
- IPC timeout: Retry with exponential backoff
- Malformed tree: Log error, skip window detection (proceed with workspace reassignment)

---

## 5. Assign Workspace to Output

Move workspace to specific output.

**IPC Message Type**: `COMMAND`

**Command Format**: `workspace number <num> output <output_name>`

**Request** (via i3ipc-python):
```python
await i3.command(f"workspace number {workspace_num} output {output_name}")
```

**Example**:
```bash
workspace number 5 output HEADLESS-1
```

**Response**:
```json
[
  {
    "success": true
  }
]
```

**Behavior**:
- Workspace is assigned to output
- All windows on workspace move with it
- Workspace numbers are preserved
- Visible workspace on that output may change
- Focus is NOT changed (windows don't auto-focus)

**Error Conditions**:
- Invalid workspace number: `success: false`, error message provided
- Invalid output name: `success: false`, error message provided
- Output not active: `success: false`, workspace stays on current output

**Performance**:
- Each command takes ~10-20ms
- Commands are sequential (not batched in Sway IPC)
- For 9 workspaces: ~90-180ms total

---

## 6. Batch Workspace Assignment

Assign multiple workspaces to outputs in sequence.

**IPC Message Type**: `COMMAND` (multiple)

**Request Pattern**:
```python
# Sequential assignment (required for reliability)
for ws_num, output_name in workspace_assignments.items():
    result = await i3.command(f"workspace number {ws_num} output {output_name}")
    if not result[0].success:
        # Log error, continue with next workspace
        pass
```

**Example Commands**:
```bash
workspace number 1 output HEADLESS-1
workspace number 2 output HEADLESS-1
workspace number 3 output HEADLESS-2
workspace number 4 output HEADLESS-2
workspace number 5 output HEADLESS-2
workspace number 6 output HEADLESS-3
```

**Error Handling**:
- If one command fails, continue with remaining commands
- Collect failed assignments for logging
- Return partial success status

**Performance Target**:
- 9 workspaces reassigned in <200ms
- 70 workspaces reassigned in <1.5s (if all active)

---

## 7. Focus Workspace (Optional)

Switch to workspace to verify assignment (diagnostic only).

**IPC Message Type**: `COMMAND`

**Command Format**: `workspace number <num>`

**Request** (via i3ipc-python):
```python
await i3.command(f"workspace number {workspace_num}")
```

**Example**:
```bash
workspace number 5
```

**Usage**:
- NOT used during automatic reassignment (to avoid focus changes)
- Used only in diagnostic/testing scenarios to verify workspace state

---

## Error Handling Strategy

### Connection Errors
- Auto-reconnect with exponential backoff (1s, 2s, 4s, 8s, max 60s)
- Log connection loss events
- Queue reassignment requests during disconnection

### Command Failures
- Log failed commands with workspace number and error message
- Continue with remaining commands
- Report partial success in ReassignmentResult

### Timeout Errors
- Default timeout: 5s for GET commands, 10s for COMMAND operations
- Retry once on timeout
- If retry fails, log error and report failure

### Invalid State
- If no active outputs detected: Log critical error, do not reassign
- If workspace list empty: Log critical error, do not reassign
- If tree query fails: Proceed without window migration logging

---

## Performance Monitoring

Track timing for each IPC operation:

```python
import time

start = time.time()
outputs = await i3.get_outputs()
duration_ms = (time.time() - start) * 1000

# Log slow operations (>100ms warning, >500ms error)
if duration_ms > 100:
    logger.warning(f"Slow GET_OUTPUTS: {duration_ms}ms")
```

Target latencies:
- GET_OUTPUTS: <10ms
- GET_WORKSPACES: <20ms
- GET_TREE: <50ms
- COMMAND (workspace assignment): <20ms per command

---

## Integration with Daemon Event Loop

```python
async def _on_output_event(self, i3: Connection, event: OutputEvent):
    """Handle output connect/disconnect events."""
    # Cancel pending reassignment
    if self._pending_reassignment_task:
        self._pending_reassignment_task.cancel()

    # Schedule debounced reassignment
    self._pending_reassignment_task = asyncio.create_task(
        self._debounced_reassignment()
    )

async def _debounced_reassignment(self):
    """Perform reassignment after debounce delay."""
    await asyncio.sleep(0.5)  # 500ms debounce

    start_time = time.time()

    # 1. Query current state
    outputs = await self.i3.get_outputs()
    workspaces = await self.i3.get_workspaces()
    tree = await self.i3.get_tree()

    # 2. Calculate new distribution
    distribution = calculate_distribution(outputs)

    # 3. Assign workspaces
    for ws_num, output_name in distribution.items():
        await self.i3.command(f"workspace number {ws_num} output {output_name}")

    # 4. Persist state
    save_monitor_state(outputs, distribution)

    duration_ms = (time.time() - start_time) * 1000
    logger.info(f"Reassignment complete in {duration_ms}ms")
```

---

## Testing Contracts

### Mock IPC Responses
For pytest tests, mock i3ipc responses:

```python
@pytest.fixture
async def mock_i3():
    conn = AsyncMock(spec=Connection)
    conn.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True, primary=True),
        Mock(name="HEADLESS-2", active=True, primary=False),
    ]
    conn.get_workspaces.return_value = [
        Mock(num=1, name="1", output="HEADLESS-1"),
        Mock(num=5, name="5", output="HEADLESS-2"),
    ]
    conn.command.return_value = [Mock(success=True)]
    return conn
```

### Contract Validation Tests
Verify IPC command format and response handling:

```python
async def test_workspace_assignment_command():
    """Verify workspace assignment command format."""
    i3 = await get_mock_i3()
    await i3.command("workspace number 5 output HEADLESS-1")

    i3.command.assert_called_once_with("workspace number 5 output HEADLESS-1")
```

---

## References

- Sway IPC Protocol: https://github.com/swaywm/sway/blob/master/sway/sway-ipc.7.scd
- i3ipc-python Documentation: https://i3ipc-python.readthedocs.io/
- Existing i3pm daemon IPC usage: home-modules/desktop/i3-project-event-daemon/handlers.py
