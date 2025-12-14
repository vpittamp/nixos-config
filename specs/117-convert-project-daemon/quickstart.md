# Quickstart: Convert i3pm Project Daemon to User-Level Service

**Feature**: 117-convert-project-daemon
**Date**: 2025-12-14

## Overview

This feature converts the i3pm project daemon from a system-level systemd service to a user-level home-manager service, simplifying the architecture by removing the socket discovery wrapper and enabling proper session lifecycle binding.

## What Changed

### Before (System Service)

```
systemd system service
        │
        ▼
daemonWrapper (55 lines)
  - Scan /run/user/{uid} for sway-ipc sockets
  - Clean up stale sockets
  - Pick newest by mtime
  - Export SWAYSOCK, WAYLAND_DISPLAY
        │
        ▼
python3 -m i3_project_daemon
        │
        ▼
Socket: /run/i3-project-daemon/ipc.sock
```

### After (User Service)

```
systemd user service
        │
        ▼
Environment inherited from session:
  - SWAYSOCK (native)
  - WAYLAND_DISPLAY (native)
  - XDG_RUNTIME_DIR (native)
        │
        ▼
python3 -m i3_project_daemon
        │
        ▼
Socket: $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock
```

## Key Commands

### Check Service Status

```bash
# User service (new)
systemctl --user status i3-project-daemon

# View logs
journalctl --user -u i3-project-daemon -f
```

### Verify Socket

```bash
# Check socket exists
ls -la $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock

# Test connection
i3pm daemon status
```

### Verify Environment

```bash
# Check daemon has session environment
journalctl --user -u i3-project-daemon | grep "SWAYSOCK"

# Should show: SWAYSOCK=/run/user/1000/sway-ipc.1000.XXXXX.sock
# NOT: "Found Sway IPC socket:" (wrapper message)
```

### Restart Service

```bash
systemctl --user restart i3-project-daemon
```

## Migration Steps

If upgrading from the system service:

1. **Rebuild NixOS configuration**:
   ```bash
   sudo nixos-rebuild switch --flake .#<target>
   ```

2. **Stop old system service** (if still running):
   ```bash
   sudo systemctl stop i3-project-daemon
   sudo systemctl disable i3-project-daemon
   ```

3. **Start user service** (should auto-start):
   ```bash
   systemctl --user start i3-project-daemon
   ```

4. **Verify everything works**:
   ```bash
   i3pm daemon status
   i3pm project list
   ```

## Configuration

### Enable in Home Configuration

```nix
# In your home-manager configuration
programs.i3-project-daemon = {
  enable = true;
  logLevel = "DEBUG";  # or "INFO", "WARNING", "ERROR"
};
```

### Service Configuration Location

After rebuild, service unit will be at:
```
~/.config/systemd/user/i3-project-daemon.service
```

## Socket Path Reference

### New Socket Path

```
$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock
```

Typically: `/run/user/1000/i3-project-daemon/ipc.sock`

### Backward Compatibility

During transition, daemon clients check both paths:
1. User socket: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock` (primary)
2. System socket: `/run/i3-project-daemon/ipc.sock` (fallback)

## Troubleshooting

### Service Fails to Start

```bash
# Check for errors
journalctl --user -u i3-project-daemon --since "5 minutes ago"

# Common issues:
# - Socket directory doesn't exist (should be created by ExecStartPre)
# - SWAYSOCK not set (graphical session not ready)
```

### Socket Not Found

```bash
# Verify XDG_RUNTIME_DIR is set
echo $XDG_RUNTIME_DIR

# Check socket directory exists
ls -la $XDG_RUNTIME_DIR/i3-project-daemon/

# Check if old system socket exists (migration not complete)
ls -la /run/i3-project-daemon/ipc.sock
```

### Daemon Not Connecting to Sway

```bash
# Verify SWAYSOCK is set in service environment
systemctl --user show i3-project-daemon | grep Environment

# Check if Sway IPC socket exists
ls -la $SWAYSOCK
```

### Clients Using Wrong Socket

If daemon clients are still connecting to the old system socket:

```bash
# Check which socket is being used
strace -e connect -p $(pgrep -f "python.*i3_project") 2>&1 | grep sock

# Force rebuild of affected clients
sudo nixos-rebuild switch --flake .#<target>
```

## Benefits

| Aspect | Before (System) | After (User) |
|--------|-----------------|--------------|
| Wrapper code | 55 lines | 0 lines |
| Session binding | Manual workarounds | PartOf=graphical-session.target |
| Environment access | Scan /run/user | Native inheritance |
| Socket cleanup | Manual stale detection | Systemd handles |
| Restart with session | Doesn't work | Automatic |
| Complexity | High | Low |

## Implementation Status

**Status**: ✅ IMPLEMENTED (2025-12-14)

### Completed Tasks

- ✅ Created user service module at `home-modules/services/i3-project-daemon.nix`
- ✅ Configured systemd.user.services with Type=notify, watchdog, graphical-session.target binding
- ✅ Updated 18+ files with socket path migration (user socket first, system socket fallback)
- ✅ Removed system service module (`modules/services/i3-project-daemon.nix`)
- ✅ Updated all configuration targets (hetzner, ryzen, thinkpad)
- ✅ Dry-build verification passed for all targets

### Files Modified

**New:**
- `home-modules/services/i3-project-daemon.nix` - User service module

**Socket Path Updates:**
- Python clients: `daemon_client.py` (core, monitor, workspace-panel), `monitoring_data.py`, `workspace_mode_block.py`, `system.py`, `__main__.py`
- TypeScript: `socket.ts`, `daemon-client.ts`
- Bash: `i3pm-workspace-mode.sh`, `workspace-preview-daemon`, `badge-ipc-client.sh`, `stop-notification.sh`, `prompt-submit-notification.sh`, `app-launcher-wrapper.sh`
- Nix: `eww-monitoring-panel.nix`, `app-launcher.nix`

**Removed:**
- `modules/services/i3-project-daemon.nix` - Old system service module

## Related Documentation

- [Specification](./spec.md) - Full feature specification
- [Research](./research.md) - Technical decisions and patterns
- [Data Model](./data-model.md) - Socket path and configuration details
