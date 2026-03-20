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
OTEL_LOGS_ENDPOINT="${OTEL_EXPORTER_OTLP_LOGS_ENDPOINT:-${OTEL_EXPORTER_OTLP_ENDPOINT:-http://127.0.0.1:4318}/v1/logs}"
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty')"
STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // empty')"
CWD_PATH="$(echo "$INPUT" | jq -r '.cwd // empty')"

PARENT_PID="${PPID}"
TARGET_PID="${PARENT_PID}"
TIMESTAMP_MS="$(date +%s%3N)"

# Resolve the actual Claude Code PID, not the intermediate finished.sh shell.
# Stop hooks run `finished.sh`, which then invokes this script as a child
# process, so PPID here points at finished.sh rather than the live Claude
# process. SessionStart/UserPromptSubmit already persist sessionId -> pid
# metadata, so prefer that mapping when available.
if [[ -n "$SESSION_ID" ]]; then
  for session_file in "${RUNTIME_DIR}"/claude-session-*.json; do
    [[ -f "$session_file" ]] || continue
    FILE_SESSION_ID="$(jq -r '.sessionId // empty' "$session_file" 2>/dev/null || true)"
    if [[ "$FILE_SESSION_ID" != "$SESSION_ID" ]]; then
      continue
    fi
    FILE_PID="$(jq -r '.pid // empty' "$session_file" 2>/dev/null || true)"
    if [[ "$FILE_PID" =~ ^[0-9]+$ ]]; then
      TARGET_PID="$FILE_PID"
      break
    fi
  done
fi

STOP_FILE="${RUNTIME_DIR}/claude-stop-${TARGET_PID}.json"

# Always write the file (even if session_id is missing) so the interceptor can end turns.
jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg transcriptPath "$TRANSCRIPT_PATH" \
  --arg stopHookActive "$STOP_HOOK_ACTIVE" \
  --arg pid "$TARGET_PID" \
  --arg hookPid "$PARENT_PID" \
  --arg ts "$TIMESTAMP_MS" \
  '{
    version: 1,
    sessionId: (if $sessionId == "" then null else $sessionId end),
    transcriptPath: (if $transcriptPath == "" then null else $transcriptPath end),
    stopHookActive: (if $stopHookActive == "" then null else ($stopHookActive | test("^(true|false)$") as $isBool | (if $isBool then ($stopHookActive == "true") else null end)) end),
    pid: ($pid | tonumber),
    hookPid: ($hookPid | tonumber),
    timestampMs: ($ts | tonumber)
  }' > "$STOP_FILE" 2>/dev/null || true

# Also emit the explicit completion signal directly into the OTEL monitor path.
# This keeps Claude's retained "stopped" badge reliable even if the interceptor
# misses the stop runtime file race.
if [[ -n "$SESSION_ID" ]]; then
  EVENT_TIMESTAMP="$(date -u -d "@$((TIMESTAMP_MS / 1000))" +"%Y-%m-%dT%H:%M:%S.${TIMESTAMP_MS: -3}Z" 2>/dev/null || true)"
  jq -n \
    --arg sessionId "$SESSION_ID" \
    --arg ts "$TIMESTAMP_MS" \
    --arg eventTimestamp "$EVENT_TIMESTAMP" \
    --arg pid "$TARGET_PID" \
    --arg cwd "$CWD_PATH" \
    '{
      resourceLogs: [{
        resource: {
          attributes: [
            { key: "service.name", value: { stringValue: "claude-code" } },
            { key: "process.pid", value: { intValue: ($pid | tostring) } }
          ]
          + (if $cwd == "" then [] else [{ key: "working_directory", value: { stringValue: $cwd } }] end)
        },
        scopeLogs: [{
          scope: { name: "claude-stop-hook", version: "1.0.0" },
          logRecords: [{
            timeUnixNano: (($ts | tonumber) * 1000000 | tostring),
            observedTimeUnixNano: (($ts | tonumber) * 1000000 | tostring),
            body: { stringValue: "ag_ui.run_finished" },
            attributes: [
              { key: "event.name", value: { stringValue: "ag_ui.run_finished" } },
              { key: "event.timestamp", value: { stringValue: $eventTimestamp } },
              { key: "session.id", value: { stringValue: $sessionId } },
              { key: "conversation.id", value: { stringValue: $sessionId } },
              { key: "ag_ui.type", value: { stringValue: "RUN_FINISHED" } },
              { key: "ag_ui.thread_id", value: { stringValue: $sessionId } },
              { key: "ag_ui.run_id", value: { stringValue: $sessionId } },
              { key: "terminal_state_source", value: { stringValue: "claude_stop_hook" } },
              { key: "provider_stop_signal", value: { stringValue: "Stop" } }
            ]
          }]
        }]
      }]
    }' | curl -fsS -X POST \
      -H 'Content-Type: application/json' \
      --data-binary @- \
      "$OTEL_LOGS_ENDPOINT" >/dev/null 2>&1 || true
fi

exit 0
