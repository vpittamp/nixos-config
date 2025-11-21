# Quickstart: Monitor Panel Focus Enhancement

**Feature 086** | **Status**: Implementation Complete (awaiting deployment)

## Overview

The monitoring panel now supports non-disruptive viewing with optional keyboard focus lock.

## Usage

### Panel Visibility (unchanged)

| Key | Action |
|-----|--------|
| `Mod+M` | Toggle panel visibility |
| `Alt+1` | Switch to Windows tab |
| `Alt+2` | Switch to Projects tab |
| `Alt+3` | Switch to Apps tab |
| `Alt+4` | Switch to Health tab |

### Focus Control (new)

| Key | Action |
|-----|--------|
| `Mod+Shift+M` | Enter monitoring focus mode |

### In Focus Mode (📊 Monitor)

| Key | Action |
|-----|--------|
| `1-4` | Switch tabs (Windows/Projects/Apps/Health) |
| `j` / `↓` | Navigate down |
| `k` / `↑` | Navigate up |
| `Enter` / `l` / `→` | Select/open item |
| `h` / `←` / `Backspace` | Go back |
| `Home` / `End` | Jump to first/last |
| `Escape` / `q` / `Mod+Shift+M` | Exit focus mode |

## Behavior

### Default (Panel Visible, Unfocused)

- Panel displays as overlay on right side of screen
- Clicking anywhere continues to work normally
- Typing goes to your focused application
- Panel updates in real-time via deflisten

### Focus Mode Active (📊 Monitor)

- **Glowing purple border** and **"⌨ FOCUS" badge** indicate focus mode
- All keys captured for panel navigation
- Vim-style (h/j/k/l) and arrow key navigation
- Press `Escape` or `Mod+Shift+M` to exit and return focus

## Quick Test

```bash
# 1. Open a terminal and start typing
# 2. Press Mod+M to show panel - typing should continue
# 3. Press Mod+Shift+M to focus panel
# 4. Press Mod+Shift+M again - focus returns to terminal
```

## Troubleshooting

### Panel still steals focus on show

Verify configuration:

```bash
# Check eww window config
grep -A10 "defwindow monitoring-panel" ~/.config/eww-monitoring-panel/eww.yuck

# Should show: :focusable "ondemand"
```

### Focus toggle doesn't work

```bash
# Check keybinding exists
grep "Shift+m" ~/.config/sway/config

# Test script directly
toggle-panel-focus
```

### Previous window not restored

The focus toggle uses `swaymsg 'focus prev'`. If the wrong window is focused after unlock:

```bash
# Check focus history
swaymsg -t get_tree | jq '.. | select(.focused? == true) | {app_id, name}'
```

## Technical Details

### Key Configuration Changes

1. **Eww**: `focusable: "ondemand"` (was `true`)
2. **Sway**: `no_focus` rule for `[app_id="eww-monitoring-panel"]`
3. **Keybinding**: `Mod+Shift+M` → `toggle-panel-focus`

### Architecture

```
Mod+M          → eww open/close (visibility)
Mod+Shift+M    → swaymsg focus/prev (focus toggle)
no_focus rule  → prevents auto-focus on panel updates
```

## Related Documentation

- **Feature 085**: [Monitoring Panel](../085-sway-monitoring-widget/quickstart.md)
- **CLAUDE.md**: System keybindings reference
