# JSON-RPC API Contract: i3 Project Daemon Extensions

**Branch**: `017-now-lets-create` | **Date**: 2025-10-20

## Overview

This document defines the extended JSON-RPC API for the i3 project daemon to support the monitor tool. All methods follow JSON-RPC 2.0 specification.

## Connection

**Socket Path**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`

**Protocol**: JSON-RPC 2.0 over Unix domain socket (SOCK_STREAM)

**Request Format**: JSON object followed by newline (`\n`)

**Response Format**: JSON object followed by newline (`\n`)

## Existing Methods (For Reference)

These methods already exist in the daemon and will be used by the monitor tool.

### get_status

Retrieve daemon status and statistics.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_status",
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
    "connection_status": "connected",
    "i3_socket_path": "/run/user/1000/i3/ipc-socket.1234",
    "uptime_seconds": 3600.5,
    "events_processed": 1523,
    "error_count": 0,
    "active_project": "nixos",
    "tracked_windows": 8
  },
  "id": 1
}
```

**Fields**:
- `status`: Always "running" if daemon responds
- `connected`: Boolean, true if connected to i3 IPC
- `connection_status`: "connected" | "disconnected" | "connecting"
- `i3_socket_path`: Path to i3 IPC socket
- `uptime_seconds`: Daemon uptime in seconds (float)
- `events_processed`: Total i3 events processed
- `error_count`: Number of errors during event processing
- `active_project`: Current active project name or null for global mode
- `tracked_windows`: Number of windows with project marks

### get_active_project

Get the currently active project.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_active_project",
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

**Fields**:
- `project_name`: Current project name or null
- `is_global`: Boolean, true when project_name is null

### get_projects

List all configured projects with window counts.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_projects",
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
        "directory": "/home/user/code/stacks",
        "window_count": 5
      }
    }
  },
  "id": 3
}
```

### get_windows

Query tracked windows with optional filtering.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_windows",
  "params": {
    "project": "nixos"  // Optional: filter by project
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
        "window_id": 94558,
        "class": "Ghostty",
        "title": "~/code/nixos",
        "project": "nixos",
        "workspace": "1"
      },
      {
        "window_id": 94562,
        "class": "code",
        "title": "NixOS Configuration",
        "project": "nixos",
        "workspace": "2"
      }
    ]
  },
  "id": 4
}
```

**Parameters**:
- `project` (optional): Filter windows by project name

## New Methods (To Be Implemented)

### list_monitors

Retrieve detected monitors with workspace assignments.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "list_monitors",
  "id": 5
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "monitors": [
      {
        "name": "eDP-1",
        "width": 1920,
        "height": 1080,
        "refresh_rate": 60.0,
        "primary": true,
        "assigned_workspaces": [1, 2],
        "active_workspace": 1,
        "connected": true,
        "enabled": true
      },
      {
        "name": "HDMI-1",
        "width": 2560,
        "height": 1440,
        "refresh_rate": 60.0,
        "primary": false,
        "assigned_workspaces": [3, 4, 5],
        "active_workspace": 3,
        "connected": true,
        "enabled": true
      }
    ]
  },
  "id": 5
}
```

**Implementation**:
- Query i3 outputs via `Connection.get_outputs()`
- Query i3 workspaces via `Connection.get_workspaces()`
- Map workspaces to outputs based on `output` field
- Determine active workspace from `visible=true` and `focused=true`

**Fields**:
- `name`: Output name from i3 (e.g., "eDP-1", "HDMI-1")
- `width`, `height`: Current resolution in pixels
- `refresh_rate`: Refresh rate in Hz (float)
- `primary`: Boolean, true if this is the primary output
- `assigned_workspaces`: List of workspace numbers on this output
- `active_workspace`: Currently visible workspace number or null
- `connected`: Boolean, true if output is physically connected
- `enabled`: Boolean, true if output is enabled in i3

### subscribe_events

Subscribe to real-time event notifications.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "subscribe_events",
  "params": {
    "event_types": ["window", "workspace"]  // Optional: filter by type prefix
  },
  "id": 6
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "subscribed": true,
    "subscription_id": "sub_12345",
    "event_types": ["window", "workspace"]
  },
  "id": 6
}
```

**Behavior**:
- Client connection remains open after response
- Daemon will send JSON-RPC notifications (no `id` field) for matching events
- Client must keep socket open to receive notifications
- Subscription ends when client closes connection

**Parameters**:
- `event_types` (optional): List of event type prefixes to filter ("window", "workspace", "tick"). Empty list or omitted = all events.

**Notifications Sent After Subscription**:

Each event triggers a notification:

```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "event_id": 1523,
    "event_type": "window::new",
    "timestamp": "2025-10-20T14:23:45.123456",
    "window_id": 94558,
    "window_class": "Ghostty",
    "workspace_name": "1",
    "project_name": "nixos",
    "tick_payload": null,
    "processing_duration_ms": 2.5,
    "error": null
  }
}
```

