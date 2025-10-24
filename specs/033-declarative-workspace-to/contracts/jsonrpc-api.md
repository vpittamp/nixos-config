# JSON-RPC API Contracts

**Feature**: 033-declarative-workspace-to
**Protocol**: JSON-RPC 2.0
**Transport**: Unix Domain Socket (`$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`)
**Date**: 2025-10-23

## Overview

This document defines the JSON-RPC 2.0 API contract between the Python daemon (server) and Deno CLI (client) for workspace-to-monitor management.

---

## Transport Protocol

### Connection

- **Socket Path**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock` (typically `/run/user/1000/i3-project-daemon/ipc.sock`)
- **Protocol**: JSON-RPC 2.0 over Unix domain socket
- **Format**: Newline-delimited JSON (`\n` separator)
- **Encoding**: UTF-8

### Request Format

```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": { /* method-specific parameters */ },
  "id": 1
}
```

### Response Format (Success)

```json
{
  "jsonrpc": "2.0",
  "result": { /* method-specific result */ },
  "id": 1
}
```

### Response Format (Error)

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32601,
    "message": "Method not found: invalid_method"
  },
  "id": 1
}
```

### Error Codes

| Code | Meaning | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON received |
| -32600 | Invalid Request | JSON is not a valid Request object |
| -32601 | Method not found | Method does not exist |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Internal JSON-RPC error |
| -32000 | Server error | Generic server error (check message) |

---

## Method Definitions

### 1. get_monitors

**Description**: Retrieve current monitor/output configuration from i3 IPC.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_monitors",
  "params": {},
  "id": 1
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": [
    {
      "name": "rdp0",
      "active": true,
      "primary": true,
      "role": "primary",
      "rect": {
        "x": 0,
        "y": 0,
        "width": 1920,
        "height": 1080
      },
      "current_workspace": "1",
      "make": "Generic",
      "model": "RDP",
      "serial": null
    },
    {
      "name": "rdp1",
      "active": true,
      "primary": false,
      "role": "secondary",
      "rect": {
        "x": 1920,
        "y": 0,
        "width": 1920,
        "height": 1080
      },
      "current_workspace": "3",
      "make": null,
      "model": null,
      "serial": null
    }
  ],
  "id": 1
}
```

**Return Type**: `List[MonitorConfig]` (see data-model.md)

**Errors**:
- `-32603`: Internal error querying i3 IPC

---

### 2. get_workspaces

**Description**: Retrieve current workspace assignments with target output information.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_workspaces",
  "params": {},
  "id": 2
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": [
    {
      "workspace_num": 1,
      "output_name": "rdp0",
      "target_role": "primary",
      "target_output": "rdp0",
      "source": "default",
      "visible": true,
      "window_count": 2
    },
    {
      "workspace_num": 2,
      "output_name": "rdp0",
      "target_role": "primary",
      "target_output": "rdp0",
      "source": "default",
      "visible": false,
      "window_count": 0
    },
    {
      "workspace_num": 3,
      "output_name": "rdp1",
      "target_role": "secondary",
      "target_output": "rdp1",
      "source": "default",
      "visible": true,
      "window_count": 5
    }
  ],
  "id": 2
}
```

**Return Type**: `List[WorkspaceAssignment]` (see data-model.md)

**Errors**:
- `-32603`: Internal error querying i3 IPC or parsing config

---

### 3. get_system_state

**Description**: Retrieve complete monitor and workspace state in a single call.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_system_state",
  "params": {},
  "id": 3
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "monitors": [ /* List[MonitorConfig] */ ],
    "workspaces": [ /* List[WorkspaceAssignment] */ ],
    "active_monitor_count": 2,
    "primary_output": "rdp0",
    "last_updated": 1730000000.123
  },
  "id": 3
}
```

**Return Type**: `MonitorSystemState` (see data-model.md)

**Errors**:
- `-32603`: Internal error querying i3 IPC

---

### 4. get_config

**Description**: Retrieve current workspace-to-monitor configuration.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_config",
  "params": {},
  "id": 4
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "version": "1.0",
    "distribution": {
      "1_monitor": {
        "primary": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        "secondary": [],
        "tertiary": []
      },
      "2_monitors": {
        "primary": [1, 2],
        "secondary": [3, 4, 5, 6, 7, 8, 9, 10],
        "tertiary": []
      },
      "3_monitors": {
        "primary": [1, 2],
        "secondary": [3, 4, 5],
        "tertiary": [6, 7, 8, 9, 10]
      }
    },
    "workspace_preferences": {
      "18": "secondary",
      "42": "tertiary"
    },
    "output_preferences": {
      "primary": ["rdp0", "DP-1", "eDP-1"],
      "secondary": ["rdp1", "HDMI-1"],
      "tertiary": ["rdp2", "HDMI-2"]
    },
    "debounce_ms": 1000,
    "enable_auto_reassign": true
  },
  "id": 4
}
```

**Return Type**: `WorkspaceMonitorConfig` (see data-model.md)

