#!/usr/bin/env bash
# otel-subagent-stop.sh - SubagentStop hook for Claude Code tracing
#
# Purpose (v131 Phase 3):
# - Capture when a Task subagent completes
# - Provides explicit subagent completion signal (vs inferring from process tree)
# - Enables linking parent Task span to child session
#
# Files written (per Claude Code PID = PPID, per tool_use_id):
# - $XDG_RUNTIME_DIR/claude-subagent-stop-${PPID}-${tool_use_id}.json
#
# Input (JSON via stdin):
# {
#   "session_id": "parent-session-uuid",
#   "hook_event_name": "SubagentStop",
#   "tool_use_id": "toolu_01ABC123...",
#   "subagent_session_id": "child-session-uuid"
# }
#
# Notes:
# - Fires on the PARENT process when a subagent (Task) completes
# - Interceptor polls for these files to complete Task Tool spans
# - Provides subagent.session_id for cross-session correlation in Grafana

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TOOL_USE_ID="$(echo "$INPUT" | jq -r '.tool_use_id // empty')"
SUBAGENT_SESSION_ID="$(echo "$INPUT" | jq -r '.subagent_session_id // empty')"

# Require tool_use_id for correlation
if [[ -z "$TOOL_USE_ID" ]]; then
  exit 0
fi

PARENT_PID="${PPID}"
TIMESTAMP_MS="$(date +%s%3N)"

# Write subagent-stop file (interceptor will poll for these)
SUBAGENT_FILE="${RUNTIME_DIR}/claude-subagent-stop-${PARENT_PID}-${TOOL_USE_ID}.json"

jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg toolUseId "$TOOL_USE_ID" \
  --arg subagentSessionId "$SUBAGENT_SESSION_ID" \
  --arg pid "$PARENT_PID" \
  --arg ts "$TIMESTAMP_MS" \
  '{
    version: 1,
    sessionId: (if $sessionId == "" then null else $sessionId end),
    toolUseId: $toolUseId,
    subagentSessionId: (if $subagentSessionId == "" then null else $subagentSessionId end),
    pid: ($pid | tonumber),
    completedAtMs: ($ts | tonumber)
  }' > "$SUBAGENT_FILE" 2>/dev/null || true

exit 0
