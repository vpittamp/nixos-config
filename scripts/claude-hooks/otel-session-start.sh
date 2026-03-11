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
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"
PROJECT_PATH="${I3PM_PROJECT_PATH:-$CWD}"
TMUX_SESSION="${TMUX_SESSION:-}"
TMUX_WINDOW="${TMUX_WINDOW:-}"
TMUX_PANE="${TMUX_PANE:-}"
PTY_PATH="${TTY:-}"
HOST_NAME="$(hostname 2>/dev/null || true)"
EXECUTION_MODE="${I3PM_CONTEXT_VARIANT:-${I3PM_EXECUTION_MODE:-local}}"
CONNECTION_KEY="${I3PM_CONNECTION_KEY:-}"
CONTEXT_KEY="${I3PM_CONTEXT_KEY:-}"
REMOTE_TARGET=""
if [[ -n "${I3PM_REMOTE_HOST:-}" ]]; then
  REMOTE_USER="${I3PM_REMOTE_USER:-}"
  REMOTE_PORT="${I3PM_REMOTE_PORT:-22}"
  if [[ -n "$REMOTE_USER" ]]; then
    REMOTE_TARGET="${REMOTE_USER}@${I3PM_REMOTE_HOST}:${REMOTE_PORT}"
  else
    REMOTE_TARGET="${I3PM_REMOTE_HOST}:${REMOTE_PORT}"
  fi
fi

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
    --arg projectName "$PROJECT_NAME" \
    --arg projectPath "$PROJECT_PATH" \
    --arg terminalAnchorId "${I3PM_TERMINAL_ANCHOR_ID:-}" \
    --arg tmuxSession "$TMUX_SESSION" \
    --arg tmuxWindow "$TMUX_WINDOW" \
    --arg tmuxPane "$TMUX_PANE" \
    --arg pty "$PTY_PATH" \
    --arg hostName "$HOST_NAME" \
    --arg executionMode "$EXECUTION_MODE" \
    --arg connectionKey "$CONNECTION_KEY" \
    --arg contextKey "$CONTEXT_KEY" \
    --arg remoteTarget "$REMOTE_TARGET" \
    --arg pid "$PARENT_PID" \
    --arg ts "$TIMESTAMP_MS" \
    '{
      version: 1,
      sessionId: $sessionId,
      transcriptPath: (if $transcriptPath == "" then null else $transcriptPath end),
      cwd: (if $cwd == "" then null else $cwd end),
      projectName: (if $projectName == "" then null else $projectName end),
      projectPath: (if $projectPath == "" then null else $projectPath end),
      terminalAnchorId: (if $terminalAnchorId == "" then null else $terminalAnchorId end),
      tmuxSession: (if $tmuxSession == "" then null else $tmuxSession end),
      tmuxWindow: (if $tmuxWindow == "" then null else $tmuxWindow end),
      tmuxPane: (if $tmuxPane == "" then null else $tmuxPane end),
      pty: (if $pty == "" then null else $pty end),
      hostName: (if $hostName == "" then null else $hostName end),
      executionMode: (if $executionMode == "" then null else $executionMode end),
      connectionKey: (if $connectionKey == "" then null else $connectionKey end),
      contextKey: (if $contextKey == "" then null else $contextKey end),
      remoteTarget: (if $remoteTarget == "" then null else $remoteTarget end),
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
