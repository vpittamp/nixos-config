#!/usr/bin/env bash
# otel-notification.sh - Notification hook for Claude Code tracing
#
# Purpose (v131 Phase 3):
# - Capture Claude Code notification events for observability
# - Creates NOTIFICATION spans for permission_prompt, auth_success, etc.
#
# Files written (per Claude Code PID = PPID, with unique timestamp):
# - $XDG_RUNTIME_DIR/claude-notification-${PPID}-${timestamp}.json
#
# Input (JSON via stdin):
# {
#   "session_id": "abc123",
#   "hook_event_name": "Notification",
#   "notification_type": "permission_prompt",
#   "message": "Claude wants to edit file.txt"
# }
#
# Notification types (from Claude Code docs):
# - permission_prompt: User sees permission dialog
# - idle_prompt: User idle for extended period
# - auth_success: Authentication completed
# - elicitation_dialog: User input dialog
#
# Notes:
# - Interceptor polls for these files to create NOTIFICATION spans
# - We only register matchers for actionable notifications

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
NOTIFICATION_TYPE="$(echo "$INPUT" | jq -r '.notification_type // empty')"
MESSAGE="$(echo "$INPUT" | jq -r '.message // empty')"

# Require notification_type for meaningful spans
if [[ -z "$NOTIFICATION_TYPE" ]]; then
  exit 0
fi

PARENT_PID="${PPID}"
TIMESTAMP_MS="$(date +%s%3N)"

# Truncate message to 200 chars
MESSAGE_TRUNCATED=""
if [[ -n "$MESSAGE" ]]; then
  MESSAGE_TRUNCATED="$(echo "$MESSAGE" | head -c 200 | tr '\n' ' ')"
fi

# Write notification file with unique timestamp (multiple notifications possible)
NOTIF_FILE="${RUNTIME_DIR}/claude-notification-${PARENT_PID}-${TIMESTAMP_MS}.json"

jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg notificationType "$NOTIFICATION_TYPE" \
  --arg message "$MESSAGE_TRUNCATED" \
  --arg pid "$PARENT_PID" \
  --arg ts "$TIMESTAMP_MS" \
  '{
    version: 1,
    sessionId: (if $sessionId == "" then null else $sessionId end),
    notificationType: $notificationType,
    message: (if $message == "" then null else $message end),
    pid: ($pid | tonumber),
    timestampMs: ($ts | tonumber)
  }' > "$NOTIF_FILE" 2>/dev/null || true

exit 0
