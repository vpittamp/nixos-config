#!/usr/bin/env bash
# otel-session-start.sh - SessionStart hook for Claude Code session metadata
#
# This hook runs when Claude Code starts (or resumes) a session.
#
# Purpose (v131):
# - Persist Claude Code's `session_id` (UUID) to a per-process runtime file so
#   the Node fetch interceptor can attach the same `session.id` to traces.
# - Optionally export CLAUDE_SESSION_ID/CLAUDE_TRANSCRIPT_PATH to CLAUDE_ENV_FILE
#   so downstream hook scripts and Bash tool executions can correlate.
#
# NOTE:
# - This hook intentionally does NOT generate trace/span IDs and does NOT write
#   `.claude-trace-context.json`. Trace context propagation is handled by the
#   Node interceptor.

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Read JSON from stdin
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty')"
CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"

# Use PPID to target the actual Claude Code (Node) process, not this hook PID.
PARENT_PID="${PPID}"
TIMESTAMP_MS="$(date +%s%3N)"

# Write a per-process metadata file for the interceptor to read.
STATE_FILE="${RUNTIME_DIR}/claude-session-${PARENT_PID}.json"
PROMPT_FILE="${RUNTIME_DIR}/claude-user-prompt-${PARENT_PID}.json"
STOP_FILE="${RUNTIME_DIR}/claude-stop-${PARENT_PID}.json"

if [[ -n "$SESSION_ID" ]]; then
  # Best-effort cleanup of any stale per-PID files (PID reuse/crashes).
  rm -f "$PROMPT_FILE" "$STOP_FILE" 2>/dev/null || true

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

# Persist session metadata for subsequent Claude-executed bash commands (hooks/tools).
if [[ -n "${CLAUDE_ENV_FILE:-}" && -n "$SESSION_ID" ]]; then
  {
    echo "export CLAUDE_SESSION_ID=\"${SESSION_ID}\""
    if [[ -n "$TRANSCRIPT_PATH" ]]; then
      echo "export CLAUDE_TRANSCRIPT_PATH=\"${TRANSCRIPT_PATH}\""
    fi
    if [[ -n "$CWD" ]]; then
      echo "export CLAUDE_SESSION_CWD=\"${CWD}\""
    fi
  } >> "$CLAUDE_ENV_FILE"
fi

exit 0
