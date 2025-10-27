# IPC Endpoints Contract

**Feature**: 041-ipc-launch-context
**Date**: 2025-10-27
**Version**: 1.0

## Overview

This document specifies the JSON-RPC IPC endpoints for the launch notification system. All endpoints follow the existing daemon IPC server conventions using JSON-RPC 2.0 over Unix socket.

**Transport**: Unix socket at `~/.cache/i3-project/daemon.sock`
**Protocol**: JSON-RPC 2.0

---

## New Endpoints

### 1. notify_launch

**Purpose**: Notify daemon that an application is about to launch, providing project context for window correlation.

**Direction**: Launcher wrapper → Daemon

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "notify_launch",
  "params": {
    "app_name": "vscode",
    "project_name": "nixos",
    "project_directory": "/etc/nixos",
    "launcher_pid": 12345,
    "workspace_number": 2,
    "timestamp": 1698765432.123
  },
  "id": 1
}
```

**Parameters**:

| Field | Type | Required | Constraints | Description |
|-------|------|----------|-------------|-------------|
| `app_name` | string | Yes | Non-empty, matches app registry | Application name (e.g., "vscode", "terminal") |
| `project_name` | string | Yes | Non-empty | Project name for this launch |
| `project_directory` | string | Yes | Absolute path | Project directory path |
| `launcher_pid` | integer | Yes | > 0 | Process ID of launcher wrapper |
| `workspace_number` | integer | Yes | 1-70 | Target workspace number |
| `timestamp` | float | Yes | Not in future | Unix timestamp (seconds.microseconds) |

**Success Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "status": "registered",
    "launch_id": "vscode-1698765432.123",
    "expected_class": "Code",
    "pending_count": 3
  },
  "id": 1
}
```

**Result Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | Always "registered" on success |
| `launch_id` | string | Unique identifier for this launch (for debugging) |
| `expected_class` | string | Window class resolved from app registry |
| `pending_count` | integer | Total pending launches after this registration |

**Error Responses**:

```json
// Application not found in registry
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params",
    "data": {
      "field": "app_name",
      "reason": "Application 'unknown-app' not found in registry"
    }
  },
  "id": 1
}

// Invalid workspace number
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params",
    "data": {
      "field": "workspace_number",
      "reason": "Workspace number must be 1-70, got 100"
    }
  },
  "id": 1
}

// Future timestamp
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params",
    "data": {
      "field": "timestamp",
      "reason": "Timestamp 1698765999.0 is in the future (now=1698765432.0)"
    }
  },
  "id": 1
}
```

**Side Effects**:
1. Creates `PendingLaunch` object in launch registry
2. Triggers cleanup of expired launches (age > 5s)
3. Increments `total_notifications` counter in stats

**Performance**:
- Target latency: <5ms
- Typical latency: 2-3ms (Unix socket, in-memory operation)

---

### 2. get_launch_stats

**Purpose**: Query statistics about the launch registry for diagnostics and monitoring.

**Direction**: CLI tool / Monitor → Daemon

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_launch_stats",
  "params": {},
  "id": 2
}
```

**Parameters**: None

**Success Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "total_pending": 3,
    "unmatched_pending": 2,
    "total_notifications": 127,
    "total_matched": 120,
    "total_expired": 5,
    "total_failed_correlation": 2,
    "match_rate": 94.5,
    "expiration_rate": 3.9
  },
  "id": 2
}
```

**Result Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `total_pending` | integer | Current pending launches in registry |
| `unmatched_pending` | integer | Pending launches not yet matched |
| `total_notifications` | integer | Total launch notifications since daemon start |
| `total_matched` | integer | Total successful correlations |
| `total_expired` | integer | Total launches expired without matching |
| `total_failed_correlation` | integer | Total windows without matching launch |
| `match_rate` | float | Percentage of notifications successfully matched |
| `expiration_rate` | float | Percentage of notifications that expired |

**Error Responses**: None (always succeeds)

**Side Effects**: None (read-only query)

**Performance**:
- Target latency: <5ms
- Typical latency: <1ms (simple counter reads)

---

### 3. get_pending_launches (Debug Endpoint)

**Purpose**: List all pending launches for debugging and diagnostics.

