#!/usr/bin/env bash
# fzf-based application launcher for i3
# Based on: https://fearby.com/article/using-fzf-as-a-dmenu-replacement/
# Feature 106: Portable paths via FLAKE_ROOT

# Source flake root discovery
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib/flake-root.sh" ]]; then
    source "$SCRIPT_DIR/lib/flake-root.sh"
else
    # Fallback: try to find via git or use default
    FLAKE_ROOT="${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "/etc/nixos")}"
fi

# Keybindings:
# - Enter: Execute command normally in foreground
# - Ctrl+Space: Execute exactly what you typed in foreground
# - Ctrl+B: Execute command in BACKGROUND with notification
# - Tab: Replace query with selected item

OPTS='--info=inline --print-query --expect=ctrl-b,ctrl-space --bind=tab:replace-query'

# Run fzf and capture output
OUTPUT=$(compgen -c | fzf $OPTS)

# Parse output - fzf with --expect outputs:
# Line 1: The key that was pressed (empty for Enter)
# Line 2: The query (what user typed)
# Line 3: The selected item
KEY=$(echo "$OUTPUT" | sed -n '1p')
QUERY=$(echo "$OUTPUT" | sed -n '2p')
SELECTED=$(echo "$OUTPUT" | sed -n '3p')

# Determine the command to execute
if [ "$KEY" = "ctrl-space" ]; then
    # Ctrl+Space: use exactly what was typed
    COMMAND="$QUERY"
elif [ -n "$SELECTED" ]; then
    # Enter or Ctrl+B: use selected item
    COMMAND="$SELECTED"
else
    # No selection: use query
    COMMAND="$QUERY"
fi

# Exit if no command
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Execute based on key pressed
if [ "$KEY" = "ctrl-b" ]; then
    # Background execution with notification
    "$FLAKE_ROOT/scripts/run-background-command.sh" "$COMMAND"
else
    # Normal foreground execution
    exec i3-msg -q "exec --no-startup-id $COMMAND"
fi
