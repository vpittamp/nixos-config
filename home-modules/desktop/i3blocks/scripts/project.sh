#!/usr/bin/env bash
# Project context indicator for i3blocks
# Displays active project from i3 project management system
# Updated for Feature 015: Event-driven daemon (T012)

# Try to query daemon first, fallback to file if daemon not running
if command -v i3-project-current &>/dev/null; then
  # Daemon-based query (Feature 015)
  OUTPUT=$(i3-project-current --format=icon 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$OUTPUT" ]; then
    # Daemon query successful
    if [ "$OUTPUT" != "" ]; then
      TEXT="$OUTPUT"
      COLOR="#b4befe"  # Lavender (Catppuccin Mocha - active project)
    else
      TEXT="∅ Global"
      COLOR="#6c7086"  # Overlay0 (Catppuccin Mocha - global mode)
    fi
  else
    # Daemon not running, fallback to file-based (Feature 012)
    PROJECT_FILE="$HOME/.config/i3/active-project"

    if [ -f "$PROJECT_FILE" ]; then
      NAME=$(jq -r '.display_name // .name // empty' "$PROJECT_FILE" 2>/dev/null)
      ICON=$(jq -r '.icon // ""' "$PROJECT_FILE" 2>/dev/null)

      if [ -n "$NAME" ] && [ "$NAME" != "null" ]; then
        if [ ! -z "$ICON" ] && [ "$ICON" != "null" ] && [ "$ICON" != '""' ]; then
          TEXT="$ICON  $NAME"
        else
          TEXT=" $NAME"
        fi
        COLOR="#b4befe"
      else
        TEXT="∅ No Project"
        COLOR="#6c7086"
      fi
    else
      TEXT="∅ No Project"
      COLOR="#6c7086"
    fi
  fi
else
  # i3-project-current not available, use file-based (Feature 012)
  PROJECT_FILE="$HOME/.config/i3/active-project"

  if [ -f "$PROJECT_FILE" ]; then
    NAME=$(jq -r '.display_name // .name // empty' "$PROJECT_FILE" 2>/dev/null)
    ICON=$(jq -r '.icon // ""' "$PROJECT_FILE" 2>/dev/null)

    if [ -n "$NAME" ] && [ "$NAME" != "null" ]; then
      if [ ! -z "$ICON" ] && [ "$ICON" != "null" ] && [ "$ICON" != '""' ]; then
        TEXT="$ICON  $NAME"
      else
        TEXT=" $NAME"
      fi
      COLOR="#b4befe"
    else
      TEXT="∅ No Project"
      COLOR="#6c7086"
    fi
  else
    TEXT="∅ No Project"
    COLOR="#6c7086"
  fi
fi

# Output with Pango markup for color
echo "<span foreground='$COLOR'>$TEXT</span>"
