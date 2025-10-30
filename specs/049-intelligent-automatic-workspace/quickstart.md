# Quickstart: Intelligent Automatic Workspace-to-Monitor Assignment

**Feature**: 049-intelligent-automatic-workspace
**Status**: Implementation Phase
**Last Updated**: 2025-10-29

## Overview

Automatic workspace redistribution across Sway monitors when displays connect or disconnect. No manual intervention required - workspaces automatically distribute based on active monitor count, and windows migrate to preserve accessibility.

**Key Benefits**:
- ✅ Zero manual configuration - works out of the box
- ✅ Automatic workspace distribution when monitors change
- ✅ Windows never lost when monitors disconnect
- ✅ Predictable layouts based on monitor count
- ✅ Fast reassignment (<1 second typical)

---

## Quick Reference

### Automatic Behavior

**Monitor Connect**: Workspaces automatically redistribute across all active monitors within 1 second

**Monitor Disconnect**: Windows from disconnected monitor automatically migrate to active monitors, workspaces reassign

**Rapid Changes**: 500ms debounce prevents flapping - only final state triggers reassignment

### Default Workspace Distribution

| Monitor Count | Primary (WS) | Secondary (WS) | Tertiary (WS) | Overflow (WS) |
|---------------|--------------|----------------|---------------|---------------|
| 1 monitor     | 1-70         | -              | -             | -             |
| 2 monitors    | 1-2          | 3-70           | -             | -             |
| 3 monitors    | 1-2          | 3-5            | 6-70          | -             |
| 4+ monitors   | 1-2          | 3-5            | 6-9           | 10-70         |

### Diagnostic Commands

```bash
# Check current monitor configuration
i3pm monitors status

# View reassignment history
i3pm monitors history --limit=10

# View window migration logs
i3pm monitors migrations --limit=20

# Show distribution rules
i3pm monitors config show
```

---

## Installation

### Prerequisites

- NixOS with Sway compositor (Hetzner Sway configuration)
- i3pm daemon running (`systemctl --user status i3-project-event-listener`)
- Feature 047 (Sway Config Manager) installed

### Enable Feature

Feature is automatically enabled when i3pm daemon is running. No additional configuration required.

### Verify Installation

```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Verify monitor detection
i3pm monitors status
```

Expected output:
```
┌──────────────┬───────────┬────────┬────────────────┐
│ Monitor      │ Role      │ Active │ Workspaces     │
├──────────────┼───────────┼────────┼────────────────┤
│ HEADLESS-1   │ primary   │ ✓      │ 1-2            │
│ HEADLESS-2   │ secondary │ ✓      │ 3-5            │
│ HEADLESS-3   │ tertiary  │ ✓      │ 6-9            │
└──────────────┴───────────┴────────┴────────────────┘
```

---

## Usage Scenarios

### Scenario 1: Connect Additional Monitor

**Situation**: You connect a third VNC client to HEADLESS-3 (port 5902)

**Automatic Behavior**:
1. Sway detects HEADLESS-3 connection (output event)
2. Daemon waits 500ms for additional changes (debounce)
3. Workspaces automatically redistribute:
   - WS 1-2 stay on HEADLESS-1 (primary)
   - WS 3-5 stay on HEADLESS-2 (secondary)
   - WS 6-9 automatically move to HEADLESS-3 (tertiary)
4. Reassignment completes in <1 second

**User Action**: None required - workspaces automatically available on new monitor

**Verify**:
```bash
i3pm monitors status
# Should show 3 active monitors with distributed workspaces

i3pm monitors history --limit=1
# Should show recent "output_connected" reassignment
```

---

### Scenario 2: Disconnect Secondary Monitor

**Situation**: You disconnect VNC client from HEADLESS-2, leaving HEADLESS-1 and HEADLESS-3 active

**Automatic Behavior**:
1. Sway detects HEADLESS-2 disconnection (output event)
2. Daemon detects windows on workspaces 3-5 (HEADLESS-2)
3. Workspaces 3-5 automatically migrate to HEADLESS-1 (primary)
4. All windows remain accessible on their original workspace numbers
5. Reassignment completes in <1 second

**User Action**: None required - all windows remain accessible

**Verify**:
```bash
# Check workspace distribution
swaymsg -t get_workspaces | jq '.[] | {num, output}'

# View window migration logs
i3pm monitors migrations --workspace=3
```

---

### Scenario 3: Rapid Monitor Changes

**Situation**: You disconnect and reconnect VNC clients rapidly (within 1 second)

