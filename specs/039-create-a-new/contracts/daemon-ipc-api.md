# Daemon IPC API Contract

**Feature**: 039-create-a-new
**Protocol**: JSON-RPC 2.0
**Transport**: Unix domain socket at `~/.local/share/i3-project-daemon/daemon.sock`

## Overview

The i3-project-daemon exposes a JSON-RPC API for diagnostic tools and CLI commands. All methods return structured data defined in data-model.md.

---

## Connection

```python
import json
import socket

# Connect to daemon socket
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect("/home/vpittamp/.local/share/i3-project-daemon/daemon.sock")

# Send JSON-RPC request
request = {
    "jsonrpc": "2.0",
    "method": "health_check",
    "params": {},
    "id": 1
}
sock.sendall(json.dumps(request).encode() + b'\n')

# Receive response
response = sock.recv(4096)
result = json.loads(response)
print(result)
```

---

## Methods

### 1. health_check

Get comprehensive daemon health status.

**Request**:
```json
{
    "jsonrpc": "2.0",
    "method": "health_check",
    "params": {},
    "id": 1
}
```

**Response**:
```json
{
    "jsonrpc": "2.0",
    "result": {
        "daemon_version": "1.4.0",
        "uptime_seconds": 3600.5,
        "i3_ipc_connected": true,
        "json_rpc_server_running": true,
        "event_subscriptions": [
            {
                "subscription_type": "window",
                "is_active": true,
                "event_count": 1234,
                "last_event_time": "2025-10-26T12:34:56",
                "last_event_change": "new"
            }
        ],
        "total_events_processed": 1350,
        "total_windows": 23,
        "overall_status": "healthy",
        "health_issues": []
    },
    "id": 1
}
```

**Return Type**: `DiagnosticReport` (subset - health info only)

**Errors**:
- None - always returns status (even if unhealthy)

---

### 2. get_window_identity

Get complete identity and context for a specific window.

**Request**:
```json
{
    "jsonrpc": "2.0",
    "method": "get_window_identity",
    "params": {
        "window_id": 14680068
    },
    "id": 2
}
```

**Response**:
```json
{
    "jsonrpc": "2.0",
    "result": {
        "window_id": 14680068,
        "window_class": "com.mitchellh.ghostty",
        "window_class_normalized": "ghostty",
        "window_instance": "ghostty",
        "window_title": "vpittamp@hetzner: ~",
        "window_pid": 823199,
        "workspace_number": 5,
        "workspace_name": "5",
        "output_name": "HDMI-1",
        "is_floating": false,
        "is_focused": true,
        "is_hidden": false,
        "i3pm_env": {
            "app_id": "terminal-stacks-823199-1730000000",
            "app_name": "terminal",
            "project_name": "stacks",
            "scope": "scoped"
        },
        "i3pm_marks": ["project:stacks", "app:terminal"],
        "matched_app": "terminal",
        "match_type": "instance"
    },
    "id": 2
}
```

**Parameters**:
- `window_id` (int, required): i3 container ID

**Return Type**: `WindowIdentity`

**Errors**:
- `-32001`: Window not found
- `-32002`: Window not tracked by daemon

---

### 3. get_workspace_rule

Get workspace assignment rule for an application.

**Request**:
```json
{
    "jsonrpc": "2.0",
    "method": "get_workspace_rule",
    "params": {
        "app_name": "lazygit"
    },
    "id": 3
}
```

**Response**:
```json
{
    "jsonrpc": "2.0",
    "result": {
        "app_identifier": "ghostty",
        "matching_strategy": "normalized",
        "aliases": ["com.mitchellh.ghostty", "Ghostty"],
        "target_workspace": 3,
        "fallback_behavior": "current",
        "app_name": "lazygit",
        "description": "Git TUI in terminal on workspace 3"
    },
    "id": 3
}
```

**Parameters**:
- `app_name` (str, required): Application name from registry

**Return Type**: `WorkspaceRule | null`

**Errors**:
- `-32003`: Application not found in registry

---

### 4. validate_state

Validate daemon state consistency against i3 IPC.

**Request**:
```json
{
    "jsonrpc": "2.0",
    "method": "validate_state",
    "params": {},
    "id": 4
}
```

**Response**:
```json
{
    "jsonrpc": "2.0",
    "result": {
        "validated_at": "2025-10-26T12:34:56",
        "total_windows_checked": 23,
        "windows_consistent": 21,
        "windows_inconsistent": 2,
        "mismatches": [
            {
                "window_id": 14680068,
                "property_name": "workspace",
                "daemon_value": "3",
                "i3_value": "5",
                "severity": "warning"
            }
        ],
        "is_consistent": false,
        "consistency_percentage": 91.3
    },
    "id": 4
}
```

**Return Type**: `StateValidation`

**Errors**:
- `-32010`: i3 IPC connection failed

---

### 5. get_recent_events

Get recent events from circular buffer.

**Request**:
```json
{
    "jsonrpc": "2.0",
    "method": "get_recent_events",
    "params": {
        "limit": 50,
        "event_type": "window"
    },
    "id": 5
}
```

