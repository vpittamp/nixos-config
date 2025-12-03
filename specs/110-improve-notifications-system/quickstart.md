# Quickstart: Feature 110 - Unified Notification System

**Feature**: Notification badge in Eww top bar with real-time updates
**Branch**: `110-improve-notifications-system`
**Date**: 2025-12-02

## Overview

This feature adds a notification count badge to the Eww top bar that:
- Shows unread notification count (0-9, or "9+")
- Pulses with a glow animation when notifications are pending
- Indicates Do Not Disturb status
- Toggles the SwayNC control center on click

## Quick Usage

### View Notification Count

Look at the top bar - the notification icon (`󰂚`) displays:
- **No badge**: No notifications
- **Number badge (1-9)**: Notification count
- **"9+" badge**: 10 or more notifications
- **󰂛 icon**: Do Not Disturb enabled

### Toggle Notification Center

- **Click** the notification icon in the top bar
- **Keyboard**: `Mod+Shift+I`

### Test Notifications

```bash
# Send a test notification
notify-send "Test" "This is a test notification"

# Send multiple notifications
for i in {1..5}; do notify-send "Test $i" "Message $i"; done

# Toggle DND
swaync-client --toggle-dnd

# Clear all notifications
swaync-client --close-all
```

## Visual States

| State | Icon | Badge | Glow |
|-------|------|-------|------|
| No notifications | 󰂜 | Hidden | None |
| Has notifications | 󰂚 | [N] | Pulsing red/peach |
| DND enabled | 󰂛 | [N] or hidden | None |
| Center open | 󰂚 | [N] | Pulsing blue |

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Mod+Shift+I` | Toggle notification center |
| `Escape` | Close notification center |
| `Enter` | Activate default action on focused notification |
| `Delete` | Dismiss focused notification |

## Troubleshooting

### Badge Not Updating

```bash
# Check if SwayNC is running
systemctl --user status swaync

# Check notification monitor script
ps aux | grep notification-monitor

# Restart Eww top bar
systemctl --user restart eww-top-bar

# Test SwayNC subscribe directly
swaync-client --subscribe
```

### Badge Shows Wrong Count

```bash
# Get current count from SwayNC
swaync-client --count

# Subscribe to see events
swaync-client --subscribe
```

### Control Center Won't Open

```bash
# Test toggle directly
swaync-client --toggle-panel

# Check if toggle-swaync script works
toggle-swaync

# Check SwayNC logs
journalctl --user -u swaync -f
```

## Architecture

```
SwayNC daemon
      │
      │ swaync-client --subscribe
      ▼
notification-monitor.py (streaming)
      │
      │ JSON to stdout
      ▼
Eww deflisten (notification_data variable)
      │
      ▼
notification-badge widget (top bar)
```

## Files Modified

| File | Purpose |
|------|---------|
| `eww-top-bar/eww.yuck.nix` | Widget definition + deflisten |
| `eww-top-bar/eww.scss.nix` | Badge CSS + animations |
| `eww-top-bar/scripts/notification-monitor.py` | Streaming backend |

## Related Features

- **Feature 057**: Unified bar theme (Catppuccin Mocha)
- **Feature 060**: Eww top bar system
- **Feature 085**: Monitoring panel (similar deflisten pattern)
- **Feature 090**: Notification callback for Claude Code
