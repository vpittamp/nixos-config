#!/usr/bin/env bash
# SwayNC Action Callback for Claude Code Notifications
# Feature 090: Enhanced Notification Callback
# Feature 119: Rewritten to mirror focusWindowScript logic for reliable window focusing
#
# This script is triggered by SwayNC when the user clicks the "Return to Window"
# action button or presses Enter on a Claude Code notification.
#
# SwayNC provides environment variables:
#   SWAYNC_BODY - Notification body text
#   SWAYNC_SUMMARY - Notification summary/title
#   SWAYNC_ID - Notification ID
#
# We receive callback context via environment variables from stop-notification.sh:
#   CALLBACK_WINDOW_ID - Sway window ID to focus
#   CALLBACK_PROJECT_NAME - Project name for context switch
#   CALLBACK_TMUX_SESSION - Tmux session name (if applicable)
#   CALLBACK_TMUX_WINDOW - Tmux window index (if applicable)

set -euo pipefail

# Fix PATH for systemd service execution (SwayNC may have limited PATH)
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Feature 119: Two notification callback methods
# Method 1: Environment variables (preferred - set by stop-notification.sh)
# Method 2: Metadata files (fallback - for manual testing)

if [ -n "${CALLBACK_WINDOW_ID:-}" ]; then
    # Method 1: stop-notification.sh passed metadata via environment variables
    WINDOW_ID="${CALLBACK_WINDOW_ID}"
    PROJECT_NAME="${CALLBACK_PROJECT_NAME:-}"
    TMUX_SESSION="${CALLBACK_TMUX_SESSION:-}"
    TMUX_WINDOW="${CALLBACK_TMUX_WINDOW:-}"
elif [ -n "${SWAYNC_ID:-}" ]; then
    # Method 2: Metadata file from manual testing or SwayNC script system
    STATE_FILE="/tmp/claude-code-notification-${SWAYNC_ID}.meta"

    if [ ! -f "$STATE_FILE" ]; then
        notify-send -u low "Claude Code" "Window context lost - please return to terminal manually"
        exit 0
    fi

    # Read metadata from file
    WINDOW_ID=$(grep "^WINDOW_ID=" "$STATE_FILE" | cut -d= -f2)
    PROJECT_NAME=$(grep "^PROJECT_NAME=" "$STATE_FILE" | cut -d= -f2)
    TMUX_SESSION=$(grep "^TMUX_SESSION=" "$STATE_FILE" | cut -d= -f2)
    TMUX_WINDOW=$(grep "^TMUX_WINDOW=" "$STATE_FILE" | cut -d= -f2)

    # Clean up state file
    rm -f "$STATE_FILE"
else
    # No metadata available
    notify-send -u critical "Claude Code" "No window context available - callback failed"
    exit 1
fi

