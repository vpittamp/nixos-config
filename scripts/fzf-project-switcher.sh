#!/usr/bin/env bash
# fzf-based project switcher for i3
# Uses i3pm CLI for project management

set -euo pipefail

# Clear screen at start and on exit, hide cursor
trap 'tput cnorm; clear' EXIT
tput civis  # Hide cursor

# Get i3pm path
I3PM="i3pm"

# Get active project (suppress warnings)
ACTIVE_PROJECT=$($I3PM project current 2>&1 | grep -v '^Warning:' | tr -d '\n')

# Build project list
PROJECT_LIST=""
PROJECT_KEYS=()

# Add "Clear Project" option if a project is active
if [ -n "$ACTIVE_PROJECT" ]; then
    PROJECT_LIST="  Clear Project (Return to Global Mode)"$'\n'
    PROJECT_KEYS+=("__CLEAR__")
fi

# Get projects from i3pm and format for fzf (suppress warnings)
PROJECTS_JSON=$($I3PM project list --json 2>&1 | grep -v '^Warning:')

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
done < <(echo "$PROJECTS_JSON" | jq -c '.[]')

# Exit if no projects
if [ ${#PROJECT_KEYS[@]} -eq 0 ] || ([ ${#PROJECT_KEYS[@]} -eq 1 ] && [ "${PROJECT_KEYS[0]}" = "__CLEAR__" ]); then
    echo "No projects found"
    read -n 1 -s -r -p "Press any key to close..."
    exit 0
fi

# Run fzf in fullscreen mode with dark Catppuccin Mocha theme
# --no-info hides the "3/3" match count
SELECTED=$(echo -n "$PROJECT_LIST" | fzf \
    --height=100% \
    --reverse \
    --border=rounded \
    --no-info \
    --prompt="  " \
    --pointer=">" \
    --marker="✓" \
    --header="  Switch Project  |  Enter: Switch  |  Esc: Cancel" \
    --color="bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8" \
    --color="fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc" \
    --color="marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8" \
    --color="border:#6c7086" \
    || true)

# Clear screen immediately after fzf exits
clear

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

    # Feature 072 fix: Close preview window before switching projects
    i3pm-workspace-mode cancel 2>/dev/null || true

    # Handle selection (redirect output to suppress success messages)
    if [ "$SELECTED_NAME" = "__CLEAR__" ]; then
        $I3PM project clear >/dev/null 2>&1
    else
        $I3PM project switch "$SELECTED_NAME" >/dev/null 2>&1
    fi
fi
