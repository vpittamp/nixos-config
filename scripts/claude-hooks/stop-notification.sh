#!/usr/bin/env bash
# Claude Code Stop Hook - Enhanced notification with context
#
# This hook runs when Claude Code stops and is waiting for the next user message.
# It provides rich notification content: last message preview, tool summary, files modified.

set -euo pipefail

LOG_FILE="/tmp/stop-notification.log"
echo "--- $(date) ---" >> "$LOG_FILE"
echo "stop-notification.sh invoked" >> "$LOG_FILE"

# Read hook input JSON from stdin
INPUT=$(cat)
echo "INPUT length: ${#INPUT}" >> "$LOG_FILE"

# Extract context from hook input
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
WORKING_DIR=$(echo "$INPUT" | jq -r '.cwd // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# Find the terminal window running Claude Code robustly
# Strategy: Find the starting PID (tmux client or current shell) and walk up the process tree.
# We match each ancestor PID against the list of PIDs managed by Sway.
WINDOW_ID=""
START_PID=$PPID

TMUX_SESSION=""
TMUX_WINDOW=""

# Check if we're running inside tmux (TMUX environment variable is set)
if [ -n "${TMUX:-}" ]; then
    TMUX_SESSION=$(tmux display-message -p "#{session_name}" 2>/dev/null || true)
    TMUX_WINDOW=$(tmux display-message -p "#{window_index}" 2>/dev/null || true)
    echo "Tmux session: $TMUX_SESSION, window: $TMUX_WINDOW" >> "$LOG_FILE"
    
    # If in tmux, the actual terminal emulator is the parent of the tmux client process
    TMUX_CLIENT_PID=$(tmux display-message -p "#{client_pid}" 2>/dev/null || true)
    if [ -n "$TMUX_CLIENT_PID" ]; then
        START_PID=$TMUX_CLIENT_PID
    fi
fi

echo "Tracing up from PID: $START_PID" >> "$LOG_FILE"

# Get mapping of sway pid -> window id
SWAY_MAPPINGS=$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | objects | select(.type=="con" and .pid!=null) | "\(.pid)=\(.id)"' || echo "")

# Walk up process tree to find a matching Sway window
current_pid=$START_PID
while [ -n "$current_pid" ] && [ "$current_pid" -gt 1 ]; do
    match=$(echo "$SWAY_MAPPINGS" | grep -E "^${current_pid}=" || true)
    if [ -n "$match" ]; then
        WINDOW_ID=$(echo "$match" | cut -d'=' -f2)
        echo "Found Sway window ID $WINDOW_ID matching ancestor PID $current_pid" >> "$LOG_FILE"
        break
    fi
    # Get parent pid
    current_pid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ' || true)
done

# Fallback to currently focused window if walking the tree failed
if [ -z "$WINDOW_ID" ]; then
    echo "Could not find WINDOW_ID by walking tree. Falling back to focused window." >> "$LOG_FILE"
    FOCUSED_WINDOW_ID=$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | objects | select(.focused==true) | .id' || echo "")
    if [ -n "$FOCUSED_WINDOW_ID" ]; then
        WINDOW_ID=$FOCUSED_WINDOW_ID
        echo "Fallback FOCUSED_WINDOW_ID: $WINDOW_ID" >> "$LOG_FILE"
    fi
fi

# Parse transcript for notification content
LAST_MESSAGE=""
TOOL_SUMMARY=""
FILES_MODIFIED=""

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Extract last assistant text message (first 150 chars)
    LAST_MESSAGE=$(tac "$TRANSCRIPT_PATH" 2>/dev/null | \
        grep -m1 '"role":"assistant"' | \
        jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null | \
        head -c 150 | tr '\n' ' ' || echo "")

    # Count tool uses in last 30 lines
    BASH_COUNT=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | grep -c '"name":"Bash"' || echo "0")
    EDIT_COUNT=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | grep -c '"name":"Edit"' || echo "0")
    WRITE_COUNT=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | grep -c '"name":"Write"' || echo "0")
    READ_COUNT=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | grep -c '"name":"Read"' || echo "0")

    # Build tool summary
    TOOL_PARTS=()
    [ "$BASH_COUNT" -gt 0 ] && TOOL_PARTS+=("$BASH_COUNT bash")
    [ "$EDIT_COUNT" -gt 0 ] && TOOL_PARTS+=("$EDIT_COUNT edits")
    [ "$WRITE_COUNT" -gt 0 ] && TOOL_PARTS+=("$WRITE_COUNT writes")
    [ "$READ_COUNT" -gt 0 ] && TOOL_PARTS+=("$READ_COUNT reads")

    if [ ${#TOOL_PARTS[@]} -gt 0 ]; then
        TOOL_SUMMARY=$(IFS=", "; echo "${TOOL_PARTS[*]}")
    fi

    # Extract files modified (last 30 lines)
    FILES_MODIFIED=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | \
        jq -r 'select(.message.content[]?.type == "tool_use") | .message.content[] | select(.type == "tool_use") | select(.name == "Edit" or .name == "Write") | .input.file_path' 2>/dev/null | \
        sort -u | \
        head -3 | \
        awk '{print "  • " $0}' | \
        tr '\n' '\n' || echo "")
fi

# Fallback message if we couldn't extract from transcript
if [ -z "$LAST_MESSAGE" ]; then
    LAST_MESSAGE="Task complete - awaiting your input"
fi

# Build notification body
NOTIFICATION_BODY="$LAST_MESSAGE"

if [ -n "$TOOL_SUMMARY" ]; then
    NOTIFICATION_BODY="${NOTIFICATION_BODY}\n\n📊 Activity: ${TOOL_SUMMARY}"
fi

if [ -n "$FILES_MODIFIED" ]; then
    NOTIFICATION_BODY="${NOTIFICATION_BODY}\n\n📝 Modified:\n${FILES_MODIFIED}"
fi

if [ -n "$WORKING_DIR" ]; then
    DIR_NAME=$(basename "$WORKING_DIR")
    NOTIFICATION_BODY="${NOTIFICATION_BODY}\n\n📁 ${DIR_NAME}"
fi

echo "Invoking handler with WINDOW_ID: $WINDOW_ID, Session: $TMUX_SESSION, Window: $TMUX_WINDOW" >> "$LOG_FILE"

# Call notification handler in background (non-blocking)
nohup "${BASH_SOURCE%/*}/stop-notification-handler.sh" \
    "$WINDOW_ID" \
    "$NOTIFICATION_BODY" \
    "$TMUX_SESSION" \
    "$TMUX_WINDOW" \
    >/dev/null 2>&1 &

exit 0
