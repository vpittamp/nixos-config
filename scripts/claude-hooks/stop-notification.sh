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

# Feature 107: Update badge to "stopped" state using IPC-first with file fallback
# This changes the spinner to a bell icon indicating Claude is waiting for input
# Primary path: IPC to daemon for <100ms latency
# Fallback path: File-based for reliability when daemon unavailable

IPC_SUCCESS=false
if [ -n "$WINDOW_ID" ]; then
    # Try IPC first (fast path)
    IPC_SOCKET="/run/i3-project-daemon/ipc.sock"
    if [ -S "$IPC_SOCKET" ]; then
        # Use badge-ipc-client.sh for IPC communication
        if /etc/nixos/scripts/claude-hooks/badge-ipc-client.sh create "$WINDOW_ID" "claude-code" --state stopped >/dev/null 2>&1; then
            IPC_SUCCESS=true
        fi
    fi

    # Fallback to file-based (reliability path) if IPC failed
    if [ "$IPC_SUCCESS" = false ]; then
        BADGE_STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
        mkdir -p "$BADGE_STATE_DIR"
        BADGE_FILE="$BADGE_STATE_DIR/$WINDOW_ID.json"
        cat > "$BADGE_FILE" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "stopped",
  "source": "claude-code",
  "count": "1",
  "timestamp": $(date +%s)
}
EOF
    fi
fi

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

    # Execute callback script (Feature 106: Use FLAKE_ROOT for portable path)
    "$FLAKE_ROOT/scripts/claude-hooks/swaync-action-callback.sh"
fi

exit 0