**Direction**: CLI tool / Monitor → Daemon

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_pending_launches",
  "params": {
    "include_matched": false
  },
  "id": 3
}
```

**Parameters**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `include_matched` | boolean | No | false | Include already-matched launches |

**Success Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "pending_launches": [
      {
        "launch_id": "vscode-1698765432.123",
        "app_name": "vscode",
        "project_name": "nixos",
        "project_directory": "/etc/nixos",
        "expected_class": "Code",
        "workspace_number": 2,
        "timestamp": 1698765432.123,
        "age": 2.5,
        "matched": false
      },
      {
        "launch_id": "terminal-1698765430.456",
        "app_name": "terminal",
        "project_name": "stacks",
        "project_directory": "/home/user/stacks",
        "expected_class": "Alacritty",
        "workspace_number": 3,
        "timestamp": 1698765430.456,
        "age": 4.2,
        "matched": false
      }
    ],
    "count": 2
  },
  "id": 3
}
```

**Result Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `pending_launches` | array | List of pending launch objects |
| `count` | integer | Number of launches returned |

**Launch Object Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `launch_id` | string | Unique launch identifier |
| `app_name` | string | Application name |
| `project_name` | string | Project name |
| `project_directory` | string | Project directory path |
| `expected_class` | string | Expected window class |
| `workspace_number` | integer | Target workspace |
| `timestamp` | float | Launch notification timestamp |
| `age` | float | Seconds since notification |
| `matched` | boolean | Whether launch has been matched |

**Error Responses**: None

**Side Effects**: None (read-only query)

**Performance**:
- Target latency: <10ms
- Typical latency: 1-2ms (<10 pending launches typical)

---

## Modified Endpoints

### get_window_state (Extended)

**Purpose**: Query window state including correlation information.

**Changes**: Add `correlation` field to response if window was matched via launch context.

**Existing Endpoint**: Already exists in daemon

**Response Extension**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "window_id": 94532735639728,
    "window_class": "Code",
    "project_name": "nixos",
    "workspace_number": 2,
    "correlation": {
      "matched_via_launch": true,
      "launch_id": "vscode-1698765432.123",
      "confidence": 0.85,
      "confidence_level": "HIGH",
      "signals_used": {
        "class_match": true,
        "time_delta": 0.5,
        "workspace_match": true
      }
    }
  },
  "id": 4
}
```

**New Field**: `correlation`

| Subfield | Type | Description |
|----------|------|-------------|
| `matched_via_launch` | boolean | True if window was correlated to launch |
| `launch_id` | string | Launch identifier that matched |
| `confidence` | float | Correlation confidence score (0.0-1.0) |
| `confidence_level` | string | Categorical confidence (EXACT/HIGH/MEDIUM/LOW/NONE) |
| `signals_used` | object | Correlation signals and values |

**Note**: If window was not correlated (e.g., appeared without launch notification), `correlation` field is absent or `matched_via_launch=false`.

---

## Client Examples

### Bash (socat)

```bash
#!/bin/bash
# Send launch notification from wrapper script

send_launch_notification() {
    local app_name="$1"
    local project_name="$2"
    local project_dir="$3"
    local workspace="$4"
    local timestamp=$(date +%s.%N)

    echo "{
        \"jsonrpc\": \"2.0\",
        \"method\": \"notify_launch\",
        \"params\": {
            \"app_name\": \"$app_name\",
            \"project_name\": \"$project_name\",
            \"project_directory\": \"$project_dir\",
            \"launcher_pid\": $$,
            \"workspace_number\": $workspace,
            \"timestamp\": $timestamp
        },
        \"id\": 1
    }" | socat - UNIX-CONNECT:$HOME/.cache/i3-project/daemon.sock
}

# Usage
send_launch_notification "vscode" "nixos" "/etc/nixos" 2
```

### Python (async)

```python
import asyncio
import time
from i3_project_manager.client import DaemonClient

async def notify_launch_example():
    """Send launch notification via Python client."""
    async with DaemonClient() as daemon:
        result = await daemon.notify_launch(
            app_name="vscode",
            project_name="nixos",
            project_directory="/etc/nixos",
            launcher_pid=12345,
            workspace_number=2,
            timestamp=time.time()
        )
        print(f"Launch registered: {result['launch_id']}")
        print(f"Expected class: {result['expected_class']}")
        print(f"Pending launches: {result['pending_count']}")

async def get_stats_example():
    """Query launch statistics."""
    async with DaemonClient() as daemon:
        stats = await daemon.get_launch_stats()
        print(f"Match rate: {stats['match_rate']:.1f}%")
        print(f"Expiration rate: {stats['expiration_rate']:.1f}%")
        print(f"Current pending: {stats['total_pending']}")
