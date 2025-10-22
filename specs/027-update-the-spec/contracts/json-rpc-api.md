# JSON-RPC API Contract: i3pm CLI ↔ Daemon

**Version**: 2.0 (Deno CLI)
**Protocol**: JSON-RPC 2.0
**Transport**: Unix Socket
**Socket Path**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
**Format**: Newline-delimited JSON

---

## Protocol Basics

### Transport

- **Type**: Unix domain socket (stream-oriented)
- **Path Discovery**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock` or `/run/user/<uid>/i3-project-daemon/ipc.sock`
- **Message Framing**: Each JSON-RPC message terminated by newline (`\n`)
- **Encoding**: UTF-8
- **Bi-directional**: Client sends requests, server sends responses + notifications

### JSON-RPC 2.0 Structure

**Request** (client → server):
```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": { /* optional parameters */ },
  "id": 1
}
```

**Response** (server → client):
```json
{
  "jsonrpc": "2.0",
  "result": { /* success result */ },
  "id": 1
}
```

**Error Response**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Invalid Request",
    "data": { /* optional additional info */ }
  },
  "id": 1
}
```

**Notification** (server → client, no id):
```json
{
  "jsonrpc": "2.0",
  "method": "event_notification",
  "params": { /* notification data */ }
}
```

---

## Methods

### Project Management

#### `switch_project`

Activate a project context, hiding windows not scoped to the project.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "switch_project",
  "params": {
    "project_name": "nixos"
  },
  "id": 1
}
```

**Response** (Success):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project_name": "nixos",
    "windows_hidden": 5,
    "windows_shown": 3
  },
  "id": 1
}
```

**Response** (Error - Project Not Found):
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params",
    "data": {
      "reason": "Project 'unknown' does not exist",
      "available_projects": ["nixos", "stacks", "personal"]
    }
  },
  "id": 1
}
```

---

#### `clear_project`

Deactivate project context, showing all windows (global mode).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "clear_project",
  "params": {},
  "id": 2
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "previous_project": "nixos",
    "windows_shown": 5
  },
  "id": 2
}
```

---

#### `get_current_project`

Get currently active project name (or null for global mode).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_current_project",
  "params": {},
  "id": 3
}
```

**Response** (Project Active):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project_name": "nixos"
  },
  "id": 3
}
```

**Response** (Global Mode):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project_name": null
  },
  "id": 3
}
```

---

#### `list_projects`

Get all configured projects.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "list_projects",
  "params": {},
  "id": 4
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "projects": [
      {
        "name": "nixos",
        "display_name": "NixOS",
        "icon": "",
        "directory": "/etc/nixos",
        "scoped_classes": ["Ghostty", "code-url-handler"],
        "created_at": 1698000000,
        "last_used_at": 1698012345
      },
      {
        "name": "stacks",
        "display_name": "Stacks",
        "icon": "",
        "directory": "/home/user/projects/stacks",
        "scoped_classes": ["Ghostty", "code-url-handler"],
        "created_at": 1698000100,
        "last_used_at": 1698010000
      }
    ]
  },
  "id": 4
}
```

---

#### `get_project`

Get details for a specific project.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_project",
  "params": {
    "project_name": "nixos"
  },
  "id": 5
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "name": "nixos",
    "display_name": "NixOS",
    "icon": "",
    "directory": "/etc/nixos",
    "scoped_classes": ["Ghostty", "code-url-handler"],
    "created_at": 1698000000,
    "last_used_at": 1698012345
  },
  "id": 5
}
```

---

#### `create_project`

Create a new project configuration.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "create_project",
  "params": {
    "name": "newproject",
    "display_name": "New Project",
    "icon": "",
    "directory": "/home/user/projects/newproject"
  },
  "id": 6
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "name": "newproject",
    "display_name": "New Project",
    "icon": "",
    "directory": "/home/user/projects/newproject",
    "scoped_classes": ["Ghostty", "code-url-handler"],
    "created_at": 1698020000,
    "last_used_at": 1698020000
  },
  "id": 6
}
```

---

#### `delete_project`

