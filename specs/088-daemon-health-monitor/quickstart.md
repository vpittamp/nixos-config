# Quickstart Guide: Daemon Health Monitoring

**Feature**: 088-daemon-health-monitor
**Last Updated**: 2025-11-22

## Quick Start

### Viewing Service Health

```bash
# Open monitoring panel
Mod+M

# Switch to Health tab
Alt+4  # or press 4 in focus mode
```

### Restarting Failed Services

**User Services** (no sudo required):
1. Open Health tab (Mod+M, Alt+4)
2. Find failed service (red ✗ indicator)
3. Click [↻ Restart] button
4. Service restarts automatically
5. Wait 5s for health status to update

**System Services** (requires sudo):
1. Open Health tab
2. Find failed service (i3-project-daemon)
3. Click [↻ Restart] button
4. Terminal opens with sudo prompt
5. Enter password
6. Service restarts

### Health Indicators

| Icon | Color | Meaning | Action |
|------|-------|---------|--------|
| ✓ | Green | Healthy | None |
| ⚠ | Yellow | Degraded (high restarts) | Monitor |
| ✗ | Red | Critical (failed) | Restart immediately |
| ○ | Gray | Disabled (intentional) | None |
| ? | Orange | Unknown (not found) | Investigate |

### Service Categories

**Core Daemons** (critical background processes):
- i3-project-daemon (system service - requires sudo)
- workspace-preview-daemon
- sway-tree-monitor

**UI Services** (user-facing widgets):
- eww-top-bar
- eww-workspace-bar
- eww-monitoring-panel
- eww-quick-panel
- swaync (notification center)
- sov (workspace overview)
- elephant (application launcher)

**System Services** (configuration/utility):
- sway-config-manager
- i3wsr (workspace renaming)

**Optional Services** (mode-dependent):
- wayvnc@HEADLESS-1/2/3 (VNC servers)
- tailscale-rtp-default-sink (headless audio)

### Troubleshooting

#### Service shows "unknown" state

**Cause**: Service not found in systemd
**Fix**: Check if service name is correct or if service was removed

```bash
# Check if service exists
systemctl --user list-unit-files | grep <service-name>

# View service status manually
systemctl --user status <service-name>
```

#### Health tab not updating

**Cause**: eww-monitoring-panel service down
**Fix**: Restart monitoring panel

```bash
systemctl --user restart eww-monitoring-panel

# Check if backend is running
ps aux | grep "monitoring_data.*--listen"
```

#### All services show "disabled"

**Cause**: Monitor profile not detected or systemctl query failed
**Fix**: Check monitor profile and systemctl availability

```bash
# Check current profile
cat ~/.config/sway/monitor-profile.current

# Test systemctl command
systemctl --user show eww-top-bar.service -p ActiveState --value
```

#### Service restart fails

**System Service (i3-project-daemon)**:
- Ensure sudo is configured
- Check if you have permission to restart system services
- View error logs: `journalctl --system -u i3-project-daemon -n 50`

**User Service**:
- Check service logs: `journalctl --user -u <service-name> -n 50`
- Verify service configuration: `systemctl --user cat <service-name>`

### Manual Commands

```bash
# Query health data directly
monitoring-data-backend --mode health | jq .

# View service health for specific service
systemctl --user show eww-top-bar.service \
  -p LoadState,ActiveState,SubState,UnitFileState,MainPID,MemoryCurrent,NRestarts \
  --no-pager

# Restart services manually
systemctl --user restart <service-name>           # User service
sudo systemctl restart i3-project-daemon.service  # System service

# Check service logs
journalctl --user -u <service-name> -f            # User service (follow)
journalctl --system -u <service-name> -f          # System service (follow)
```

### Reference

- Feature Spec: [spec.md](spec.md)
- Data Model: [data-model.md](data-model.md)
- Research: [research.md](research.md)