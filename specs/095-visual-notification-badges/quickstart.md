# Quickstart: Visual Notification Badges in Monitoring Panel

**Feature**: 095-visual-notification-badges | **Date**: 2025-11-24

## What Are Notification Badges?

Visual notification badges are persistent indicators that appear on window items in the Eww monitoring panel when terminal applications (like Claude Code or build tools) require your attention. Unlike desktop notifications that can be dismissed or missed, badges remain visible until you focus the window.

**Core Benefit**: Eliminates "which terminal was that?" confusion by making pending notifications discoverable within your existing window management UI.

## Quick Start

### Viewing Badges

1. **Open monitoring panel**: `Mod+M` (default keybinding)
2. **Look for bell icons (🔔)** on window items in the Windows tab
3. **Badge shows count**: "1", "2", ..., "9+" (for 10+ notifications)
4. **Click window item** to focus window - badge disappears immediately

### Creating Badges (For Application Developers)

Badges are created via IPC calls to the i3pm daemon:

```bash
# Create badge for window ID 12345 with source "claude-code"
echo '{"jsonrpc":"2.0","method":"create_badge","params":{"window_id":12345,"source":"claude-code"},"id":1}' \
  | nc -U /run/user/$(id -u)/i3pm-daemon.sock
```

**Helper Script** (recommended):
```bash
# scripts/claude-hooks/badge-ipc-client.sh
badge-ipc create <window_id> [source]   # Create/increment badge
badge-ipc clear <window_id>             # Clear badge (rarely needed - happens on focus)
badge-ipc get-state                     # Get all badges (diagnostics)
```

### Integration Example: Claude Code Hooks

Claude Code hooks already trigger desktop notifications (Feature 090). Extending them to create badges:

```bash
# In scripts/claude-hooks/stop-notification.sh (after line 55)

# Get window ID of current terminal
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' | head -1)

# Send desktop notification (existing Feature 090)
notify-send -w -A "focus=🖥️  Return to Window" "Claude Code Ready" "$MESSAGE"

# Create badge for persistent reminder (NEW - Feature 095)
badge-ipc create "$WINDOW_ID" "claude-code"
```

### Alternative Notification Mechanisms

**Design Principle**: Badge system is **notification-agnostic** - it works with any notification mechanism via a generic IPC interface.

#### Ghostty Native Notifications

```bash
# ~/.config/ghostty/hooks/on-background-complete.sh
# Triggered when background process in Ghostty completes

WINDOW_ID="$GHOSTTY_WINDOW_ID"  # Ghostty provides window context
EXIT_CODE="$1"

# Send Ghostty native notification
ghostty-notify --title "Process Complete" --message "Exit code: $EXIT_CODE"

# Create badge (same IPC as SwayNC)
badge-ipc create "$WINDOW_ID" "ghostty-background-process"
```

**Benefit**: Ghostty notifications are terminal-native, don't require desktop notification daemon.

---

#### tmux Activity Alerts

```bash
# ~/.config/tmux/tmux.conf
# Enable activity monitoring with badge integration

set-option -g activity-action other
set-hook -g alert-activity 'run-shell "/path/to/tmux-badge-hook.sh #{pane_id} #{window_id}"'

# ~/.local/bin/tmux-badge-hook.sh
TMUX_PANE="$1"

# Map tmux pane to Sway window ID (via terminal PID)
TERMINAL_PID=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_pid}')
WINDOW_ID=$(swaymsg -t get_tree | jq --arg pid "$TERMINAL_PID" -r \
  '.. | select(.pid? == ($pid | tonumber)).id' | head -1)

# Send tmux notification
tmux display-message "Activity in pane $TMUX_PANE"

# Create badge
badge-ipc create "$WINDOW_ID" "tmux-activity"
```

**Use Case**: Background build/test processes in tmux panes trigger badges when complete.

---

#### Build Tool Integration

