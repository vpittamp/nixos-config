#!/usr/bin/env bash
# Project context indicator for i3blocks
# Displays active project from i3 project management system

PROJECT_FILE="$HOME/.config/i3/active-project"

# Check if file exists and is valid JSON
if [ -f "$PROJECT_FILE" ]; then
  # Parse JSON (requires jq)
  NAME=$(jq -r '.display_name // .name // empty' "$PROJECT_FILE" 2>/dev/null)
  ICON=$(jq -r '.icon // ""' "$PROJECT_FILE" 2>/dev/null)

  if [ -n "$NAME" ] && [ "$NAME" != "null" ]; then
    # Active project - combine icon and name
    if [ -n "$ICON" ] && [ "$ICON" != "null" ]; then
      TEXT="$ICON  $NAME"
    else
      TEXT=" $NAME"
    fi
    COLOR="#b4befe"  # Lavender (Catppuccin Mocha - active project)
  else
    # Invalid JSON or missing fields
    TEXT="∅ No Project"
    COLOR="#6c7086"  # Overlay0 (Catppuccin Mocha - dimmed)
  fi
else
  # No project active
  TEXT="∅ No Project"
  COLOR="#6c7086"  # Overlay0 (Catppuccin Mocha - dimmed)
fi

# Output JSON with color
cat <<EOF
{
  "full_text": "$TEXT",
  "color": "$COLOR",
  "separator": true,
  "separator_block_width": 15
}
EOF
