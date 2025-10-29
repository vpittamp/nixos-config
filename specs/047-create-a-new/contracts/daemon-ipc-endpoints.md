# Daemon IPC Endpoints: Configuration Management

**Feature**: 047-create-a-new
**Protocol**: JSON-RPC 2.0 over Unix socket
**Socket Path**: `~/.cache/i3pm/daemon.sock`

## Overview

This document defines the JSON-RPC endpoints for dynamic configuration management, extending the existing i3pm daemon IPC server.

## Endpoint Reference

### 1. `config_reload`

Trigger hot-reload of configuration files without restarting daemon or Sway.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_reload",
  "params": {
    "files": ["keybindings", "window-rules", "workspace-assignments"],  // Optional: specific files to reload, default: all
    "validate_only": false,  // Optional: only validate, don't apply (default: false)
    "skip_git_commit": false  // Optional: skip auto-commit on success (default: false)
  },
  "id": 1
}
```

**Response (Success)**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "reload_time_ms": 1250,
    "files_reloaded": ["keybindings", "window-rules"],
    "validation_summary": {
      "syntax_errors": 0,
      "semantic_errors": 0,
      "warnings": 1
    },
    "warnings": [
      {
        "file_path": "~/.config/sway/keybindings.toml",
        "line_number": 8,
        "error_type": "conflict",
        "message": "Keybinding Control+1 defined in both Nix and runtime config",
        "suggestion": "Using runtime config (higher precedence)"
      }
    ],
    "commit_hash": "a1b2c3d4e5f6...",
    "previous_version": "f9e8d7c6b5a4..."
  },
  "id": 1
}
```

**Response (Validation Error)**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Configuration validation failed",
    "data": {
      "errors": [
        {
          "file_path": "~/.config/sway/keybindings.toml",
          "line_number": 15,
          "error_type": "syntax",
          "message": "Invalid key combo: Mod++Return",
          "suggestion": "Use single + between modifiers (e.g., Mod+Return)"
        }
      ],
      "warnings": []
    }
  },
  "id": 1
}
```

**Error Codes**:
- `-32600`: Validation failed (syntax, semantic, or conflict errors)
- `-32603`: Internal error during reload (Sway IPC failed, file I/O error)
- `-32001`: Git commit failed (changes applied but not committed)

---

### 2. `config_validate`

Validate configuration files without applying changes.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_validate",
  "params": {
    "files": ["keybindings"],  // Optional: specific files, default: all
    "strict": true  // Optional: treat warnings as errors (default: false)
  },
  "id": 2
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "valid": true,
    "validation_time_ms": 85,
    "files_validated": ["keybindings", "window-rules", "workspace-assignments"],
    "summary": {
      "syntax_errors": 0,
      "semantic_errors": 0,
      "warnings": 2
    },
    "errors": [],
    "warnings": [
      {
        "file_path": "~/.config/sway/window-rules.json",
        "line_number": null,
        "error_type": "semantic",
        "message": "Window rule for app_id 'nonexistent-app' has never matched",
        "suggestion": "Verify app_id is correct or remove unused rule"
      }
    ]
  },
  "id": 2
}
```

---

### 3. `config_rollback`

Rollback to a previous configuration version.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_rollback",
  "params": {
    "commit_hash": "f9e8d7c6b5a4...",  // Git commit SHA to rollback to
    "auto_reload": true  // Optional: automatically reload after rollback (default: true)
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
    "rollback_time_ms": 2100,
    "previous_version": "a1b2c3d4e5f6...",
    "restored_version": "f9e8d7c6b5a4...",
    "files_restored": ["keybindings.toml", "window-rules.json"],
    "reload_triggered": true
  },
  "id": 3
}
```

**Error Codes**:
- `-32602`: Invalid commit hash
- `-32603`: Git checkout failed
- `-32001`: Rollback succeeded but reload failed (manual reload required)

---

### 4. `config_get_versions`

List available configuration versions from git history.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_get_versions",
  "params": {
    "limit": 10,  // Optional: max versions to return (default: 20)
    "since": "2025-10-01T00:00:00Z"  // Optional: only versions after this timestamp
  },
  "id": 4
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "versions": [
      {
        "commit_hash": "a1b2c3d4e5f6...",
        "timestamp": "2025-10-29T14:30:00Z",
        "message": "Update keybindings for project workflow",
        "files_changed": ["keybindings.toml"],
        "author": "user",
        "is_active": true
      },
      {
        "commit_hash": "f9e8d7c6b5a4...",
        "timestamp": "2025-10-28T10:15:00Z",
        "message": "Add floating rule for calculator",
        "files_changed": ["window-rules.json"],
        "author": "user",
        "is_active": false
      }
    ],
    "total_versions": 47,
    "active_version": "a1b2c3d4e5f6..."
  },
  "id": 4
}
```

---

### 5. `config_show`

