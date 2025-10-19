#!/usr/bin/env bash
# FZF history picker
# Selects a command from bash history and copies to clipboard

# Read from bash history file directly (not the history command which needs an interactive shell)
HISTFILE="${HISTFILE:-$HOME/.bash_history}"

# Get history from file, reverse it (newest first), remove duplicates, and select with fzf
selected=$(tac "$HISTFILE" 2>/dev/null | awk '!seen[$0]++' | fzf --prompt="History: " --height=40%)

if [ -n "$selected" ]; then
    # Copy to clipboard
    echo -n "$selected" | xclip -selection clipboard
    echo "Command copied to clipboard: $selected"
    sleep 1
else
    echo "No command selected"
    sleep 1
fi