**Notification Fields**:
- `event_id`: Incremental event counter
- `event_type`: i3 event type (e.g., "window::new", "tick", "workspace::init")
- `timestamp`: ISO 8601 timestamp
- `window_id`: Window ID if applicable, else null
- `window_class`: Window class if applicable, else null
- `workspace_name`: Workspace name if applicable, else null
- `project_name`: Project name if applicable, else null
- `tick_payload`: Tick event payload if type is "tick", else null
- `processing_duration_ms`: Time daemon took to handle event (float)
- `error`: Error message if event processing failed, else null

### get_events (Extended)

Retrieve historical events from daemon's circular buffer.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_events",
  "params": {
    "limit": 50,           // Optional: max events to return (default: 100, max: 500)
    "event_type": "window" // Optional: filter by event type prefix
  },
  "id": 7
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "events": [
      {
        "event_id": 1520,
        "event_type": "window::new",
        "timestamp": "2025-10-20T14:20:30.123456",
        "window_id": 94550,
        "window_class": "firefox",
        "workspace_name": "3",
        "project_name": null,
        "tick_payload": null,
        "processing_duration_ms": 1.2,
        "error": null
      },
      {
        "event_id": 1521,
        "event_type": "tick",
        "timestamp": "2025-10-20T14:21:00.000000",
        "window_id": null,
        "window_class": null,
        "workspace_name": null,
        "project_name": "nixos",
        "tick_payload": "project:nixos",
        "processing_duration_ms": 5.8,
        "error": null
      },
      {
        "event_id": 1522,
        "event_type": "window::close",
        "timestamp": "2025-10-20T14:22:15.456789",
        "window_id": 94520,
        "window_class": "code",
        "workspace_name": "2",
        "project_name": "stacks",
        "tick_payload": null,
        "processing_duration_ms": 0.8,
        "error": null
      }
    ],
    "total_events": 1523,
    "buffer_size": 500
  },
  "id": 7
}
```

**Parameters**:
- `limit` (optional): Maximum events to return (default: 100, max: 500)
- `event_type` (optional): Filter by event type prefix (e.g., "window", "workspace")

**Response Fields**:
- `events`: Array of event entries (most recent first)
- `total_events`: Total events processed since daemon start
- `buffer_size`: Maximum buffer capacity (500)

**Implementation**:
- Daemon maintains `collections.deque(maxlen=500)` for events
- Events added in FIFO order (oldest evicted when full)
- Query returns most recent N matching events

## Error Responses

All methods may return JSON-RPC errors:

**Method Not Found**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32601,
    "message": "Method not found: unknown_method"
  },
  "id": 8
}
```

**Invalid Parameters**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params: limit must be <= 500"
  },
  "id": 9
}
```

**Internal Error**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32603,
    "message": "Internal error: Failed to query i3 outputs"
  },
  "id": 10
}
```

**Parse Error** (invalid JSON):
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32700,
    "message": "Parse error"
  },
  "id": null
}
```

## Implementation Requirements

### Daemon Changes Required

1. **Add EventBuffer to state.py**:
   - `collections.deque(maxlen=500)` for event storage
   - Add event to buffer in each handler in `handlers.py`
   - Include event metadata: id, type, timestamp, window_id, project, duration

2. **Add list_monitors to ipc_server.py**:
   - Query `Connection.get_outputs()`
   - Query `Connection.get_workspaces()`
   - Map workspaces to outputs
   - Return formatted monitor list

3. **Add subscribe_events to ipc_server.py**:
   - Maintain `set[SubscribedClient]` tracking subscriptions
   - Add client to set on subscribe request
   - Remove client on disconnect
   - Broadcast event notifications to subscribed clients

4. **Extend get_events in ipc_server.py**:
   - Return events from EventBuffer
   - Apply limit and event_type filtering
   - Return total_events and buffer_size metadata

5. **Update event handlers in handlers.py**:
   - After processing each event, create EventEntry
   - Add EventEntry to EventBuffer
   - Trigger broadcast to subscribed clients

## Connection Management

### Client Reconnection Pattern

When monitor tool loses connection:

1. Close existing socket
2. Wait with exponential backoff: 1s, 2s, 4s, 8s, 16s
3. Attempt reconnect on each retry
4. After 5 failed attempts (total ~30s), exit with error
5. Display retry status to user during backoff

### Subscription Lifecycle

```
Client connects → subscribe_events request → daemon adds to subscribed_clients
                                          ↓
                              daemon broadcasts event notifications
                                          ↓
Client disconnects → daemon removes from subscribed_clients
```

## Testing Checklist

- [ ] `list_monitors` returns all connected outputs with correct workspace assignments
- [ ] `subscribe_events` successfully subscribes client and receives notifications
- [ ] Event notifications include all required fields with correct types
- [ ] `get_events` returns events in reverse chronological order (most recent first)
- [ ] `get_events` filtering by `event_type` returns only matching events
- [ ] `get_events` respects `limit` parameter
- [ ] EventBuffer correctly evicts oldest events when full (500 capacity)
- [ ] Multiple clients can subscribe simultaneously without interference
- [ ] Client disconnect properly removes subscription
- [ ] Error responses return correct JSON-RPC error codes

---

**API Contract Status**: ✅ Complete - All methods, parameters, and responses defined
