# Quickstart: Improve Socket Discovery and Service Reliability

**Feature Branch**: `121-improve-socket-discovery`
**Date**: 2025-12-16

## Overview

This feature improves Sway IPC socket reliability through:
1. **Standardized service targets**: All Sway-specific services use `sway-session.target`
2. **Health monitoring endpoint**: Query socket status via `i3pm diagnose socket-health`
3. **Automatic cleanup**: Stale sockets removed every 5 minutes

## Quick Commands

### Check Service Dependencies
```bash
# View all services depending on sway-session.target
systemctl --user list-dependencies sway-session.target

# Check specific service status
systemctl --user status i3-project-daemon
systemctl --user status eww-monitoring-panel
```

### Check Socket Health
```bash
# Query daemon for socket health (human-readable table)
i3pm diagnose socket-health

# Example output:
# Sway IPC Socket Health
#
# Status             HEALTHY
# Socket Path        /run/user/1000/sway-ipc.1000.12345.sock
# Last Validated     2025-12-16T10:30:00
# Latency            5.23ms
# Reconnection Count 0
# Uptime             3600.0s

# JSON output for scripting
i3pm diagnose socket-health --json
# {
#   "status": "healthy",
#   "socket_path": "/run/user/1000/sway-ipc.1000.12345.sock",
#   "last_validated": "2025-12-16T10:30:00",
#   "latency_ms": 5.23,
#   "reconnection_count": 0,
#   "uptime_seconds": 3600.0
# }
```

### Manual Socket Inspection
```bash
# List all Sway sockets
ls -la /run/user/$(id -u)/sway-ipc.*.sock

# Check socket validity (should match running sway process)
pgrep -a sway
```

### Cleanup Timer Status
```bash
# Check cleanup timer status (after implementation)
systemctl --user status sway-socket-cleanup.timer
systemctl --user list-timers --all | grep sway

# View cleanup logs
journalctl --user -u sway-socket-cleanup.service
```

## Troubleshooting

### Services Not Starting After Sway

If services fail to start after Sway launches:

```bash
# Check if sway-session.target is active
systemctl --user is-active sway-session.target

# Manually start services
systemctl --user start i3-project-daemon

# Check journal for errors
journalctl --user -u i3-project-daemon -f
```

### Stale Socket Preventing Connection

If daemon can't connect due to stale socket:

```bash
# Manual cleanup (before timer is implemented)
for sock in /run/user/$(id -u)/sway-ipc.*.sock; do
  pid=$(basename "$sock" | cut -d. -f3)
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Removing stale: $sock"
    rm -f "$sock"
  fi
done

# Restart daemon
systemctl --user restart i3-project-daemon
```

### Health Check Shows "stale"

```bash
# Socket exists but Sway not responding
# 1. Check if Sway is running
pgrep sway

# 2. Try reloading Sway
swaymsg reload

# 3. If Sway crashed, restart it
# (usually requires logging out and back in)
```

## Configuration Files

| File | Purpose |
|------|---------|
| `home-modules/services/i3-project-daemon.nix` | Daemon service with sway-session.target |
| `home-modules/desktop/eww-monitoring-panel.nix` | Monitoring panel service |
| `home-modules/desktop/sway-config-manager.nix` | Config manager service |
| `home-modules/desktop/i3wsr.nix` | Workspace renamer service |
| `home-modules/tools/sway-socket-cleanup/` | Cleanup timer (new) |

## Testing Changes

```bash
# Dry-build before applying
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Apply changes
sudo nixos-rebuild switch --flake .#hetzner-sway

# Verify services migrated correctly
systemctl --user list-dependencies sway-session.target | grep -E 'i3-project|eww|sway-config|i3wsr'
```

## Success Criteria Verification

| Criteria | Command | Expected |
|----------|---------|----------|
| Services on correct target | `systemctl --user show i3-project-daemon.service -p PartOf` | `sway-session.target` |
| Health endpoint works | `i3pm diagnose socket-health` | JSON with status |
| Services reconnect after restart | Restart Sway, wait 30s | All services healthy |
| Stale sockets cleaned | Create fake socket, wait 5min | Socket removed |