Delete a project configuration (does not affect windows).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "delete_project",
  "params": {
    "project_name": "oldproject"
  },
  "id": 7
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "deleted": true,
    "project_name": "oldproject"
  },
  "id": 7
}
```

---

### Window State Queries

#### `get_windows`

Get window state for all outputs, workspaces, and windows.

**Request** (No Filter):
```json
{
  "jsonrpc": "2.0",
  "method": "get_windows",
  "params": {},
  "id": 10
}
```

**Request** (With Filter):
```json
{
  "jsonrpc": "2.0",
  "method": "get_windows",
  "params": {
    "filter": {
      "workspace": "1",
      "hidden": false
    }
  },
  "id": 10
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "outputs": [
      {
        "name": "Virtual-1",
        "active": true,
        "primary": true,
        "geometry": { "x": 0, "y": 0, "width": 1920, "height": 1080 },
        "current_workspace": "1",
        "workspaces": [
          {
            "number": 1,
            "name": "1",
            "focused": true,
            "visible": true,
            "output": "Virtual-1",
            "windows": [
              {
                "id": 94608348372768,
                "class": "Ghostty",
                "instance": "ghostty",
                "title": "nvim",
                "workspace": "1",
                "output": "Virtual-1",
                "marks": ["project:nixos"],
                "focused": true,
                "hidden": false,
                "floating": false,
                "fullscreen": false,
                "geometry": { "x": 0, "y": 0, "width": 960, "height": 1080 }
              }
            ]
          }
        ]
      }
    ]
  },
  "id": 10
}
```

---

#### `get_window_tree`

Get raw i3 window tree structure (for debugging).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_window_tree",
  "params": {},
  "id": 11
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "tree": {
      "id": 1,
      "type": "root",
      "nodes": [
        // Full i3 tree structure (complex, used for debugging)
      ]
    }
  },
  "id": 11
}
```

---

### Daemon Status

#### `get_status`

Get daemon status and connection information.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_status",
  "params": {},
  "id": 20
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "status": "running",
    "connected": true,
    "uptime": 3600,
    "active_project": "nixos",
    "window_count": 8,
    "workspace_count": 9,
    "event_count": 1523,
    "error_count": 0,
    "version": "1.0.0",
    "socket_path": "/run/user/1000/i3-project-daemon/ipc.sock"
  },
  "id": 20
}
```

---

#### `get_events`

Get recent event history from daemon buffer.

**Request** (All Events):
```json
{
  "jsonrpc": "2.0",
  "method": "get_events",
  "params": {
    "limit": 20
  },
  "id": 21
}
```

**Request** (Filtered):
```json
{
  "jsonrpc": "2.0",
  "method": "get_events",
  "params": {
    "limit": 50,
    "event_type": "window",
    "since_id": 1000
  },
  "id": 21
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "events": [
      {
        "event_id": 1523,
        "event_type": "window",
        "change": "focus",
        "container": {
          "id": 94608348372768,
          "class": "Ghostty",
          "title": "nvim",
          // ... full WindowState
        },
        "timestamp": 1698012345678
      }
    ],
    "total_events": 1523,
    "oldest_id": 1023,
    "newest_id": 1523
  },
  "id": 21
}
```

---

#### `subscribe_events`

Subscribe to real-time event notifications from daemon.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "subscribe_events",
  "params": {
    "event_types": ["window", "workspace", "output"]
  },
  "id": 22
}
```

**Response** (Subscription Confirmed):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "subscribed": true,
    "event_types": ["window", "workspace", "output"]
  },
  "id": 22
}
```

**Subsequent Notifications** (server → client):
```json
{
  "jsonrpc": "2.0",
  "method": "event_notification",
  "params": {
    "event": {
      "event_id": 1524,
      "event_type": "window",
      "change": "new",
      "container": {
        "id": 94608348373000,
        "class": "firefox",
        "title": "Mozilla Firefox",
        // ... full WindowState
      },
      "timestamp": 1698012346000
    }
  }
}
```

---

### Window Classification

#### `list_rules`

Get all window classification rules.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "list_rules",
  "params": {},
  "id": 30
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "rules": [
      {
        "rule_id": "550e8400-e29b-41d4-a716-446655440000",
        "class_pattern": "Ghostty",
        "scope": "scoped",
        "priority": 100,
        "enabled": true
      },
      {
        "rule_id": "550e8400-e29b-41d4-a716-446655440001",
        "class_pattern": "firefox",
        "scope": "global",
        "priority": 50,
        "enabled": true
      }
    ]
  },
  "id": 30
}
```

---

#### `classify_window`

