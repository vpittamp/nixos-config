# Deployment Guide: Feature 037 - Unified Project-Scoped Window Management

**Status**: Ready for Production Deployment
**Version**: 1.2.0 (Phases 1-5 Complete)
**Date**: 2025-10-25

---

## Overview

This feature provides automatic window filtering, workspace persistence, and guaranteed workspace assignment for i3 window manager projects.

**Implemented Features**:
- ✅ **User Story 1**: Automatic window hiding/showing on project switch
- ✅ **User Story 2**: Workspace persistence across project switches
- ✅ **User Story 3**: Guaranteed workspace assignment on application launch

**Not Yet Implemented** (Optional - Future Work):
- ⏭️ User Story 4: Monitor redistribution integration (T030-T035)
- ⏭️ User Story 5: Visibility commands for hidden windows (T036-T045)
- ⏭️ Phase 8: Polish and documentation updates (T046-T058)

---

## Pre-Deployment Checklist

### Prerequisites

- [ ] NixOS system with i3 window manager
- [ ] Feature 035 (I3PM registry-centric architecture) deployed
- [ ] Feature 033 (workspace-monitor mapping) deployed
- [ ] Application registry configured at `~/.config/i3/application-registry.json`
- [ ] At least 2 projects configured in `~/.config/i3/projects/`

### Backup Current State

```bash
# 1. Backup current daemon code (if upgrading)
sudo cp -r /etc/nixos/home-modules/desktop/i3-project-event-daemon \
           /etc/nixos/home-modules/desktop/i3-project-event-daemon.backup-$(date +%Y%m%d)

# 2. Backup current configuration
cp ~/.config/i3/window-workspace-map.json \
   ~/.config/i3/window-workspace-map.json.backup 2>/dev/null || true

# 3. Note current daemon version
systemctl --user status i3-project-event-listener | grep "version"
```

---

## Deployment Steps

### Step 1: Stage and Rebuild NixOS

```bash
# Navigate to NixOS config directory
cd /etc/nixos

# Verify you're on the correct branch
git branch --show-current
# Should show: 037-given-our-top

# Stage all changes (if not already staged)
git add -A

# Rebuild with new daemon code
sudo nixos-rebuild switch --flake .#hetzner

# This will:
# - Build new daemon package (version 1.2.0)
# - Update systemd service configuration
# - Install updated daemon code
# - Preserve existing runtime state
```

**Expected Output**:
```
building the system configuration...
activating the configuration...
setting up /etc...
reloading user units for vpittamp...
```

**Troubleshooting**:
- If build fails with "version already exists", bump version in `i3-project-daemon.nix`
- If Python syntax errors, run: `python3 -m py_compile <file>` to identify issues

### Step 2: Restart Daemon

```bash
# Stop the daemon
systemctl --user stop i3-project-event-listener

# Clear any stale socket files
rm -f ~/.run/i3-project-daemon/ipc.sock 2>/dev/null

# Start the daemon with new code
systemctl --user start i3-project-event-listener

# Check status
systemctl --user status i3-project-event-listener
```

**Expected Output**:
```
● i3-project-event-listener.service - i3 Project Event Listener Daemon
     Loaded: loaded (...i3-project-event-listener.service; enabled; preset: enabled)
     Active: active (running) since Fri 2025-10-25 ...
   Main PID: <pid> (python3)
     Status: "Ready: Connected to i3"
```

**Key Status Indicators**:
- `Active: active (running)` - Daemon is running
- `Status: "Ready: Connected to i3"` - Successfully connected to i3
- No errors in Recent logs

### Step 3: Verify Daemon Initialization

```bash
# Check daemon logs for successful initialization
journalctl --user -u i3-project-event-listener --since "1 minute ago" -n 50
```

**Look for these log messages**:
```
✓ Workspace tracker initialized
✓ Application registry loaded: N applications
✓ Project switch request queue initialized
✓ Explicit subscription completed
✓ Project switch worker started
```

**Red Flags** (errors to watch for):
- `Failed to load application registry` - Check registry file exists
- `connection refused` - i3 socket not available
- `AttributeError` or `TypeError` - Code bugs, check Python syntax

---

## Post-Deployment Validation

### Validation Test 1: Automatic Window Filtering (User Story 1)

**Goal**: Verify windows hide/restore on project switch

