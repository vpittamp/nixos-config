#!/usr/bin/env bash
# Claude Code Stop Notification Script
# Feature 090: Enhanced Notification Callback (SwayNC Edition)
#
# This script sends a notification when Claude Code stops and waits for input.
# The notification includes an action button that, when clicked, focuses the
# terminal window and switches to the correct project/tmux context.
#
# Architecture:
# 1. This script sends notification with action button
# 2. SwayNC stores the notification
# 3. User clicks button or presses Enter
# 4. SwayNC triggers swaync-action-callback.sh with SWAYNC_* env vars
# 5. Callback script reads metadata file and focuses window

set -euo pipefail

# Get window ID of current terminal
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' | head -1)

# Get project name from environment
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"

# Get tmux context if running in tmux
TMUX_SESSION=""
TMUX_WINDOW=""
if [ -n "${TMUX:-}" ]; then
    TMUX_SESSION=$(tmux display-message -p "#{session_name}" 2>/dev/null || echo "")
    TMUX_WINDOW=$(tmux display-message -p "#{window_index}" 2>/dev/null || echo "")
fi

# Build notification message
MESSAGE="Task complete - awaiting your input"

# Add project context if available
if [ -n "$PROJECT_NAME" ]; then
    MESSAGE="${MESSAGE}\n\n📁 ${PROJECT_NAME}"
fi

# Add tmux context if available
if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    MESSAGE="${MESSAGE}\n\nSource: ${TMUX_SESSION}:${TMUX_WINDOW}"
fi

# Send notification with action button
# The notification ID will be captured via SwayNC's response
# We'll use a predictable pattern for the state file
NOTIFICATION_OUTPUT=$(notify-send \
    -i "robot" \
    -u normal \
    -p \
    -A "focus=🖥️  Return to Window" \
    "Claude Code Ready" \
    "$MESSAGE" 2>&1)

# Extract notification ID from output (notify-send -p prints the ID)
NOTIFICATION_ID="$NOTIFICATION_OUTPUT"

# Store metadata in a temporary file that the callback script will read
STATE_FILE="/tmp/claude-code-notification-${NOTIFICATION_ID}.meta"
cat > "$STATE_FILE" << METADATA
WINDOW_ID=$WINDOW_ID
PROJECT_NAME=$PROJECT_NAME
TMUX_SESSION=$TMUX_SESSION
TMUX_WINDOW=$TMUX_WINDOW
METADATA

# Set a timeout to clean up the state file if notification is never acted upon
(sleep 300 && rm -f "$STATE_FILE" 2>/dev/null) &

exit 0
