# IPC API Contract: Workspace Mode Navigation

**Feature**: Event-Driven Workspace Mode Navigation
**Branch**: 042-event-driven-workspace-mode
**Protocol**: JSON-RPC 2.0
**Transport**: UNIX domain socket (`~/.local/state/i3-project-daemon.sock`)

## Overview

This document defines the JSON-RPC IPC API for workspace mode navigation. All methods follow the existing i3pm daemon IPC patterns and use JSON-RPC 2.0 protocol.

---

## Connection Setup

**Socket Path**: `~/.local/state/i3-project-daemon.sock`

**Connection Example** (Python):
```python
import asyncio
import json

async def connect_daemon():
    reader, writer = await asyncio.open_unix_connection(
        str(Path.home() / ".local" / "state" / "i3-project-daemon.sock")
    )
    return reader, writer
```

**Request Format**:
```json
{
  "jsonrpc": "2.0",
  "method": "<method_name>",
  "params": { /* method-specific parameters */ },
  "id": <unique_integer>
}
```

**Response Format** (success):
```json
{
  "jsonrpc": "2.0",
  "result": { /* method-specific result */ },
  "id": <request_id>
}
```

**Response Format** (error):
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": <error_code>,
    "message": "<error_message>",
    "data": { /* optional error details */ }
  },
  "id": <request_id>
}
```

---

## Methods

### 1. workspace_mode.digit

**Purpose**: Add a digit to the accumulated workspace number

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.digit",
  "params": {
    "digit": "2"
  },
  "id": 1
}
```

**Parameters**:
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `digit` | string | Yes | Single digit character ("0"-"9") |

**Response** (success):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "accumulated_digits": "2"
  },
  "id": 1
}
```

**Response Fields**:
| Name | Type | Description |
|------|------|-------------|
| `accumulated_digits` | string | Current accumulated digits after adding this digit |

**Error Cases**:
```json
// Invalid digit (not 0-9)
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params: digit must be 0-9",
    "data": {
      "param": "digit",
      "value": "x"
    }
  },
  "id": 1
}

// Mode not active
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Workspace mode not active",
    "data": {}
  },
  "id": 1
}
```

**Side Effects**:
- Broadcasts `workspace_mode` event to subscribed clients with updated `accumulated_digits`

**Latency Target**: <10ms (IPC round-trip + state update + event broadcast)

---

### 2. workspace_mode.execute

**Purpose**: Execute workspace switch using accumulated digits

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.execute",
  "params": {},
  "id": 2
}
```

**Parameters**: None

**Response** (success):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "workspace": 23,
    "output": "HEADLESS-2",
    "success": true
  },
  "id": 2
}
```

**Response Fields**:
| Name | Type | Description |
|------|------|-------------|
| `workspace` | integer | Workspace number that was switched to |
| `output` | string | Physical output name that was focused |
| `success` | boolean | Whether switch executed successfully |

**Response** (empty accumulated_digits):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "workspace": null,
    "output": null,
    "success": false,
    "reason": "No digits accumulated"
  },
  "id": 2
}
```

**Error Cases**:
```json
// Mode not active
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Workspace mode not active",
    "data": {}
  },
  "id": 2
}

// i3 IPC command failed
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32003,
    "message": "Failed to execute workspace switch",
    "data": {
      "workspace": 23,
      "error": "i3 IPC connection lost"
    }
  },
  "id": 2
}
```

**Side Effects**:
- Sends i3 IPC commands: `workspace number <N>` (or `move container to workspace number <N>; workspace number <N>` for move mode)
- Sends i3 IPC command: `focus output <output_name>`
- Records `WorkspaceSwitch` in history (circular buffer, max 100)
- Resets workspace mode state (active=False, accumulated_digits="")
- Broadcasts `workspace_mode` event with `mode_active=False`
- Triggers Sway mode exit (returns to default mode)

**Latency Target**: <20ms (IPC command + i3 processing + focus change)

---

