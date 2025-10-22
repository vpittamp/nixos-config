#!/usr/bin/env bash
# Claude Code hook to save bash commands to user's bash history
# Security: This script validates input and prevents path traversal

set -euo pipefail

# Read JSON from stdin
input=$(cat)

# Extract and validate the command
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Skip empty commands
if [[ -z "$command" ]]; then
    exit 0
fi

# Validate that HOME is set
if [[ -z "${HOME:-}" ]]; then
    echo "Error: HOME environment variable not set" >&2
    exit 1
fi

# Safely append to bash history
# Using >> with proper quoting to prevent injection
echo "$command" >> "${HOME}/.bash_history"

exit 0