Test how a window would be classified.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "classify_window",
  "params": {
    "class": "Ghostty",
    "instance": "ghostty"
  },
  "id": 31
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "class": "Ghostty",
    "instance": "ghostty",
    "scope": "scoped",
    "matched_rule": {
      "rule_id": "550e8400-e29b-41d4-a716-446655440000",
      "class_pattern": "Ghostty",
      "scope": "scoped",
      "priority": 100
    }
  },
  "id": 31
}
```

---

#### `get_app_classes`

Get application class metadata.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_app_classes",
  "params": {},
  "id": 32
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "scoped": [
      {
        "class_name": "Ghostty",
        "display_name": "Ghostty Terminal",
        "scope": "scoped",
        "icon": "",
        "description": "Project-scoped terminal emulator"
      },
      {
        "class_name": "code-url-handler",
        "display_name": "VS Code",
        "scope": "scoped",
        "icon": "",
        "description": "Project-scoped code editor"
      }
    ],
    "global": [
      {
        "class_name": "firefox",
        "display_name": "Firefox Browser",
        "scope": "global",
        "icon": "",
        "description": "Global web browser"
      }
    ]
  },
  "id": 32
}
```

---

## Error Codes

Standard JSON-RPC 2.0 error codes plus custom daemon errors:

| Code | Name | Description |
|------|------|-------------|
| -32700 | Parse error | Invalid JSON received |
| -32600 | Invalid Request | JSON-RPC request malformed |
| -32601 | Method not found | Method does not exist |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Daemon internal error |
| -32000 | Server error | General daemon error |
| -32001 | i3 Connection Lost | Daemon lost connection to i3 IPC |
| -32002 | Project Not Found | Requested project does not exist |
| -32003 | Window Not Found | Requested window does not exist |
| -32004 | Validation Error | Parameter validation failed |

---

## Connection Lifecycle

### 1. Connect to Socket

```typescript
const socketPath = Deno.env.get("XDG_RUNTIME_DIR") + "/i3-project-daemon/ipc.sock";
const conn = await Deno.connect({ path: socketPath, transport: "unix" });
```

### 2. Send Request

```typescript
const request = {
  jsonrpc: "2.0",
  method: "get_status",
  params: {},
  id: 1,
};
await conn.write(new TextEncoder().encode(JSON.stringify(request) + "\n"));
```

### 3. Read Response

```typescript
const buffer = new Uint8Array(8192);
const n = await conn.read(buffer);
const response = JSON.parse(new TextDecoder().decode(buffer.subarray(0, n)));
```

### 4. Handle Events (if subscribed)

```typescript
// Continue reading for notifications
while (true) {
  const n = await conn.read(buffer);
  if (n === null) break;
  const msg = JSON.parse(new TextDecoder().decode(buffer.subarray(0, n)));

  if ("id" in msg) {
    // Response to request
    handleResponse(msg);
  } else {
    // Notification (event)
    handleEvent(msg);
  }
}
```

### 5. Close Connection

```typescript
conn.close();
```

---

## Timeout and Retry Policy

- **Request Timeout**: 5 seconds per FR-014
- **Connection Timeout**: 5 seconds for initial connect
- **Retry Logic**: Exponential backoff for transient failures (connection refused, timeout)
  - Attempt 1: Immediate
  - Attempt 2: 1 second delay
  - Attempt 3: 2 seconds delay
  - Attempt 4: 4 seconds delay
  - Max attempts: 4
- **Subscription Keep-Alive**: No keep-alive required (daemon sends events as they occur)

---

## Versioning

- **Protocol Version**: JSON-RPC 2.0 (fixed)
- **API Version**: Tracked via daemon's `version` field in `get_status` response
- **Compatibility**: Deno CLI must check daemon version on connect and warn if mismatch
- **Breaking Changes**: Major version bump (1.x → 2.x) indicates breaking API changes

---

## Testing Recommendations

1. **Mock Daemon**: Create mock JSON-RPC server for unit tests
2. **Contract Tests**: Validate all request/response schemas against Zod schemas
3. **Integration Tests**: Test against real daemon in test environment
4. **Error Cases**: Test all error codes and timeout scenarios
5. **Event Handling**: Test event subscription and notification processing
6. **Concurrent Requests**: Test multiple simultaneous requests

---

## Summary

This JSON-RPC API contract provides:
- **27 methods** across 4 categories (project management, window queries, daemon status, classification)
- **Type-safe communication** via TypeScript types and Zod validation
- **Real-time events** via JSON-RPC notifications
- **Clear error handling** with standard and custom error codes
- **Comprehensive testing** patterns for validation

All methods align with functional requirements (FR-010 through FR-048) from spec.md.
