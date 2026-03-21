#!/usr/bin/env bash
# Unified AI "Finished" notification for all AI CLIs (Claude Code, Codex, Gemini)
#
# Usage: ai-finished-notification.sh CLI_NAME [MESSAGE]
# Env: TMUX/PPID auto-detected unless explicit I3PM_NOTIFY_* overrides are set
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
EXPLICIT_WINDOW_ID="${I3PM_NOTIFY_WINDOW_ID:-}"
EXPLICIT_PROJECT_NAME="${I3PM_NOTIFY_PROJECT_NAME:-}"
EXPLICIT_TARGET_VARIANT="${I3PM_NOTIFY_TARGET_VARIANT:-}"
EXPLICIT_TMUX_SESSION="${I3PM_NOTIFY_TMUX_SESSION:-}"
EXPLICIT_TMUX_WINDOW="${I3PM_NOTIFY_TMUX_WINDOW:-}"
EXPLICIT_TMUX_PANE="${I3PM_NOTIFY_TMUX_PANE:-}"
PLAY_SOUND="${I3PM_NOTIFY_SOUND:-0}"
ICON="${I3PM_NOTIFY_ICON:-robot}"
TITLE="${I3PM_NOTIFY_TITLE:-${CLI_NAME} Ready}"
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

play_completion_sound() {
    [ "$PLAY_SOUND" = "1" ] || return 0

    local player
    player="$(command -v pw-play 2>/dev/null || true)"
    [ -n "$player" ] || return 0

    local runtime_dir sound_file
    runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
    sound_file="${runtime_dir}/i3pm-ai-session-complete.wav"

    if [ ! -f "$sound_file" ]; then
        python3 - "$sound_file" <<'PY' >/dev/null 2>&1 || return 0
import math
import os
import struct
import sys
import wave

path = sys.argv[1]
tmp = f"{path}.tmp"
os.makedirs(os.path.dirname(path), exist_ok=True)
sample_rate = 44100
duration = 0.16
frequency = 880.0
frame_count = int(sample_rate * duration)

with wave.open(tmp, "wb") as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)
    for index in range(frame_count):
        attack = min(1.0, index / (sample_rate * 0.01))
        release = min(1.0, (frame_count - index) / (sample_rate * 0.05))
        amplitude = min(attack, release) * 0.22
        sample = int(32767 * amplitude * math.sin(2 * math.pi * frequency * index / sample_rate))
        wav_file.writeframesraw(struct.pack("<h", sample))

os.replace(tmp, path)
PY
    fi

    nohup "$player" "$sound_file" >/dev/null 2>&1 &
}

# ── Window detection ──────────────────────────────────────────────────
# Walk process tree from PPID to find a matching Sway window ID.
WINDOW_ID=""
START_PID=$PPID

TMUX_SESSION=""
TMUX_WINDOW=""
TMUX_PANE=""

if [ -n "$EXPLICIT_WINDOW_ID" ]; then
    WINDOW_ID="$EXPLICIT_WINDOW_ID"
fi
if [ -n "$EXPLICIT_TMUX_SESSION" ]; then
    TMUX_SESSION="$EXPLICIT_TMUX_SESSION"
fi
if [ -n "$EXPLICIT_TMUX_WINDOW" ]; then
    TMUX_WINDOW="$EXPLICIT_TMUX_WINDOW"
fi
if [ -n "$EXPLICIT_TMUX_PANE" ]; then
    TMUX_PANE="$EXPLICIT_TMUX_PANE"
fi

# Check if we're running inside tmux
if [ -z "$TMUX_SESSION$TMUX_WINDOW$TMUX_PANE" ] && [ -n "${TMUX:-}" ]; then
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
SWAY_MAPPINGS=""
if [ -z "$WINDOW_ID" ]; then
    SWAY_MAPPINGS=$(printf '%s\n' "$WINDOW_TREE" | jq -r '.. | objects | select((.pid? // 0) > 0) | "\(.pid)=\(.id)"' || echo "")
fi

# Walk up process tree to find a matching Sway window
if [ -z "$WINDOW_ID" ]; then
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
fi

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
echo "Sending notification: $TITLE (window=$WINDOW_ID)" >> "$LOG_FILE"
play_completion_sound

if [ -n "$WINDOW_ID" ]; then
    RESPONSE=$(notify-send -i "$ICON" -u normal -w --transient \
        -A "focus=Return to Terminal" \
        -A "dismiss=Dismiss" \
        "$TITLE" "$NOTIFICATION_BODY" 2>/dev/null || echo "error")
    echo "notify-send response: $RESPONSE" >> "$LOG_FILE"

    if [ "$RESPONSE" = "focus" ]; then
        echo "Focusing window $WINDOW_ID" >> "$LOG_FILE"

        PROJECT_NAME="$EXPLICIT_PROJECT_NAME"
        TARGET_VARIANT="$EXPLICIT_TARGET_VARIANT"
        if [ -z "$PROJECT_NAME" ]; then
            PROJECT_NAME=$(printf '%s\n' "$WINDOW_TREE" | jq -r --argjson id "$WINDOW_ID" '
                .. | objects | select(.id? == $id) | .project // empty
            ' 2>/dev/null | head -n1 || echo "")
        fi
        if [ -z "$TARGET_VARIANT" ]; then
            TARGET_VARIANT=$(printf '%s\n' "$WINDOW_TREE" | jq -r --argjson id "$WINDOW_ID" '
                .. | objects | select(.id? == $id) | .execution_mode // empty
            ' 2>/dev/null | head -n1 || echo "")
        fi
        FOCUS_PARAMS=$(jq -nc \
            --argjson window_id "$WINDOW_ID" \
            --arg project_name "$PROJECT_NAME" \
            --arg target_variant "$TARGET_VARIANT" \
            '{window_id:$window_id, project_name:$project_name, target_variant:$target_variant}')
        daemon_rpc "window.focus" "$FOCUS_PARAMS" >> "$LOG_FILE" 2>&1 || true

        if [ "$TARGET_VARIANT" != "ssh" ] && [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ] && command -v tmux >/dev/null 2>&1; then
            if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
                tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" >> "$LOG_FILE" 2>&1 || true
            fi
        fi
        if [ "$TARGET_VARIANT" != "ssh" ] && [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
            tmux select-pane -t "$TMUX_PANE" >> "$LOG_FILE" 2>&1 || true
        fi
    fi
else
    echo "No window ID, sending simple notification" >> "$LOG_FILE"
    notify-send -i "$ICON" -u normal --transient "$TITLE" "$NOTIFICATION_BODY" 2>/dev/null || true
fi

exit 0
