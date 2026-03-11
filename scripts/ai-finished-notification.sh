#!/usr/bin/env bash
# Unified AI "Finished" notification for all AI CLIs (Claude Code, Codex, Gemini)
#
# Usage: ai-finished-notification.sh CLI_NAME [MESSAGE]
# Env: TMUX (auto-detected), PPID (auto-detected)
#
# This script:
# 1. Walks the process tree to find the owning Sway window
# 2. Detects tmux session/window/pane context
# 3. Sends a desktop notification with "Return to Terminal" action
# 4. On action click, focuses the Sway window and selects the tmux pane

set -euo pipefail

CLI_NAME="${1:-AI}"
MESSAGE="${2:-Task complete - awaiting your input}"

LOG_FILE="/tmp/ai-finished-notification.log"
DAEMON_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
echo "--- $(date) ---" >> "$LOG_FILE"
echo "CLI: $CLI_NAME, Message length: ${#MESSAGE}" >> "$LOG_FILE"

daemon_rpc() {
    local method="$1"
    local params_json="${2:-{}}"
    local request response
    request=$(jq -nc --arg method "$method" --argjson params "$params_json" \
        '{jsonrpc:"2.0", method:$method, params:$params, id:1}')
    [[ -S "$DAEMON_SOCKET" ]] || return 1
    response=$(timeout 2s socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$request" 2>/dev/null || true)
    [[ -n "$response" ]] || return 1
    jq -ec '.result' <<< "$response"
}

# ── Window detection ──────────────────────────────────────────────────
# Walk process tree from PPID to find a matching Sway window ID.
WINDOW_ID=""
START_PID=$PPID

TMUX_SESSION=""
TMUX_WINDOW=""
TMUX_PANE=""

# Check if we're running inside tmux
if [ -n "${TMUX:-}" ]; then
    TMUX_SESSION=$(tmux display-message -p "#{session_name}" 2>/dev/null || true)
    TMUX_WINDOW=$(tmux display-message -p "#{window_index}" 2>/dev/null || true)
    TMUX_PANE=$(tmux display-message -p "#{pane_id}" 2>/dev/null || true)
    echo "Tmux session: $TMUX_SESSION, window: $TMUX_WINDOW, pane: $TMUX_PANE" >> "$LOG_FILE"

    # The actual terminal emulator is the parent of the tmux client process
    TMUX_CLIENT_PID=$(tmux display-message -p "#{client_pid}" 2>/dev/null || true)
    if [ -n "$TMUX_CLIENT_PID" ]; then
        START_PID=$TMUX_CLIENT_PID
    fi
fi

echo "Tracing up from PID: $START_PID" >> "$LOG_FILE"

# Get daemon window tree and build pid -> window id mapping
WINDOW_TREE=$(daemon_rpc "get_windows" '{}' || echo '[]')
SWAY_MAPPINGS=$(printf '%s\n' "$WINDOW_TREE" | jq -r '.. | objects | select((.pid? // 0) > 0) | "\(.pid)=\(.id)"' || echo "")

# Walk up process tree to find a matching Sway window
current_pid=$START_PID
while [ -n "$current_pid" ] && [ "$current_pid" -gt 1 ]; do
    match=$(echo "$SWAY_MAPPINGS" | grep -E "^${current_pid}=" || true)
    if [ -n "$match" ]; then
        WINDOW_ID=$(echo "$match" | cut -d'=' -f2)
        echo "Found Sway window ID $WINDOW_ID matching ancestor PID $current_pid" >> "$LOG_FILE"
        break
    fi
    current_pid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ' || true)
done

# Fallback to currently focused window
if [ -z "$WINDOW_ID" ]; then
    echo "Could not find WINDOW_ID by walking tree. Falling back to focused window." >> "$LOG_FILE"
    FOCUSED_WINDOW_ID=$(printf '%s\n' "$WINDOW_TREE" | jq -r '.. | objects | select(.focused==true) | .id' || echo "")
    if [ -n "$FOCUSED_WINDOW_ID" ]; then
        WINDOW_ID=$FOCUSED_WINDOW_ID
        echo "Fallback FOCUSED_WINDOW_ID: $WINDOW_ID" >> "$LOG_FILE"
    fi
fi

# ── Build notification body ───────────────────────────────────────────
NOTIFICATION_BODY="$MESSAGE"

if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    NOTIFICATION_BODY="${NOTIFICATION_BODY}\n\nSource: ${TMUX_SESSION}:${TMUX_WINDOW}"
fi

# ── Send notification and handle action ───────────────────────────────
ICON="robot"
TITLE="${CLI_NAME} Ready"

echo "Sending notification: $TITLE (window=$WINDOW_ID)" >> "$LOG_FILE"

if [ -n "$WINDOW_ID" ]; then
    RESPONSE=$(notify-send -i "$ICON" -u normal -w --transient \
        -A "focus=Return to Terminal" \
        -A "dismiss=Dismiss" \
        "$TITLE" "$NOTIFICATION_BODY" 2>/dev/null || echo "error")
    echo "notify-send response: $RESPONSE" >> "$LOG_FILE"

    if [ "$RESPONSE" = "focus" ]; then
        echo "Focusing window $WINDOW_ID" >> "$LOG_FILE"

        PROJECT_NAME=$(printf '%s\n' "$WINDOW_TREE" | jq -r --argjson id "$WINDOW_ID" '
            .. | objects | select(.id? == $id) | .project // empty
        ' 2>/dev/null | head -n1 || echo "")
        TARGET_VARIANT=$(printf '%s\n' "$WINDOW_TREE" | jq -r --argjson id "$WINDOW_ID" '
            .. | objects | select(.id? == $id) | .execution_mode // empty
        ' 2>/dev/null | head -n1 || echo "")
        FOCUS_PARAMS=$(jq -nc \
            --argjson window_id "$WINDOW_ID" \
            --arg project_name "$PROJECT_NAME" \
            --arg target_variant "$TARGET_VARIANT" \
            '{window_id:$window_id, project_name:$project_name, target_variant:$target_variant}')
        daemon_rpc "window.focus" "$FOCUS_PARAMS" >> "$LOG_FILE" 2>&1 || true

        if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
            if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
                tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" >> "$LOG_FILE" 2>&1 || true
            fi
        fi
        if [ -n "${TMUX_PANE:-}" ]; then
            tmux select-pane -t "$TMUX_PANE" >> "$LOG_FILE" 2>&1 || true
        fi
    fi
else
    echo "No window ID, sending simple notification" >> "$LOG_FILE"
    notify-send -i "$ICON" -u normal --transient "$TITLE" "$NOTIFICATION_BODY" 2>/dev/null || true
fi

exit 0