```bash
# cargo-watch with badge notifications
cargo watch -x build -x test --shell '
  if [ $? -ne 0 ]; then
    # Get current terminal window ID
    WINDOW_ID=$(swaymsg -t get_tree | jq -r '\''.. | select(.focused==true).id'\'')

    # Send notification (your preferred mechanism)
    notify-send "Build Failed" "Check terminal for errors"

    # Create badge
    badge-ipc create "$WINDOW_ID" "cargo-watch"
  fi
'
```

**Flexibility**: Works with any build tool (cargo, make, npm, pytest) - just call badge-ipc.

---

#### Custom Notification Scripts

```python
#!/usr/bin/env python3
# my-notification-script.py - Custom notification with badge

import subprocess
import json

def send_notification_and_badge(title, message, source="custom"):
    """Send notification via user's preferred mechanism + create badge."""

    # Get current window ID
    result = subprocess.run(
        ["swaymsg", "-t", "get_tree"],
        capture_output=True, text=True
    )
    tree = json.loads(result.stdout)
    window_id = find_focused_window(tree)

    # Send notification (choose your mechanism)
    # Option 1: SwayNC
    subprocess.run(["notify-send", title, message])

    # Option 2: Ghostty
    # subprocess.run(["ghostty-notify", "--title", title, "--message", message])

    # Option 3: tmux
    # subprocess.run(["tmux", "display-message", f"{title}: {message}"])

    # Create badge (same interface regardless of notification choice)
    badge_ipc_create(window_id, source)

# Usage
send_notification_and_badge("Task Complete", "Your analysis is ready", source="my-script")
```

**Key Point**: Badge creation (last line) is identical regardless of notification mechanism chosen (lines 17-24).

---

### Migration Example: SwayNC → Ghostty

**Before (SwayNC)**:
```bash
notify-send "Build Complete" "$OUTPUT"
badge-ipc create "$WINDOW_ID" "build"
```

**After (Ghostty)**:
```bash
ghostty-notify --title "Build Complete" --message "$OUTPUT"
badge-ipc create "$WINDOW_ID" "build"  # ← No change needed!
```

**Code Changes**: 1 line (notification API), 0 lines (badge creation).

## User Scenarios

### Scenario 1: Long-Running Task with Context Switch

**Setup**: You're working in project A (nixos-095) with Claude Code running a long task ("analyze entire codebase").

**Workflow**:
1. Start Claude Code task in terminal on workspace 1
2. Switch to project B (different workspace) to continue other work
3. Claude Code finishes and needs input
4. Desktop notification appears briefly (Feature 090)
5. **Badge appears** on terminal window in monitoring panel (Feature 095)
6. You work for 10 minutes, forget about Claude Code
7. Open monitoring panel (Mod+M) to check system state
8. **See badge (🔔 1)** on terminal window - immediate reminder
9. Click window item in panel → terminal focused, badge clears

**Time Saved**: 10-15 seconds of manual terminal searching eliminated.

### Scenario 2: Multiple Pending Notifications

**Setup**: You're away from desk for 15 minutes. Claude Code completes two separate tasks while you're gone.

**Workflow**:
1. First task completes → badge created (count=1)
2. You start second task before checking first notification
3. Second task completes → badge incremented (count=2)
4. Return to desk, open monitoring panel
5. **See badge (🔔 2)** - know there are multiple pending items
6. Click window item → terminal focused, both notifications addressed, badge clears

**Benefit**: Badge count provides context about notification volume.

### Scenario 3: Badge Persistence Across Panel Toggles

**Setup**: Badge created while monitoring panel is closed.

**Workflow**:
1. Claude Code creates badge while panel is hidden
2. You open panel (Mod+M) 10 minutes later
3. **Badge is still visible** (in-memory daemon state persists)
4. Click window item → badge clears as expected

**Reliability**: Badges don't disappear due to UI state changes.

## Features

### P1: Visual Badge on Window Awaiting Input (Core Feature)

