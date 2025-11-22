#!/usr/bin/env bash
# Claude Code Stop Notification Handler
#
# Feature 090: Enhanced Notification Callback for Claude Code
#
# CALLBACK WORKFLOW:
# 1. Receive notification context from stop-notification.sh
# 2. Display SwayNC notification with action buttons:
#    - "Return to Window" (Ctrl+R) - Primary action
#    - "Dismiss" (Escape) - Secondary action
# 3. Wait for user action (blocking until click/dismiss/timeout)
# 4. If "Return to Window" clicked:
#    a. Check if window exists (via Sway IPC) - Feature 090
#    b. Switch to i3pm project (if PROJECT_NAME provided) - Feature 090
#    c. Focus terminal window (via swaymsg con_id focus)
#    d. Check if tmux session exists (via tmux has-session)
#    e. Select tmux window (if session exists)
# 5. If "Dismiss" clicked: Exit immediately (no focus change)
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
#   $5 - i3pm project name (optional) - Feature 090

set -euo pipefail

WINDOW_ID="${1:-}"
FULL_MESSAGE="${2:-Task complete - awaiting your input}"
TMUX_SESSION="${3:-}"
TMUX_WINDOW="${4:-}"
PROJECT_NAME="${5:-}"  # Feature 090: T018 - Receive project name parameter

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

# Feature 090: T042 - Check if SwayNC is available
if ! command -v notify-send >/dev/null 2>&1; then
    # notify-send not available - fallback to terminal bell
    if [ -n "$WINDOW_ID" ]; then
        swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1 || true
        # Send terminal bell (ASCII 7)
        printf '\a' >/dev/tty 2>/dev/null || true
    fi
    exit 0
fi

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
        # Feature 090: T010 - Check if window still exists before focusing
        WINDOW_EXISTS=$(swaymsg -t get_tree | jq -r --arg id "$WINDOW_ID" '
            .. | objects | select(.type=="con") | select(.id == ($id | tonumber)) | .id
        ' | head -1)

        if [ -z "$WINDOW_EXISTS" ]; then
            # Feature 090: T013 - Window no longer exists, show error notification
            notify-send -u critical "Claude Code Terminal Unavailable" \
                "The terminal window running Claude Code has been closed." 2>/dev/null || true
            exit 0
        fi

        # Feature 090: T019 - Switch to i3pm project (if PROJECT_NAME provided)
        if [ -n "$PROJECT_NAME" ]; then
            # Feature 090: T020 - Check if i3pm daemon is available
            if ! systemctl --user is-active i3-project-event-listener >/dev/null 2>&1; then
                # Feature 090: T021 - Show error if daemon unavailable
                notify-send -u low "Project Switch Skipped" \
                    "i3pm daemon not running - focusing terminal without project switch" 2>/dev/null || true
            else
                # Feature 090: T021 - Try project switch with error handling
                if ! i3pm project switch "$PROJECT_NAME" 2>/dev/null; then
                    # Project switch failed - show warning but continue to focus
                    notify-send -u low "Project Switch Failed" \
                        "Could not switch to project '$PROJECT_NAME' - focusing terminal anyway" 2>/dev/null || true
                fi
            fi
        fi

        # Feature 090: T011 - Focus terminal window (only if window exists)
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