```bash
# 1. Switch to nixos project
i3pm project switch nixos

# 2. Launch VS Code and terminal (scoped apps)
# Via Walker or command line

# 3. Switch to stacks project
i3pm project switch stacks

# 4. Verify windows hidden
# VS Code and terminal should disappear
# Firefox (global) should still be visible

# 5. Check daemon logs for filtering confirmation
journalctl --user -u i3-project-event-listener -n 20 | grep "Window filtering complete"

# Expected log:
# "Window filtering complete: hidden 2, restored 0 (2.4ms)"

# 6. Switch back to nixos
i3pm project switch nixos

# 7. Verify windows restored
# VS Code and terminal should reappear on original workspaces

# Expected log:
# "Window filtering complete: hidden 0, restored 2 (2.2ms)"
```

**Success Criteria**:
- ✅ Windows disappear when switching away from project
- ✅ Windows reappear when switching back to project
- ✅ Global apps (Firefox) remain visible throughout
- ✅ Filtering completes in <100ms (check logs for duration)

---

### Validation Test 2: Workspace Persistence (User Story 2)

**Goal**: Verify windows return to exact workspace locations

```bash
# 1. Switch to nixos project
i3pm project switch nixos

# 2. Launch VS Code (default workspace: 2)
# Via Walker: "VS Code [WS2]"

# 3. Verify VS Code on workspace 2
i3-msg -t get_tree | jq '.. | select(.window_class? == "Code") | .workspace'
# Should show: 2

# 4. Manually move VS Code to workspace 5
# Use i3 keybinding: Win+Shift+5

# 5. Check daemon logs for move tracking
journalctl --user -u i3-project-event-listener -n 10 | grep "Tracked window move"

# Expected log:
# "Tracked window move: <id> (Code) → workspace 5, floating=false, project=nixos"

# 6. Switch to different project
i3pm project switch stacks

# 7. Switch back to nixos
i3pm project switch nixos

# 8. Verify VS Code returned to workspace 5 (not default WS2)
i3-msg -t get_tree | jq '.. | select(.window_class? == "Code") | .workspace'
# Should show: 5

# 9. Check workspace tracking file
cat ~/.config/i3/window-workspace-map.json | jq '.windows | to_entries[] | select(.value.window_class == "Code")'
# Should show workspace_number: 5
```

**Success Criteria**:
- ✅ Window move tracked immediately (check logs)
- ✅ Window returns to moved workspace (not default)
- ✅ Tracking persists across daemon restarts
- ✅ Floating state preserved if window was floating

---

### Validation Test 3: Workspace Assignment (User Story 3)

**Goal**: Verify apps open on configured workspace regardless of focus

```bash
# 1. Go to workspace 7
i3-msg workspace 7

# 2. Check current workspace
i3-msg -t get_workspaces | jq '.[] | select(.focused == true) | .num'
# Should show: 7

# 3. Launch VS Code via Walker
# Search for "VS Code [WS2]" and launch

# 4. Check daemon logs for workspace assignment
journalctl --user -u i3-project-event-listener -n 10 | grep "Moved window"

# Expected log:
# "Moved window <id> (Code/vscode) from workspace 7 to preferred workspace 2"

# 5. Verify VS Code is now on workspace 2
i3-msg -t get_tree | jq '.. | select(.window_class? == "Code") | .workspace'
# Should show: 2

# 6. Repeat with terminal (preferred workspace: 1)
# Launch from WS7, should move to WS1

# 7. Verify registry loaded at daemon startup
journalctl --user -u i3-project-event-listener --since "5 minutes ago" | grep "Application registry"

# Expected log:
# "Application registry loaded: N applications"
```

**Success Criteria**:
- ✅ Applications move to preferred workspace automatically
- ✅ Works regardless of which workspace is focused when launching
- ✅ Initial workspace position tracked in window-workspace-map.json
- ✅ Registry successfully loaded at daemon startup

---

## Performance Validation

### Expected Performance Metrics

```bash
# Check filtering performance from logs
journalctl --user -u i3-project-event-listener | grep "Window filtering complete" | tail -20

# Example good performance:
# "Window filtering complete: hidden 5, restored 0 (2.8ms)"
# "Window filtering complete: hidden 0, restored 5 (3.1ms)"
```

**Performance Targets**:
- Window filtering: <100ms for 30 windows (typically 2-5ms)
- Workspace assignment: <50ms per window
- Memory overhead: <15MB total daemon size
- CPU usage: <1% idle, <5% during switches

