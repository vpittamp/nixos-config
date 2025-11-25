#!/usr/bin/env bash
# Claude Code Stop Hook - Enhanced notification with context
#
# This hook runs when Claude Code stops and is waiting for the next user message.
# It provides rich notification content: last message preview, tool summary, files modified.

set -euo pipefail

# Read hook input JSON from stdin
INPUT=$(cat)

# Extract context from hook input
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
WORKING_DIR=$(echo "$INPUT" | jq -r '.cwd // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# Find the terminal window running Claude Code
# Strategy: Extract terminal PID from environment variables or find focused window
WINDOW_ID=""
TERMINAL_PID=""

# Alacritty: extract PID from ALACRITTY_SOCKET (e.g., /run/user/1000/Alacritty-wayland-1-813367.sock)
if [ -n "${ALACRITTY_SOCKET:-}" ]; then
    TERMINAL_PID=$(echo "$ALACRITTY_SOCKET" | grep -oP '\d+(?=\.)' | tail -1 || true)
fi

# Ghostty: Get PID via shell parent process
# Current process (bash hook) -> parent (bash interactive) -> grandparent (ghostty)
if [ -z "$TERMINAL_PID" ] && [ -n "${GHOSTTY_RESOURCES_DIR:-}" ]; then
    # Get parent of parent process
    SHELL_PPID=$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ' || true)
    if [ -n "$SHELL_PPID" ]; then
        # Check if grandparent is ghostty
        GRANDPARENT_CMD=$(ps -o comm= -p "$SHELL_PPID" 2>/dev/null || true)
        if [[ "$GRANDPARENT_CMD" == *"ghostty"* ]]; then
            TERMINAL_PID=$SHELL_PPID
        fi
    fi
fi

# Find Sway window by terminal PID
if [ -n "$TERMINAL_PID" ]; then
    WINDOW_ID=$(swaymsg -t get_tree | jq -r --arg pid "$TERMINAL_PID" '
        .. | objects |
        select(has("type")) |
        select(.type=="con") |
        select(.pid == ($pid | tonumber)) |
        .id' | head -1)
fi

# Feature 079: T065 - Extract tmux session and window information
TMUX_SESSION=""
TMUX_WINDOW=""

# Check if we're running inside tmux (TMUX environment variable is set)
if [ -n "${TMUX:-}" ]; then
    # Extract current session name and window index
    TMUX_SESSION=$(tmux display-message -p "#{session_name}" 2>/dev/null || true)
    TMUX_WINDOW=$(tmux display-message -p "#{window_index}" 2>/dev/null || true)
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
    BASH_COUNT=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | \
        grep -c '"name":"Bash"' || echo "0")
    EDIT_COUNT=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | \
        grep -c '"name":"Edit"' || echo "0")
    WRITE_COUNT=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | \
        grep -c '"name":"Write"' || echo "0")
    READ_COUNT=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | \
        grep -c '"name":"Read"' || echo "0")

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

# Call notification handler in background (non-blocking)
# This allows the hook to return immediately while the notification waits for user action
# Feature 079: T066 - Pass TMUX_SESSION and TMUX_WINDOW to handler script
nohup "${BASH_SOURCE%/*}/stop-notification-handler.sh" \
    "$WINDOW_ID" \
    "$NOTIFICATION_BODY" \
    "$TMUX_SESSION" \
    "$TMUX_WINDOW" \
    >/dev/null 2>&1 &

# Exit immediately (don't block Claude Code)
exit 0