**Errors**:
- `-32603`: Internal error loading config file
- `-32000`: Config file not found or invalid JSON

---

### 5. validate_config

**Description**: Validate configuration file and return structured validation result.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "validate_config",
  "params": {
    "config_path": "/home/user/.config/i3/workspace-monitor-mapping.json"
  },
  "id": 5
}
```

**Parameters**:
- `config_path` (string, optional): Path to config file. Defaults to standard location if omitted.

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "valid": false,
    "issues": [
      {
        "severity": "error",
        "field": "distribution.2_monitors.primary",
        "message": "Duplicate workspace assignments: {5}"
      },
      {
        "severity": "warning",
        "field": "workspace_preferences.18",
        "message": "Workspace 18 assigned to 'secondary' but not in 2_monitors.secondary distribution"
      }
    ],
    "config": null
  },
  "id": 5
}
```

**Return Type**: `ConfigValidationResult` (see data-model.md)

**Errors**:
- `-32602`: Invalid config_path parameter
- `-32000`: File not found

---

### 6. reload_config

**Description**: Reload configuration from disk and apply new settings without restarting daemon.

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
    "changes": [
      "workspace_preferences.18: added",
      "debounce_ms: 1000 → 500"
    ],
    "validation_issues": []
  },
  "id": 6
}
```

**Return Type**:
```typescript
{
  success: boolean;
  changes: string[];
  validation_issues: ValidationIssue[];
}
```

**Errors**:
- `-32603`: Internal error reloading config
- `-32000`: Config file invalid (daemon keeps old config)

---

### 7. reassign_workspaces

**Description**: Redistribute all workspaces according to current configuration and monitor setup.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "reassign_workspaces",
  "params": {
    "dry_run": false
  },
  "id": 7
}
```

**Parameters**:
- `dry_run` (boolean, optional): If true, return what would change without applying. Default: false.

**Response** (dry_run=false):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "assignments_made": 8,
    "errors": []
  },
  "id": 7
}
```

**Response** (dry_run=true):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "assignments_made": 0,
    "planned_changes": [
      "Workspace 3: rdp0 → rdp1 (role: secondary)",
      "Workspace 5: rdp0 → rdp1 (role: secondary)",
      "Workspace 18: rdp0 → rdp1 (role: secondary, explicit preference)"
    ],
    "errors": []
  },
  "id": 7
}
```

**Return Type**: `ReassignWorkspacesResponse` (see data-model.md)

**Errors**:
- `-32603`: Internal error during reassignment
- `-32000`: No active monitors available

---

### 8. move_workspace

**Description**: Move a specific workspace to a target output or role.

**Request** (by role):
```json
{
  "jsonrpc": "2.0",
  "method": "move_workspace",
  "params": {
    "workspace_num": 5,
    "target_role": "secondary"
  },
  "id": 8
}
```

**Request** (by output name):
```json
{
  "jsonrpc": "2.0",
  "method": "move_workspace",
  "params": {
    "workspace_num": 5,
    "target_output": "rdp1"
  },
  "id": 8
}
```

**Parameters**:
- `workspace_num` (int, required): Workspace number to move
- `target_role` (string, optional): Target role ("primary", "secondary", "tertiary")
- `target_output` (string, optional): Target output name (e.g., "rdp1")
- Exactly one of `target_role` or `target_output` must be provided

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "workspace_num": 5,
    "from_output": "rdp0",
    "to_output": "rdp1",
    "error": null
  },
  "id": 8
}
```

**Return Type**: `MoveWorkspaceResponse` (see data-model.md)

**Errors**:
- `-32602`: Invalid parameters (missing both target_role and target_output, or both provided)
- `-32000`: Target output not found or inactive
- `-32603`: Internal error moving workspace

---

### 9. get_monitor_history

**Description**: Retrieve recent monitor change events and workspace reassignment history.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_monitor_history",
  "params": {
    "limit": 20
  },
  "id": 9
}
```

