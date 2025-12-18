# Quickstart: Monitoring Panel Click-Through Fix and Docking Mode

**Feature**: 125-convert-sidebar-split-pane
**Date**: 2025-12-18

## What Changed

### New Capabilities

1. **Click-through when hidden**: Mouse clicks pass through to underlying windows when the monitoring panel is hidden (in both modes)
2. **Docked mode**: Panel can reserve screen space, causing tiled windows to automatically resize
3. **Clickable mode toggle**: Click the mode indicator in the panel header to switch modes
4. **Keyboard mode toggle**: `Mod+Shift+M` or `F10` to switch between overlay and docked modes
5. **Persistent mode**: Your dock mode preference survives session restarts

### Removed Features

- **Focus mode**: The `Mod+Shift+M` focus mode has been replaced by dock mode toggle
- **Sway "📊 Panel" mode**: No longer exists

## Panel States

The panel has two independent states:

1. **Visibility** (Active/Inactive)
   - `Mod+M`: Toggle visibility
   - When hidden, clicks pass through to underlying windows

2. **Mode** (when visible)
   - **Overlay**: Panel floats over windows (blue indicator: 🔳 Overlay)
   - **Docked**: Panel reserves screen space (green indicator: 📌 Docked)

## Keybindings

| Keybinding | Action |
|------------|--------|
| `Mod+M` | Toggle panel visibility (show/hide) |
| `Mod+Shift+M` | Toggle dock mode (overlay ↔ docked) |
| `F10` | Toggle dock mode (alternative for VNC) |
| `Alt+1-6` | Switch tabs (when panel visible) |

## Switching Modes

### Via Mouse (Recommended)
Click the mode toggle button below the tabs in the panel header:
- Shows 󰘔 (layers) for overlay or 󰤻 (pin) for docked
- Hover to see tooltip with current mode and shortcut
- Click to toggle between modes

### Via Keyboard
Press `Mod+Shift+M` or `F10` to toggle modes

## Modes Explained

### Overlay Mode (Default) - 󰘔

- Panel floats over windows
- Tiled windows use full screen width
- When hidden: Panel window closes, clicks pass through
- Best for: Quick monitoring checks, temporary reference

### Docked Mode - 󰤻

- Panel reserves screen space on the right
- Tiled windows automatically resize to fit remaining space
- When hidden: Window closes, space released (windows expand)
- Best for: Extended monitoring sessions, dedicated panel space

## Testing the Feature

### Test Click-Through Fix

1. Show the panel (`Mod+M` if hidden)
2. Position a window to the right side of screen
3. Hide the panel (`Mod+M`)
4. Click on the window where the panel was → Click should register

### Test Dock Mode

1. Open several windows and tile them
2. Click the mode indicator or press `Mod+Shift+M` to enable dock mode
3. Observe windows resize to accommodate panel space
4. Toggle again to return to overlay
5. Observe windows expand to full width

### Test Persistence

1. Set your preferred mode (click indicator or `Mod+Shift+M`)
2. Log out and log back in
3. Panel should be in the same mode

## Visual Indicator

The panel header shows a subtle mode toggle button (below the tabs):

| Mode | Icon | Description |
|------|------|-------------|
| Overlay | 󰘔 (layers) | Floating over windows |
| Docked | 󰤻 (pin) | Reserved screen space |

The button brightens on hover. Tooltip shows current mode and toggle shortcut.

## Troubleshooting

### Panel Not Appearing

```bash
# Check service status
systemctl --user status eww-monitoring-panel

# Restart service
systemctl --user restart eww-monitoring-panel

# Check logs
journalctl --user -u eww-monitoring-panel -f
```

### Dock Mode Not Working

```bash
# Check state file
cat ~/.local/state/eww-monitoring-panel/dock-mode

# Reset to overlay
echo "overlay" > ~/.local/state/eww-monitoring-panel/dock-mode
systemctl --user restart eww-monitoring-panel
```

### Windows Not Resizing in Dock Mode

- Ensure you're using tiled layout (not floating)
- Check that the panel is on the correct monitor
- Run `swaymsg -t get_outputs` to verify monitor configuration

### Mode Toggle Button Not Working

```bash
# Test the toggle script directly
toggle-panel-dock-mode

# Check if script exists
which toggle-panel-dock-mode
```

## Technical Details

- Dock mode uses Sway's layer-shell exclusive zones
- Two eww window definitions: `monitoring-panel-overlay` and `monitoring-panel-docked`
- Mode state persisted at `~/.local/state/eww-monitoring-panel/dock-mode`
- Panel height: 90% to fit between top bar (26px) and bottom bar (36px)
- CPU optimizations preserved (deflisten, disabled tabs, 30s polling)
