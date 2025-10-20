# JSON-RPC API Contract: i3 Project Daemon Testing Extensions

**Feature**: 018-create-a-new
**Date**: 2025-10-20
**Protocol**: JSON-RPC 2.0 over UNIX socket
**Socket Path**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`

## Overview

This document defines JSON-RPC API extensions to the i3 project event daemon (Feature 015) to support the testing and debugging framework. Most required functionality already exists in the daemon's IPC server - this contract documents the existing API and identifies minimal new methods needed.

## Existing API (Feature 015)

The following methods are already implemented and will be used by the test framework without modification:

### get_status

Get daemon health and statistics.

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
    "status": "running",
    "connected": true,
    "uptime_seconds": 3600.5,
    "window_count": 5,
    "workspace_count": 3,
    "active_project": "nixos",
    "event_count": 1250,
    "error_count": 0
  },
  "id": 1
}
```

**Usage**: Test framework uses this to validate daemon is running and healthy before test execution.

---

### get_active_project

Get currently active project.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_active_project",
  "params": {},
  "id": 2
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project_name": "nixos",
    "is_global": false
  },
  "id": 2
}
```

**Usage**: Core assertion validation - verify project switch occurred correctly.

---

### get_projects

List all configured projects with window counts.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_projects",
  "params": {},
  "id": 3
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "projects": {
      "nixos": {
        "display_name": "NixOS",
        "icon": "",
        "directory": "/etc/nixos",
        "window_count": 3
      },
      "stacks": {
        "display_name": "Stacks",
        "icon": "",
        "directory": "/home/user/stacks",
        "window_count": 2
      }
    }
  },
  "id": 3
}
```

**Usage**: Validate projects exist, verify window counts after test actions.

---

### get_windows

Query windows with optional project filter.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_windows",
  "params": {
    "project": "nixos"  // Optional filter
  },
  "id": 4
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "windows": [
      {
        "window_id": 94557483810864,
        "class": "Ghostty",
        "title": "nvim",
        "project": "nixos",
        "workspace": "1"
      },
      {
        "window_id": 94557483810912,
        "class": "code-oss",
        "title": "flake.nix",
        "project": "nixos",
        "workspace": "2"
      }
    ]
  },
  "id": 4
}
```

**Usage**: Validate window marking, verify windows assigned to correct projects.

---

### get_events

Retrieve recent events from event buffer for diagnostics.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_events",
  "params": {
    "limit": 100,           // Optional, default 100
    "event_type": "window"  // Optional filter: window, workspace, output, tick
  },
  "id": 5
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "events": [
      {
        "event_id": 1250,
        "event_type": "window::new",
        "timestamp": "2025-10-20T10:30:00.123456Z",
        "window_id": 94557483810864,
        "window_class": "Ghostty",
        "workspace_name": "1",
        "project_name": "nixos",
        "tick_payload": null,
        "processing_duration_ms": 15.2,
        "error": null
      }
    ],
    "stats": {
      "total_events": 1250,
      "buffer_size": 500,
      "max_size": 500
    }
  },
  "id": 5
}
```

**Usage**: Event stream validation, verify expected events occurred, diagnostic capture.

---

### list_monitors

List all connected JSON-RPC clients (monitor tools).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "list_monitors",
  "params": {},
  "id": 6
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "monitors": [
      {
        "monitor_id": 0,
        "peer": "/tmp/tmux-1000/default",
        "subscribed": true
      }
    ],
    "total_clients": 1,
    "subscribed_clients": 1
  },
  "id": 6
}
```

**Usage**: Diagnostic capture, verify monitor tool connections.

---

### subscribe_events

Subscribe/unsubscribe from real-time event stream.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "subscribe_events",
  "params": {
    "subscribe": true  // true to subscribe, false to unsubscribe
  },
  "id": 7
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "subscribed": true,
    "message": "Event subscription enabled",
    "subscriber_count": 1
  },
  "id": 7
}
```

**Event Notifications** (sent to subscribed clients):
```json
{
  "jsonrpc": "2.0",
  "method": "event_notification",
  "params": {
    "event_id": 1251,
    "event_type": "tick",
    "timestamp": "2025-10-20T10:30:05.123456Z",
    "tick_payload": "project_switch:nixos",
    "processing_duration_ms": 8.5
  }
}
```

**Usage**: Real-time event monitoring during test execution, live validation.

---

## New API Methods (Feature 018)

The following new methods are minimal additions needed for testing framework:

### get_diagnostic_state

