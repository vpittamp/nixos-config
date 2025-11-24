# Quickstart Guide: Interactive Monitoring Widget Actions

**Feature**: 093-actions-window-widget
**Version**: 1.0.0
**Last Updated**: 2025-11-23

## Overview

The monitoring panel now supports click interactions for quick window focusing and project switching. This guide shows you how to use the new click features.

## Quick Start

### Open the Monitoring Panel

**Keyboard**: `Mod+M` (Win+M on most systems)

The panel displays:
- **Windows by Project tab** (Alt+1): Hierarchical view of all windows grouped by project
- **Projects tab** (Alt+2): List of all projects with window counts
- Other tabs: Apps, Health

### Click a Window to Focus

1. **Locate your target window** in the "Windows by Project" tab
2. **Click on the window row** (anywhere on the row - workspace badge, title, or app name)
3. **System automatically**:
   - Switches to the target project (if different)
   - Switches to the target workspace
   - Focuses the target window

**Visual Feedback**:
- Hover: Row background brightens, subtle shadow appears
- Click: Row highlights blue for 2 seconds, then auto-resets
- Success: Notification "Window Focused" (if notifications enabled)

**Performance**:
- Same project: ~300ms
- Different project: ~500ms

### Click a Project to Switch

1. **Locate your target project** in the "Windows by Project" tab (project header rows)
2. **Click on the project header** (the row showing project name and icon)
3. **System switches project context**:
   - Hides scoped windows from old project
   - Restores scoped windows for new project

**Visual Feedback**:
- Hover: Header background brightens, blue border glow
- Click: Header highlights blue for 2 seconds
- Success: Notification "Switched to project [name]"

## Examples

### Example 1: Jump to VS Code in Different Project

**Scenario**: You're in project "webapp" but need to edit code in project "nixos"

**Steps**:
1. Press `Mod+M` to open monitoring panel
2. Scroll to "nixos" project section
3. Find "VS Code - eww-monitoring-panel.nix" window
4. Click on the window row

**Result**: System switches to "nixos" project and focuses VS Code (~500ms total)

---

### Example 2: Switch to Project Without Specific Window

**Scenario**: You want to switch to "dotfiles" project context

