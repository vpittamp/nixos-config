#!/usr/bin/env bash
# otel-permission-request.sh - PermissionRequest hook for Claude Code tracing
#
# Purpose (v131+):
# - Capture when a permission dialog is shown to the user
# - Write start timestamp so interceptor can calculate wait time when tool_result arrives
#
# Files written (per Claude Code PID = PPID, per tool_use_id):
# - $XDG_RUNTIME_DIR/claude-permission-${PPID}-${tool_use_id}.json
#
# Input (JSON via stdin):
# {
#   "session_id": "abc123",
#   "hook_event_name": "PermissionRequest",
#   "tool_name": "Write",
#   "tool_input": { "file_path": "/path/to/file.txt", ... },
#   "tool_use_id": "toolu_01ABC123..."
# }
#
# Notes:
# - Permission wait span is completed when interceptor sees matching tool_result
# - If permission is denied, span is marked as denied when turn ends

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
TOOL_USE_ID="$(echo "$INPUT" | jq -r '.tool_use_id // empty')"
TOOL_INPUT="$(echo "$INPUT" | jq -c '.tool_input // {}')"

# Require tool_use_id for correlation
if [[ -z "$TOOL_USE_ID" ]]; then
  exit 0
fi

PARENT_PID="${PPID}"
TIMESTAMP_MS="$(date +%s%3N)"

# Create a truncated description from tool_input for span attributes
TOOL_DESC=""
case "$TOOL_NAME" in
  Read|Write|Edit)
    TOOL_DESC="$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' | head -c 200)"
    ;;
  Bash)
    TOOL_DESC="$(echo "$TOOL_INPUT" | jq -r '.command // empty' | head -c 200)"
    ;;
  *)
    TOOL_DESC="$(echo "$TOOL_INPUT" | jq -r 'to_entries | map(.key + ":" + (.value | tostring)[0:50]) | join(", ")' 2>/dev/null | head -c 200 || true)"
    ;;
esac

# Write permission request file (interceptor will poll for these)
PERM_FILE="${RUNTIME_DIR}/claude-permission-${PARENT_PID}-${TOOL_USE_ID}.json"

jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg toolName "$TOOL_NAME" \
  --arg toolUseId "$TOOL_USE_ID" \
  --arg toolDesc "$TOOL_DESC" \
  --arg pid "$PARENT_PID" \
  --arg ts "$TIMESTAMP_MS" \
  '{
    version: 1,
    sessionId: (if $sessionId == "" then null else $sessionId end),
    toolName: $toolName,
    toolUseId: $toolUseId,
    toolDescription: (if $toolDesc == "" then null else $toolDesc end),
    pid: ($pid | tonumber),
    startTimestampMs: ($ts | tonumber)
  }' > "$PERM_FILE" 2>/dev/null || true

exit 0