**If Performance Issues**:
```bash
# Check CPU usage
top -p $(pgrep -f i3-project-daemon)

# Check memory usage
systemctl --user status i3-project-event-listener | grep Memory

# Enable debug logging for detailed timing
journalctl --user -u i3-project-event-listener -f
```

---

## Troubleshooting

### Issue: Daemon Won't Start

**Symptoms**: `systemctl --user status` shows "failed" or "inactive"

**Diagnosis**:
```bash
# Check daemon logs for errors
journalctl --user -u i3-project-event-listener -n 50

# Check Python syntax
python3 -m py_compile /etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon.py
python3 -m py_compile /etc/nixos/home-modules/desktop/i3-project-event-daemon/handlers.py

# Check socket file permissions
ls -la ~/.run/i3-project-daemon/
```

**Solutions**:
1. Fix Python syntax errors if any
2. Remove stale socket: `rm -f ~/.run/i3-project-daemon/ipc.sock`
3. Restart i3: `i3-msg restart`
4. Restart daemon: `systemctl --user restart i3-project-event-listener`

---

### Issue: Windows Not Filtering

**Symptoms**: Windows don't hide when switching projects

**Diagnosis**:
```bash
# 1. Check if project switch request queued
journalctl --user -u i3-project-event-listener -f

# Look for:
# "Queued project switch request: nixos (queue size: 1)"
# "Processing queued switch request: nixos"

# 2. Check window environment variables
xprop _NET_WM_PID | awk '{print $3}' | xargs -I {} cat /proc/{}/environ | tr '\0' '\n' | grep I3PM_

# Should show I3PM_PROJECT_NAME, I3PM_SCOPE, etc.

# 3. Verify workspace tracker loaded
ls -la ~/.config/i3/window-workspace-map.json

# 4. Check queue initialization
journalctl --user -u i3-project-event-listener | grep "queue initialized"
```

**Solutions**:
1. If no I3PM_* variables: App not launched via registry (use Walker/Elephant)
2. If queue not initialized: Restart daemon
3. If workspace tracker file missing: Will be created automatically
4. If persistent issue: Check logs for errors during filtering

---

### Issue: Windows Not Returning to Correct Workspace

**Symptoms**: Windows restore but not to saved workspace location

**Diagnosis**:
```bash
# 1. Check tracking file contents
cat ~/.config/i3/window-workspace-map.json | jq .

# Should contain window entries with workspace_number, floating, last_seen

# 2. Check window move tracking
journalctl --user -u i3-project-event-listener | grep "Tracked window move"

# 3. Verify window IDs match
# Get current window ID:
xdotool getactivewindow
# Check if it exists in tracking:
cat ~/.config/i3/window-workspace-map.json | jq '.windows."<window_id>"'
```

**Solutions**:
1. If tracking file empty: Move windows manually to trigger tracking
2. If window IDs mismatch: Old stale entries, daemon will clean up automatically
3. If workspaces don't exist: Check with `i3-msg -t get_workspaces`
4. If persistent: Delete tracking file, will rebuild: `rm ~/.config/i3/window-workspace-map.json`

---

### Issue: Apps Not Opening on Preferred Workspace

**Symptoms**: Applications open on current workspace instead of configured workspace

**Diagnosis**:
```bash
# 1. Verify registry file exists and is valid
cat ~/.config/i3/application-registry.json | jq .

# 2. Check daemon loaded registry
journalctl --user -u i3-project-event-listener | grep "Application registry"

# Expected: "Application registry loaded: N applications"

# 3. Verify app definition in registry
cat ~/.config/i3/application-registry.json | jq '.applications[] | select(.name == "vscode")'

# Should show preferred_workspace field

# 4. Check window environment has app name
xprop _NET_WM_PID | awk '{print $3}' | xargs -I {} cat /proc/{}/environ | tr '\0' '\n' | grep I3PM_APP_NAME
```

**Solutions**:
1. If registry not loaded: Check file path and permissions
2. If app not in registry: Add to `app-registry.nix` and rebuild
3. If no I3PM_APP_NAME: App not launched via app-launcher-wrapper.sh
4. If workspace number invalid: Check workspace exists with `i3-msg -t get_workspaces`

---

## Rollback Procedure

If issues occur and you need to rollback:

### Option 1: NixOS Generation Rollback

```bash
# 1. List recent generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# 2. Rollback to previous generation
sudo nixos-rebuild switch --rollback

# 3. Restart daemon
systemctl --user restart i3-project-event-listener

# 4. Verify old version running
systemctl --user status i3-project-event-listener | grep version
```

