# Daemon IPC Contract

**Feature**: Event-Based i3 Project Synchronization
**Contract Type**: Inter-Process Communication
**Version**: 1.0.0

## Overview

This contract defines the IPC interface between the event listener daemon and external clients (CLI tools, status bars, diagnostic utilities). The daemon exposes a UNIX domain socket for queries and commands.

---

## Connection

### Socket Location

**Path**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
**Example**: `/run/user/1000/i3-project-daemon/ipc.sock`

### Protocol

**Type**: UNIX domain socket (SOCK_STREAM)
**Format**: JSON-RPC 2.0 over newline-delimited JSON

Each request and response is a single JSON object terminated by `\n`.

---

## Request Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "method_name",
  "params": {
    "param1": "value1"
  }
}
```

### Fields

- `jsonrpc`: Always `"2.0"`
- `id`: Request identifier (integer or string), echoed in response
- `method`: Method name (string)
- `params`: Method-specific parameters (object), optional

---

## Response Format

### Success Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "key": "value"
  }
}
```

### Error Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32600,
    "message": "Invalid Request",
    "data": {
      "details": "Additional error context"
    }
  }
}
```

### Error Codes

| Code | Message | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid Request | Missing required fields |
| -32601 | Method not found | Unknown method |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Daemon internal error |
| -32000 | Server error | i3 IPC communication failure |
| -32001 | Not connected | Daemon not connected to i3 |
| -32002 | Project not found | Specified project doesn't exist |

---

## Methods

### 1. `get_status`

Get daemon runtime status.

**Parameters**: None

**Returns**:
```json
{
  "is_connected": true,
  "socket_path": "/run/user/1000/i3/ipc-socket.12345",
  "uptime_seconds": 3600,
  "event_count": 1234,
  "error_count": 0,
  "subscribed_events": ["window", "workspace", "tick", "shutdown"],
  "active_project": "nixos"
}
```

**Errors**: None (always succeeds)

---

### 2. `get_active_project`

Get currently active project.

**Parameters**: None

**Returns**:
```json
{
  "project_name": "nixos",
  "activated_at": "2025-10-20T10:30:00Z",
  "previous_project": "stacks"
}
```

Returns `null` if no project is active (global mode).

**Errors**: None

---

### 3. `get_projects`

List all configured projects.

**Parameters**: None

**Returns**:
```json
{
  "projects": [
    {
      "name": "nixos",
      "display_name": "NixOS",
      "icon": "",
      "directory": "/etc/nixos",
      "window_count": 5,
      "is_active": true
    },
    {
      "name": "stacks",
      "display_name": "Stacks",
      "icon": "",
      "directory": "/home/user/projects/stacks",
      "window_count": 0,
      "is_active": false
    }
  ]
}
```

**Errors**: None

---

### 4. `get_windows`

Query tracked windows.

**Parameters**:
```json
{
  "project": "nixos",    // Optional: filter by project
  "workspace": "1",      // Optional: filter by workspace
  "window_class": "Code" // Optional: filter by class
}
```

All filters are optional. If no filters provided, returns all tracked windows.

**Returns**:
```json
{
  "windows": [
    {
      "window_id": 94557896564,
      "con_id": 140737329456128,
      "window_class": "Code",
      "window_title": "/etc/nixos - Visual Studio Code",
      "project": "nixos",
      "marks": ["project:nixos", "editor"],
      "workspace": "1",
      "output": "DP-1",
      "is_floating": false,
      "is_focused": true
    }
  ]
}
```

**Errors**: None (returns empty array if no matches)

---

### 5. `get_workspaces`

Query workspace information.

**Parameters**: None

**Returns**:
```json
{
  "workspaces": [
    {
      "name": "1",
      "num": 1,
      "output": "DP-1",
      "visible": true,
      "focused": true,
      "urgent": false,
      "window_count": 3,
      "project_window_count": 2
    }
  ]
}
```

**Errors**:
- `-32001`: Not connected to i3

---

### 6. `switch_project`

Switch to a different project.

**Parameters**:
```json
{
  "project_name": "nixos"  // or null for global mode
}
```

**Returns**:
```json
{
  "success": true,
  "previous_project": "stacks",
  "new_project": "nixos",
  "windows_hidden": 3,
  "windows_shown": 5
}
```

**Errors**:
- `-32002`: Project not found
- `-32001`: Not connected to i3

---

### 7. `get_events`

Retrieve recent events (for diagnostics).

**Parameters**:
```json
{
  "limit": 50,                  // Optional: max events to return (default 50)
  "event_type": "window"        // Optional: filter by event type
}
```

**Returns**:
```json
{
  "events": [
    {
      "event_type": "window",
      "event_subtype": "new",
      "received_at": "2025-10-20T10:35:12Z",
      "processing_status": "completed",
      "window_id": 94557896564,
      "window_class": "Code"
    }
  ],
  "total_events": 1234
}
```

**Errors**: None

---

### 8. `reload_config`

Reload project configurations from disk.

**Parameters**: None

**Returns**:
```json
{
  "success": true,
  "projects_loaded": 3,
  "errors": []
}
```

If errors occurred during loading:
```json
{
  "success": false,
  "projects_loaded": 2,
  "errors": [
    {
      "file": "/home/user/.config/i3/projects/invalid.json",
      "error": "Invalid JSON: Unexpected token"
    }
  ]
}
```

**Errors**: None (errors reported in response)

---

### 9. `subscribe_events`

Subscribe to daemon events (for real-time updates).

**Parameters**:
```json
{
  "events": ["project_switch", "window_update"]
}
```

**Available Events**:
- `project_switch`: Active project changed
- `window_update`: Window added/removed/modified
- `connection_status`: i3 connection status changed

**Returns**:
```json
{
  "success": true,
  "subscription_id": "sub-1234"
}
```

**Event Notifications** (sent asynchronously after subscription):
```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "subscription_id": "sub-1234",
    "event_type": "project_switch",
    "data": {
      "previous_project": "stacks",
      "new_project": "nixos"
    }
  }
}
```

**Errors**:
- `-32602`: Invalid event type

---

### 10. `unsubscribe_events`

Unsubscribe from daemon events.

**Parameters**:
```json
{
  "subscription_id": "sub-1234"
}
```

**Returns**:
```json
{
  "success": true
}
```

**Errors**:
- `-32602`: Invalid subscription ID

---

## Usage Examples

### CLI Query (Bash)

```bash
#!/usr/bin/env bash
# Query active project