# Feature 119: Verify window still exists before attempting to focus
WINDOW_EXISTS=$(swaymsg -t get_tree | jq -r --arg id "$WINDOW_ID" '
    .. | objects | select(.type=="con") | select(.id == ($id | tonumber)) | .id
' 2>/dev/null | head -1 || echo "")

if [ -z "$WINDOW_EXISTS" ]; then
    notify-send -u critical "Claude Code Terminal Unavailable" \
        "The terminal window running Claude Code has been closed."
    exit 0
fi

# Feature 119: Get current project from active-worktree.json (single source of truth)
# This mirrors the focusWindowScript logic exactly
CURRENT_PROJECT=$(jq -r '.qualified_name // "global"' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "global")

# Debug: Log the currently focused window and its marks BEFORE switch
FOCUSED_BEFORE=$(swaymsg -t get_tree | jq -r '.. | objects | select(.focused==true) | "\(.id) \(.app_id // .window_class) \(.marks)"' 2>/dev/null | head -1)
logger -t claude-callback "[Feature 119] Before switch: focused=$FOCUSED_BEFORE, current_project=$CURRENT_PROJECT, target_project=$PROJECT_NAME"

# Feature 119: Only switch projects if different (avoid unnecessary switches)
if [ -n "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]; then
    # Check if i3pm daemon is available
    if command -v i3pm >/dev/null 2>&1; then
        # Log before switch for debugging
        logger -t claude-callback "[Feature 119] Switching project: $CURRENT_PROJECT -> $PROJECT_NAME (window_id=$WINDOW_ID)"

        # Feature 119: Synchronous project switch (no arbitrary sleep)
        # i3pm worktree switch completes synchronously
        # NOTE: Removed 2>/dev/null to ensure errors are visible for debugging
        SWITCH_OUTPUT=$(i3pm worktree switch "$PROJECT_NAME" 2>&1)
        SWITCH_EXIT=$?

        if [ $SWITCH_EXIT -ne 0 ]; then
            # Project switch failed - log error and show critical notification
            # Match eww focusWindowScript behavior: exit on failure rather than continue
            logger -t claude-callback "[Feature 119] Project switch FAILED (exit=$SWITCH_EXIT): $SWITCH_OUTPUT"
            notify-send -u critical "Project Switch Failed" \
                "Failed to switch to project $PROJECT_NAME (exit code: $SWITCH_EXIT). Please return to terminal manually."
            exit 1
        fi

        # Log success
        logger -t claude-callback "[Feature 119] Project switched successfully from $CURRENT_PROJECT to $PROJECT_NAME"

        # Verify the switch happened by re-reading the active project
        NEW_ACTIVE=$(jq -r '.qualified_name // "global"' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "global")
        if [ "$NEW_ACTIVE" != "$PROJECT_NAME" ]; then
            logger -t claude-callback "[Feature 119] WARNING: After switch, active project is $NEW_ACTIVE, expected $PROJECT_NAME"
        fi

        # Debug: Check if any visible windows still belong to the origin project (CURRENT_PROJECT)
        # These windows should have been hidden by the project switch
        ORIGIN_WINDOWS=$(swaymsg -t get_tree | jq -r --arg proj "$CURRENT_PROJECT" \
            '.. | objects | select(.type=="con") | select(.app_id != null) |
             select(.marks[] | contains($proj)) |
             select(.marks[] | startswith("scoped:")) |
             "\(.id) \(.app_id)"' 2>/dev/null || echo "")
        if [ -n "$ORIGIN_WINDOWS" ]; then
            logger -t claude-callback "[Feature 119] WARNING: Found visible windows from origin project ($CURRENT_PROJECT): $ORIGIN_WINDOWS"
        fi
    fi
else
    logger -t claude-callback "[Feature 119] No project switch needed: current=$CURRENT_PROJECT, target=$PROJECT_NAME"
fi

# Feature 119: Focus terminal window immediately (no sleep/delay)
logger -t claude-callback "[Feature 119] Attempting to focus window $WINDOW_ID"
FOCUS_OUTPUT=$(swaymsg "[con_id=$WINDOW_ID] focus" 2>&1)
FOCUS_EXIT=$?

if [ $FOCUS_EXIT -ne 0 ]; then
    logger -t claude-callback "[Feature 119] Focus FAILED (exit=$FOCUS_EXIT): $FOCUS_OUTPUT"
    notify-send -u critical "Focus Failed" "Could not focus window $WINDOW_ID"
    exit 1
fi

# Debug: Log the state AFTER focus
FOCUSED_AFTER=$(swaymsg -t get_tree | jq -r '.. | objects | select(.focused==true) | "\(.id) \(.app_id // .window_class) \(.marks)"' 2>/dev/null | head -1)
logger -t claude-callback "[Feature 119] After focus: focused=$FOCUSED_AFTER"

# Feature 119: Clear badge file after successfully focusing window
# This removes the notification badge since the user has returned to the window
BADGE_STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
BADGE_FILE="$BADGE_STATE_DIR/$WINDOW_ID.json"
if [ -f "$BADGE_FILE" ]; then
    rm -f "$BADGE_FILE"
fi

# Feature 119: Select tmux window if specified (after focusing the terminal)
if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
    fi
fi

exit 0
