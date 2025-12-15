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
# Feature 117: Single reliable window detection method (tmux PID → process tree → Sway)
# Remove fallback to focused window - fail explicitly if detection fails
get_terminal_window_id() {
    # Must be running in tmux for reliable detection
    if [ -z "${TMUX:-}" ]; then
        echo ""
        return 1
    fi

    # Get the tmux client PID for our session
    local client_pid
    client_pid=$(tmux display-message -p "#{client_pid}" 2>/dev/null || echo "")

    if [ -z "$client_pid" ]; then
        echo ""
        return 1
    fi

    # Walk up the process tree from tmux client to find ghostty
    local current="$client_pid"
    while [ "$current" != "1" ] && [ -n "$current" ]; do
        local cmd
        cmd=$(ps -p "$current" -o args= 2>/dev/null | head -c 100 || echo "")

        # Check if this is a ghostty process
        if echo "$cmd" | grep -qi ghostty; then
            # Found ghostty - look up its window ID in sway tree
            local window_id
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

    # Detection failed - return empty (no fallback to focused window)
    echo ""
    return 1
}

WINDOW_ID=$(get_terminal_window_id)

# Feature 117: File-only badge storage (removed IPC dual-write)
# Files at $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json are the single source of truth

if [ -n "$WINDOW_ID" ]; then
    # Create badge file (monitoring_data.py reads via inotify)
    BADGE_STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
    mkdir -p "$BADGE_STATE_DIR"
    BADGE_FILE="$BADGE_STATE_DIR/$WINDOW_ID.json"
    # Feature 117: Include project from I3PM_PROJECT_NAME environment variable
    # This is set by app-launcher-wrapper.sh when terminal was launched
    PROJECT_NAME="${I3PM_PROJECT_NAME:-}"
    cat > "$BADGE_FILE" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "working",
  "source": "claude-code",
  "project": "$PROJECT_NAME",
  "timestamp": $(date +%s.%N)
}
EOF
fi

exit 0
