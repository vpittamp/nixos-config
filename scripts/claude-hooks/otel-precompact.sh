#!/usr/bin/env bash
# otel-precompact.sh - PreCompact hook for Claude Code tracing
#
# Purpose (v131 Phase 3):
# - Capture when Claude Code compacts the conversation context
# - Creates COMPACTION spans to track context window management
# - Helps debug "lost context" issues
#
# Files written (per Claude Code PID = PPID, with unique timestamp):
# - $XDG_RUNTIME_DIR/claude-precompact-${PPID}-${timestamp}.json
#
# Input (JSON via stdin):
# {
#   "session_id": "abc123",
#   "hook_event_name": "PreCompact",
#   "compact_type": "manual" | "auto",
#   "transcript_path": "/path/to/transcript.jsonl"
# }
#
# Compact types (from Claude Code docs):
# - manual: User executed /compact command
# - auto: Context window full, automatic compaction
#
# Notes:
# - Interceptor polls for these files to create COMPACTION spans
# - Compaction may significantly alter conversation context
# - Rare events; spans only appear when relevant

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
COMPACT_TYPE="$(echo "$INPUT" | jq -r '.compact_type // empty')"
TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty')"

# Default to manual if not specified
if [[ -z "$COMPACT_TYPE" ]]; then
  COMPACT_TYPE="manual"
fi

PARENT_PID="${PPID}"
TIMESTAMP_MS="$(date +%s%3N)"

# Determine trigger description
TRIGGER=""
case "$COMPACT_TYPE" in
  manual)
    TRIGGER="/compact command"
    ;;
  auto)
    TRIGGER="context_full"
    ;;
  *)
    TRIGGER="$COMPACT_TYPE"
    ;;
esac

# Try to count messages in transcript (if accessible)
# This is best-effort; transcript may be locked or inaccessible
MESSAGE_COUNT=""
if [[ -n "$TRANSCRIPT_PATH" && -r "$TRANSCRIPT_PATH" ]]; then
  MESSAGE_COUNT="$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d ' ' || true)"
fi

# Write precompact file (interceptor will poll for these)
COMPACT_FILE="${RUNTIME_DIR}/claude-precompact-${PARENT_PID}-${TIMESTAMP_MS}.json"

jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg compactType "$COMPACT_TYPE" \
  --arg trigger "$TRIGGER" \
  --arg messageCount "$MESSAGE_COUNT" \
  --arg transcriptPath "$TRANSCRIPT_PATH" \
  --arg pid "$PARENT_PID" \
  --arg ts "$TIMESTAMP_MS" \
  '{
    version: 1,
    sessionId: (if $sessionId == "" then null else $sessionId end),
    compactType: $compactType,
    trigger: $trigger,
    messagesBefore: (if $messageCount == "" then null else ($messageCount | tonumber) end),
    transcriptPath: (if $transcriptPath == "" then null else $transcriptPath end),
    pid: ($pid | tonumber),
    timestampMs: ($ts | tonumber)
  }' > "$COMPACT_FILE" 2>/dev/null || true

exit 0
