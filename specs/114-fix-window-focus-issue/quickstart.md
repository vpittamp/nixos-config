# Quickstart: Fix Window Focus/Click Issue

**Feature**: 114-fix-window-focus-issue
**Date**: 2025-12-13

## Problem

Certain windows cannot receive click/input events when tiled, but work correctly when maximized.

**Root Cause**: The Eww monitoring panel is configured with `:focusable "ondemand"` which causes it to intercept all pointer input in its 460px-wide region.

## Quick Fix (Manual Testing)

Before applying the permanent fix, you can verify the root cause by stopping the panel:

```bash
# Stop the monitoring panel
systemctl --user stop eww-monitoring-panel

# Or close just the window
eww --config ~/.config/eww-monitoring-panel close monitoring-panel

# Test - clicks should now work in tiled windows
```

If stopping the panel fixes the issue, proceed with the permanent fix below.

## Permanent Fix

### Step 1: Apply Configuration Changes

The fix modifies `home-modules/desktop/eww-monitoring-panel.nix`:

1. Add `panel_focus_mode` variable (defaults to false)
2. Change `:focusable` from `"ondemand"` to `{panel_focus_mode ? "ondemand" : false}`
3. Update toggle-monitoring-panel script to manage focus mode

### Step 2: Build and Test

```bash
# Test build (ALWAYS DO THIS FIRST)
sudo nixos-rebuild dry-build --flake .#thinkpad

# If successful, apply
sudo nixos-rebuild switch --flake .#thinkpad

# Restart Sway to apply changes
# (Or press Mod+Shift+C to reload config, then restart eww)
systemctl --user restart eww-monitoring-panel
```

### Step 3: Verify Fix

1. **Test click-through (default mode)**:
   - Panel should be visible on right side
   - Click on a tiled window beneath the panel area
   - Click should register on the window

2. **Test interactive mode (Mod+M)**:
   - Press Mod+M to focus the panel
   - Click on panel controls
   - Clicks should register on panel

3. **Test return to click-through**:
   - Press Escape or Mod+M again
   - Panel remains visible but returns to click-through mode

## Verification Commands

```bash
# Check panel focus mode state
eww --config ~/.config/eww-monitoring-panel get panel_focus_mode
# Should return: false (click-through) or true (interactive)

# Check panel visibility
eww --config ~/.config/eww-monitoring-panel get panel_visible

# Monitor Sway window events (for debugging)
swaymsg -t subscribe '["window"]' -m
```

## Testing on All Configurations

### ThinkPad (Current)

```bash
cd /home/vpittamp/repos/vpittamp/nixos-config/114-fix-window-focus-issue
sudo nixos-rebuild switch --flake .#thinkpad
```

### M1 Mac

```bash
# On M1 system
sudo nixos-rebuild switch --flake .#m1 --impure
```

### Hetzner-Sway

```bash
# SSH to Hetzner
ssh hetzner-sway
cd /etc/nixos
sudo nixos-rebuild switch --flake .#hetzner-sway
```

## Rollback

If the fix introduces new issues:

```bash
# List available generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo nixos-rebuild switch --rollback
```

## Test Cases (Manual Verification)

| Test | Steps | Expected Result |
|------|-------|-----------------|
| Click-through default | 1. Restart session 2. Click on window beneath panel | Click registers on window |
| Interactive mode | 1. Press Mod+M 2. Click on panel control | Click registers on panel |
| Exit focus mode | 1. Press Escape while panel focused | Panel stays visible, clicks pass through |
| Toggle behavior | 1. Press Mod+M twice | Panel shows (interactive) → hides |
| Maximized unchanged | 1. Maximize window 2. Click anywhere | Clicks work (unchanged behavior) |

## Automated Testing

Once fix is implemented, run sway-test framework tests:

```bash
cd home-modules/tools/sway-test
deno task test tests/sway-tests/114-window-focus/

# Or run specific test
sway-test run tests/sway-tests/114-window-focus/test_click_through.json
```

## Troubleshooting

### Panel still blocking clicks after fix

1. Check if panel_focus_mode is stuck on true:
   ```bash
   eww --config ~/.config/eww-monitoring-panel get panel_focus_mode
   # If true, reset it:
   eww --config ~/.config/eww-monitoring-panel update panel_focus_mode=false
   ```

2. Verify the fix was applied:
   ```bash
   grep "panel_focus_mode" ~/.config/eww-monitoring-panel/eww.yuck
   # Should see: :focusable {panel_focus_mode ? "ondemand" : false}
   ```

### Panel not becoming interactive with Mod+M

1. Check keybinding is updated:
   ```bash
   swaymsg -t get_binding_state
   ```

2. Verify toggle script sets focus mode:
   ```bash
   cat $(which toggle-monitoring-panel)
   # Should include: panel_focus_mode=true
   ```

## Related Files

| File | Purpose |
|------|---------|
| `home-modules/desktop/eww-monitoring-panel.nix` | Panel configuration and window definition |
| `home-modules/desktop/sway.nix` | Keybindings including Mod+M |
| `specs/114-fix-window-focus-issue/research.md` | Root cause analysis |
| `specs/114-fix-window-focus-issue/contracts/eww-panel-interface.md` | Interface specification |
