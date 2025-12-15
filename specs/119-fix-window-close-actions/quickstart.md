# Quickstart: Eww Monitoring Widget Improvements

**Feature Branch**: `119-fix-window-close-actions`
**Date**: 2025-12-15

## Prerequisites

- NixOS with Sway compositor
- eww-monitoring-panel enabled in home-manager
- Panel accessible via `Mod+M` keybinding

## Building and Testing

### 1. Build Configuration

```bash
# Test build (always do this first)
cd ~/repos/vpittamp/nixos-config/119-fix-window-close-actions
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Apply changes
sudo nixos-rebuild switch --flake .#hetzner-sway
```

### 2. Restart Panel Service

After rebuild, restart the eww monitoring panel:

```bash
systemctl --user restart eww-monitoring-panel
```

### 3. Open Panel

Press `Mod+M` to toggle the monitoring panel.

## Testing Each Feature

### Window Close Actions (P1)

**Test Individual Close**:
1. Open several applications (e.g., `firefox`, `ghostty`)
2. Open monitoring panel (`Mod+M`)
3. Right-click on a window row to show action bar
4. Click close button (󰅖)
5. Verify window closes and panel updates

**Test Rapid Close**:
1. Right-click on multiple window rows quickly
2. Click close on each
3. Verify no errors, all windows close

**Test Project Close**:
1. Switch to a project with multiple windows
2. Right-click on project header
3. Click "Close all windows"
4. Verify all project windows close
5. Verify notification shows correct count

### Debug Mode Toggle (P2)

**Test Toggle Off (Default)**:
1. Open monitoring panel
2. Verify NO JSON expand icons (󰅂) visible
3. Verify NO environment icons (󰀫) visible

**Test Toggle On**:
1. Click debug toggle button in header (or run `eww --config ~/.config/eww-monitoring-panel update debug_mode=true`)
2. Verify JSON expand icons now visible
3. Verify environment icons now visible
4. Click on JSON icon - panel should expand
5. Click on env icon - environment panel should expand

**Test Toggle While Panels Open**:
1. With debug mode ON, expand a JSON panel
2. Toggle debug mode OFF
3. Verify JSON panel collapses gracefully

### Panel Width (P2)

**Verify Reduced Width**:
1. Open panel
2. Panel should be noticeably narrower (~307px instead of 460px)
3. Content should still be readable
4. Scrolling should work if content overflows

**Compare Hosts** (if available):
- Non-ThinkPad: 307px default
- ThinkPad: 213px default

### UI Cleanup (P3)

**Verify Removed Elements**:
1. Open monitoring panel
2. Look at any window row
3. Verify NO "WS5" type workspace badges visible
4. Look at header
5. Verify count badges show numbers only (no "PRJ", "WS", "WIN" text)

**Verify Preserved Elements**:
1. Open a PWA window
2. Verify "PWA" badge still shows
3. Verify notification badges still work

## Troubleshooting

### Panel Not Opening

```bash
# Check service status
systemctl --user status eww-monitoring-panel

# Check logs
journalctl --user -u eww-monitoring-panel -f

# Manual restart
systemctl --user restart eww-monitoring-panel
```

### Window Close Not Working

```bash
# Test swaymsg directly
swaymsg -t get_tree | jq '.nodes[].nodes[].nodes[].id'
swaymsg '[con_id=WINDOW_ID] kill'

# Check for lock files
ls -la /tmp/eww-close-*
rm /tmp/eww-close-*  # Clear stale locks
```

### Debug Mode Not Toggling

```bash
# Check current state
eww --config ~/.config/eww-monitoring-panel get debug_mode

# Force toggle
eww --config ~/.config/eww-monitoring-panel update debug_mode=true
eww --config ~/.config/eww-monitoring-panel update debug_mode=false
```

### Panel Width Looks Wrong

```bash
# Check configured width
grep panelWidth home-modules/desktop/eww-monitoring-panel.nix

# Check eww window properties
eww --config ~/.config/eww-monitoring-panel active-windows
```

### Return-to-Window Notification (P1)

**Test Basic Flow**:
1. Open a terminal in a project (e.g., `i3pm worktree switch my-project`)
2. Run `claude` (Claude Code CLI)
3. Ask Claude to do something and wait for it to finish
4. When "Claude Code Ready" notification appears, click "Return to Window"
5. Verify the terminal is focused and you're in the correct project

**Test Cross-Project**:
1. Start Claude Code in project A
2. Switch to project B (`i3pm worktree switch project-b`)
3. Wait for Claude Code notification from project A
4. Click "Return to Window"
5. Verify:
   - Project switches back to A
   - Correct terminal is focused

**Test Same Project**:
1. Start Claude Code in project A
2. Stay in project A (open a different window)
3. Click "Return to Window" when notification appears
4. Verify terminal is focused WITHOUT unnecessary project switch

**Test Error Handling**:
1. Start Claude Code in a terminal
2. Close the terminal manually
3. Click "Return to Window" on stale notification
4. Verify error message appears

**Debug Callback**:
```bash
# Check logs
journalctl --user -t claude-callback -f

# Manually test callback logic
CALLBACK_WINDOW_ID=12345 \
CALLBACK_PROJECT_NAME="test-project" \
CALLBACK_TMUX_SESSION="" \
CALLBACK_TMUX_WINDOW="" \
./scripts/claude-hooks/swaync-action-callback.sh
```

## Manual CLI Commands

```bash
# Toggle panel
toggle-monitoring-panel

# Switch tabs (0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces)
monitor-panel-tab 0

# Toggle debug mode
eww --config ~/.config/eww-monitoring-panel update debug_mode=true

# Close specific project's windows
close-worktree-action "project-name"

# Close all scoped windows
close-all-windows-action

# Check current active project
jq -r '.qualified_name' ~/.config/i3/active-worktree.json
```
