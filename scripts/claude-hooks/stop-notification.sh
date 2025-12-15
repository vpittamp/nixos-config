#!/usr/bin/env bash
# Claude Code Stop Notification Script
# Feature 090: Enhanced Notification Callback (SwayNC Edition)
# Feature 106: Portable paths via FLAKE_ROOT
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

# Feature 106: FLAKE_ROOT discovery for portable paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../lib/flake-root.sh" ]]; then
    source "$SCRIPT_DIR/../lib/flake-root.sh"
else
    # Fallback: try to find via git or use default
    FLAKE_ROOT="${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "/etc/nixos")}"
fi

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

# Debug: Log window detection result
logger -t claude-stop "[Feature 120] Window detection: TMUX=${TMUX:-unset}, WINDOW_ID=${WINDOW_ID:-empty}"

# Feature 117: File-only badge storage (removed IPC dual-write)
# Files at $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json are the single source of truth

# Get project name from environment (set by app-launcher-wrapper.sh)
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"

if [ -n "$WINDOW_ID" ]; then
    # Update badge file to stopped state (monitoring_data.py reads via inotify)
    BADGE_STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
    mkdir -p "$BADGE_STATE_DIR"
    BADGE_FILE="$BADGE_STATE_DIR/$WINDOW_ID.json"
    # Feature 117: Include project in badge for efficient lookup
    cat > "$BADGE_FILE" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "stopped",
  "source": "claude-code",
  "project": "$PROJECT_NAME",
  "count": 1,
  "timestamp": $(date +%s.%N)
}
EOF
fi

# Get tmux context if running in tmux (kept for callback, not shown in notification)
TMUX_SESSION=""
TMUX_WINDOW=""
if [ -n "${TMUX:-}" ]; then
    TMUX_SESSION=$(tmux display-message -p "#{session_name}" 2>/dev/null || echo "")
    TMUX_WINDOW=$(tmux display-message -p "#{window_index}" 2>/dev/null || echo "")
fi

# Feature 117: Concise notification content
# Show only project name (or "Awaiting input" if no project)
# Remove verbose tmux session:window info
if [ -n "$PROJECT_NAME" ]; then
    MESSAGE="📁 ${PROJECT_NAME}"
else
    MESSAGE="Awaiting input"
fi

# Send notification with action button and wait for response
# The -w flag makes notify-send wait until user interacts with notification
# It will return the action ID if an action was clicked, or empty string if dismissed
RESPONSE=$(notify-send \
    -i "robot" \
    -u normal \
    -w \
    -A "focus=Return to Window" \
    "Claude Code Ready" \
    "$MESSAGE" 2>&1 || echo "")

# Debug: Log notification response
logger -t claude-stop "[Feature 120] Notification response: '$RESPONSE'"

# If user clicked the "Return to Window" button, execute callback
if [ "$RESPONSE" = "focus" ]; then
    # Call the callback script directly, passing metadata via environment variables
    # This bypasses SwayNC's script system entirely
    export CALLBACK_WINDOW_ID="$WINDOW_ID"
    export CALLBACK_PROJECT_NAME="$PROJECT_NAME"
    export CALLBACK_TMUX_SESSION="$TMUX_SESSION"
    export CALLBACK_TMUX_WINDOW="$TMUX_WINDOW"

    logger -t claude-stop "[Feature 120] Executing callback with WINDOW_ID=$WINDOW_ID, PROJECT_NAME=$PROJECT_NAME"

    # Execute callback script (Feature 119: Use SCRIPT_DIR for reliable path)
    "$SCRIPT_DIR/swaync-action-callback.sh"

    logger -t claude-stop "[Feature 120] Callback completed with exit code $?"
fi

exit 0
