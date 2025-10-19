#!/usr/bin/env bash
# FZF-based launcher that sends commands to another window
# Usage: fzf-send-to-window.sh [target_workspace]

TARGET_WORKSPACE="${1:-4}"  # Default to workspace 4

# FZF options
OPTS='--info=inline --print-query --expect=ctrl-space --bind=tab:replace-query'

# Header with instructions
HEADER="Send command to workspace $TARGET_WORKSPACE | Enter=selected | Ctrl+Space=typed | Tab=replace"

# Run fzf and capture output
OUTPUT=$(compgen -c | fzf $OPTS --header="$HEADER")

# Parse output - fzf with --expect outputs:
# Line 1: The key that was pressed (empty for Enter)
# Line 2: The query (what user typed)
# Line 3: The selected item
KEY=$(echo "$OUTPUT" | sed -n '1p')
QUERY=$(echo "$OUTPUT" | sed -n '2p')
SELECTED=$(echo "$OUTPUT" | sed -n '3p')

# Determine the command to send
if [ "$KEY" = "ctrl-space" ]; then
    # Ctrl+Space: use exactly what was typed
    COMMAND="$QUERY"
elif [ -n "$SELECTED" ]; then
    # Enter: use selected item
    COMMAND="$SELECTED"
else
    # No selection: use query
    COMMAND="$QUERY"
fi

# Exit if no command
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Get window info from i3 for the target workspace
WINDOW_INFO=$(i3-msg -t get_tree | jq -r "
  .. | select(.type? == \"workspace\" and .num? == $TARGET_WORKSPACE)
  | .nodes[] | select(.window_properties?)
  | {window: .window, class: .window_properties.class, name: .name}
" | jq -s '.[0]')

if [ "$WINDOW_INFO" == "null" ] || [ -z "$WINDOW_INFO" ]; then
    notify-send -u critical "Send to Window" "No window found in workspace $TARGET_WORKSPACE"
    exit 1
fi

WINDOW_CLASS=$(echo "$WINDOW_INFO" | jq -r '.class')
WINDOW_NAME=$(echo "$WINDOW_INFO" | jq -r '.name')

# Focus the workspace
i3-msg "workspace number $TARGET_WORKSPACE" > /dev/null 2>&1

# Give i3 a moment to switch
sleep 0.1

# Type the command using xdotool
xdotool type --clearmodifiers "$COMMAND"

# Press Enter to execute
xdotool key Return

# Show notification
notify-send -u low "Sent to Workspace $TARGET_WORKSPACE" "$COMMAND\n→ $WINDOW_CLASS"
