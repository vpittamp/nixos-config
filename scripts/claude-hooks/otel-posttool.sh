#!/usr/bin/env bash
# otel-posttool.sh - PostToolUse hook for Claude Code tracing
#
# Purpose (v131 Phase 3):
# - Capture tool execution completion metadata (exit_code, output summary, duration)
# - Enriches Tool spans with execution details beyond success/failure
#
# Files written (per Claude Code PID = PPID, per tool_use_id):
# - $XDG_RUNTIME_DIR/claude-posttool-${PPID}-${tool_use_id}.json
#
# Input (JSON via stdin):
# {
#   "session_id": "abc123",
#   "hook_event_name": "PostToolUse",
#   "tool_name": "Bash",
#   "tool_input": { "command": "ls -la", ... },
#   "tool_use_id": "toolu_01ABC123...",
#   "tool_response": { "content": "...", "is_error": false }
# }
#
# Notes:
# - Interceptor polls for these files to enrich Tool spans before completion
# - Exit code extracted from tool_response for Bash tools
# - Output summary truncated to 200 chars for span attribute

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
TOOL_USE_ID="$(echo "$INPUT" | jq -r '.tool_use_id // empty')"
TOOL_RESPONSE="$(echo "$INPUT" | jq -c '.tool_response // {}')"
IS_ERROR="$(echo "$TOOL_RESPONSE" | jq -r '.is_error // false')"

# Require tool_use_id for correlation
if [[ -z "$TOOL_USE_ID" ]]; then
  exit 0
fi

PARENT_PID="${PPID}"
TIMESTAMP_MS="$(date +%s%3N)"

# Extract exit code for Bash tools (if present in response)
EXIT_CODE=""
if [[ "$TOOL_NAME" == "Bash" ]]; then
  # Bash tool may include exit code in response
  EXIT_CODE="$(echo "$TOOL_RESPONSE" | jq -r '.exit_code // empty')"
  # If not explicit, infer from is_error
  if [[ -z "$EXIT_CODE" && "$IS_ERROR" == "true" ]]; then
    EXIT_CODE="1"
  elif [[ -z "$EXIT_CODE" ]]; then
    EXIT_CODE="0"
  fi
fi

# Extract output summary (truncated)
OUTPUT_CONTENT="$(echo "$TOOL_RESPONSE" | jq -r '.content // empty' 2>/dev/null || true)"
if [[ -z "$OUTPUT_CONTENT" ]]; then
  # Try alternative field names
  OUTPUT_CONTENT="$(echo "$TOOL_RESPONSE" | jq -r '.text // .output // .result // empty' 2>/dev/null || true)"
fi

# Truncate to 200 chars and escape for JSON
OUTPUT_SUMMARY=""
if [[ -n "$OUTPUT_CONTENT" ]]; then
  OUTPUT_SUMMARY="$(echo "$OUTPUT_CONTENT" | head -c 200 | tr '\n' ' ' | sed 's/[[:cntrl:]]/ /g')"
fi

# Count lines for Read/Bash output
OUTPUT_LINES=""
if [[ -n "$OUTPUT_CONTENT" && ("$TOOL_NAME" == "Read" || "$TOOL_NAME" == "Bash") ]]; then
  OUTPUT_LINES="$(echo "$OUTPUT_CONTENT" | wc -l | tr -d ' ')"
fi

# Classify error type if is_error is true
ERROR_TYPE=""
if [[ "$IS_ERROR" == "true" ]]; then
  case "$OUTPUT_CONTENT" in
    *"not found"*|*"No such file"*|*"does not exist"*)
      ERROR_TYPE="not_found"
      ;;
    *"permission denied"*|*"Permission denied"*|*"EACCES"*)
      ERROR_TYPE="permission_denied"
      ;;
    *"timeout"*|*"Timeout"*|*"ETIMEDOUT"*)
      ERROR_TYPE="timeout"
      ;;
    *"syntax error"*|*"SyntaxError"*|*"invalid"*)
      ERROR_TYPE="validation"
      ;;
    *)
      ERROR_TYPE="execution"
      ;;
  esac
fi

# Write posttool file (interceptor will poll for these)
POSTTOOL_FILE="${RUNTIME_DIR}/claude-posttool-${PARENT_PID}-${TOOL_USE_ID}.json"

jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg toolName "$TOOL_NAME" \
  --arg toolUseId "$TOOL_USE_ID" \
  --arg exitCode "$EXIT_CODE" \
  --arg outputSummary "$OUTPUT_SUMMARY" \
  --arg outputLines "$OUTPUT_LINES" \
  --arg isError "$IS_ERROR" \
  --arg errorType "$ERROR_TYPE" \
  --arg pid "$PARENT_PID" \
  --arg ts "$TIMESTAMP_MS" \
  '{
    version: 1,
    sessionId: (if $sessionId == "" then null else $sessionId end),
    toolName: $toolName,
    toolUseId: $toolUseId,
    exitCode: (if $exitCode == "" then null else ($exitCode | tonumber) end),
    outputSummary: (if $outputSummary == "" then null else $outputSummary end),
    outputLines: (if $outputLines == "" then null else ($outputLines | tonumber) end),
    isError: ($isError == "true"),
    errorType: (if $errorType == "" then null else $errorType end),
    pid: ($pid | tonumber),
    completedAtMs: ($ts | tonumber)
  }' > "$POSTTOOL_FILE" 2>/dev/null || true

exit 0
