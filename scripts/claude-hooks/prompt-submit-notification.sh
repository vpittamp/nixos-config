#!/usr/bin/env bash
# Claude Code Prompt Submit Notification Script
# Feature 095: Activity Indicator for Claude Code
#
# This script is triggered by Claude Code's UserPromptSubmit hook when
# the user submits a prompt and Claude starts processing.
#
# It creates a "working" badge in the monitoring panel to show that
# Claude Code is actively processing the request.

set -euo pipefail

# Fix PATH for systemd service execution
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Get window ID of the terminal running this hook
# BUG FIX: Previously used focused window, but hook may fire when user has switched
# to another window. Now we trace from tmux client PID up the process tree to find
# the actual terminal window (ghostty) that contains the Claude Code session.
get_terminal_window_id() {
    local window_id=""

    # Method 1: If in tmux, trace from tmux client to find the ghostty window
    if [ -n "${TMUX:-}" ]; then
        # Get the tmux client PID for our session
        local client_pid
        client_pid=$(tmux display-message -p "#{client_pid}" 2>/dev/null || echo "")

        if [ -n "$client_pid" ]; then
            # Walk up the process tree from tmux client to find ghostty
            local current="$client_pid"
            while [ "$current" != "1" ] && [ -n "$current" ]; do
                local cmd
                cmd=$(ps -p "$current" -o args= 2>/dev/null | head -c 100 || echo "")

                # Check if this is a ghostty process
                if echo "$cmd" | grep -qi ghostty; then
                    # Found ghostty - look up its window ID in sway tree
                    window_id=$(swaymsg -t get_tree | jq -r --arg pid "$current" \
                        '.. | objects | select(.app_id) | select(.pid == ($pid | tonumber)) | .id' 2>/dev/null | head -1)
                    if [ -n "$window_id" ] && [ "$window_id" != "null" ]; then
                        echo "$window_id"
                        return 0
                    fi
                fi

                # Move to parent process
                current=$(ps -o ppid= -p "$current" 2>/dev/null | tr -d ' ')
            done
        fi
    fi

    # Method 2: Fallback to focused window (original behavior)
    # This works when not in tmux or if process tracing fails
    window_id=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' 2>/dev/null | head -1)
    echo "$window_id"
}

WINDOW_ID=$(get_terminal_window_id)

# Feature 095: Create "working" badge using file-based state
# This shows a spinner animation indicating Claude Code is processing
# Uses a simple JSON file instead of daemon IPC for reliability
BADGE_STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
mkdir -p "$BADGE_STATE_DIR"

if [ -n "$WINDOW_ID" ]; then
    # Write badge state as JSON file keyed by window ID
    BADGE_FILE="$BADGE_STATE_DIR/$WINDOW_ID.json"
    cat > "$BADGE_FILE" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "working",
  "source": "claude-code",
  "timestamp": $(date +%s)
}
EOF
fi

exit 0
