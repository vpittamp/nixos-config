#!/usr/bin/env bash
# otel-pretool-task.sh - PreToolUse hook for Task tool trace context propagation
#
# This hook runs BEFORE the Task tool spawns a subagent. It:
# 1. Reads the current session's trace context
# 2. Generates a new span ID for this Task tool invocation
# 3. Writes trace context files that the subagent's SessionStart will read
#
# This ensures proper parent-child span relationships in traces.
#
# NOTE (v131):
# This hook is no longer wired by default. Subagent correlation is handled by
# the Node interceptor via per-Task context files in $XDG_RUNTIME_DIR.

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Generate random hex ID
generate_id() {
  local bytes=$1
  head -c "$bytes" /dev/urandom | xxd -p | tr -d '\n'
}

# Read JSON from stdin
INPUT=$(cat)

# Extract tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_USE_ID=$(echo "$INPUT" | jq -r '.tool_use_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Only process Task tool
if [[ "$TOOL_NAME" != "Task" ]]; then
  exit 0
fi

# Determine trace context file location
CWD_TRACE_FILE="${CWD:-.}/.claude-trace-context.json"

# Try to get our current trace context
TRACE_ID=""
PARENT_SPAN_ID=""

# Method 1: From environment (set by SessionStart hook)
if [[ -n "${OTEL_SESSION_TRACE_ID:-}" ]]; then
  TRACE_ID="$OTEL_SESSION_TRACE_ID"
  PARENT_SPAN_ID="${OTEL_SESSION_SPAN_ID:-}"
fi

# Method 2: From our state file in runtime directory
if [[ -z "$TRACE_ID" ]]; then
  STATE_FILE="$RUNTIME_DIR/claude-otel-$$.json"
  if [[ -f "$STATE_FILE" ]]; then
    CTX=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
    TRACE_ID=$(echo "$CTX" | jq -r '.traceId // empty')
    PARENT_SPAN_ID=$(echo "$CTX" | jq -r '.spanId // empty')
  fi
fi

# Method 3: From working directory file
if [[ -z "$TRACE_ID" && -f "$CWD_TRACE_FILE" ]]; then
  CTX=$(cat "$CWD_TRACE_FILE" 2>/dev/null || echo '{}')
  CTX_PID=$(echo "$CTX" | jq -r '.pid // empty')
  # Only use if it's our own context (same PID)
  if [[ "$CTX_PID" == "$$" ]]; then
    TRACE_ID=$(echo "$CTX" | jq -r '.traceId // empty')
    PARENT_SPAN_ID=$(echo "$CTX" | jq -r '.spanId // empty')
  fi
fi

# If we still don't have a trace ID, we can't propagate context
if [[ -z "$TRACE_ID" ]]; then
  # Generate a new trace for orphaned subagents
  TRACE_ID=$(generate_id 16)
  PARENT_SPAN_ID=$(generate_id 8)
fi

# Generate a new span ID for this Task tool invocation
# This becomes the parent span for the subagent
TASK_SPAN_ID=$(generate_id 8)
TIMESTAMP=$(date +%s%3N)

# Create context JSON for the subagent to discover
CONTEXT_JSON=$(jq -n \
  --arg traceId "$TRACE_ID" \
  --arg spanId "$TASK_SPAN_ID" \
  --arg pid "$$" \
  --arg timestamp "$TIMESTAMP" \
  --arg toolUseId "$TOOL_USE_ID" \
  --arg sessionId "$SESSION_ID" \
  '{
    traceId: $traceId,
    spanId: $spanId,
    pid: ($pid | tonumber),
    timestamp: ($timestamp | tonumber),
    toolUseId: $toolUseId,
    parentSessionId: $sessionId
  }')

# Write to runtime directory (for process tree lookup by subagent)
# Use a task-specific file that won't be overwritten by our session file
TASK_STATE_FILE="$RUNTIME_DIR/claude-otel-task-$$.json"
echo "$CONTEXT_JSON" > "$TASK_STATE_FILE" 2>/dev/null || true

# Also update the working directory file (primary discovery method)
echo "$CONTEXT_JSON" > "$CWD_TRACE_FILE" 2>/dev/null || true

# Set environment variable for immediate subprocess inheritance
# Note: This may not work due to Claude Code's subprocess isolation,
# but the file-based approach will work via the SessionStart hook
export OTEL_TRACE_PARENT="00-${TRACE_ID}-${TASK_SPAN_ID}-01"

# Output JSON to allow the tool and potentially add context
# We allow the tool to proceed normally
jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "OTEL trace context propagated"
  },
  "suppressOutput": true
}'

exit 0
