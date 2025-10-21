# Daemon IPC Contract: i3pm

**Branch**: `019-re-explore-and` | **Date**: 2025-10-20 | **Phase**: Phase 1 Design
**Existing Daemon**: Feature 015 (i3-project-event-listener)

## Overview

The `i3pm` CLI/TUI communicates with the existing i3-project-event-listener daemon via JSON-RPC over Unix socket. This contract defines all daemon methods, request/response formats, and error handling.

**Socket Path**: `~/.cache/i3-project/daemon.sock`

**Protocol**: JSON-RPC 2.0 over Unix domain socket

---

## JSON-RPC Protocol

### Request Format

```json
{
  "jsonrpc": "2.0",
  "method": "get_status",
  "params": {},
  "id": 1
}
```

### Response Format (Success)

```json
{
  "jsonrpc": "2.0",
  "result": {
    "daemon_connected": true,
    "uptime_seconds": 9240.5
  },
  "id": 1
}
```

### Response Format (Error)

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Invalid request"
  },
  "id": 1
}
```

### Error Codes

| Code | Meaning |
|------|---------|
| `-32700` | Parse error (invalid JSON) |
| `-32600` | Invalid request (malformed JSON-RPC) |
| `-32601` | Method not found |
| `-32602` | Invalid params |
| `-32603` | Internal error |
| `-1` | Application error (custom) |

---

## Daemon Methods

### 1. `get_status`

**Purpose**: Get daemon status and active project.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_status",
  "params": {},
  "id": 1
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "daemon_connected": true,
    "uptime_seconds": 9240.5,
    "pid": 12345,
    "active_project": "nixos",
    "total_windows": 12,
    "tracked_windows": 5,
    "event_count": 1234,
    "event_rate_per_second": 2.3
  },
  "id": 1
}
```

**No Active Project**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "daemon_connected": true,
    "uptime_seconds": 9240.5,
    "pid": 12345,
    "active_project": null,
    "total_windows": 12,
    "tracked_windows": 0,
    "event_count": 1234,
    "event_rate_per_second": 2.3
  },
  "id": 1
}
```

---

### 2. `get_events`

**Purpose**: Get recent daemon events (for debugging/monitoring).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_events",
  "params": {
    "limit": 20,
    "event_type": "window"
  },
  "id": 2
}
```

**Parameters**:
- `limit` (optional, default 20): Number of events to return
- `event_type` (optional): Filter by type: "window", "workspace", "tick", "output"

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "events": [
      {
        "timestamp": "2025-10-20T14:30:15Z",
        "event_type": "window::new",
        "details": {
          "window_id": 12345,
          "window_class": "Ghostty",
          "mark": "project:nixos"
        }
      },
      {
        "timestamp": "2025-10-20T14:30:10Z",
        "event_type": "workspace::focus",
        "details": {
          "workspace": 1,
          "output": "eDP-1"
        }
      }
    ],
    "total": 2
  },
  "id": 2
}
```

---

### 3. `get_windows`

**Purpose**: Get list of tracked windows.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_windows",
  "params": {
    "project": "nixos"
  },
  "id": 3
}
```

**Parameters**:
- `project` (optional): Filter by project name

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "windows": [
      {
        "id": 12345,
        "class": "Ghostty",
        "title": "nvim flake.nix",
        "workspace": 1,
        "output": "eDP-1",
        "marks": ["project:nixos"],
        "geometry": {
          "width": 1920,
          "height": 1080,
          "x": 0,
          "y": 0
        }
      }
    ],
    "total": 1
  },
  "id": 3
}
```

---

### 4. `switch_project`

**Purpose**: Switch to a different project.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "switch_project",
  "params": {
    "project_name": "nixos"
  },
  "id": 4
}
```

**Parameters**:
- `project_name` (required): Project name to switch to

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "project": "nixos",
    "marked_windows": 5
  },
  "id": 4
}
```

**Error (project not found)**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -1,
    "message": "Project 'invalid' not found"
  },
  "id": 4
}
```

---

### 5. `clear_project`

**Purpose**: Clear active project (return to global mode).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "clear_project",
  "params": {},
  "id": 5
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "previous_project": "nixos"
  },
  "id": 5
}
```

---

### 6. `reload_config`

**Purpose**: Reload project configurations from disk.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "reload_config",
  "params": {},
  "id": 6
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "projects_loaded": 3,
    "app_classes_loaded": true
  },
  "id": 6
}
```

---

## Client Implementation

### DaemonClient Class

