#!/usr/bin/env bash
# Test script to send a command to a window

COMMAND="$1"
TARGET_WORKSPACE="${2:-4}"  # Default to workspace 4

echo "=== Testing window command sending ==="
echo "Target workspace: $TARGET_WORKSPACE"
echo "Command to send: $COMMAND"
echo ""

# Method 1: Using i3-msg + xdotool (most reliable for terminals)
echo "Method 1: i3-msg to focus + xdotool to type"
echo "---"

# Get window info from i3 for the target workspace
WINDOW_INFO=$(i3-msg -t get_tree | jq -r "
  .. | select(.type? == \"workspace\" and .num? == $TARGET_WORKSPACE)
  | .nodes[] | select(.window_properties?)
  | {window: .window, class: .window_properties.class, name: .name}
" | jq -s '.[0]')

if [ "$WINDOW_INFO" == "null" ] || [ -z "$WINDOW_INFO" ]; then
    echo "ERROR: No window found in workspace $TARGET_WORKSPACE"
    exit 1
fi

WINDOW_ID=$(echo "$WINDOW_INFO" | jq -r '.window')
WINDOW_CLASS=$(echo "$WINDOW_INFO" | jq -r '.class')
WINDOW_NAME=$(echo "$WINDOW_INFO" | jq -r '.name')

echo "Found window:"
echo "  ID: $WINDOW_ID"
echo "  Class: $WINDOW_CLASS"
echo "  Name: $WINDOW_NAME"
echo ""

# Focus the workspace and window
echo "Focusing workspace $TARGET_WORKSPACE..."
i3-msg "workspace number $TARGET_WORKSPACE" > /dev/null

# Give i3 a moment to switch
sleep 0.1

# Type the command using xdotool
echo "Typing command: $COMMAND"
xdotool type --clearmodifiers "$COMMAND"

# Press Enter to execute
echo "Pressing Enter..."
xdotool key Return

echo ""
echo "✓ Command sent successfully!"
