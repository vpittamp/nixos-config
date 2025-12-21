#!/usr/bin/env bash
# otel-stop.sh - Stop hook for Claude Code tracing metadata
#
# Purpose (v131+):
# - Persist a "turn complete" marker so the Node interceptor can end the Turn span
#
# Files written (per Claude Code PID = PPID):
# - $XDG_RUNTIME_DIR/claude-stop-${PPID}.json
#
# Notes:
# - We keep payloads small and treat this as best-effort.

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty')"
STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // empty')"

PARENT_PID="${PPID}"
TIMESTAMP_MS="$(date +%s%3N)"

STOP_FILE="${RUNTIME_DIR}/claude-stop-${PARENT_PID}.json"

# Always write the file (even if session_id is missing) so the interceptor can end turns.
jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg transcriptPath "$TRANSCRIPT_PATH" \
  --arg stopHookActive "$STOP_HOOK_ACTIVE" \
  --arg pid "$PARENT_PID" \
  --arg ts "$TIMESTAMP_MS" \
  '{
    version: 1,
    sessionId: (if $sessionId == "" then null else $sessionId end),
    transcriptPath: (if $transcriptPath == "" then null else $transcriptPath end),
    stopHookActive: (if $stopHookActive == "" then null else ($stopHookActive | test(\"^(true|false)$\") as $isBool | (if $isBool then ($stopHookActive == \"true\") else null end)) end),
    pid: ($pid | tonumber),
    timestampMs: ($ts | tonumber)
  }' > "$STOP_FILE" 2>/dev/null || true

exit 0