**Steps**:
1. Press `Mod+M` to open monitoring panel
2. Find "dotfiles" project header (top row of that project's section)
3. Click on the project header

**Result**: System switches to "dotfiles" project (~200ms total)

---

### Example 3: Focus Window on Different Workspace (Same Project)

**Scenario**: You're on workspace 1, need to focus terminal on workspace 5 (same project)

**Steps**:
1. Press `Mod+M` to open monitoring panel
2. Find terminal window showing "[WS 5]" badge
3. Click on the window row

**Result**: System switches to workspace 5 and focuses terminal (~300ms total)

---

## Hover States

### Window Rows

**Normal**: Gray background (40% opacity)
**Hover**: Lighter gray background (50% opacity), shadow
**Clicked**: Blue background (30% opacity), blue glow

**Cursor**: Pointer icon when hovering over clickable rows

### Project Headers

**Normal**: Gray background (60% opacity)
**Hover**: Lighter gray background (80% opacity), blue border, glow
**Clicked**: Blue background (30% opacity), blue glow

**Cursor**: Pointer icon when hovering over project headers

---

## Error Handling

### Window No Longer Available

**Symptom**: Click on window, see error notification "Window no longer available"

**Cause**: Window was closed between panel refresh and your click

**Solution**: Panel auto-refreshes within 100ms - window will disappear from list

---

### Project Switch Failed

**Symptom**: Click on project, see error notification "Project switch failed"

**Cause**: i3pm daemon not running or project configuration issue

**Solution**:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Restart daemon if needed
systemctl --user restart i3-project-event-listener
```

---

### Previous Action Still in Progress

**Symptom**: Click on window/project, see notification "Previous action still in progress"

**Cause**: You clicked too quickly (rapid clicks within 300ms)

**Solution**: Wait 1 second and try again - previous action will complete

---

## Troubleshooting

### Panel Not Responding to Clicks

**Check 1**: Verify panel is running
```bash
systemctl --user status eww-monitoring-panel
```

**Check 2**: View panel logs
```bash
journalctl --user -u eww-monitoring-panel -f
```

**Check 3**: Restart panel
```bash
systemctl --user restart eww-monitoring-panel
```

---

### Clicks Work But No Visual Feedback

**Check 1**: Verify CSS styles loaded
```bash
# Panel should show hover state on mouseover
# If not, CSS may not be loaded correctly
```

**Check 2**: Check Eww variables
```bash
eww --config ~/.config/eww-monitoring-panel get clicked_window_id
# Should be 0 when idle, window ID when clicked
```

**Check 3**: Restart Eww
```bash
systemctl --user restart eww-monitoring-panel
```

---

### Window Focus Works But Notifications Missing

**Check 1**: Verify SwayNC is running
```bash
systemctl --user status swaync
```

**Check 2**: Test notification manually
```bash
notify-send "Test" "This is a test notification"
```

**Check 3**: Restart SwayNC
```bash
systemctl --user restart swaync
```

---

## Advanced Usage

### Test Scripts Manually

**Test window focus script**:
```bash
# Syntax: focus-window-action PROJECT_NAME WINDOW_ID
focus-window-action "nixos" 94638583398848
```

**Test project switch script**:
```bash
# Syntax: switch-project-action PROJECT_NAME
switch-project-action "webapp"
```

---

### Debug Lock Files

Lock files prevent rapid duplicate clicks. They're stored in `/tmp/`:

```bash
# Check for active locks
ls -la /tmp/eww-monitoring-focus-*.lock

# Remove stale locks (if script crashed)
rm /tmp/eww-monitoring-focus-*.lock
```

**Note**: Locks auto-remove when script completes (via trap mechanism).

---

### Performance Monitoring

**Measure window focus timing**:
```bash
time focus-window-action "nixos" 94638583398848
```

**Expected**:
- Same project: <0.300s
- Different project: <0.500s

**If slower**: Check i3pm daemon performance
```bash
i3pm daemon status
journalctl --user -u i3-project-event-listener -f | grep "Feature 091"
```

---

## Keyboard Shortcuts (Unchanged)

The new click features **complement** existing keyboard shortcuts - they don't replace them.

**Panel Control**:
- `Mod+M`: Toggle monitoring panel
- `Mod+Shift+M`: Enter focus mode (keyboard navigation)
- `Alt+1-4`: Switch tabs (Windows, Projects, Apps, Health)

**Project Management** (existing):
- `Win+P`: Project switcher (keyboard-driven fuzzy search)
- `Win+Shift+P`: Clear project (global mode)

**Window Management** (existing):
- Workspace mode (CapsLock or Ctrl+0): Type digits to navigate to workspace 1-70

---

## Configuration

### Disable Click Features

If you want to disable click interactions (keep panel view-only):

**Option 1**: Don't rebuild with this feature
```bash
# Check out previous commit before Feature 093
git checkout HEAD~1
sudo nixos-rebuild switch --flake .#<target>
```

**Option 2**: Comment out onclick handlers in `eww-monitoring-panel.nix`
```nix
# Find all :onclick attributes and comment them out
# This requires manual Nix editing - not recommended
```

---

### Adjust Auto-Reset Timing

Click highlight auto-resets after 2 seconds. To change:

**Edit**: `home-modules/desktop/eww-monitoring-panel.nix`
**Find**: `sleep 2 && eww update clicked_window_id=0`
**Change**: `sleep 5 && eww update clicked_window_id=0` (5 seconds instead)

**Rebuild**:
```bash
sudo nixos-rebuild switch --flake .#<target>
```

---

### Adjust Debounce Timing

Rapid click prevention uses 300ms debounce. To change:

**Edit**: `home-modules/desktop/eww-monitoring-panel.nix`
**Find**: Lock file timeout logic in focus-window-action script
**Modify**: Adjust lock file age check

*This is advanced usage - not recommended for most users.*

---

## Integration with Other Features

### Feature 085: Monitoring Panel

Click interactions build on the existing monitoring panel infrastructure:
- Data source: Same `monitoring_data.py --listen` stream
- UI framework: Same Eww panel window
- Styling: Same Catppuccin Mocha theme

**No conflicts**: Click features extend the panel without breaking existing functionality.

---

### Feature 091: Optimized Project Switching

Click-triggered project switches use the same optimized code path:
- <200ms project switch performance
- Parallel window filtering
- Cached tree queries

**Performance**: Click actions benefit from Feature 091's speed improvements.

---

### Feature 090: SwayNC Notifications

Click action notifications use the same notification system:
- Success/error messages
- Urgency levels (normal, critical)
- Action buttons (if needed)

**Consistency**: Users see familiar notification style.

---

## FAQ

**Q: Can I click on workspace badges separately?**
A: No - the entire window row is clickable. Clicking anywhere (workspace badge, title, app name) focuses that window. Workspace switching happens automatically.

**Q: What if I click during an active project switch?**
A: The system shows "Previous action still in progress" notification and ignores the duplicate click. Wait ~1 second and try again.

**Q: Do clicks work over VNC/RDP?**
A: Yes! Click events work over remote desktop protocols (VNC, RDP) since Eww captures mouse events at the application level.

**Q: Can I click on hidden/scratchpad windows?**
A: Yes - clicking a hidden window automatically restores it from scratchpad and focuses it.

**Q: Do clicks break existing keyboard shortcuts?**
A: No - all existing keyboard shortcuts (Mod+M, Win+P, workspace mode) continue to work. Clicks are an alternative, not a replacement.

**Q: What happens if the panel refreshes while I'm clicking?**
A: The deflisten stream updates panel data every ~100ms. Your click registers before the refresh, so it always targets the window you clicked on (not the refreshed data).

---

## Feedback & Issues

If you encounter issues with click interactions:

1. **Check logs**:
   ```bash
   journalctl --user -u eww-monitoring-panel -f
   journalctl --user -u i3-project-event-listener -f
   ```

2. **Verify state**:
   ```bash
   eww --config ~/.config/eww-monitoring-panel state
   ```

3. **Test manually**:
   ```bash
   focus-window-action "test-project" 12345
   switch-project-action "test-project"
   ```

4. **Report issues**: Include logs, steps to reproduce, and expected vs. actual behavior

---

## Related Documentation

- **Feature 085**: Live Window/Project Monitoring Panel (base infrastructure)
- **Feature 091**: Optimized i3pm Project Switching (performance)
- **Feature 090**: SwayNC Notification Callbacks (feedback system)
- **CLAUDE.md**: Master documentation with all keyboard shortcuts

---

**Last Updated**: 2025-11-23
**Feature Version**: 093-actions-window-widget v1.0.0
