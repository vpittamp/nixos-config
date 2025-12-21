#!/usr/bin/env bash
# otel-session-end.sh - SessionEnd hook for Claude Code session metadata cleanup
#
# This hook runs when Claude Code ends a session.
#
# v131: Clean up the per-process session metadata file written by
# `otel-session-start.sh`. This prevents stale `session.id` values from being
# reused if a PID is recycled quickly.

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Read JSON from stdin (currently unused, but keep to match hook contract)
cat >/dev/null

# Delete metadata file for the parent Claude Code PID (not this hook PID)
PARENT_PID="${PPID}"
rm -f "${RUNTIME_DIR}/claude-session-${PARENT_PID}.json" 2>/dev/null || true

exit 0
