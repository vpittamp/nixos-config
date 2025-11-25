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

# Get window ID of current terminal
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.type=="con") | select(.focused==true) | .id' | head -1)

# Feature 095: Create "working" badge in monitoring panel daemon
# This shows a spinner animation indicating Claude Code is processing
DAEMON_SOCKET="/run/i3-project-daemon/ipc.sock"
if [ -S "$DAEMON_SOCKET" ] && [ -n "$WINDOW_ID" ]; then
    # Send JSON-RPC request to create badge with state="working"
    # Using timeout to prevent hanging if daemon is unresponsive
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"create_badge\",\"params\":{\"window_id\":$WINDOW_ID,\"source\":\"claude-code\",\"state\":\"working\"},\"id\":1}" | \
        timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" >/dev/null 2>&1 || true
fi

exit 0