```python
# i3_project_manager/core/daemon_client.py
import asyncio
import json
from pathlib import Path
from typing import Optional, Dict, List, Any

class DaemonClient:
    """IPC client for i3-project-event-listener daemon."""

    def __init__(self, socket_path: Path = Path.home() / ".cache/i3-project/daemon.sock"):
        self.socket_path = socket_path
        self._reader: Optional[asyncio.StreamReader] = None
        self._writer: Optional[asyncio.StreamWriter] = None
        self._request_id = 0

    async def connect(self) -> None:
        """Connect to daemon socket."""
        if not self.socket_path.exists():
            raise ConnectionError("Daemon socket not found. Is the daemon running?")

        self._reader, self._writer = await asyncio.open_unix_connection(self.socket_path)

    async def call(self, method: str, params: Dict[str, Any] = None) -> Any:
        """Send JSON-RPC request to daemon."""
        if not self._writer:
            await self.connect()

        self._request_id += 1

        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self._request_id
        }

        # Send request
        request_json = json.dumps(request) + "\n"
        self._writer.write(request_json.encode())
        await self._writer.drain()

        # Read response
        response_line = await self._reader.readline()
        if not response_line:
            raise ConnectionError("Daemon closed connection")

        response = json.loads(response_line.decode())

        # Handle error
        if "error" in response:
            error = response["error"]
            raise DaemonError(error["message"], error["code"])

        return response["result"]

    async def close(self) -> None:
        """Close connection."""
        if self._writer:
            self._writer.close()
            await self._writer.wait_closed()

    # High-level methods (convenience wrappers)

    async def get_status(self) -> Dict[str, Any]:
        """Get daemon status."""
        return await self.call("get_status")

    async def get_active_project(self) -> Optional[str]:
        """Get current active project."""
        status = await self.get_status()
        return status.get("active_project")

    async def get_events(self, limit: int = 20, event_type: Optional[str] = None) -> List[Dict]:
        """Get recent events."""
        result = await self.call("get_events", {"limit": limit, "event_type": event_type})
        return result["events"]

    async def get_windows(self, project: Optional[str] = None) -> List[Dict]:
        """Get tracked windows."""
        result = await self.call("get_windows", {"project": project})
        return result["windows"]

    async def switch_project(self, project_name: str) -> None:
        """Switch to project."""
        await self.call("switch_project", {"project_name": project_name})

    async def clear_project(self) -> str:
        """Clear active project."""
        result = await self.call("clear_project")
        return result["previous_project"]

    async def reload_config(self) -> None:
        """Reload configurations."""
        await self.call("reload_config")


class DaemonError(Exception):
    """Daemon RPC error."""

    def __init__(self, message: str, code: int):
        super().__init__(message)
        self.code = code
```

### Usage Examples

```python
# CLI command
async def cmd_switch(args):
    """Switch to project (CLI command)."""
    client = DaemonClient()

    try:
        await client.switch_project(args.project_name)
        print(f"✓ Switched to project: {args.project_name}")
    except DaemonError as e:
        print(f"✗ Error: {e}", file=sys.stderr)
        sys.exit(1)
    except ConnectionError as e:
        print(f"✗ Daemon not running: {e}", file=sys.stderr)
        sys.exit(2)
    finally:
        await client.close()

# TUI reactive widget
class ProjectStatusWidget(Static):
    """Display active project (auto-updates)."""

    active_project: reactive[Optional[str]] = reactive(None)

    def on_mount(self) -> None:
        """Start polling daemon."""
        self.set_interval(1.0, self.refresh_status)

    async def refresh_status(self) -> None:
        """Poll daemon for active project."""
        client = DaemonClient()
        try:
            self.active_project = await client.get_active_project()
        except (ConnectionError, DaemonError):
            self.active_project = None
        finally:
            await client.close()

    def watch_active_project(self, old: Optional[str], new: Optional[str]) -> None:
        """Update UI when active project changes."""
        if new:
            self.update(f"Active: {new}")
        else:
            self.update("No active project")
```

---

## Error Handling Best Practices

### Connection Errors

```python
try:
    await client.connect()
except ConnectionError:
    # Daemon not running
    print("✗ Daemon not running. Start with: systemctl --user start i3-project-event-listener")
    sys.exit(2)
```

### Timeout Handling

```python
try:
    result = await asyncio.wait_for(client.get_status(), timeout=1.0)
except asyncio.TimeoutError:
    print("✗ Daemon not responding")
    sys.exit(2)
```

### Graceful Degradation (TUI)

```python
async def refresh_status(self) -> None:
    """Poll daemon with graceful degradation."""
    try:
        status = await client.get_status()
        self.daemon_connected = True
        self.active_project = status["active_project"]
    except (ConnectionError, DaemonError):
        # Daemon not available - continue with cached state
        self.daemon_connected = False
```

---

## Performance Considerations

- **Connection Pooling**: Reuse connection for multiple requests (CLI batch operations)
- **Timeout**: 1 second default timeout for all requests
- **Retry**: No automatic retry (fail fast, let user retry)
- **Caching**: TUI caches daemon responses (1 second refresh interval)

---

## Summary

**Protocol**: JSON-RPC 2.0 over Unix socket
**Methods**: 6 daemon methods (status, events, windows, switch, clear, reload)
**Client**: Async Python client with connection pooling
**Error Handling**: Graceful degradation, clear error messages
**Performance**: <100ms latency for all methods

**Next Steps**:
1. Create config schema (JSON Schema for validation)
2. Generate quickstart guide
3. Implement DaemonClient in `core/daemon_client.py`
