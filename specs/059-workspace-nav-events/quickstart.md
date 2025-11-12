# Quickstart: Workspace Navigation with Arrow Keys

**Feature**: 059-workspace-nav-events
**Status**: Implemented
**Platform**: Hetzner (Ctrl+0), M1 (CapsLock)

## Overview

Navigate through workspace previews using arrow keys, Home/End for jumping, and Delete to close windows - all without touching the mouse.

**Quick Keys**:
- **Arrow Keys** (↑↓←→): Navigate between workspaces and windows
- **Home/End**: Jump to first/last item
- **Delete**: Close selected window
- **Enter**: Switch to highlighted workspace
- **Escape**: Cancel without switching

## Basic Usage

### 1. Enter Workspace Mode

**Hetzner** (x86_64): Press `Ctrl+0`
**M1** (arm64): Press `CapsLock`

You'll see a preview overlay showing all workspaces with their windows.

### 2. Navigate with Arrow Keys

**Down (↓)**: Move highlight to next workspace
**Up (↑)**: Move highlight to previous workspace
**Right (→)**: Enter workspace to see individual windows
**Left (←)**: Exit workspace back to workspace list

**Wrapping**: Navigation wraps at boundaries (last → first, first → last)

### 3. Confirm or Cancel

**Enter**: Switch to highlighted workspace
**Escape**: Cancel and stay on current workspace

---

## Examples

### Example 1: Navigate to Workspace 23

```
1. Press Ctrl+0 (or CapsLock on M1)
   → Preview shows all workspaces

2. Press ↓ repeatedly until workspace 23 is highlighted
   → Visual highlight moves with each press (<50ms latency)

3. Press Enter
   → Switch to workspace 23, preview closes
```

**Tip**: Type "2" then "3" to filter to workspace 23 immediately, then navigate from there.

### Example 2: Navigate Within a Workspace

```
1. Press Ctrl+0
   → Preview shows all workspaces

2. Press ↓ to highlight workspace 5 (has 3 windows)
   → Workspace 5 highlighted

3. Press → to enter workspace
   → First window in workspace 5 highlighted

4. Press ↓ twice
   → Navigate through 3 windows in workspace 5

5. Press Enter
   → Focus on third window, workspace mode exits
```

### Example 3: Close a Window from Preview

```
1. Press Ctrl+0
   → Preview shows all workspaces

2. Navigate to desired workspace with ↓/↑
   → Workspace highlighted

3. Press → to see windows
   → First window highlighted

4. Navigate to unwanted window with ↓/↑
   → Window highlighted

5. Press Delete
   → Window closes, highlight moves to next window

6. Press Escape to exit without switching
   → Workspace mode exits, stay on current workspace
```

### Example 4: Jump with Home/End

```
1. Press Ctrl+0
   → Preview shows workspaces 1-70

2. Press End
   → Jump to last workspace with windows (e.g., workspace 52)

3. Press Home
   → Jump back to first workspace (workspace 1)

4. Press Enter
   → Switch to workspace 1
```

---

## Keybindings Reference

### In Workspace Mode (after Ctrl+0 or CapsLock)

| Key | Action |
|-----|--------|
| ↓ | Navigate to next workspace/window |
| ↑ | Navigate to previous workspace/window |
| → | Enter workspace (show windows) |
| ← | Exit workspace (back to workspace list) |
| Home | Jump to first item |
| End | Jump to last item |
| Delete | Close selected window |
| Enter | Switch to highlighted workspace |
| Escape | Cancel workspace mode |
| 0-9 | Type workspace number (filters list) |

### Outside Workspace Mode

| Key | Action |
|-----|--------|
| Ctrl+0 (Hetzner) | Enter workspace mode (goto) |
| CapsLock (M1) | Enter workspace mode (goto) |
| Ctrl+0 Shift (Hetzner) | Enter workspace mode (move) |
| CapsLock Shift (M1) | Enter workspace mode (move) |

---

## Navigation Modes

### Goto Mode (Default)

**Trigger**: Ctrl+0 or CapsLock

Navigating and pressing Enter **switches to** the highlighted workspace.

**Example**:
```
Ctrl+0 → ↓ (3 times) → Enter
= Switch to workspace 4
```

### Move Mode (Advanced)

**Trigger**: Ctrl+0 Shift or CapsLock Shift

Navigating and pressing Enter **moves current window** to highlighted workspace and follows.

**Example**:
```
Ctrl+0 Shift → ↓ (2 times) → Enter
= Move current window to workspace 3 and follow
```

---

## Visual Feedback

### Highlight Colors

