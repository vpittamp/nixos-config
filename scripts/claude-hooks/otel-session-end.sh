#!/usr/bin/env bash
# otel-session-end.sh - SessionEnd hook for OTEL trace context cleanup
#
# This hook runs when Claude Code ends a session. It cleans up:
# 1. Runtime directory trace context files
# 2. Working directory trace context file (if we created it)

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Read JSON from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Clean up our state files
rm -f "$RUNTIME_DIR/claude-otel-$$.json" 2>/dev/null || true
rm -f "$RUNTIME_DIR/claude-otel-task-$$.json" 2>/dev/null || true

# Clean up working directory file only if it's ours
CWD_TRACE_FILE="${CWD:-.}/.claude-trace-context.json"
if [[ -f "$CWD_TRACE_FILE" ]]; then
  CTX_PID=$(jq -r '.pid // empty' "$CWD_TRACE_FILE" 2>/dev/null || echo "")
  if [[ "$CTX_PID" == "$$" ]]; then
    rm -f "$CWD_TRACE_FILE" 2>/dev/null || true
  fi
fi

exit 0