### 3. workspace_mode.cancel

**Purpose**: Exit workspace mode without executing switch

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.cancel",
  "params": {},
  "id": 3
}
```

**Parameters**: None

**Response** (success):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "cancelled": true
  },
  "id": 3
}
```

**Response Fields**:
| Name | Type | Description |
|------|------|-------------|
| `cancelled` | boolean | Always true if mode was active |

**Response** (mode not active):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "cancelled": false,
    "reason": "Mode not active"
  },
  "id": 3
}
```

**Side Effects**:
- Resets workspace mode state (active=False, accumulated_digits="")
- Broadcasts `workspace_mode` event with `mode_active=False`
- Does NOT trigger Sway mode exit (user presses Escape to exit mode, which triggers Sway mode event)

**Latency Target**: <5ms

---

### 4. workspace_mode.state

**Purpose**: Query current workspace mode state

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.state",
  "params": {},
  "id": 4
}
```

**Parameters**: None

**Response** (mode active):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "active": true,
    "mode_type": "goto",
    "accumulated_digits": "23",
    "entered_at": 1698768000.0,
    "output_cache": {
      "PRIMARY": "eDP-1",
      "SECONDARY": "eDP-1",
      "TERTIARY": "eDP-1"
    }
  },
  "id": 4
}
```

**Response** (mode inactive):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "active": false,
    "mode_type": null,
    "accumulated_digits": "",
    "entered_at": null,
    "output_cache": {
      "PRIMARY": "eDP-1",
      "SECONDARY": "eDP-1",
      "TERTIARY": "eDP-1"
    }
  },
  "id": 4
}
```

**Response Fields**:
| Name | Type | Description |
|------|------|-------------|
| `active` | boolean | Whether workspace mode is currently active |
| `mode_type` | string \| null | "goto" or "move" when active, null when inactive |
| `accumulated_digits` | string | Digits typed so far (empty when inactive) |
| `entered_at` | float \| null | Unix timestamp when mode entered, null when inactive |
| `output_cache` | object | Mapping of output roles (PRIMARY/SECONDARY/TERTIARY) to physical output names |

**Side Effects**: None (read-only query)

**Latency Target**: <5ms

---

### 5. workspace_mode.history

**Purpose**: Query workspace navigation history

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.history",
  "params": {
    "limit": 10
  },
  "id": 5
}
```

**Parameters**:
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `limit` | integer | No | Maximum number of entries to return (default: all, max 100) |

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "history": [
      {
        "workspace": 5,
        "output": "HEADLESS-1",
        "timestamp": 1698768123.456,
        "mode_type": "goto"
      },
      {
        "workspace": 23,
        "output": "HEADLESS-2",
        "timestamp": 1698768100.123,
        "mode_type": "move"
      }
    ],
    "total": 42
  },
  "id": 5
}
```

**Response Fields**:
| Name | Type | Description |
|------|------|-------------|
| `history` | array | List of workspace switches, most recent first |
| `total` | integer | Total number of switches in history buffer |

**History Entry Fields**:
| Name | Type | Description |
|------|------|-------------|
| `workspace` | integer | Workspace number that was switched to |
| `output` | string | Physical output name that was focused |
| `timestamp` | float | Unix timestamp when switch occurred |
| `mode_type` | string | "goto" or "move" |

**Side Effects**: None (read-only query)

**Latency Target**: <5ms

---

## Event Broadcasting

### workspace_mode Event

**Purpose**: Notify subscribed clients of workspace mode state changes

**Subscription**:
```json
{
  "jsonrpc": "2.0",
  "method": "subscribe",
  "params": {},
  "id": 100
}
```

**Event Notification** (mode active):
```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "type": "workspace_mode",
    "payload": {
      "mode_active": true,
      "mode_type": "goto",
      "accumulated_digits": "23",
      "timestamp": 1698768123.456
    }
  }
}
```