Capture complete diagnostic snapshot in a single call (optimization for diagnostic mode).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_diagnostic_state",
  "params": {
    "include_events": true,      // Include event buffer
    "event_limit": 500,          // Number of events to include
    "include_tree": true,        // Include i3 tree dump
    "include_monitors": true     // Include monitor client list
  },
  "id": 8
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "daemon_state": {
      "status": "running",
      "connected": true,
      "active_project": "nixos",
      "window_count": 5,
      "workspace_count": 3,
      "uptime_seconds": 3600.5,
      "event_count": 1250,
      "error_count": 0
    },
    "projects": { /* same as get_projects */ },
    "windows": { /* same as get_windows */ },
    "events": [ /* same as get_events */ ],
    "monitors": { /* same as list_monitors */ },
    "i3_tree": { /* i3 tree structure */ },
    "capture_duration_ms": 245.8
  },
  "id": 8
}
```

**Rationale**: Reduces round-trips for diagnostic capture. Single atomic snapshot ensures consistency.

**Implementation**: Combines existing queries into single response. Already has access to i3 connection for tree dump.

---

## API Usage Patterns

### Test Scenario Validation Pattern

```python
# 1. Check daemon health
status = await client.call("get_status", {})
assert status["status"] == "running"

# 2. Execute test action (via CLI, not API)
subprocess.run(["i3-project-switch", "nixos"])
await asyncio.sleep(0.5)

# 3. Validate state changed
active_project = await client.call("get_active_project", {})
assert active_project["project_name"] == "nixos"

# 4. Validate windows marked correctly
windows = await client.call("get_windows", {"project": "nixos"})
assert len(windows["windows"]) > 0

# 5. Validate events recorded
events = await client.call("get_events", {"limit": 10, "event_type": "tick"})
assert any(e["tick_payload"] == "project_switch:nixos" for e in events["events"])
```

### Diagnostic Capture Pattern

```python
# Single call captures everything
diagnostic = await client.call("get_diagnostic_state", {
    "include_events": True,
    "event_limit": 500,
    "include_tree": True,
    "include_monitors": True
})

# Save to JSON file
with open(f"diagnostic-{timestamp}.json", "w") as f:
    json.dump(diagnostic, f, indent=2)
```

### Real-time Monitoring Pattern

```python
# Subscribe to events
await client.call("subscribe_events", {"subscribe": True})

# Listen for notifications
async for notification in client.listen_notifications():
    if notification["method"] == "event_notification":
        event = notification["params"]
        print(f"Event: {event['event_type']} at {event['timestamp']}")
```

## Error Handling

All methods follow JSON-RPC 2.0 error convention:

**Error Response**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32603,
    "message": "Internal error: Failed to connect to i3 IPC"
  },
  "id": 1
}
```

**Standard Error Codes**:
- `-32700`: Parse error (invalid JSON)
- `-32600`: Invalid request (missing fields)
- `-32601`: Method not found
- `-32602`: Invalid params (wrong parameter types)
- `-32603`: Internal error (daemon error)

**Test Framework Error Handling**:
- Retry on connection errors (daemon not ready)
- Fail fast on method not found (API mismatch)
- Log internal errors for debugging
- Timeout after 5 seconds on any call

## Connection Management

### Socket Connection

```python
import asyncio
import json

async def connect_daemon():
    socket_path = os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
        "i3-project-daemon/ipc.sock"
    )
    reader, writer = await asyncio.open_unix_connection(socket_path)
    return reader, writer

async def call_method(reader, writer, method, params, request_id=1):
    request = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": request_id
    }
    writer.write(json.dumps(request).encode() + b"\n")
    await writer.drain()

    response_line = await reader.readline()
    response = json.loads(response_line.decode())

    if "error" in response:
        raise DaemonError(response["error"])

    return response["result"]
```

### Connection Pooling

Test framework should reuse connection across multiple calls:

```python
class DaemonClient:
    def __init__(self):
        self.reader = None
        self.writer = None

    async def connect(self):
        self.reader, self.writer = await connect_daemon()

    async def call(self, method, params):
        if not self.reader:
            await self.connect()
        return await call_method(self.reader, self.writer, method, params)

    async def close(self):
        if self.writer:
            self.writer.close()
            await self.writer.wait_closed()
```

## API Versioning

Current API version: **1.0.0**

Version compatibility:
- **Major version**: Breaking changes (remove methods, change response structure)
- **Minor version**: Add new methods, add optional parameters
- **Patch version**: Bug fixes, no API changes

Test framework should:
1. Query daemon version (TBD: add get_version method?)
2. Validate compatibility (fail if major version mismatch)
3. Gracefully degrade if optional features unavailable

## Summary

**Existing API Coverage**: 95%

The existing daemon API (Feature 015) provides nearly all functionality needed:
- ✅ Health checks (`get_status`)
- ✅ State queries (`get_active_project`, `get_projects`, `get_windows`)
- ✅ Event history (`get_events`)
- ✅ Real-time monitoring (`subscribe_events`)
- ✅ Monitor client tracking (`list_monitors`)

**New Requirements**: 5%

Only one new method needed:
- `get_diagnostic_state`: Optimized single-call diagnostic capture

**No Breaking Changes**: All enhancements are additive. Existing clients (Feature 017 monitor tool) continue working without modification.
