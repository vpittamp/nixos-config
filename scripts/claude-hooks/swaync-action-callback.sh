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

# Feature 119: Only switch projects if different (avoid unnecessary switches)
if [ -n "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]; then
    # Check if i3pm daemon is available
    if command -v i3pm >/dev/null 2>&1; then
        # Feature 119: Synchronous project switch (no arbitrary sleep)
        # i3pm worktree switch completes synchronously
        if ! i3pm worktree switch "$PROJECT_NAME" 2>/dev/null; then
            # Project switch failed - show warning but still try to focus window
            notify-send -u normal "Project Switch Warning" \
                "Failed to switch to project $PROJECT_NAME, attempting to focus window anyway"
        fi

        # Log to systemd journal
        logger -t claude-callback "[Feature 119] Project switched from $CURRENT_PROJECT to $PROJECT_NAME"
    fi
fi

# Feature 119: Focus terminal window immediately (no sleep/delay)
if ! swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1; then
    notify-send -u critical "Focus Failed" "Could not focus window $WINDOW_ID"
    exit 1
fi

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