SOCKET="$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock"

request='{"jsonrpc":"2.0","id":1,"method":"get_active_project"}'

response=$(echo "$request" | nc -U "$SOCKET" -W 1)

project=$(echo "$response" | jq -r '.result.project_name')

echo "Active project: $project"
```

### Python Client

```python
import socket
import json
from pathlib import Path

def query_daemon(method, params=None):
    """Send JSON-RPC request to daemon."""
    socket_path = Path.home() / ".local/run/i3-project-daemon/ipc.sock"

    request = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": method,
        "params": params or {}
    }

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(str(socket_path))
        sock.sendall((json.dumps(request) + "\n").encode())

        response = b""
        while b"\n" not in response:
            response += sock.recv(4096)

        return json.loads(response.decode())

# Usage
status = query_daemon("get_status")
print(f"Daemon uptime: {status['result']['uptime_seconds']}s")

projects = query_daemon("get_projects")
for project in projects['result']['projects']:
    print(f"- {project['display_name']} ({project['window_count']} windows)")
```

---

## Security

### Access Control

- Socket permissions: `0600` (owner read/write only)
- Socket owner: User running the daemon
- No authentication required (UNIX socket permissions provide access control)

### Rate Limiting

- Max 100 requests per second per connection
- Connections exceeding limit are disconnected
- Prevents DoS attacks from malicious clients

### Timeout

- Idle connections closed after 30 seconds of inactivity
- Prevents resource exhaustion from abandoned connections

---

## Implementation Notes

### Socket Creation

```python
import socket
import os
from pathlib import Path

socket_dir = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp')) / 'i3-project-daemon'
socket_dir.mkdir(parents=True, exist_ok=True)

socket_path = socket_dir / 'ipc.sock'

# Remove stale socket
if socket_path.exists():
    socket_path.unlink()

# Create socket
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(str(socket_path))
sock.listen(5)

# Set permissions
os.chmod(socket_path, 0o600)
```

### Request Handling

```python
import json

def handle_request(request_data):
    """Handle JSON-RPC request."""
    try:
        request = json.loads(request_data)

        # Validate JSON-RPC 2.0
        if request.get('jsonrpc') != '2.0':
            return error_response(request.get('id'), -32600, "Invalid Request")

        # Dispatch method
        method = request.get('method')
        params = request.get('params', {})

        if method == 'get_status':
            result = get_status()
        elif method == 'get_active_project':
            result = get_active_project()
        # ... other methods

        return success_response(request['id'], result)

    except json.JSONDecodeError:
        return error_response(None, -32700, "Parse error")
    except Exception as e:
        return error_response(request.get('id'), -32603, "Internal error", str(e))
```

---

## Testing

### Manual Testing

```bash
# Test connection
echo '{"jsonrpc":"2.0","id":1,"method":"get_status"}' | nc -U "$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock"

# Test project query
echo '{"jsonrpc":"2.0","id":2,"method":"get_projects"}' | nc -U "$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock"

# Test project switch
echo '{"jsonrpc":"2.0","id":3,"method":"switch_project","params":{"project_name":"nixos"}}' | nc -U "$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock"
```

### Automated Testing

```python
import pytest
import socket
import json

@pytest.fixture
def daemon_client():
    """Connect to daemon socket."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect("/run/user/1000/i3-project-daemon/ipc.sock")
    yield sock
    sock.close()

def test_get_status(daemon_client):
    """Test get_status method."""
    request = {"jsonrpc": "2.0", "id": 1, "method": "get_status"}
    daemon_client.sendall((json.dumps(request) + "\n").encode())

    response = json.loads(daemon_client.recv(4096).decode())

    assert response['jsonrpc'] == '2.0'
    assert response['id'] == 1
    assert 'result' in response
    assert response['result']['is_connected'] in [True, False]
```

---

## Versioning

**Current Version**: 1.0.0

**Compatibility Policy**:
- **MAJOR**: Breaking changes to request/response format
- **MINOR**: New methods added (backward compatible)
- **PATCH**: Bug fixes, documentation updates

Clients should check daemon version via `get_status` response and handle version mismatches gracefully.