**Event Notification** (mode inactive):
```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "type": "workspace_mode",
    "payload": {
      "mode_active": false,
      "mode_type": null,
      "accumulated_digits": "",
      "timestamp": 1698768125.789
    }
  }
}
```

**Trigger Conditions**:
- Mode entry (user enters goto_workspace or move_workspace mode)
- Digit accumulation (user types digit 0-9)
- Mode exit (user presses Escape or executes switch)

**Consumers**:
- Status bar scripts (i3bar blocks)
- Monitoring tools (diagnostic displays)

---

## Error Codes

| Code | Meaning | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON received |
| -32600 | Invalid Request | Not a valid JSON-RPC request |
| -32601 | Method not found | Method does not exist |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Internal JSON-RPC error |
| -32001 | Mode not active | Workspace mode is not currently active |
| -32002 | Invalid state | Daemon state is inconsistent |
| -32003 | i3 IPC error | Failed to communicate with i3/Sway |
| -32004 | Command failed | i3/Sway command execution failed |

---

## CLI Tool Integration

The `i3pm workspace-mode` CLI tool wraps these IPC methods:

```bash
# Add digit
i3pm workspace-mode digit 2
# Calls: workspace_mode.digit {"digit": "2"}

# Execute switch
i3pm workspace-mode execute
# Calls: workspace_mode.execute {}

# Cancel mode
i3pm workspace-mode cancel
# Calls: workspace_mode.cancel {}

# Query state
i3pm workspace-mode state [--json]
# Calls: workspace_mode.state {}

# Query history
i3pm workspace-mode history [--limit 10] [--json]
# Calls: workspace_mode.history {"limit": 10}
```

---

## Testing Contract Compliance

### Unit Tests
```python
async def test_digit_method():
    """Test workspace_mode.digit IPC method."""
    response = await send_ipc_request({
        "jsonrpc": "2.0",
        "method": "workspace_mode.digit",
        "params": {"digit": "2"},
        "id": 1
    })

    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 1
    assert "result" in response
    assert response["result"]["accumulated_digits"] == "2"
```

### Integration Tests
```python
async def test_full_navigation_workflow():
    """Test complete workspace navigation workflow."""
    # Enter mode
    await enter_sway_mode("goto_workspace")

    # Add digits
    await send_ipc_request({
        "method": "workspace_mode.digit",
        "params": {"digit": "2"},
        "id": 1
    })
    await send_ipc_request({
        "method": "workspace_mode.digit",
        "params": {"digit": "3"},
        "id": 2
    })

    # Execute
    response = await send_ipc_request({
        "method": "workspace_mode.execute",
        "params": {},
        "id": 3
    })

    assert response["result"]["workspace"] == 23
    assert response["result"]["success"] is True

    # Verify focus
    focused_workspace = await get_focused_workspace()
    assert focused_workspace.num == 23
```

---

## Compatibility

**Daemon Version**: Requires i3pm daemon v1.0.0+ with workspace mode extension

**Protocol Version**: JSON-RPC 2.0

**i3/Sway Compatibility**: Requires i3 or Sway window manager with IPC support

**Backward Compatibility**: These methods are new, no backward compatibility concerns

---

## Performance Guarantees

| Operation | Target Latency | Measurement Point |
|-----------|---------------|-------------------|
| digit accumulation | <10ms | IPC request → response |
| workspace switch | <20ms | execute call → focus change |
| event broadcast | <5ms | state change → client notification |
| state query | <5ms | IPC request → response |
| history query | <5ms | IPC request → response |

---

## Summary

The workspace mode IPC API follows these principles:

1. **Consistency**: Uses existing i3pm daemon JSON-RPC patterns
2. **Simplicity**: Five focused methods, clear request/response schemas
3. **Performance**: <10ms digit accumulation, <20ms workspace switch
4. **Reliability**: Comprehensive error handling with specific error codes
5. **Observability**: Event broadcasting for real-time status bar updates

All methods are async-safe, stateless (from caller perspective), and follow JSON-RPC 2.0 specification.
