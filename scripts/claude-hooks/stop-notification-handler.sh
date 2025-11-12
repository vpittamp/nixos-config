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
FULL_MESSAGE="${2:-Task complete - awaiting your input}"

# Make notification brief - extract first line or first sentence (max 80 chars)
MESSAGE=$(echo "$FULL_MESSAGE" | head -1 | cut -c1-80)
if [ ${#MESSAGE} -lt ${#FULL_MESSAGE} ]; then
    MESSAGE="${MESSAGE}..."
fi

# Icon: use robot/AI-like icon or terminal icon
ICON="robot"  # Standard freedesktop icon for AI/bot

# Send notification with SwayNC
if [ -n "$WINDOW_ID" ]; then
    # Send with action button to return to terminal
    # --transient makes notification auto-dismiss when actions complete
    RESPONSE=$(notify-send \
        -i "$ICON" \
        -u normal \
        -w \
        --transient \
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
    # --transient makes notification auto-dismiss
    notify-send \
        -i "$ICON" \
        -u normal \
        --transient \
        "Claude Code Ready" \
        "$MESSAGE" 2>/dev/null || true
fi

exit 0