### Option 2: Git Revert

```bash
# 1. Revert the feature commits
cd /etc/nixos
git revert 126854e  # Phase 5
git revert 1116ca7  # Phase 3-4

# 2. Rebuild
sudo nixos-rebuild switch --flake .#hetzner

# 3. Restart daemon
systemctl --user restart i3-project-event-listener
```

### Option 3: Disable Feature

```bash
# 1. Disable workspace filtering temporarily
# Edit ~/.config/i3/window-workspace-map.json
echo '{"version":"1.0","last_updated":0,"windows":{}}' > ~/.config/i3/window-workspace-map.json

# 2. Daemon will continue running but won't filter windows

# 3. To fully disable, unload module:
# Edit home.nix, comment out i3-project-event-daemon module
# Rebuild and restart
```

---

## Monitoring and Maintenance

### Daily Health Checks

```bash
# Check daemon is running
systemctl --user is-active i3-project-event-listener

# Check for errors in last hour
journalctl --user -u i3-project-event-listener --since "1 hour ago" | grep -i error

# Check queue size (should be 0 when idle)
journalctl --user -u i3-project-event-listener -n 5 | grep "queue size"

# Check tracking file size (should grow slowly)
ls -lh ~/.config/i3/window-workspace-map.json
```

### Weekly Maintenance

```bash
# Review tracking file for stale entries
cat ~/.config/i3/window-workspace-map.json | jq '.windows | length'
# Should be reasonable (< 100 entries typically)

# Check daemon performance over time
journalctl --user -u i3-project-event-listener --since "1 week ago" | grep "Window filtering complete" | awk -F'[()]' '{print $2}' | sort -n | tail -20
# Should show consistent <100ms times

# Restart daemon weekly to clear any accumulated state
systemctl --user restart i3-project-event-listener
```

---

## Success Metrics

After 1 week of production use, validate:

**Functional Success**:
- [ ] Zero unhandled exceptions in daemon logs
- [ ] Windows consistently hide/restore on project switches
- [ ] Workspace positions persist across switches
- [ ] Applications open on configured workspaces

**Performance Success**:
- [ ] Filtering completes in <100ms for typical workload
- [ ] Daemon memory usage <20MB
- [ ] CPU usage <2% average
- [ ] No lag or delays noticed by user

**User Experience Success**:
- [ ] Context switching between projects feels natural
- [ ] Window organization preserved without manual work
- [ ] Global apps (browser, etc.) always accessible
- [ ] No unexpected window movements

---

## Next Steps (Optional Future Work)

Once deployment is stable, consider implementing:

1. **Phase 6: Monitor Redistribution** (T030-T035)
   - Automatic workspace redistribution on monitor changes
   - Integration with Feature 033 monitor management

2. **Phase 7: Visibility Commands** (T036-T045)
   - `i3pm windows hidden` - List hidden windows
   - `i3pm windows restore <project>` - Manual restoration
   - `i3pm windows inspect <id>` - Window state inspection

3. **Phase 8: Polish** (T046-T058)
   - Shell aliases (phidden, prestore, pwinspect)
   - i3 keybindings for window management
   - Performance optimization
   - Documentation updates

---

## Support

**Documentation**:
- Feature specification: `/etc/nixos/specs/037-given-our-top/spec.md`
- Implementation plan: `/etc/nixos/specs/037-given-our-top/plan.md`
- Task breakdown: `/etc/nixos/specs/037-given-our-top/tasks.md`

**Logs**:
```bash
# Real-time daemon logs
journalctl --user -u i3-project-event-listener -f

# Filter by severity
journalctl --user -u i3-project-event-listener -p err  # Errors only
journalctl --user -u i3-project-event-listener -p warning  # Warnings and up

# Search for specific events
journalctl --user -u i3-project-event-listener | grep "Window filtering"
journalctl --user -u i3-project-event-listener | grep "Tracked window move"
```

**Diagnostics**:
```bash
# Daemon status
i3pm daemon status

# Recent events
i3pm daemon events --limit=50

# Check window marks
i3-msg -t get_tree | jq '.. | select(.marks? != null) | {id, marks, window_class}'
```

---

**Deployment Prepared By**: Claude Code
**Last Updated**: 2025-10-25
**Deployment Version**: 1.2.0 (Phases 1-5)
