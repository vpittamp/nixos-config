# Daemon IPC API Contract

**Feature**: 049-intelligent-automatic-workspace
**Date**: 2025-10-29
**Phase**: Phase 1 - Design

## Overview

This document defines the JSON-RPC IPC API extensions for the i3pm daemon to support automatic workspace redistribution diagnostics and monitoring.

---

## 1. Get Monitor Status

Query current monitor configuration and workspace assignments.

**Method**: `monitors.status`

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "monitors.status",
  "params": {},
  "id": 1
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "monitor_count": 3,
    "active_monitors": [
      {
        "name": "HEADLESS-1",
        "role": "primary",
        "active": true,
        "workspaces": [1, 2]
      },
      {
        "name": "HEADLESS-2",
        "role": "secondary",
        "active": true,
        "workspaces": [3, 4, 5]
      },
      {
        "name": "HEADLESS-3",
        "role": "tertiary",
        "active": true,
        "workspaces": [6, 7, 8, 9]
      }
    ],
    "last_reassignment": "2025-10-29T12:34:56Z",
    "reassignment_count": 5
  },
  "id": 1
}
```

**CLI Usage**:
```bash
i3pm monitors status
```

**Output Format** (table):
```
┌──────────────┬───────────┬────────┬────────────────┐
│ Monitor      │ Role      │ Active │ Workspaces     │
├──────────────┼───────────┼────────┼────────────────┤
│ HEADLESS-1   │ primary   │ ✓      │ 1-2            │
│ HEADLESS-2   │ secondary │ ✓      │ 3-5            │
│ HEADLESS-3   │ tertiary  │ ✓      │ 6-9            │
└──────────────┴───────────┴────────┴────────────────┘

Last reassignment: 2025-10-29 12:34:56 (5 total reassignments)
```

---

## 2. Get Reassignment History

Query recent reassignment operations with performance metrics.

**Method**: `monitors.reassignment_history`

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "monitors.reassignment_history",
  "params": {
    "limit": 10
  },
  "id": 2
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "reassignments": [
      {
        "timestamp": "2025-10-29T12:34:56Z",
        "trigger": "output_disconnected",
        "success": true,
        "workspaces_reassigned": 9,
        "windows_migrated": 12,
        "duration_ms": 850,
        "monitor_count_before": 3,
        "monitor_count_after": 2
      },
      {
        "timestamp": "2025-10-29T11:20:15Z",
        "trigger": "output_connected",
        "success": true,
        "workspaces_reassigned": 9,
        "windows_migrated": 0,
        "duration_ms": 420,
        "monitor_count_before": 2,
        "monitor_count_after": 3
      }
    ]
  },
  "id": 2
}
```

**CLI Usage**:
```bash
i3pm monitors history --limit=10
```

---

## 3. Trigger Manual Reassignment (Diagnostic)

Manually trigger workspace reassignment (for testing/debugging only).

**Method**: `monitors.reassign`

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "monitors.reassign",
  "params": {
    "force": true
  },
  "id": 3
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "workspaces_reassigned": 9,
    "windows_migrated": 0,
    "duration_ms": 520,
    "error_message": null
  },
  "id": 3
}
```

**CLI Usage**:
```bash
i3pm monitors reassign --force
```

**Note**: This command is for diagnostic purposes only. Automatic reassignment should handle all normal scenarios.

---

## 4. Get Monitor Configuration

Query detailed monitor configuration including distribution rules.

**Method**: `monitors.config`

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "monitors.config",
  "params": {},
  "id": 4
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "monitor_count": 3,
    "distribution_rules": {
      "1": "primary",
      "2": "primary",
      "3": "secondary",
      "4": "secondary",
      "5": "secondary",
      "6": "tertiary"
    },
    "debounce_ms": 500,
    "auto_reassignment_enabled": true,
    "state_file": "~/.config/sway/monitor-state.json"
  },
  "id": 4
}
```

**CLI Usage**:
```bash
i3pm monitors config show
```

---

