#!/usr/bin/env bash
# otel-session-start.sh - SessionStart hook for OTEL trace context initialization
#
# This hook runs when Claude Code starts a session. It:
# 1. Generates or inherits a trace context
# 2. Sets OTEL_TRACE_PARENT in CLAUDE_ENV_FILE for bash commands
# 3. Writes trace context to files for subagent discovery

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
CWD_TRACE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude-trace-context.json"

# Generate random hex ID
generate_id() {
  local bytes=$1
  head -c "$bytes" /dev/urandom | xxd -p | tr -d '\n'
}

# Check if a process is running
is_process_running() {
  kill -0 "$1" 2>/dev/null
}

# Read JSON from stdin
INPUT=$(cat)

# Extract session_id and cwd from input
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Update CWD_TRACE_FILE if we have a cwd
if [[ -n "$CWD" ]]; then
  CWD_TRACE_FILE="$CWD/.claude-trace-context.json"
fi

# Try to find parent trace context (we might be a subagent)
PARENT_TRACE_ID=""
PARENT_SPAN_ID=""

# Method 1: Check environment variable (if inherited)
if [[ -n "${OTEL_TRACE_PARENT:-}" ]]; then
  # Parse W3C trace context format: 00-{traceId}-{spanId}-01
  IFS='-' read -r _ PARENT_TRACE_ID PARENT_SPAN_ID _ <<< "$OTEL_TRACE_PARENT"
fi

# Method 2: Check working directory file
if [[ -z "$PARENT_TRACE_ID" && -f "$CWD_TRACE_FILE" ]]; then
  CTX=$(cat "$CWD_TRACE_FILE" 2>/dev/null || echo '{}')
  CTX_PID=$(echo "$CTX" | jq -r '.pid // empty')
  CTX_TRACE_ID=$(echo "$CTX" | jq -r '.traceId // empty')
  CTX_SPAN_ID=$(echo "$CTX" | jq -r '.spanId // empty')

  # Only use if from a different, running process
  if [[ -n "$CTX_PID" && "$CTX_PID" != "$$" && -n "$CTX_TRACE_ID" ]]; then
    if is_process_running "$CTX_PID"; then
      PARENT_TRACE_ID="$CTX_TRACE_ID"
      PARENT_SPAN_ID="$CTX_SPAN_ID"
    fi
  fi
fi

# Method 3: Walk up process tree looking for trace context files
if [[ -z "$PARENT_TRACE_ID" && -d /proc ]]; then
  CURRENT_PID=$PPID
  DEPTH=0
  MAX_DEPTH=10

  while [[ $CURRENT_PID -gt 1 && $DEPTH -lt $MAX_DEPTH ]]; do
    STATE_FILE="$RUNTIME_DIR/claude-otel-$CURRENT_PID.json"
    if [[ -f "$STATE_FILE" ]]; then
      CTX=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
      CTX_TRACE_ID=$(echo "$CTX" | jq -r '.traceId // empty')
      CTX_SPAN_ID=$(echo "$CTX" | jq -r '.spanId // empty')
      if [[ -n "$CTX_TRACE_ID" ]]; then
        PARENT_TRACE_ID="$CTX_TRACE_ID"
        PARENT_SPAN_ID="$CTX_SPAN_ID"
        break
      fi
    fi

    # Get parent's parent PID
    # Note: /proc/PID/status is more robust than /proc/PID/stat because
    # the stat file's command field can contain spaces which breaks awk parsing
    if [[ -f "/proc/$CURRENT_PID/status" ]]; then
      CURRENT_PID=$(awk '/^PPid:/{print $2}' "/proc/$CURRENT_PID/status")
      # Validate we got a numeric PID
      if ! [[ "$CURRENT_PID" =~ ^[0-9]+$ ]]; then
        break
      fi
    else
      break
    fi
    DEPTH=$((DEPTH + 1))
  done
fi

# Determine our trace context
if [[ -n "$PARENT_TRACE_ID" ]]; then
  # We're a subagent - use parent's trace ID, generate new session span
  TRACE_ID="$PARENT_TRACE_ID"
  IS_SUBAGENT="true"
else
  # We're a root session - generate new trace ID
  TRACE_ID=$(generate_id 16)
  IS_SUBAGENT="false"
fi

# Generate our session span ID
SPAN_ID=$(generate_id 8)
TIMESTAMP=$(date +%s%3N)

# Create trace context JSON
CONTEXT_JSON=$(jq -n \
  --arg traceId "$TRACE_ID" \
  --arg spanId "$SPAN_ID" \
  --arg pid "$$" \
  --arg timestamp "$TIMESTAMP" \
  --arg sessionId "$SESSION_ID" \
  --arg isSubagent "$IS_SUBAGENT" \
  --arg parentSpanId "${PARENT_SPAN_ID:-}" \
  '{
    traceId: $traceId,
    spanId: $spanId,
    pid: ($pid | tonumber),
    timestamp: ($timestamp | tonumber),
    sessionId: $sessionId,
    isSubagent: ($isSubagent == "true"),
    parentSpanId: (if $parentSpanId == "" then null else $parentSpanId end)
  }')

# Write to CLAUDE_ENV_FILE if available (persists env vars for bash commands)
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  echo "export OTEL_TRACE_PARENT=\"00-${TRACE_ID}-${SPAN_ID}-01\"" >> "$CLAUDE_ENV_FILE"
  echo "export OTEL_SESSION_TRACE_ID=\"${TRACE_ID}\"" >> "$CLAUDE_ENV_FILE"
  echo "export OTEL_SESSION_SPAN_ID=\"${SPAN_ID}\"" >> "$CLAUDE_ENV_FILE"
  if [[ "$IS_SUBAGENT" == "true" && -n "$PARENT_SPAN_ID" ]]; then
    echo "export OTEL_PARENT_SPAN_ID=\"${PARENT_SPAN_ID}\"" >> "$CLAUDE_ENV_FILE"
  fi
fi

# Write to runtime directory (for process tree lookup)
STATE_FILE="$RUNTIME_DIR/claude-otel-$$.json"
echo "$CONTEXT_JSON" > "$STATE_FILE" 2>/dev/null || true

# Write to working directory (for same-project subagents)
echo "$CONTEXT_JSON" > "$CWD_TRACE_FILE" 2>/dev/null || true

# Output additional context for Claude (goes into session context)
if [[ "$IS_SUBAGENT" == "true" ]]; then
  echo "[OTEL] Subagent session linked to parent trace: $TRACE_ID (parent span: $PARENT_SPAN_ID)"
else
  echo "[OTEL] New trace session: $TRACE_ID"
fi

exit 0
