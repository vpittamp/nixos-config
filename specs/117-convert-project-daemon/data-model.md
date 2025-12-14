# Data Model: Convert i3pm Project Daemon to User-Level Service

**Feature**: 117-convert-project-daemon
**Date**: 2025-12-14

## Overview

This feature is a configuration refactor, not a new application. No new data models are introduced. The only data change is the socket file location.

## Socket Path Migration

### Before (System Service)

| Entity | Path | Ownership |
|--------|------|-----------|
| Socket Directory | `/run/i3-project-daemon/` | root:users |
| IPC Socket | `/run/i3-project-daemon/ipc.sock` | vpittamp:users |
| Created By | systemd tmpfiles.rules | At boot |

### After (User Service)

| Entity | Path | Ownership |
|--------|------|-----------|
| Socket Directory | `$XDG_RUNTIME_DIR/i3-project-daemon/` | vpittamp:vpittamp |
| IPC Socket | `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock` | vpittamp:vpittamp |
| Created By | ExecStartPre | At service start |

**Note**: `$XDG_RUNTIME_DIR` typically resolves to `/run/user/1000` for user ID 1000.

## Configuration Entities

### User Service Module Options

```nix
# home-modules/services/i3-project-daemon.nix

programs.i3-project-daemon = {
  enable = mkEnableOption "i3 project event listener daemon";

  logLevel = mkOption {
    type = types.enum [ "DEBUG" "INFO" "WARNING" "ERROR" ];
    default = "DEBUG";
    description = "Logging level for the daemon";
  };
};
```

**Removed Options** (from system service):
- `user` - No longer needed (service runs as logged-in user)

## Environment Variables

### Session Environment (Inherited)

| Variable | Source | Description |
|----------|--------|-------------|
| `SWAYSOCK` | Sway session | Path to Sway IPC socket |
| `WAYLAND_DISPLAY` | Sway session | Wayland display name |
| `XDG_RUNTIME_DIR` | systemd user session | User runtime directory |
| `HOME` | User session | User home directory |
| `PATH` | User session | Include user profile bin |

### Service Environment (Configured)

| Variable | Value | Description |
|----------|-------|-------------|
| `LOG_LEVEL` | `${cfg.logLevel}` | Python logging level |
| `PYTHONUNBUFFERED` | `1` | Disable output buffering |
| `PYTHONPATH` | Package site-packages | Python module path |
| `PYTHONWARNINGS` | `ignore::DeprecationWarning` | Suppress deprecation spam |

## File Changes Summary

### New Files

| File | Type | Description |
|------|------|-------------|
| `home-modules/services/i3-project-daemon.nix` | Nix module | User service definition |

### Removed Files

| File | Type | Description |
|------|------|-------------|
| `modules/services/i3-project-daemon.nix` | Nix module | System service definition |

### Modified Files (Socket Path Updates)

18+ files require socket path resolution updates. See `spec.md` section "Files Requiring Modification" for complete list.

## State Transitions

### Service Lifecycle

```
[Session Start]
      │
      ▼
[graphical-session.target ready]
      │
      ▼
[ExecStartPre: mkdir -p $XDG_RUNTIME_DIR/i3-project-daemon]
      │
      ▼
[ExecStart: python3 -m i3_project_daemon]
      │
      ├─► [Socket created]
      │
      ├─► [sd_notify READY]
      │
      ▼
[Running - processing Sway IPC events]
      │
      │ (graphical-session.target stops)
      ▼
[Service stopped via PartOf=]
      │
      ▼
[Socket file removed]
```

### Socket Resolution (Client-Side)

```
[Client needs socket]
      │
      ▼
[Check $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock]
      │
      ├─► [Exists] ─► Use user socket
      │
      ▼
[Check /run/i3-project-daemon/ipc.sock]
      │
      ├─► [Exists] ─► Use system socket (fallback)
      │
      ▼
[Return user socket path for error message]
```

## Validation Rules

### Socket Path Validation

- Socket path MUST be absolute
- Parent directory MUST exist before socket creation
- Socket file MUST be created with mode 0600 (owner read/write only)
- Socket MUST be removed on service stop (cleanup)

### Service Validation

- Service MUST have PartOf=graphical-session.target
- Service MUST wait for graphical-session.target (After=)
- Service MUST auto-start with graphical session (WantedBy=)
- Service MUST inherit session environment (no explicit SWAYSOCK, etc.)
