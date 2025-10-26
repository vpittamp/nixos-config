#!/usr/bin/env bash
# Sesh Session Switcher for i3/Walker
# Based on: https://github.com/joshmedeski/sesh

set -euo pipefail

# Get selected session using Walker in dmenu mode
# -d: dmenu mode
# -p: placeholder text
SELECTED_SESSION=$(sesh list -d -c -t -T | walker -d -p "Sesh Sessions")

if [ -n "$SELECTED_SESSION" ]; then
    # Launch Ghostty with the selected tmux session
    ghostty -e tmux attach-session -t "$SELECTED_SESSION" &
fi
