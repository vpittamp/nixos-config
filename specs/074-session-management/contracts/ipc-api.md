# IPC API Contract: Session Management

**Feature**: 074-session-management
**Date**: 2025-01-14
**Protocol**: JSON-RPC over Unix socket

## Overview

The i3pm daemon exposes session management functionality via JSON-RPC IPC server on Unix socket `/tmp/i3pm-daemon.sock`.

## Base Protocol

All requests follow JSON-RPC 2.0 format:

```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": { },
  "id": 1
}
```

All responses:

```json
{
  "jsonrpc": "2.0",
  "result": { },
  "id": 1
}
```

## Methods

### 1. layout.capture

**Purpose**: Capture current layout for active project

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "layout.capture",
  "params": {
    "project": "nixos",
    "name": "main"
  },
  "id": 1
}
```

**Parameters**:
- `project` (string, required): Project name (lowercase alphanumeric with hyphens)
- `name` (string, required): Layout name (lowercase alphanumeric with hyphens)

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "layout_path": "/home/user/.local/share/i3pm/layouts/nixos/main.json",
    "workspace_count": 3,
    "window_count": 8,
    "focused_workspace": 3
  },
  "id": 1
}
```

**Errors**:
- `PROJECT_NOT_ACTIVE`: Project is not currently active
- `INVALID_PROJECT_NAME`: Project name doesn't match pattern
- `INVALID_LAYOUT_NAME`: Layout name doesn't match pattern
- `CAPTURE_FAILED`: Layout capture failed (I/O error, Sway IPC error)

---

### 2. layout.restore

**Purpose**: Restore saved layout for project

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "layout.restore",
  "params": {
    "project": "nixos",
    "name": "main",
    "timeout": 30.0
  },
  "id": 2
}
```

**Parameters**:
- `project` (string, required): Project name
- `name` (string, required): Layout name (or "latest" for most recent auto-save)
- `timeout` (float, optional): Max correlation timeout in seconds (default: 30.0)

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "windows_launched": 8,
    "windows_matched": 8,
    "windows_timeout": 0,
    "windows_failed": 0,
    "elapsed_seconds": 4.2,
    "correlations": [
      {
        "restoration_mark": "i3pm-restore-a1b2c3d4",
        "window_class": "ghostty",
        "status": "matched",
        "window_id": 12345,
        "correlation_time": 0.3
      }
    ]
  },
  "id": 2
}
```

**Errors**:
- `LAYOUT_NOT_FOUND`: No layout file found at specified path
- `PROJECT_NOT_ACTIVE`: Project is not currently active
- `RESTORE_FAILED`: Restoration failed (parsing error, Sway IPC error)

---

### 3. layout.list

**Purpose**: List all saved layouts for a project

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "layout.list",
  "params": {
    "project": "nixos",
    "include_auto_saves": true
  },
  "id": 3
}
```

**Parameters**:
- `project` (string, required): Project name
- `include_auto_saves` (bool, optional): Include auto-saved layouts (default: true)

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "layouts": [
      {
        "name": "main",
        "created_at": "2025-01-14T10:30:00",
        "is_auto_save": false,
        "workspace_count": 3,
        "window_count": 8,
        "focused_workspace": 3
      },
      {
        "name": "auto-20250114-103000",
        "created_at": "2025-01-14T10:30:00",
        "is_auto_save": true,
        "workspace_count": 2,
        "window_count": 5,
        "focused_workspace": 2
      }
    ],
    "total_count": 2
  },
  "id": 3
}
```

---

### 4. layout.delete

**Purpose**: Delete a saved layout

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "layout.delete",
  "params": {
    "project": "nixos",
    "name": "auto-20250114-103000"
  },
  "id": 4
}
```

**Parameters**:
- `project` (string, required): Project name
- `name` (string, required): Layout name

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "deleted_path": "/home/user/.local/share/i3pm/layouts/nixos/auto-20250114-103000.json"
  },
  "id": 4
}
```

**Errors**:
- `LAYOUT_NOT_FOUND`: Layout file does not exist
- `DELETE_FAILED`: Failed to delete file (permissions, I/O error)

---

### 5. project.get_focused_workspace

**Purpose**: Get focused workspace for a project

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "project.get_focused_workspace",
  "params": {
    "project": "nixos"
  },
  "id": 5
}
```

**Parameters**:
- `project` (string, required): Project name

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project": "nixos",
    "focused_workspace": 3,
    "workspace_exists": true
  },
  "id": 5
}
```

**Notes**:
- If no focus history exists for project, `focused_workspace` is `null`
- `workspace_exists` indicates whether workspace currently exists in Sway

---

### 6. project.set_focused_workspace

**Purpose**: Manually set focused workspace for a project (override tracking)

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "project.set_focused_workspace",
  "params": {
    "project": "nixos",
    "workspace": 3
  },
  "id": 6
}
```

**Parameters**:
- `project` (string, required): Project name
- `workspace` (int, required): Workspace number (1-70)

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "project": "nixos",
    "focused_workspace": 3
  },
  "id": 6
}
```

**Errors**:
- `INVALID_WORKSPACE`: Workspace number out of range (1-70)

---

### 7. config.get

**Purpose**: Get session management configuration for a project

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config.get",
  "params": {
    "project": "nixos"
  },
  "id": 7
}
```

**Parameters**:
- `project` (string, required): Project name

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project": "nixos",
    "auto_save": true,
    "auto_restore": false,
    "default_layout": "main",
    "max_auto_saves": 10
  },
  "id": 7
}
```

