#!/usr/bin/env bash
# Claude Code Stop Hook - Unified "finished" notification
#
# Reads hook input JSON from stdin (session_id, transcript_path, cwd),
# parses transcript for rich content (last message, tool summary),
# then delegates to ai-finished-notification.sh for the desktop notification.

set -euo pipefail

LOG_FILE="/tmp/claude-finished.log"
echo "--- $(date) ---" >> "$LOG_FILE"

# Read hook input JSON from stdin
INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Feed the interceptor's stop-hook file path before doing notification work.
# This keeps QuickShell/session state in sync with the desktop toast.
printf '%s' "$INPUT" | "${SCRIPT_DIR}/otel-stop.sh" >/dev/null 2>&1 || true

# Extract context from hook input
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
WORKING_DIR=$(echo "$INPUT" | jq -r '.cwd // ""')

# Parse transcript for notification content
LAST_MESSAGE=""
TOOL_SUMMARY=""

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
fi

# Build message
MESSAGE="${LAST_MESSAGE:-Task complete - awaiting your input}"

if [ -n "$TOOL_SUMMARY" ]; then
    MESSAGE="${MESSAGE}\n\nActivity: ${TOOL_SUMMARY}"
fi

if [ -n "$WORKING_DIR" ]; then
    DIR_NAME=$(basename "$WORKING_DIR")
    MESSAGE="${MESSAGE}\n\n${DIR_NAME}"
fi

echo "Delegating to ai-finished-notification.sh" >> "$LOG_FILE"

# Call shared notification script in background (non-blocking)
nohup "${SCRIPT_DIR}/../ai-finished-notification.sh" "Claude Code" "$MESSAGE" \
    >/dev/null 2>&1 &

exit 0