Display current active configuration with source attribution.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_show",
  "params": {
    "category": "keybindings",  // Optional: "keybindings"|"window-rules"|"workspaces"|"all" (default: "all")
    "include_sources": true,  // Optional: include source attribution (default: true)
    "project_context": "nixos"  // Optional: show with specific project overrides
  },
  "id": 5
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "keybindings": [
      {
        "key_combo": "Mod+Return",
        "command": "exec terminal",
        "description": "Open terminal",
        "source": "nix",
        "mode": "default",
        "file_path": "/nix/store/.../sway-config-base.nix",
        "precedence_level": 1
      },
      {
        "key_combo": "Control+1",
        "command": "workspace number 1",
        "description": "Workspace 1",
        "source": "runtime",
        "mode": "default",
        "file_path": "~/.config/sway/keybindings.toml",
        "precedence_level": 2
      }
    ],
    "window_rules": [ /* ... */ ],
    "workspace_assignments": [ /* ... */ ],
    "active_project": "nixos",
    "config_version": "a1b2c3d4e5f6..."
  },
  "id": 5
}
```

---

### 6. `config_get_conflicts`

Identify configuration conflicts across precedence levels.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_get_conflicts",
  "params": {},
  "id": 6
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "conflicts": [
      {
        "setting_path": "keybindings.Control+1",
        "conflict_type": "duplicate",
        "sources": [
          {
            "source": "nix",
            "value": "workspace number 1",
            "file_path": "/nix/store/.../sway.nix",
            "precedence_level": 1,
            "active": false
          },
          {
            "source": "runtime",
            "value": "workspace number 1",
            "file_path": "~/.config/sway/keybindings.toml",
            "precedence_level": 2,
            "active": true
          }
        ],
        "resolution": "runtime config takes precedence (higher priority)",
        "severity": "warning"
      }
    ],
    "total_conflicts": 1
  },
  "id": 6
}
```

---

### 7. `config_watch_start`

Enable file watcher for automatic reload on configuration file changes.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_watch_start",
  "params": {
    "debounce_ms": 500  // Optional: debounce delay for rapid changes (default: 500)
  },
  "id": 7
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "watching": true,
    "watched_files": [
      "~/.config/sway/keybindings.toml",
      "~/.config/sway/window-rules.json",
      "~/.config/sway/workspace-assignments.json"
    ],
    "debounce_ms": 500
  },
  "id": 7
}
```

---

### 8. `config_watch_stop`

Disable file watcher for configuration files.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_watch_stop",
  "params": {},
  "id": 8
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "watching": false
  },
  "id": 8
}
```

---

## Event Notifications

The daemon emits events via IPC when configuration changes occur (subscription-based).

### `config_reloaded`

Emitted after successful configuration reload.

**Notification**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_reloaded",
  "params": {
    "timestamp": "2025-10-29T14:35:00Z",
    "trigger": "file_watcher",  // "file_watcher"|"manual"|"rollback"
    "files_changed": ["keybindings.toml"],
    "reload_time_ms": 980,
    "commit_hash": "b2c3d4e5f6g7..."
  }
}
```

### `config_validation_failed`

Emitted when configuration validation fails.

**Notification**:
```json
{
  "jsonrpc": "2.0",
  "method": "config_validation_failed",
  "params": {
    "timestamp": "2025-10-29T14:40:00Z",
    "file_path": "~/.config/sway/keybindings.toml",
    "errors": [
      {
        "line_number": 12,
        "error_type": "syntax",
        "message": "Invalid TOML syntax: unclosed string",
        "suggestion": "Add closing quote on line 12"
      }
    ]
  }
}
```

---

## Error Code Reference

| Code | Meaning | Recovery |
|------|---------|----------|
| `-32600` | Validation failed | Fix errors in config files, run `config_validate` |
| `-32601` | Method not found | Check endpoint name spelling |
| `-32602` | Invalid params | Verify request parameter types and required fields |
| `-32603` | Internal error | Check daemon logs, may require daemon restart |
| `-32001` | Git operation failed | Check git configuration, file permissions |
| `-32002` | Sway IPC error | Verify Sway is running, check IPC socket |

---

## Usage Examples

### CLI Integration

```bash
# Reload configuration
i3pm config reload

# Validate without applying
i3pm config validate --strict

# Rollback to previous version
i3pm config rollback <commit-hash>

# Show current configuration
i3pm config show --category=keybindings --sources

# List available versions
i3pm config list-versions --limit=10
```

### Python Client Example

```python
import asyncio
from i3pm.daemon_client import DaemonClient

async def reload_config():
    async with DaemonClient() as client:
        result = await client.call("config_reload", {
            "validate_only": False,
            "skip_git_commit": False
        })
        if result["success"]:
            print(f"Reload complete in {result['reload_time_ms']}ms")
        else:
            print(f"Reload failed: {result['errors']}")

asyncio.run(reload_config())
```

---

## Performance Requirements

| Endpoint | Target Latency | Constraint |
|----------|---------------|-----------|
| `config_reload` | <2000ms | FR-001, SC-001 (< 5 seconds total with file edit) |
| `config_validate` | <500ms | Research Q7 (validation performance) |
| `config_rollback` | <3000ms | SC-007 (rollback within 3 seconds) |
| `config_show` | <100ms | Informational query, should be instant |
| `config_get_versions` | <200ms | Git log parsing, limit to reasonable page size |

---

## Backward Compatibility

All new endpoints are additive - existing i3pm daemon IPC endpoints remain unchanged:
- `get_daemon_status`
- `notify_launch`
- `get_window_state`
- `get_hidden_windows`
- `get_pending_launches`

Configuration management endpoints follow same JSON-RPC 2.0 protocol for consistency.