- **Badge Appearance**: Bell icon (🔔) with count on window items
- **Badge Position**: Top-right overlay, doesn't shift layout
- **Badge Color**: Catppuccin Mocha Mauve (rgba(203, 166, 247, 0.9))
- **Badge Clearing**: Immediate on window focus (any duration, any method)
- **Update Latency**: <100ms from notification to UI update

### P2: Badge Persistence Across Panel Toggles

- **In-Memory State**: Badges survive panel hide/show cycles
- **Daemon Restart**: Badges lost (acceptable - in-memory only)
- **Project Switches**: Badges persist for hidden (scratchpad) windows

### P3: Project-Level Badge Aggregation (Future Enhancement)

- **Projects Tab**: Shows aggregated badge count for projects with badged windows
- **Example**: Project A has 2 badged windows (counts 2 and 1) → Project tab shows "3"
- **Implementation**: Deferred to P3 milestone

### P4: Multi-Notification Counting

- **Count Increments**: Multiple notifications on same window increment count
- **Display Overflow**: Counts > 9 shown as "9+" (prevents UI clutter)
- **Actual Count**: Preserved internally for diagnostics

## Keyboard Shortcuts

| Shortcut | Action | Badge Behavior |
|----------|--------|----------------|
| `Mod+M` | Toggle monitoring panel | Badges visible when panel open |
| `Mod+Shift+M` | Enter monitoring focus mode | Navigate to badged windows with keyboard |
| `Alt+1` | Switch to Windows tab | View all badged windows |
| `Alt+2` | Switch to Projects tab | View projects with badged windows (P3) |
| `Escape` | Exit focus mode | Badge remains until window focused |

**Badge Clearing**: Focus window by ANY method (panel click, Alt+Tab, Sway commands, keyboard navigation) → badge clears immediately.

## Troubleshooting

### Badge Doesn't Appear

**Check daemon status**:
```bash
systemctl --user status i3-project-event-listener
```

**Check badge state**:
```bash
badge-ipc get-state
# Should show badges in JSON format
```

**Check monitoring panel service**:
```bash
systemctl --user status eww-monitoring-panel
```

**Check Eww variable**:
```bash
eww --config $HOME/.config/eww-monitoring-panel get panel_state | jq .badges
# Should show badges dict
```

### Badge Doesn't Clear on Focus

**Verify focus event subscription**:
```bash
journalctl --user -u i3-project-event-listener -f | grep "window::focus"
# Should see focus events logged
```

**Manual clear** (workaround):
```bash
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | select(.focused==true).id')
badge-ipc clear "$WINDOW_ID"
```

### Badge Persists After Window Close

**Symptom**: Badge remains in monitoring panel after closing window.

**Cause**: Window close event not handled properly (orphaned badge).

**Fix**: Restart daemon to trigger orphan cleanup:
```bash
systemctl --user restart i3-project-event-listener
```

**Manual cleanup**:
```bash
badge-ipc get-state  # Note window IDs with badges
swaymsg -t get_tree | jq '.. | select(.type=="con").id'  # List existing windows
# Clear badges for windows not in list
badge-ipc clear <orphaned_window_id>
```

### Badge Count Incorrect

**Symptom**: Badge shows wrong count (e.g., shows "1" but should be "2").

**Cause**: Race condition between notification hooks firing simultaneously.

**Workaround**: Focus window and re-trigger notification to reset count.

**Prevention**: Notification hooks should use serial execution (not parallel).

## CLI Commands

### badge-ipc (Helper Script)

```bash
# Create badge (or increment if exists)
badge-ipc create <window_id> [source]
# Example: badge-ipc create 12345 claude-code

# Clear badge (manual - usually happens on focus)
badge-ipc clear <window_id>
# Example: badge-ipc clear 12345

# Get all badge state (diagnostics)
badge-ipc get-state
# Output: JSON dict of all badges

# Test badge creation for current window
badge-ipc create-current [source]
# Creates badge for currently focused window
```

### i3pm CLI (Indirect Badge Operations)

