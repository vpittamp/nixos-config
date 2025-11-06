#!/usr/bin/env bash
# Claude Code Stop Notification Handler
#
# This script runs in the background to send a notification with an action button
# and wait for the user to click it. When clicked, it focuses the terminal window
# running Claude Code.
#
# Arguments:
#   $1 - Window ID of terminal running Claude Code (or empty)
#   $2 - Notification body (message + context)

set -euo pipefail

WINDOW_ID="${1:-}"
MESSAGE="${2:-Task complete - awaiting your input}"

# Truncate if too long (SwayNC handles ~500 chars well)
if [ ${#MESSAGE} -gt 500 ]; then
    MESSAGE="${MESSAGE:0:500}..."
fi

# Icon: use robot/AI-like icon or terminal icon
ICON="robot"  # Standard freedesktop icon for AI/bot

# Send notification with SwayNC
if [ -n "$WINDOW_ID" ]; then
    # Send with action button to return to terminal
    RESPONSE=$(notify-send \
        -i "$ICON" \
        -u normal \
        -w \
        -A "focus=🖥️  Return to Terminal" \
        -A "dismiss=Dismiss" \
        "Claude Code Ready" \
        "$MESSAGE" 2>/dev/null || echo "dismiss")

    # If user clicked "Return to Terminal", focus the window
    if [ "$RESPONSE" = "focus" ]; then
        swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1 || true
    fi
else
    # No window ID found, send notification without action
    notify-send \
        -i "$ICON" \
        -u normal \
        "Claude Code Ready" \
        "$MESSAGE" 2>/dev/null || true
fi

exit 0
