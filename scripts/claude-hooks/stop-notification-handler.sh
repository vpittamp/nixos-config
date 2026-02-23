#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/tmp/stop-notification-handler.log"
echo "--- $(date) ---" >> "$LOG_FILE"
echo "Args: $@" >> "$LOG_FILE"

WINDOW_ID="${1:-}"
FULL_MESSAGE="${2:-Task complete - awaiting your input}"
TMUX_SESSION="${3:-}"
TMUX_WINDOW="${4:-}"

MESSAGE=$(echo "$FULL_MESSAGE" | head -1 | cut -c1-80)
if [ ${#MESSAGE} -lt ${#FULL_MESSAGE} ]; then
    MESSAGE="${MESSAGE}..."
fi

if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    MESSAGE="${MESSAGE}\n\nSource: ${TMUX_SESSION}:${TMUX_WINDOW}"
fi

ICON="robot"

if [ -n "$WINDOW_ID" ]; then
    echo "Sending notification with window ID: $WINDOW_ID" >> "$LOG_FILE"
    RESPONSE=$(notify-send -i "$ICON" -u normal -w --transient -A "focus=🖥️  Return to Window" -A "dismiss=Dismiss" "Claude Code Ready" "$MESSAGE" 2>/dev/null || echo "error")
    echo "notify-send response: $RESPONSE" >> "$LOG_FILE"

    if [ "$RESPONSE" = "focus" ]; then
        echo "Executing swaymsg [con_id=$WINDOW_ID] focus" >> "$LOG_FILE"
        swaymsg "[con_id=$WINDOW_ID] focus" >> "$LOG_FILE" 2>&1 || true

        if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
            echo "Selecting tmux window ${TMUX_SESSION}:${TMUX_WINDOW}" >> "$LOG_FILE"
            if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
                tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" >> "$LOG_FILE" 2>&1 || true
            else
                echo "Tmux session $TMUX_SESSION not found" >> "$LOG_FILE"
            fi
        fi
    fi
else
    echo "No window ID provided, sending simple notification" >> "$LOG_FILE"
    notify-send -i "$ICON" -u normal --transient "Claude Code Ready" "$MESSAGE" 2>/dev/null || true
fi

exit 0
