#!/usr/bin/env bash
# fzf-based project switcher for i3
# Uses i3pm CLI for project management

set -euo pipefail

# Get i3pm path
I3PM="i3pm"

# Get active project (suppress warnings)
ACTIVE_PROJECT=$($I3PM current --json 2>&1 | grep -v '^Warning:' | jq -r '.name // ""')

# Build project list
PROJECT_LIST=""
PROJECT_KEYS=()

# Add "Clear Project" option if a project is active
if [ -n "$ACTIVE_PROJECT" ]; then
    PROJECT_LIST="  Clear Project (Return to Global Mode)"$'\n'
    PROJECT_KEYS+=("__CLEAR__")
fi

# Get projects from i3pm and format for fzf (suppress warnings)
PROJECTS_JSON=$($I3PM list --json 2>&1 | grep -v '^Warning:')

while IFS= read -r project; do
    NAME=$(echo "$project" | jq -r '.name')
    DISPLAY_NAME=$(echo "$project" | jq -r '.display_name // .name')
    ICON=$(echo "$project" | jq -r '.icon // "📁"')
    # Handle null icon
    if [ "$ICON" = "null" ]; then
        ICON="📁"
    fi
    DIRECTORY=$(echo "$project" | jq -r '.directory // ""')
    
    # Mark active project
    MARKER=""
    if [ "$NAME" = "$ACTIVE_PROJECT" ]; then
        MARKER=" ✓"
    fi
    
    # Format: ICON  DISPLAY_NAME [directory] MARKER
    LINE="$ICON  $DISPLAY_NAME"
    if [ -n "$DIRECTORY" ]; then
        # Shorten directory for display
        SHORT_DIR=$(echo "$DIRECTORY" | sed "s|$HOME|~|")
        LINE="$LINE [$SHORT_DIR]"
    fi
    LINE="$LINE$MARKER"
    
    PROJECT_LIST="$PROJECT_LIST$LINE"$'\n'
    PROJECT_KEYS+=("$NAME")
done < <(echo "$PROJECTS_JSON" | jq -c '.projects[]')

# Exit if no projects
if [ ${#PROJECT_KEYS[@]} -eq 0 ] || ([ ${#PROJECT_KEYS[@]} -eq 1 ] && [ "${PROJECT_KEYS[0]}" = "__CLEAR__" ]); then
    echo "No projects found"
    read -n 1 -s -r -p "Press any key to close..."
    exit 0
fi

# Run fzf in fullscreen mode with dark Catppuccin Mocha theme
# Using --height=100% to fill the entire terminal
SELECTED=$(echo -n "$PROJECT_LIST" | fzf \
    --height=100% \
    --reverse \
    --border=rounded \
    --prompt="󰉋  " \
    --pointer="▶" \
    --marker="✓" \
    --header="󰌽  Switch Project  |  Enter: Switch  |  Esc: Cancel" \
    --color="bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8" \
    --color="fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc" \
    --color="marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8" \
    --color="border:#6c7086" \
    || true)

# Exit if no selection
if [ -z "$SELECTED" ]; then
    exit 0
fi

# Find the index of the selected line
INDEX=0
while IFS= read -r line; do
    if [ "$line" = "$SELECTED" ]; then
        break
    fi
    ((INDEX++)) || true
done <<< "$PROJECT_LIST"

# Get project name from the index
if [ $INDEX -lt ${#PROJECT_KEYS[@]} ]; then
    SELECTED_NAME="${PROJECT_KEYS[$INDEX]}"
    
    # Handle selection
    if [ "$SELECTED_NAME" = "__CLEAR__" ]; then
        $I3PM clear
    else
        $I3PM switch "$SELECTED_NAME"
    fi
fi