## 5. Get Window Migration Records

Query detailed window migration logs from recent reassignments.

**Method**: `monitors.window_migrations`

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "monitors.window_migrations",
  "params": {
    "limit": 20,
    "workspace_number": null
  },
  "id": 5
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "migrations": [
      {
        "window_id": 94532735639728,
        "window_class": "Alacritty",
        "old_output": "HEADLESS-2",
        "new_output": "HEADLESS-1",
        "workspace_number": 5,
        "timestamp": "2025-10-29T12:35:10Z"
      },
      {
        "window_id": 94532735640000,
        "window_class": "firefox",
        "old_output": "HEADLESS-2",
        "new_output": "HEADLESS-1",
        "workspace_number": 3,
        "timestamp": "2025-10-29T12:35:10Z"
      }
    ],
    "total_count": 12
  },
  "id": 5
}
```

**CLI Usage**:
```bash
i3pm monitors migrations --limit=20
i3pm monitors migrations --workspace=5
```

---

## Error Responses

### Daemon Not Running
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Daemon not running",
    "data": {
      "hint": "Start daemon with: systemctl --user start i3-project-event-listener"
    }
  },
  "id": 1
}
```

### IPC Connection Failed
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32002,
    "message": "Cannot connect to Sway IPC",
    "data": {
      "hint": "Ensure Sway is running: pgrep -x sway"
    }
  },
  "id": 1
}
```

### Operation Timeout
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32003,
    "message": "Operation timed out",
    "data": {
      "operation": "monitors.reassign",
      "timeout_ms": 10000
    }
  },
  "id": 1
}
```

---

## CLI Command Mapping

| CLI Command | IPC Method | Description |
|-------------|-----------|-------------|
| `i3pm monitors status` | `monitors.status` | Show current monitor configuration |
| `i3pm monitors history` | `monitors.reassignment_history` | Show reassignment history |
| `i3pm monitors reassign` | `monitors.reassign` | Manually trigger reassignment |
| `i3pm monitors config show` | `monitors.config` | Show distribution rules |
| `i3pm monitors migrations` | `monitors.window_migrations` | Show window migration logs |

---

## Implementation Notes

### Handler Registration (ipc_server.py)
```python
# Add new handlers
self.handlers["monitors.status"] = self._handle_monitors_status
self.handlers["monitors.reassignment_history"] = self._handle_reassignment_history
self.handlers["monitors.reassign"] = self._handle_manual_reassign
self.handlers["monitors.config"] = self._handle_monitor_config
self.handlers["monitors.window_migrations"] = self._handle_window_migrations

async def _handle_monitors_status(self, params: dict) -> dict:
    """Handle monitors.status request."""
    # Query DynamicWorkspaceManager for current state
    manager = self.daemon.workspace_manager
    return await manager.get_monitor_status()
```

### State Tracking
- Reassignment history: Circular buffer (last 100 reassignments)
- Window migration records: Circular buffer (last 500 migrations)
- Current monitor state: Single MonitorState object in memory

### Performance
- All IPC commands should respond in <100ms
- State queries are in-memory (no file I/O)
- History queries use pre-built circular buffers

---

## Testing

### Mock IPC Server
```python
@pytest.fixture
async def mock_daemon_ipc():
    """Mock daemon IPC server for testing."""
    server = AsyncMock(spec=DaemonIPCServer)
    server.call.return_value = {
        "monitor_count": 3,
        "active_monitors": [...]
    }
    return server
```

### Contract Tests
```python
async def test_monitors_status_contract():
    """Verify monitors.status response schema."""
    response = await daemon_ipc.call("monitors.status", {})

    assert "monitor_count" in response
    assert "active_monitors" in response
    assert isinstance(response["active_monitors"], list)
```

---

## References

- Existing IPC server: home-modules/desktop/i3-project-event-daemon/ipc_server.py
- JSON-RPC specification: https://www.jsonrpc.org/specification
- Daemon client patterns: home-modules/tools/i3-project-monitor/daemon_client.py
