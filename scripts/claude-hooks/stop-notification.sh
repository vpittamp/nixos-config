#!/usr/bin/env bash
# Claude Code Stop Notification Script
# Feature 090: Enhanced Notification Callback (SwayNC Edition)
#
# This script sends a notification when Claude Code stops and waits for input.
# The notification includes an action button that, when clicked, focuses the
# terminal window and switches to the correct project/tmux context.
#
# Architecture:
# 1. This script sends notification with action button using notify-send -w
# 2. notify-send blocks until user clicks button or dismisses notification
# 3. If user clicks "Return to Window" button, we get action ID back
# 4. Script then directly executes the callback logic (focus window, switch project)
#
# This approach is simpler and more reliable than using SwayNC's script system.

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

# Send notification with action button and wait for response
# The -w flag makes notify-send wait until user interacts with notification
# It will return the action ID if an action was clicked, or empty string if dismissed
RESPONSE=$(notify-send \
    -i "robot" \
    -u normal \
    -w \
    -A "focus=🖥️  Return to Window" \
    "Claude Code Ready" \
    "$MESSAGE" 2>&1 || echo "")

# If user clicked the "Return to Window" button, execute callback
if [ "$RESPONSE" = "focus" ]; then
    # Call the callback script directly, passing metadata via environment variables
    # This bypasses SwayNC's script system entirely
    export CALLBACK_WINDOW_ID="$WINDOW_ID"
    export CALLBACK_PROJECT_NAME="$PROJECT_NAME"
    export CALLBACK_TMUX_SESSION="$TMUX_SESSION"
    export CALLBACK_TMUX_WINDOW="$TMUX_WINDOW"

    # Execute callback script
    /etc/nixos/scripts/claude-hooks/swaync-action-callback.sh
fi

exit 0