- **Yellow**: Pending/highlighted item (where you'll navigate when pressing Enter)
- **Blue**: Currently focused workspace (where you are now)
- **Light Blue**: Workspace visible on another monitor
- **Red**: Workspace with urgent window
- **Dimmed**: Empty workspace

### Preview Card Layout

```
╔═══════════════════════════════════════╗
║  → WS 23  (goto mode)                 ║  ← Mode indicator
╠═══════════════════════════════════════╣
║  WS 1  [alacritty] [firefox]          ║  ← Other workspaces
║  WS 2  [code] [ghostty]               ║
║ ⯈WS 23 [youtube] [claude] [btop]      ║  ← Highlighted workspace
║  WS 50 [youtube]                      ║
╚═══════════════════════════════════════╝
```

**Icons**: App-specific icons displayed next to app names (via pyxdg desktop entry resolution)

---

## Performance

- **Latency**: <50ms from keypress to visual feedback (typically ~20ms)
- **Rapid Navigation**: Handles 10+ key presses per second without dropping events
- **CPU Overhead**: <1% CPU usage for navigation event processing
- **State Sync**: Real-time updates when windows open/close during navigation

---

## Troubleshooting

### Preview doesn't appear after Ctrl+0

**Check**:
```bash
# 1. Verify daemons running
systemctl --user status i3-project-event-listener
systemctl --user status workspace-preview-daemon

# 2. Check keybinding
grep "Control+0" ~/.config/sway/config

# 3. Verify workspace mode entry
i3pm workspace-mode state
# Should show: active=true
```

**Fix**: Restart daemons
```bash
systemctl --user restart i3-project-event-listener
systemctl --user restart workspace-preview-daemon
```

### Arrow keys don't navigate

**Check**:
```bash
# 1. Test nav command directly
i3pm-workspace-mode nav down
# Should emit nav event

# 2. Check workspace-preview-daemon logs
journalctl --user -u workspace-preview-daemon -f | grep "nav event"
# Should see: "DEBUG: Received nav event: direction=down"

# 3. Verify keybindings exist
grep "bindsym Down exec i3pm-workspace-mode nav down" ~/.config/sway/config
```

**Fix**: Feature 059 may not be fully implemented. Check that:
- WorkspaceModeManager has nav() and delete() methods
- workspace-preview-daemon has navigation event handlers
- Sway keybindings call i3pm-workspace-mode nav <direction>

### Highlight doesn't move when pressing arrows

**Check**:
```bash
# 1. Verify SelectionManager is updating
i3pm daemon events --type=workspace_mode | grep nav
# Should see nav events when pressing arrows

# 2. Check preview daemon is receiving events
journalctl --user -u workspace-preview-daemon -f
# Should see "Received nav event" messages
```

**Fix**: Preview daemon may not be subscribed to i3pm events
```bash
# Restart preview daemon to re-establish IPC connection
systemctl --user restart workspace-preview-daemon
```

### Delete key doesn't close windows

**Check**:
```bash
# 1. Verify Delete keybinding
grep "bindsym Delete exec i3pm-workspace-mode delete" ~/.config/sway/config

# 2. Test delete command directly
i3pm-workspace-mode delete
# Should emit delete event

# 3. Check you have a window selected
# (Navigate to a window with → first, then press Delete)
```

**Fix**: Ensure you're inside a workspace (pressed →) before deleting

### Navigation is slow (>100ms latency)

**Check**:
```bash
# 1. Monitor daemon CPU usage
top -p $(pgrep -f i3-project-event-listener)
# Should be <5% CPU

# 2. Check event queue
i3pm daemon events --type=tick | grep filtering
# Should not show backlog
```

**Fix**: Restart daemon if CPU usage high
```bash
systemctl --user restart i3-project-event-listener
```

---

## Advanced Usage

### Combine Typing + Navigation

```
1. Ctrl+0 → Type "2" → ↓ (3 times)
   → Filter to workspaces 20-29, navigate to workspace 23

2. Press Enter
   → Switch to workspace 23
```

**Tip**: Typing digits filters the workspace list, arrow keys navigate within the filtered results.

### Multi-Monitor Navigation

Navigation is monitor-aware - workspaces appear in the preview based on their assigned monitor role (primary/secondary/tertiary).

**Example** (3-monitor setup):
```
Ctrl+0 → Preview shows:
  Monitor 1 (primary): WS 1-2
  Monitor 2 (secondary): WS 3-5
  Monitor 3 (tertiary): WS 6-70

Press ↓ to navigate across all monitors' workspaces sequentially.
```

### Project Mode Navigation

Press `:` during workspace mode to switch to project navigation:

```
Ctrl+0 → Type ":" → Type "nix" → Enter
= Switch to "nixos" project

(Arrow keys work in project mode too!)
```

---

## CLI Commands

### Query Navigation State

```bash
# Get current workspace mode state
i3pm workspace-mode state

# Output:
# {
#   "active": true,
#   "mode_type": "goto",
#   "accumulated_digits": "2",
#   "entered_at": "2025-11-12T14:30:00Z"
# }
```

### Manual Navigation (for testing)

```bash
# Enter workspace mode
i3pm-workspace-mode enter

# Navigate down
i3pm-workspace-mode nav down

# Navigate up
i3pm-workspace-mode nav up

# Jump to first
i3pm-workspace-mode nav home

# Jump to last
i3pm-workspace-mode nav end

# Delete selected window
i3pm-workspace-mode delete

# Cancel mode
i3pm-workspace-mode cancel
```

### Monitor Events

```bash
# Watch all workspace mode events
i3pm daemon events --type=workspace_mode

# Filter to nav events only
i3pm daemon events --type=workspace_mode | grep '"event_type": "nav"'

# Monitor with timestamps
i3pm daemon events --type=workspace_mode --follow
```

---

## Related Features

- **Feature 042**: Event-Driven Workspace Mode (digit entry, workspace switching)
- **Feature 058**: Workspace Mode Visual Feedback (pending workspace highlight)
- **Feature 059**: Interactive Workspace Menu (SelectionManager, NavigationHandler)
- **Feature 072**: Unified Workspace Switcher (all-windows preview rendering)

## See Also

- `/etc/nixos/specs/042-event-driven-workspace-mode/quickstart.md` - Workspace mode basics
- `/etc/nixos/specs/057-unified-bar-system/quickstart.md` - Visual feedback system
- `/etc/nixos/specs/072-unified-workspace-switcher/quickstart.md` - All-windows preview
- `/etc/nixos/CLAUDE.md` - Complete keyboard shortcut reference

---

**Last Updated**: 2025-11-12
**Feature Status**: Implemented (Feature 059)
**Platforms**: Hetzner (x86_64 Sway), M1 (arm64 Sway)