**Automatic Behavior**:
1. First disconnect triggers debounce timer (500ms)
2. Second disconnect cancels first timer, starts new timer
3. Monitor reconnect cancels previous timer, starts new timer
4. After 500ms of stability, daemon performs single reassignment
5. Only final monitor configuration is applied

**Result**: No workspace flapping - single reassignment after changes stabilize

**Verify**:
```bash
i3pm monitors history --limit=5
# Should show single reassignment entry despite multiple monitor changes
```

---

### Scenario 4: All Monitors Disconnect Except One

**Situation**: You disconnect HEADLESS-2 and HEADLESS-3, leaving only HEADLESS-1 active

**Automatic Behavior**:
1. Daemon detects only 1 active monitor
2. All workspaces (1-70) automatically reassign to HEADLESS-1
3. All windows from HEADLESS-2 and HEADLESS-3 migrate to HEADLESS-1
4. Windows remain on their original workspace numbers
5. All 50+ windows remain accessible on single monitor

**User Action**: Navigate between workspaces normally (Win+1-9)

**Verify**:
```bash
i3pm monitors status
# Should show single active monitor with all workspaces

i3pm monitors migrations --limit=50
# Should show all migrated windows
```

---

## Diagnostic Commands

### Monitor Status

Show current monitor configuration:

```bash
i3pm monitors status
```

Output includes:
- Active monitors with roles
- Workspace assignments per monitor
- Last reassignment timestamp
- Total reassignment count

### Reassignment History

View recent reassignment operations:

```bash
# Last 10 reassignments
i3pm monitors history --limit=10

# Show performance metrics
i3pm monitors history --limit=5
```

Output includes:
- Timestamp
- Trigger (output_connected, output_disconnected, manual)
- Success status
- Workspaces reassigned count
- Windows migrated count
- Duration in milliseconds
- Monitor count before/after

### Window Migrations

View detailed window migration logs:

```bash
# All recent migrations
i3pm monitors migrations --limit=20

# Migrations for specific workspace
i3pm monitors migrations --workspace=5
```

Output includes:
- Window ID and class
- Old output → New output
- Workspace number (preserved)
- Migration timestamp

### Configuration Rules

Show distribution rules and settings:

```bash
i3pm monitors config show
```

Output includes:
- Current monitor count
- Distribution rules (workspace → role mapping)
- Debounce delay (500ms)
- Auto-reassignment status
- State file location

---

## Troubleshooting

### Workspaces Not Redistributing

**Symptoms**: Monitors connect but workspaces stay on original monitors

**Diagnosis**:
```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Check for recent output events
i3pm daemon events --type=output --limit=10

# Check reassignment history
i3pm monitors history --limit=5
```

**Solutions**:
1. Restart daemon: `systemctl --user restart i3-project-event-listener`
2. Check daemon logs: `journalctl --user -u i3-project-event-listener -n 100`
3. Verify Sway IPC connection: `swaymsg -t get_outputs`

---

### Windows Lost After Monitor Disconnect

**Symptoms**: Windows become inaccessible after monitor disconnect

**Diagnosis**:
```bash
# Check if windows were migrated
i3pm monitors migrations --limit=50

# Check workspace assignments
swaymsg -t get_workspaces | jq '.[] | {num, output, visible}'

# Verify windows still exist
swaymsg -t get_tree | jq '.. | select(.window?) | {id, class, workspace}'
```

**Solutions**:
1. Windows should automatically migrate - check migration logs
2. Verify windows are on their original workspace numbers
3. Try switching to workspace: `swaymsg workspace number 5`
4. If windows truly lost, check daemon logs for errors

---

### Reassignment Too Slow (>2 seconds)

**Symptoms**: Workspace redistribution takes longer than 2 seconds

**Diagnosis**:
```bash
# Check reassignment duration in history
i3pm monitors history --limit=5 | grep duration_ms

# Check system load
top -n 1 -b | head -20

# Check Sway IPC responsiveness
time swaymsg -t get_workspaces
```

**Solutions**:
1. Check CPU usage - reassignment is CPU-bound
2. Verify Sway IPC response time (<50ms expected)
3. Check number of windows being migrated (100+ may be slow)
4. Review daemon logs for slow operations

---

### Rapid Monitor Changes Cause Flapping

**Symptoms**: Workspaces redistribute multiple times during rapid monitor changes

**Diagnosis**:
```bash
# Check reassignment history timing
i3pm monitors history --limit=10

# Verify debounce is working
i3pm monitors config show | grep debounce_ms
```

**Solutions**:
1. Debounce should be 500ms - verify in config
2. Check daemon logs for timer cancellation messages
3. If still flapping, may need longer debounce (contact maintainer)

