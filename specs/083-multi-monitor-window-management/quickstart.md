# Quickstart: Multi-Monitor Window Management Enhancements

**Feature Branch**: `083-multi-monitor-window-management`
**Date**: 2025-11-19

## Overview

This feature enhances the monitor profile system with:
- Real-time top bar updates (<100ms latency)
- Profile name display in top bar
- Atomic profile switching (no race conditions)
- Daemon-owned state management

## Usage

### Switch Monitor Profiles

**Via Keybinding**:
```
Mod4+Control+m → Opens profile selector menu
```

**Via CLI**:
```bash
set-monitor-profile single   # Single monitor (H1 only)
set-monitor-profile dual     # Dual monitors (H1 + H2)
set-monitor-profile triple   # All three monitors
```

### Verify Profile State

**Check Current Profile**:
```bash
cat ~/.config/sway/monitor-profile.current
# Output: dual
```

**Check Output States**:
```bash
cat ~/.config/sway/output-states.json | jq .
```

**View Profile Events**:
```bash
i3pm diagnose events --type profile_switch
```

## Top Bar Indicators

The Eww top bar displays:
- **Profile Name**: Current profile (e.g., "dual")
- **Output Indicators**: H1/H2/H3 with active/inactive state
- **Workspace Counts**: Number of workspaces per output

Updates occur within 100ms of profile switch completion.

## Troubleshooting

### Top Bar Not Updating

1. **Check daemon is running**:
   ```bash
   systemctl --user status i3-project-event-listener
   ```

2. **Check Eww is running**:
   ```bash
   systemctl --user status eww-top-bar
   ```

3. **Restart both**:
   ```bash
   systemctl --user restart i3-project-event-listener eww-top-bar
   ```

### Profile Switch Fails

1. **Check daemon logs**:
   ```bash
   journalctl --user -u i3-project-event-listener -f
   ```

2. **Check for rollback events**:
   ```bash
   i3pm diagnose events --type profile_switch_failed
   ```

3. **Verify profile exists**:
   ```bash
   ls ~/.config/sway/monitor-profiles/
   ```

### Workspaces on Wrong Monitor

1. **Force reassignment**:
   ```bash
   i3pm monitors reassign
   ```

2. **Check output states**:
   ```bash
   i3pm monitors status
   ```

## Performance Metrics

| Operation | Target | Verification |
|-----------|--------|--------------|
| Top bar update | <100ms | Observe after `set-monitor-profile` |
| Profile switch | <500ms | Check `duration_ms` in events |
| No duplicate reassignments | 0 | `i3pm diagnose events` - count workspace_reassign |

## Architecture

```
User Action
    │
    ▼
set-monitor-profile.sh
    │
    ├─► Sway IPC (enable/disable outputs via active-monitors)
    ├─► WayVNC service management
    └─► Write monitor-profile.current
           │
           ▼
    i3-project-event-daemon (Feature 083)
           │
           ├─► MonitorProfileWatcher detects file change
           ├─► MonitorProfileService.handle_profile_change():
           │   ├─► Update output-states.json (daemon owns state)
           │   ├─► Emit ProfileEvents for observability
           │   └─► Publish to Eww (<100ms latency)
           └─► Reassign workspaces (debounced 500ms)
                  │
                  ▼
           Eww Top Bar Widget
                  │
                  └─► Display profile name + output status
```

## Event-Driven Architecture

The daemon uses file watchers and i3ipc events instead of polling:

- **MonitorProfileWatcher**: Watches `~/.config/sway/monitor-profile.current`
- **OutputStatesWatcher**: Watches `~/.config/sway/output-states.json`
- **EwwPublisher**: Pushes updates via `eww update` CLI

This achieves <100ms latency compared to previous 2000ms polling.

## Configuration

### Custom Profiles

Create new profile in `~/.config/sway/monitor-profiles/`:

```json
{
  "name": "presentation",
  "description": "Single large monitor for demos",
  "outputs": [
    {
      "name": "HEADLESS-1",
      "enabled": true,
      "position": { "x": 0, "y": 0, "width": 1920, "height": 1080 }
    },
    {
      "name": "HEADLESS-2",
      "enabled": false,
      "position": { "x": 1920, "y": 0, "width": 1920, "height": 1080 }
    },
    {
      "name": "HEADLESS-3",
      "enabled": false,
      "position": { "x": 3840, "y": 0, "width": 1920, "height": 1080 }
    }
  ],
  "default": false
}
```

Then use: `set-monitor-profile presentation`

### Default Profile

Set default profile for login:
```bash
echo "dual" > ~/.config/sway/monitor-profile.default
```

## Related Features

- **Feature 001**: Declarative workspace-to-monitor assignment
- **Feature 047**: Dynamic Sway configuration management
- **Feature 049**: Auto workspace-to-monitor redistribution
- **Feature 057**: Unified bar system (Eww theming)
- **Feature 060**: Eww top bar system metrics
