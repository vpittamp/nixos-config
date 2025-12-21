#!/usr/bin/env bash
# otel-user-prompt-submit.sh - UserPromptSubmit hook for Claude Code tracing metadata
#
# Purpose (v131+):
# - Persist Claude Code's `session_id` (UUID) as early as possible (often earlier than SessionStart)
# - Persist the latest user prompt so the interceptor can start a Turn span reliably
#
# Files written (per Claude Code PID = PPID):
# - $XDG_RUNTIME_DIR/claude-session-${PPID}.json
# - $XDG_RUNTIME_DIR/claude-user-prompt-${PPID}.json
#
# Notes:
# - We keep payloads small; prompt is truncated.

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty')"
CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"
PROMPT="$(echo "$INPUT" | jq -r '.prompt // empty')"

PARENT_PID="${PPID}"
TIMESTAMP_MS="$(date +%s%3N)"

# ---------------------------------------------------------------------------
# 1) Update session metadata (same contract as SessionStart, best-effort merge)
# ---------------------------------------------------------------------------

STATE_FILE="${RUNTIME_DIR}/claude-session-${PARENT_PID}.json"

if [[ -n "$SESSION_ID" ]]; then
  # Keep prompt/session metadata small in the runtime dir.
  jq -n \
    --arg sessionId "$SESSION_ID" \
    --arg transcriptPath "$TRANSCRIPT_PATH" \
    --arg cwd "$CWD" \
    --arg pid "$PARENT_PID" \
    --arg ts "$TIMESTAMP_MS" \
    '{
      version: 1,
      sessionId: $sessionId,
      transcriptPath: (if $transcriptPath == "" then null else $transcriptPath end),
      cwd: (if $cwd == "" then null else $cwd end),
      pid: ($pid | tonumber),
      timestampMs: ($ts | tonumber)
    }' > "$STATE_FILE" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2) Persist the latest user prompt for Turn boundary detection
# ---------------------------------------------------------------------------

PROMPT_FILE="${RUNTIME_DIR}/claude-user-prompt-${PARENT_PID}.json"

if [[ -n "$PROMPT" ]]; then
  # Truncate prompt to avoid huge runtime files (Turn span uses a short preview anyway).
  PROMPT_TRUNC="$(printf '%s' "$PROMPT" | head -c 10000)"

  jq -n \
    --arg sessionId "$SESSION_ID" \
    --arg prompt "$PROMPT_TRUNC" \
    --arg pid "$PARENT_PID" \
    --arg ts "$TIMESTAMP_MS" \
    '{
      version: 1,
      sessionId: (if $sessionId == "" then null else $sessionId end),
      prompt: $prompt,
      pid: ($pid | tonumber),
      timestampMs: ($ts | tonumber)
    }' > "$PROMPT_FILE" 2>/dev/null || true
fi

exit 0

