# Feature 090: Enhanced Notification Callback (SwayNC Edition) - Status Report

## ✅ COMPLETED

### Architecture Changes

**Previous Approach** (FAILED):
- Relied on SwayNC's built-in `scripts` system with `run-on: "action"`
- stop-notification.sh saved metadata to `/tmp/claude-code-notification-*.meta`
- Expected SwayNC to trigger callback script with `SWAYNC_ID` environment variable
- **Problem**: SwayNC never executed the callback script when action was clicked

**New Approach** (WORKING):
- Uses `notify-send -w` to wait for action response directly
- stop-notification.sh blocks until user clicks button or dismisses notification
- When action is clicked, `notify-send -w` returns the action ID ("focus")
- Script then executes callback directly, passing metadata via environment variables
- **No dependency on SwayNC's unreliable script system**

### 1. Compact SwayNC Styling
- **Base font size**: 14px → 11px
- **Notification title**: 16px → 12px
- **Notification body**: 13px → 11px
- **Action buttons**: 10px font, 4px×10px padding (was 8px×16px)
- **Close button**: 18px (was 24px)
- **Notification padding**: 6px×8px (was 12px)
- **Border width**: 1px (was 2px)

### 2. Eww Monitoring Panel Styling Consistency
- **Control center background**: `rgba(30, 30, 46, 0.50)` - 50% transparency (matching eww panel)
- **Border**: 1px solid (matching eww panel's lighter borders)
- **Padding**: 8px (matching eww panel)
- **Rounded corners**: 12px border-radius

### 3. Notification-Focused Layout
**Widget order** (8 widgets, no button grid):
1. Title bar
2. Do Not Disturb toggle
3. **Notifications** (at position 3 - top priority)
4. MPRIS media controls
5. Brightness header
6. Backlight slider (display main)
7. Backlight slider (display sidecar - M1 only)
8. Backlight slider (keyboard)

**Removed**: System monitor button grid (8 buttons: htop, btop, bmon, gdu, network tools)

### 4. Notification Action System
✅ SwayNC action buttons work correctly
✅ `notify-send -w -A "id=Label"` returns action ID when clicked
✅ Can trigger Sway commands (e.g., `swaymsg workspace number 1`) from notification actions
✅ Callback script execution via direct invocation (bypassing SwayNC scripts)

### 5. Scripts and Configuration

**stop-notification.sh** (`/etc/nixos/scripts/claude-hooks/stop-notification.sh`):
- Captures window ID, project name, tmux context
- Sends notification with `notify-send -w -A "focus=🖥️  Return to Window"`
- Blocks until user clicks button or dismisses
- If action "focus" is returned, executes callback directly
- Passes metadata via environment variables (`CALLBACK_WINDOW_ID`, `CALLBACK_PROJECT_NAME`, etc.)

**swaync-action-callback.sh** (`/etc/nixos/scripts/claude-hooks/swaync-action-callback.sh`):
- Reads metadata from environment variables (not files)
- Validates window still exists
- Switches to i3pm project if specified
- Focuses terminal window via `swaymsg [con_id=$WINDOW_ID] focus`
- Selects tmux window if specified

**SwayNC Configuration** (`/etc/nixos/home-modules/desktop/swaync.nix`):
- **Removed**: `scripts` configuration (no longer needed)
- **Added**: Documentation explaining why we don't use SwayNC's script system
- **Keyboard shortcuts**: Return/Enter triggers action-0 (the "Return to Window" button)

## 🎯 How It Works

```
┌─────────────────────────────────────────────────────────────┐
│ Claude Code stops and waits for user input                 │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ stop-notification.sh captures context:                      │
│  • WINDOW_ID (Sway window ID)                               │
│  • PROJECT_NAME (i3pm project)                              │
│  • TMUX_SESSION, TMUX_WINDOW (tmux context)                 │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ notify-send -w -A "focus=🖥️  Return to Window" ...         │
│ (Script BLOCKS here waiting for user interaction)          │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
┌──────────────┐    ┌──────────────┐
│ User clicks  │    │ User dismisses│
│ "Return to   │    │ notification  │
│ Window"      │    │               │
└──────┬───────┘    └──────┬────────┘
       │                   │
       │ Returns "focus"   │ Returns empty
       ▼                   ▼
┌──────────────────┐    ┌──────────────┐
│ Execute callback │    │ No action    │
│ script directly  │    │              │
└──────┬───────────┘    └──────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ swaync-action-callback.sh:                                   │
│  1. Read metadata from environment variables                 │
│  2. Validate window exists                                   │
│  3. Switch to i3pm project (if specified)                    │
│  4. Focus terminal window                                    │
│  5. Select tmux window (if specified)                        │
└──────────────────────────────────────────────────────────────┘
```

## 📊 Summary

**Working**:
- ✅ Compact, clean SwayNC styling matching eww monitoring panel
- ✅ Notification-focused layout (no button clutter)
- ✅ Notification actions work perfectly (`notify-send -A` + `-w`)
- ✅ Window focus commands work
- ✅ Callback execution via direct invocation
- ✅ Cross-project navigation (switches projects, focuses windows, selects tmux panes)
- ✅ Environment variable-based metadata passing (no temp files)

**Not Working**: Nothing - all functionality complete!

## 🔍 Key Insights

1. **SwayNC's script system is unreliable**: The `run-on: "action"` feature doesn't consistently execute scripts or provide environment variables as documented.

2. **notify-send -w is the reliable approach**: By using the `-w` (wait) flag, we can block until user interaction and get the action ID directly from notify-send's return value.

3. **Direct callback execution is simpler**: Instead of relying on SwayNC to execute our callback, we execute it directly from stop-notification.sh after detecting the action response.

4. **Environment variables beat temp files**: Passing metadata via environment variables (`export CALLBACK_*`) is cleaner than creating/cleaning up temp files.

## 🚀 Usage

When Claude Code completes a task and waits for input, it triggers:

```bash
/etc/nixos/scripts/claude-hooks/stop-notification.sh
```

This will:
1. Send notification with "Return to Window" button
2. Block until you click or dismiss
3. If you click the button (or press Enter), it:
   - Switches to the correct i3pm project
   - Focuses the terminal window
   - Selects the correct tmux window
4. If you dismiss, it does nothing

**Keyboard shortcut**: Press **Enter** or **Return** to activate the button.

## 🧪 Testing

```bash
# Test notification display and action
notify-send -w -A "test=Test Action" "Test" "Click the button or press Enter"

# Test full callback workflow
/etc/nixos/scripts/claude-hooks/stop-notification.sh
# Then click "Return to Window" button or press Enter
```

---

**Status**: ✅ FEATURE COMPLETE
**Last Updated**: 2025-11-22
**Architecture**: `notify-send -w` with direct callback execution