**Parameters**:
- `limit` (int, optional): Maximum number of events to return. Default: 50, Max: 500.

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "events": [
      {
        "timestamp": 1730000000.123,
        "event_type": "output_connected",
        "output_name": "rdp1",
        "details": {
          "resolution": "1920x1080",
          "primary": false
        }
      },
      {
        "timestamp": 1730000001.456,
        "event_type": "workspace_reassignment",
        "details": {
          "workspace_num": 3,
          "from_output": "rdp0",
          "to_output": "rdp1",
          "reason": "auto_reassign_on_monitor_change"
        }
      },
      {
        "timestamp": 1730000005.789,
        "event_type": "output_disconnected",
        "output_name": "rdp2",
        "details": {}
      }
    ]
  },
  "id": 9
}
```

**Return Type**:
```typescript
{
  events: Array<{
    timestamp: number;
    event_type: "output_connected" | "output_disconnected" | "workspace_reassignment" | "config_reload";
    output_name?: string;
    details: Record<string, unknown>;
  }>;
}
```

**Errors**:
- `-32602`: Invalid limit parameter

---

### 10. get_diagnostics

**Description**: Generate diagnostic report for troubleshooting monitor and workspace issues.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_diagnostics",
  "params": {},
  "id": 10
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "timestamp": "2025-10-23T12:34:56Z",
    "active_monitors": 2,
    "total_workspaces": 10,
    "orphaned_workspaces": 0,
    "issues": [
      {
        "severity": "warning",
        "category": "workspace_visibility",
        "message": "Workspace 18 has 3 windows but is not visible on any active output",
        "suggested_fix": "Move workspace 18 to an active output: i3pm monitors move 18 --to secondary"
      }
    ],
    "recommendations": [
      "Consider reducing debounce_ms to 500ms for faster monitor change response",
      "Workspace 42 has explicit preference for tertiary but only 2 monitors active"
    ],
    "config_status": {
      "loaded": true,
      "valid": true,
      "path": "/home/user/.config/i3/workspace-monitor-mapping.json",
      "last_modified": 1730000000.0
    },
    "i3_ipc_status": {
      "connected": true,
      "version": "4.24"
    }
  },
  "id": 10
}
```

**Return Type**: See DiagnosticReport in data-model.md

**Errors**:
- `-32603`: Internal error generating diagnostics

---

## CLI Command to Method Mapping

| CLI Command | JSON-RPC Method | Description |
|-------------|-----------------|-------------|
| `i3pm monitors status` | `get_monitors` + `get_workspaces` | Display monitor configuration |
| `i3pm monitors workspaces` | `get_workspaces` | List workspace assignments |
| `i3pm monitors config show` | `get_config` | Display current configuration |
| `i3pm monitors config validate` | `validate_config` | Validate config file |
| `i3pm monitors config reload` | `reload_config` | Reload configuration |
| `i3pm monitors move <ws> --to <role>` | `move_workspace` | Move workspace to role/output |
| `i3pm monitors reassign` | `reassign_workspaces` | Redistribute all workspaces |
| `i3pm monitors reassign --dry-run` | `reassign_workspaces` (dry_run=true) | Preview changes |
| `i3pm monitors watch` | `get_system_state` (+ event subscription) | Live dashboard |
| `i3pm monitors tui` | Multiple methods (interactive) | Interactive TUI |
| `i3pm monitors history` | `get_monitor_history` | Show recent events |
| `i3pm monitors diagnose` | `get_diagnostics` | Generate diagnostic report |

---

## Event Subscriptions (Not Implemented in This Feature)

**Future Enhancement**: The daemon could support event subscriptions where clients can subscribe to monitor/workspace change events and receive notifications.

**Potential Method**:
```json
{
  "jsonrpc": "2.0",
  "method": "subscribe_events",
  "params": {
    "event_types": ["output", "workspace"]
  },
  "id": 11
}
```

**Notification Format** (no id field):
```json
{
  "jsonrpc": "2.0",
  "method": "event_notification",
  "params": {
    "event_type": "output",
    "output_name": "rdp1",
    "change": "connected"
  }
}
```

**Note**: For this feature (033), the Deno CLI will use one-off RPC calls. Event subscriptions remain a potential future enhancement for the `i3pm monitors watch` command.

---

## Testing API Contracts

### Python Daemon Test

```python
# tests/i3pm-monitors/python/unit/test_jsonrpc_api.py
import pytest
import json
from ipc_server import MonitorIPCServer

@pytest.mark.asyncio
async def test_get_monitors_method():
    """Test get_monitors JSON-RPC method."""
    server = MonitorIPCServer()

    request = {
        "jsonrpc": "2.0",
        "method": "get_monitors",
        "params": {},
        "id": 1,
    }

    response = await server.handle_request(json.dumps(request))
    response_data = json.loads(response)

    assert response_data["jsonrpc"] == "2.0"
    assert response_data["id"] == 1
    assert "result" in response_data
    assert isinstance(response_data["result"], list)
```

### Deno CLI Test

```typescript
// tests/i3pm-monitors/typescript/daemon_client_test.ts
import { assertEquals } from "@std/assert";
import { DaemonClient } from "../src/daemon_client.ts";

Deno.test("get_monitors returns monitor list", async () => {
  const client = new DaemonClient();
  const monitors = await client.getMonitors();

  assertEquals(Array.isArray(monitors), true);
  if (monitors.length > 0) {
    assertEquals(typeof monitors[0].name, "string");
    assertEquals(typeof monitors[0].active, "boolean");
  }

  await client.close();
});
```

---

## Summary

This API contract defines:

- **10 JSON-RPC methods** for complete monitor and workspace management
- **Standard error codes** for consistent error handling
- **Type-safe request/response** formats aligned with data-model.md
- **CLI command mapping** to show how commands translate to RPC calls
- **Testing patterns** for both Python daemon and Deno CLI

All methods follow JSON-RPC 2.0 specification and use newline-delimited JSON over Unix domain sockets for transport.
