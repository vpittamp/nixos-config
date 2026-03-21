#!/usr/bin/env bash
# Claude Code Stop Hook - explicit stop metadata bridge
#
# Reads hook input JSON from stdin and forwards the stop signal into the
# OTEL/session pipeline. Desktop notifications are emitted centrally from the
# dashboard notifier so Claude does not double-notify.

set -euo pipefail

LOG_FILE="/tmp/claude-finished.log"
echo "--- $(date) ---" >> "$LOG_FILE"

# Read hook input JSON from stdin
INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Feed the interceptor's stop-hook file path before doing notification work.
# This keeps QuickShell/session state in sync with the explicit stopped badge.
printf '%s' "$INPUT" | "${SCRIPT_DIR}/otel-stop.sh" >/dev/null 2>&1 || true

echo "Central dashboard notifier owns Claude completion toasts" >> "$LOG_FILE"

exit 0