**Response**:
```json
{
    "jsonrpc": "2.0",
    "result": [
        {
            "event_type": "window",
            "event_change": "new",
            "timestamp": "2025-10-26T12:34:56.789",
            "window_id": 14680068,
            "window_class": "com.mitchellh.ghostty",
            "window_title": "vpittamp@hetzner: ~",
            "handler_duration_ms": 45.2,
            "workspace_assigned": 3,
            "marks_applied": ["project:stacks", "app:terminal"],
            "error": null
        }
    ],
    "id": 5
}
```

**Parameters**:
- `limit` (int, optional, default=50): Max events to return (max 500)
- `event_type` (str, optional): Filter by event type (window, workspace, output, tick)

**Return Type**: `list[WindowEvent]`

**Errors**:
- `-32004`: Invalid limit (must be 1-500)

---

### 6. get_diagnostic_report

Get complete diagnostic report with all state information.

**Request**:
```json
{
    "jsonrpc": "2.0",
    "method": "get_diagnostic_report",
    "params": {
        "include_windows": true,
        "include_events": true,
        "include_validation": true
    },
    "id": 6
}
```

**Response**:
```json
{
    "jsonrpc": "2.0",
    "result": {
        "generated_at": "2025-10-26T12:34:56",
        "daemon_version": "1.4.0",
        "uptime_seconds": 3600.5,
        "i3_ipc_connected": true,
        "json_rpc_server_running": true,
        "event_subscriptions": [...],
        "tracked_windows": [...],
        "recent_events": [...],
        "state_validation": {...},
        "i3_ipc_state": {...},
        "overall_status": "warning",
        "health_issues": ["State drift detected for 2 windows"]
    },
    "id": 6
}
```

**Parameters**:
- `include_windows` (bool, optional, default=false): Include full window list
- `include_events` (bool, optional, default=false): Include event buffer
- `include_validation` (bool, optional, default=false): Run state validation

**Return Type**: `DiagnosticReport`

**Errors**:
- None - always returns report

---

## Error Codes

Standard JSON-RPC errors:

| Code | Message | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid request | Invalid JSON-RPC |
| -32601 | Method not found | Unknown method |
| -32602 | Invalid params | Invalid parameters |
| -32603 | Internal error | Server error |

Custom errors:

| Code | Message | Description |
|------|---------|-------------|
| -32001 | Window not found | Window ID doesn't exist in i3 |
| -32002 | Window not tracked | Window not tracked by daemon |
| -32003 | Application not found | App not in registry |
| -32004 | Invalid limit | Limit out of range (1-500) |
| -32010 | i3 IPC error | i3 IPC connection failed |

---

## Authentication

None - socket is user-scoped (`~/.local/share/`), only same user can connect.

---

## Versioning

API version follows daemon version. Breaking changes increment major version.

**Current Version**: 1.4.0

**Compatibility**:
- Minor version changes: Backward compatible (new optional fields)
- Major version changes: May break compatibility (deprecated methods removed)

---

## Rate Limiting

None - diagnostic tools are trusted local clients.

---

## Example Client (Python)

```python
import json
import socket
from pathlib import Path

class DaemonClient:
    def __init__(self, socket_path: str = None):
        if socket_path is None:
            socket_path = str(Path.home() / ".local/share/i3-project-daemon/daemon.sock")
        self.socket_path = socket_path
        self.request_id = 0

    def _call(self, method: str, params: dict = None) -> dict:
        """Make JSON-RPC call to daemon."""
        self.request_id += 1

        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self.request_id
        }

        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.connect(self.socket_path)
            sock.sendall(json.dumps(request).encode() + b'\n')

            response = sock.recv(16384)
            result = json.loads(response)

            if "error" in result:
                raise Exception(f"RPC Error {result['error']['code']}: {result['error']['message']}")

            return result["result"]

    def health_check(self) -> dict:
        """Get daemon health status."""
        return self._call("health_check")

    def get_window_identity(self, window_id: int) -> dict:
        """Get window identity and context."""
        return self._call("get_window_identity", {"window_id": window_id})

    def get_workspace_rule(self, app_name: str) -> dict | None:
        """Get workspace rule for application."""
        return self._call("get_workspace_rule", {"app_name": app_name})

    def validate_state(self) -> dict:
        """Validate state consistency."""
        return self._call("validate_state")

    def get_recent_events(self, limit: int = 50, event_type: str = None) -> list:
        """Get recent events from buffer."""
        params = {"limit": limit}
        if event_type:
            params["event_type"] = event_type
        return self._call("get_recent_events", params)

    def get_diagnostic_report(self, include_windows: bool = False,
                             include_events: bool = False,
                             include_validation: bool = False) -> dict:
        """Get complete diagnostic report."""
        return self._call("get_diagnostic_report", {
            "include_windows": include_windows,
            "include_events": include_events,
            "include_validation": include_validation
        })
```

---

## Implementation Notes

1. **Socket Location**: `~/.local/share/i3-project-daemon/daemon.sock`
2. **Protocol**: JSON-RPC 2.0 over Unix socket
3. **Message Framing**: Newline-delimited JSON
4. **Max Message Size**: 64KB (increase if needed for large reports)
5. **Timeout**: 5 seconds per request
6. **Concurrency**: Multiple clients supported (async server)
