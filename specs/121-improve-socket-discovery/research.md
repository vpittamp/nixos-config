# Research: Improve Socket Discovery and Service Reliability

**Feature Branch**: `121-improve-socket-discovery`
**Date**: 2025-12-16

## Research Tasks

### 1. Service Target Inconsistency Analysis

**Decision**: Standardize on `sway-session.target` for all Sway-specific services.

**Rationale**: Analysis of `home-modules/` reveals mixed target usage:
- **Using `sway-session.target`**: eww-top-bar, eww-workspace-bar, eww-quick-panel, walker (Wayland mode), sway-tree-monitor, sway.nix services (sway-config-reload, sway-bar, sway-idle, sway-update-env, xdg-desktop-portal-gtk, xdg-portal-wlr, sway-xdg-watcher)
- **Using `graphical-session.target`**: i3-project-daemon, eww-monitoring-panel, sway-config-manager, i3wsr, onepassword-autostart, tmux-ai-monitor

The inconsistency causes:
1. **Startup race conditions**: Services bound to `graphical-session.target` may start before Sway IPC is available
2. **Debugging complexity**: Mixed targets make dependency graphs harder to reason about
3. **Lifecycle mismatch**: `graphical-session.target` is more generic and doesn't align with Sway-specific needs

**Alternatives considered**:
- Keep `graphical-session.target` for cross-platform compatibility → Rejected because this config is Sway-specific
- Create custom target → Rejected as unnecessary abstraction over existing `sway-session.target`

### 2. Health Endpoint Implementation Patterns

**Decision**: Add `socket-health` subcommand to existing `i3pm diagnose` CLI.

**Rationale**: The daemon already has:
- `connection.py` with `discover_sway_socket()` and `validate_and_reconnect_if_needed()` methods
- IPC socket at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock` for CLI queries
- `recovery/i3_reconnect.py` with `I3ReconnectionManager.get_stats()` returning connection metrics

Implementation approach:
1. Add IPC message type `get_socket_health` to daemon's message handler
2. Return JSON with: status, socket_path, last_validated, latency_ms, reconnection_count
3. CLI calls daemon IPC to retrieve health status

**Alternatives considered**:
- HTTP endpoint → Rejected (adds unnecessary web server dependency)
- Direct socket inspection from CLI → Rejected (duplicates daemon logic, may conflict with daemon's socket)
- File-based health status → Rejected (stale data risk, polling required)

### 3. Stale Socket Cleanup Strategy

**Decision**: Implement systemd timer that runs cleanup script every 5 minutes.

**Rationale**: Socket file pattern is `sway-ipc.$UID.$PID.sock` where PID is Sway's process ID. Cleanup algorithm:
1. Find all `sway-ipc.*.sock` files in `/run/user/$UID/`
2. Extract PID from filename
3. Check if process with that PID exists and is `sway`
4. Remove socket files where process doesn't exist

**Alternatives considered**:
- Daemon-based cleanup → Rejected (daemon might not be running when cleanup needed)
- udev rules → Rejected (socket creation doesn't trigger udev)
- inotify watcher → Rejected (adds complexity, timer is simpler and sufficient)

### 4. Services Requiring Target Migration

Based on grep analysis, these services need migration from `graphical-session.target` to `sway-session.target`:

| Service | File | Current Target | Notes |
|---------|------|---------------|-------|
| i3-project-daemon | services/i3-project-daemon.nix | graphical-session | Core Sway service |
| eww-monitoring-panel | desktop/eww-monitoring-panel.nix | graphical-session | Depends on Sway for workspace data |
| sway-config-manager | desktop/sway-config-manager.nix | graphical-session | Directly uses swaymsg |
| i3wsr | desktop/i3wsr.nix | graphical-session | Workspace renamer for Sway |
| onepassword-autostart | tools/onepassword-autostart.nix | graphical-session | Could remain generic (not Sway-specific) |
| tmux-ai-monitor | services/tmux-ai-monitor.nix | graphical-session | Could remain generic (not Sway-specific) |

**Decision**: Migrate i3-project-daemon, eww-monitoring-panel, sway-config-manager, and i3wsr to `sway-session.target`. Leave onepassword-autostart and tmux-ai-monitor on `graphical-session.target` as they don't require Sway.

## Technology Choices

### Systemd Timer for Cleanup

Best practice: Use systemd timer with OnBootSec + OnUnitActiveSec for periodic execution.

```nix
systemd.user.timers.sway-socket-cleanup = {
  Unit.Description = "Periodic cleanup of stale Sway IPC sockets";
  Timer = {
    OnBootSec = "5min";           # First run 5 minutes after boot
    OnUnitActiveSec = "5min";     # Repeat every 5 minutes
    Persistent = false;           # Don't run if missed (sockets are transient)
  };
  Install.WantedBy = [ "timers.target" ];
};
```

### Socket Validation Script

```bash
#!/usr/bin/env bash
# Cleanup stale sway-ipc sockets
USER_RUNTIME_DIR="/run/user/$(id -u)"

for sock in "$USER_RUNTIME_DIR"/sway-ipc.*.sock; do
  [ -e "$sock" ] || continue

  # Extract PID from filename (sway-ipc.$UID.$PID.sock)
  pid=$(basename "$sock" | cut -d. -f3)

  # Check if process exists and is sway
  if ! kill -0 "$pid" 2>/dev/null || ! grep -q "sway" "/proc/$pid/comm" 2>/dev/null; then
    echo "Removing stale socket: $sock (PID $pid not running or not sway)"
    rm -f "$sock"
  fi
done
```

## Dependencies

- **i3ipc.aio**: Already used by daemon for Sway IPC
- **systemd**: Already used for service management
- **bash utilities**: coreutils, procps-ng for cleanup script

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Services fail after target migration | Low | High | Test on single service first, verify with `systemctl --user list-dependencies` |
| Cleanup removes active socket | Very Low | High | Always verify PID is not running sway before removal |
| Health endpoint adds latency | Low | Low | Async implementation, <100ms target |

## Conclusions

1. **Target Standardization**: Migrate 4 Sway-specific services to `sway-session.target`
2. **Health Endpoint**: Add to existing daemon IPC, expose via `i3pm diagnose socket-health`
3. **Cleanup Timer**: Simple bash script with systemd timer, validates PID before removal
