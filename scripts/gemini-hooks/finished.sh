#!/usr/bin/env bash
# Gemini CLI AfterAgent Hook - Unified "finished" notification
#
# Called by Gemini CLI after agent completes a turn.
# Reads hook input JSON from stdin, builds a message,
# then delegates to ai-finished-notification.sh for the desktop notification.

set -euo pipefail

LOG_FILE="/tmp/gemini-finished.log"
exec 2>> "$LOG_FILE"
echo "--- $(date) ---" >> "$LOG_FILE"
echo "Starting hook..." >> "$LOG_FILE"

# Try to read hook input JSON from stdin, but don't block forever
echo "Reading stdin..." >> "$LOG_FILE"
INPUT=$(timeout 1 cat 2>/dev/null || echo "{}")
echo "INPUT length: ${#INPUT}" >> "$LOG_FILE"

# Check if the agent is still running (has tool calls, or status is not complete)
# This handles edge cases where AfterAgent might fire prematurely.
IS_DONE=$(echo "$INPUT" | jq -r '
  if (.toolCalls and (.toolCalls | length) > 0) or
     (.tool_calls and (.tool_calls | length) > 0) or
     (.functionCalls and (.functionCalls | length) > 0) or
     (.function_calls and (.function_calls | length) > 0)
  then "false"
  else "true"
  end
' 2>/dev/null || echo "true")

if [ "$IS_DONE" = "false" ]; then
    echo "Agent has tool calls pending. Skipping notification." >> "$LOG_FILE"
    echo '{"decision": "allow"}'
    exit 0
fi

# Try to extract working directory from env or hook input
WORKING_DIR="${GEMINI_CWD:-}"
if [ -z "$WORKING_DIR" ]; then
    WORKING_DIR=$(echo "$INPUT" | jq -r '.cwd // .workingDirectory // ""' 2>/dev/null || echo "")
fi
if [ -z "$WORKING_DIR" ]; then
    WORKING_DIR="$PWD"
fi

# Build message
MESSAGE="Task complete"
if [ -n "$WORKING_DIR" ]; then
    DIR_NAME=$(basename "$WORKING_DIR")
    MESSAGE="${MESSAGE} - ${DIR_NAME}"
fi

echo "Delegating to ai-finished-notification.sh" >> "$LOG_FILE"

# Call shared notification script in background (non-blocking)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nohup "${SCRIPT_DIR}/../ai-finished-notification.sh" "Gemini" "$MESSAGE" \
    </dev/null >/dev/null 2>&1 &

echo "Hook finished." >> "$LOG_FILE"
echo '{"decision": "allow"}'
exit 0