```bash
# Query window state (includes badge status in future)
i3pm windows --json | jq '.[] | select(.has_badge==true)'

# Focus window by ID (clears badge as side effect)
swaymsg "[con_id=12345] focus"
```

## Configuration

### Enable/Disable Badge Feature

Badges are enabled by default. To disable:

```nix
# In home-modules/desktop/eww-monitoring-panel.nix
programs.eww-monitoring-panel = {
  enable = true;
  enableBadges = false;  # Disable badge rendering
};
```

**Note**: Daemon still tracks badge state (for future enable), but Eww doesn't render badges.

### Customize Badge Appearance

Badge styling in `eww-monitoring-panel.nix`:

```css
.window-badge {
  background-color: rgba(203, 166, 247, 0.9); /* Catppuccin Mocha Mauve */
  border: 1px solid #cba6f7;
  border-radius: 12px;
  padding: 2px 6px;
  font-size: 10px;
  color: #1e1e2e; /* Base color */
}
```

**Customization Options**:
- Change `background-color` for different badge color
- Adjust `border-radius` for square vs rounded badges
- Modify `font-size` for larger/smaller counts
- Change icon from 🔔 to custom Unicode character

## Performance

### Latency Targets

| Operation | Target | Measured |
|-----------|--------|----------|
| Badge appearance (notification → UI) | <100ms | TBD (test) |
| Badge clearing (focus → UI update) | <100ms | TBD (test) |
| Badge IPC create call | <10ms | TBD (test) |
| Badge IPC clear call | <5ms | TBD (test) |

### Memory Overhead

| Scenario | Memory Usage |
|----------|--------------|
| 1 badge | ~200 bytes |
| 10 badges | ~2KB |
| 50 badges (typical) | ~10KB |
| 100 badges (stress test) | ~20KB |

### Scalability

- **Max badges tested**: 20+ concurrent badges without degradation (SC-005)
- **Max badge count**: 9999 (displays as "9+")
- **Event rate**: 100+ badge create/clear events per hour (typical Claude Code + build usage)

## Next Steps

### For Users

1. Update NixOS configuration: `sudo nixos-rebuild switch --flake .#<target>`
2. Restart monitoring panel: `systemctl --user restart eww-monitoring-panel`
3. Restart daemon: `systemctl --user restart i3-project-event-listener`
4. Open monitoring panel (Mod+M) and trigger a test notification
5. Verify badge appears on window item

### For Developers

1. Read [data-model.md](./data-model.md) for badge state structure
2. Read [contracts/badge-ipc.json](./contracts/badge-ipc.json) for IPC API
3. Integrate badge creation into notification hooks
4. Test badge lifecycle (create → increment → clear)
5. Run test suite: `pytest tests/095-visual-notification-badges/`

## Related Features

- **Feature 085**: Eww monitoring panel (badge UI rendering target)
- **Feature 090**: Notification callbacks (desktop notifications that trigger badges)
- **Feature 086**: Monitoring focus mode (keyboard navigation to badged windows)
- **Feature 091**: Optimized project switching (badges persist during switches)

## FAQ

**Q: Do badges replace desktop notifications?**
A: No, badges complement notifications. Desktop notifications provide immediate alerts, badges provide persistent reminders.

**Q: Can I disable badges for specific windows?**
A: Not in MVP. Badge creation is controlled at the source (notification hook), not per-window filtering.

**Q: Do badges survive system reboot?**
A: No, badges are in-memory only. Daemon restart or reboot clears all badges.

**Q: Can I manually create badges for testing?**
A: Yes, use `badge-ipc create-current test` to create a test badge on the currently focused window.

**Q: Why does the badge show "9+" instead of the actual count?**
A: Visual overflow protection. Counts > 9 are displayed as "9+" to prevent UI clutter, but actual count is preserved internally.

**Q: How do I know which notification source a badge came from?**
A: Badge source is visible in diagnostics (`badge-ipc get-state`). UI doesn't differentiate sources in MVP (all badges look the same).