**Errors**:
- `PROJECT_NOT_FOUND`: Project not defined in registry

---

### 8. config.set

**Purpose**: Update session management configuration (runtime only, not persisted to Nix)

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config.set",
  "params": {
    "project": "nixos",
    "auto_save": true,
    "auto_restore": true,
    "default_layout": "main",
    "max_auto_saves": 15
  },
  "id": 8
}
```

**Parameters**:
- `project` (string, required): Project name
- `auto_save` (bool, optional): Enable auto-save on project switch
- `auto_restore` (bool, optional): Enable auto-restore on project activate
- `default_layout` (string, optional): Default layout name for auto-restore
- `max_auto_saves` (int, optional): Max auto-saved layouts to keep (1-100)

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "config": {
      "project": "nixos",
      "auto_save": true,
      "auto_restore": true,
      "default_layout": "main",
      "max_auto_saves": 15
    }
  },
  "id": 8
}
```

**Notes**:
- Changes are runtime only and lost on daemon restart
- To persist changes, edit `app-registry-data.nix` and rebuild

---

### 9. state.get

**Purpose**: Get current daemon state including focus tracking

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "state.get",
  "params": {},
  "id": 9
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "active_project": "nixos",
    "uptime_seconds": 3600.5,
    "event_count": 1234,
    "error_count": 0,
    "window_count": 15,
    "workspace_count": 5,
    "project_focused_workspaces": {
      "nixos": 3,
      "dotfiles": 5,
      "personal-site": 12
    },
    "workspace_focused_windows": {
      "1": 12345,
      "2": 67890,
      "3": 11111
    }
  },
  "id": 9
}
```

## CLI Integration

CLI commands map to IPC methods:

```bash
# Capture layout
i3pm layout save main
→ layout.capture(project=current, name="main")

# Restore layout
i3pm layout restore main
→ layout.restore(project=current, name="main")

# List layouts
i3pm layout list
→ layout.list(project=current, include_auto_saves=true)

# Delete layout
i3pm layout delete auto-20250114-103000
→ layout.delete(project=current, name="auto-20250114-103000")

# Get focused workspace
i3pm project focused-workspace
→ project.get_focused_workspace(project=current)

# View config
i3pm config get
→ config.get(project=current)

# Set config (runtime)
i3pm config set --auto-save true --max-auto-saves 15
→ config.set(project=current, auto_save=true, max_auto_saves=15)

# View daemon state
i3pm daemon state
→ state.get()
```

## Event Notifications

Daemon may emit event notifications (not responses to requests):

### layout.auto_saved

```json
{
  "jsonrpc": "2.0",
  "method": "layout.auto_saved",
  "params": {
    "project": "nixos",
    "layout_name": "auto-20250114-103000",
    "path": "/home/user/.local/share/i3pm/layouts/nixos/auto-20250114-103000.json",
    "window_count": 8,
    "workspace_count": 3
  }
}
```

### layout.auto_restored

```json
{
  "jsonrpc": "2.0",
  "method": "layout.auto_restored",
  "params": {
    "project": "nixos",
    "layout_name": "main",
    "windows_launched": 8,
    "windows_matched": 8,
    "elapsed_seconds": 4.2
  }
}
```

### workspace.focus_restored

```json
{
  "jsonrpc": "2.0",
  "method": "workspace.focus_restored",
  "params": {
    "project": "nixos",
    "workspace": 3,
    "previous_workspace": 1
  }
}
```

## Error Codes

| Code | Message | Description |
|------|---------|-------------|
| -32600 | Invalid Request | Malformed JSON-RPC request |
| -32601 | Method not found | Unknown method name |
| -32602 | Invalid params | Missing or invalid parameters |
| -32603 | Internal error | Server internal error |
| 1001 | PROJECT_NOT_ACTIVE | Project is not currently active |
| 1002 | PROJECT_NOT_FOUND | Project not defined in registry |
| 1003 | LAYOUT_NOT_FOUND | Layout file does not exist |
| 1004 | INVALID_PROJECT_NAME | Project name doesn't match pattern |
| 1005 | INVALID_LAYOUT_NAME | Layout name doesn't match pattern |
| 1006 | INVALID_WORKSPACE | Workspace number out of range |
| 1007 | CAPTURE_FAILED | Layout capture failed |
| 1008 | RESTORE_FAILED | Layout restoration failed |
| 1009 | DELETE_FAILED | Layout deletion failed |

## Performance Guarantees

| Operation | Target Latency |
|-----------|---------------|
| layout.capture | <200ms |
| layout.restore (per window) | <500ms |
| layout.list | <50ms |
| layout.delete | <20ms |
| project.get_focused_workspace | <10ms |
| project.set_focused_workspace | <10ms |
| config.get | <10ms |
| config.set | <20ms |
| state.get | <10ms |

## Versioning

API version: `1.0.0` (follows semantic versioning)

Version negotiation via initial handshake:

```json
{
  "jsonrpc": "2.0",
  "method": "daemon.version",
  "params": {},
  "id": 0
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "version": "1.0.0",
    "api_version": "1.0.0",
    "features": ["session-management", "mark-based-correlation", "auto-save", "auto-restore"]
  },
  "id": 0
}
```