```

---

## Error Handling

### JSON-RPC Error Codes

| Code | Meaning | Example |
|------|---------|---------|
| -32700 | Parse error | Invalid JSON in request |
| -32600 | Invalid request | Missing "jsonrpc" field |
| -32601 | Method not found | Unknown method name |
| -32602 | Invalid params | Missing required parameter, validation failure |
| -32603 | Internal error | Daemon exception during processing |

### Validation Errors

All parameter validation errors return `-32602` (Invalid params) with detailed error data:

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params",
    "data": {
      "field": "<parameter_name>",
      "reason": "<human-readable error message>"
    }
  },
  "id": <request_id>
}
```

### Client Handling

**Synchronous notification** (launcher wrapper):
- Send notification before launching app
- Wait for response to confirm registration
- If error, log warning but proceed with launch
- Timeout: 1 second (fallback to no notification)

**Asynchronous queries** (monitoring tools):
- Queries can fail gracefully (daemon not running, socket error)
- Display "daemon unavailable" state in UI
- Auto-reconnect on next query attempt

---

## Performance Targets

| Endpoint | Target Latency | Typical Latency | Notes |
|----------|----------------|-----------------|-------|
| `notify_launch` | <5ms | 2-3ms | Critical path - blocks app launch |
| `get_launch_stats` | <5ms | <1ms | Counter reads only |
| `get_pending_launches` | <10ms | 1-2ms | List iteration over <10 entries |
| `get_window_state` | <10ms | 5ms | Existing endpoint, minimal changes |

**Bottleneck**: None - all operations are in-memory and O(1) or O(n) with small n.

---

## Versioning & Compatibility

**Version**: 1.0 (initial implementation)

**Backward Compatibility**: New endpoints do not affect existing IPC functionality. Old clients continue to work without launch context support.

**Future Extensions**:
- `cancel_launch`: Explicitly cancel pending launch (e.g., app failed to start)
- `update_launch`: Modify pending launch params (e.g., workspace change)
- `get_correlation_history`: Query historical correlation outcomes

---

## Testing Considerations

### Mock IPC Server

```python
# Test fixture
class MockIPCServer:
    """Mock daemon IPC server for testing."""

    def __init__(self):
        self.notifications = []
        self.pending_launches = {}

    async def notify_launch(self, params: dict) -> dict:
        """Mock notify_launch endpoint."""
        launch_id = f"{params['app_name']}-{params['timestamp']}"
        self.pending_launches[launch_id] = params
        self.notifications.append(params)

        return {
            "status": "registered",
            "launch_id": launch_id,
            "expected_class": "MockClass",
            "pending_count": len(self.pending_launches)
        }

    async def get_launch_stats(self) -> dict:
        """Mock get_launch_stats endpoint."""
        return {
            "total_pending": len(self.pending_launches),
            "total_notifications": len(self.notifications),
            # ... other stats ...
        }
```

### Contract Validation Tests

```python
import pytest

@pytest.mark.asyncio
async def test_notify_launch_valid_params(mock_server):
    """Test notify_launch with valid parameters."""
    result = await mock_server.notify_launch({
        "app_name": "vscode",
        "project_name": "nixos",
        "project_directory": "/etc/nixos",
        "launcher_pid": 12345,
        "workspace_number": 2,
        "timestamp": 1698765432.123
    })

    assert result["status"] == "registered"
    assert "launch_id" in result
    assert "expected_class" in result
    assert result["pending_count"] >= 1

@pytest.mark.asyncio
async def test_notify_launch_invalid_workspace(mock_server):
    """Test notify_launch with invalid workspace number."""
    with pytest.raises(ValidationError) as exc:
        await mock_server.notify_launch({
            "app_name": "vscode",
            "workspace_number": 100,  # Invalid
            # ... other params ...
        })

    assert "workspace_number" in str(exc.value)
```

---

## Security Considerations

**Authentication**: Unix socket inherits filesystem permissions. Only user running daemon can connect.

**Validation**: All parameters validated via Pydantic models before processing.

**Injection Prevention**: No shell execution, no SQL - all in-memory operations.

**Resource Limits**:
- Maximum pending launches: 1000 (auto-cleanup prevents unbounded growth)
- Maximum request size: 10KB (JSON-RPC message limit)

---

## Next Steps

See `quickstart.md` for:
- End-to-end workflow examples
- Testing procedures
- Debugging commands