---

### State File Corruption

**Symptoms**: Daemon fails to start or reassignment fails with JSON errors

**Diagnosis**:
```bash
# Check state file validity
cat ~/.config/sway/monitor-state.json | jq .

# Check daemon logs for JSON errors
journalctl --user -u i3-project-event-listener | grep -i json
```

**Solutions**:
1. Delete corrupted state file: `rm ~/.config/sway/monitor-state.json`
2. Restart daemon: `systemctl --user restart i3-project-event-listener`
3. Daemon will create fresh state file on next reassignment

---

## Advanced Usage

### Manual Reassignment (Diagnostic)

Manually trigger reassignment for testing:

```bash
i3pm monitors reassign --force
```

**Note**: This is for diagnostic purposes only. Automatic reassignment should handle all normal scenarios.

### Monitor State File

View persisted monitor state:

```bash
cat ~/.config/sway/monitor-state.json | jq .
```

Structure:
- `version`: Schema version (1.0)
- `last_updated`: Timestamp of last change
- `active_monitors`: Current monitors with roles
- `workspace_assignments`: Workspace → output mapping

### Sway Config Manager Integration

Feature automatically updates Sway Config Manager's workspace assignments:

```bash
cat ~/.config/sway/workspace-assignments.json | jq .
```

This ensures `swaymsg reload` preserves workspace distribution.

---

## Performance Expectations

### Typical Latencies

| Operation | Target | Typical | Notes |
|-----------|--------|---------|-------|
| Output event → debounce start | <10ms | 5ms | Event handler latency |
| Debounce delay | 500ms | 500ms | Prevents flapping |
| Monitor detection | <20ms | 10ms | GET_OUTPUTS query |
| Distribution calculation | <5ms | 2ms | Pure computation |
| Workspace reassignment (9 WS) | <200ms | 150ms | Sequential IPC commands |
| Window migration (50 windows) | <500ms | 300ms | Tree query + migration |
| State persistence | <10ms | 5ms | JSON write |
| **Total (typical)** | **<1s** | **850ms** | Output event → completion |

### Scaling

- **10 workspaces**: ~150ms reassignment time
- **50 windows**: ~300ms migration time
- **100 windows**: ~600ms migration time (still within 2s budget)
- **4+ monitors**: Overflow workspaces distribute round-robin

---

## Migration from Legacy System

### Removed Components

- ❌ `MonitorConfigManager` class (replaced by `DynamicWorkspaceManager`)
- ❌ `~/.config/i3/workspace-monitor-mapping.json` (replaced by `monitor-state.json`)
- ❌ Manual reassignment keybinding `Win+Shift+M` (automatic reassignment eliminates need)

### No Migration Required

- Fresh state file generated on first reassignment
- No backwards compatibility needed
- Old config files can be safely deleted

---

## FAQ

**Q: Do I need to configure anything?**
A: No - feature works out of the box with default distribution rules.

**Q: Can I customize workspace distribution?**
A: Not in current version - hardcoded rules cover most use cases. Contact maintainer if custom distribution needed.

**Q: What happens to focused workspace when monitor disconnects?**
A: Focus moves to workspace on remaining active monitor. Workspace numbers preserved.

**Q: Can I disable automatic reassignment?**
A: Not currently supported - feature is always active when daemon running.

**Q: Does this work with physical monitors (not VNC)?**
A: Yes - uses Sway IPC output events, works with any monitor type (HDMI, DisplayPort, VNC, etc.)

**Q: What if I have more than 4 monitors?**
A: Overflow workspaces (WS 10-70) distribute round-robin across monitors beyond tertiary.

**Q: Does reassignment interrupt focused window?**
A: No - workspace assignments change but focus is not disrupted. Current workspace remains visible.

---

## References

- Feature Spec: `/etc/nixos/specs/049-intelligent-automatic-workspace/spec.md`
- Implementation Plan: `/etc/nixos/specs/049-intelligent-automatic-workspace/plan.md`
- Data Model: `/etc/nixos/specs/049-intelligent-automatic-workspace/data-model.md`
- API Contracts: `/etc/nixos/specs/049-intelligent-automatic-workspace/contracts/`
- i3pm Daemon: `home-modules/desktop/i3-project-event-daemon/`
- Sway Config Manager: Feature 047 (`specs/047-create-a-new/quickstart.md`)

---

## Support

**Logs**:
```bash
journalctl --user -u i3-project-event-listener -f
```

**Health Check**:
```bash
i3pm daemon status
i3pm monitors status
```

**Report Issues**: GitHub Issues with logs, monitor configuration, and reassignment history
