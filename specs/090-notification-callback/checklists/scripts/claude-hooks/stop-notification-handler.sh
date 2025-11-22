#!/usr/bin/env bash
# Claude Code Stop Notification Handler
#
# This script runs in the background to send a notification with an action button
# and wait for the user to click it. When clicked, it focuses the terminal window
# running Claude Code and selects the correct tmux window.
#
# Feature 079: T067-T070 - Enhanced with tmux session navigation
#
# Arguments:
#   $1 - Window ID of terminal running Claude Code (or empty)
#   $2 - Notification body (message + context)
#   $3 - Tmux session name (optional)
#   $4 - Tmux window index (optional)

set -euo pipefail

WINDOW_ID="${1:-}"
FULL_MESSAGE="${2:-Task complete - awaiting your input}"
TMUX_SESSION="${3:-}"
TMUX_WINDOW="${4:-}"

# Make notification brief - extract first line or first sentence (max 80 chars)
MESSAGE=$(echo "$FULL_MESSAGE" | head -1 | cut -c1-80)
if [ ${#MESSAGE} -lt ${#FULL_MESSAGE} ]; then
    MESSAGE="${MESSAGE}..."
fi

# Feature 079: T067 - Add source info with tmux session:window
if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    MESSAGE="${MESSAGE}\n\nSource: ${TMUX_SESSION}:${TMUX_WINDOW}"
fi

# Icon: use robot/AI-like icon or terminal icon
ICON="robot"  # Standard freedesktop icon for AI/bot

# Send notification with SwayNC
if [ -n "$WINDOW_ID" ]; then
    # Feature 079: T067 - Send with action buttons (Return to Window, Dismiss)
    # --transient makes notification auto-dismiss when actions complete
    RESPONSE=$(notify-send \
        -i "$ICON" \
        -u normal \
        -w \
        --transient \
        -A "focus=🖥️  Return to Window" \
        -A "dismiss=Dismiss" \
        "Claude Code Ready" \
        "$MESSAGE" 2>/dev/null || echo "dismiss")

    # Feature 079: T068 - Implement response handling for "focus" action
    if [ "$RESPONSE" = "focus" ]; then
        # Feature 079: T069 - Focus terminal window first
        swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1 || true

        # Feature 079: T069 - Add tmux select-window command with session:window
        if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
            # Feature 079: T070 - Add error handling for non-existent tmux session
            if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
                # Select the specific window in the session
                tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
            else
                # Session doesn't exist - just focus the terminal window
                # The swaymsg focus above already handled this
                :
            fi
        fi
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
