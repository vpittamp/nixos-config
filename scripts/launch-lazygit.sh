#!/usr/bin/env bash
# T020: lazygit Project-Aware Launcher
# Launches lazygit with project context and embeds project ID in window title

set -euo pipefail

# Dependencies
JQ="${JQ:-jq}"
LAZYGIT="${LAZYGIT:-lazygit}"
GHOSTTY="${GHOSTTY:-ghostty}"

# Configuration
CURRENT_PROJECT_SCRIPT="$HOME/.config/i3/scripts/project-current.sh"

# Get active project
if [ -f "$CURRENT_PROJECT_SCRIPT" ]; then
    PROJECT_DATA=$("$CURRENT_PROJECT_SCRIPT")
    PROJECT_ID=$(echo "$PROJECT_DATA" | "$JQ" -r '.project_id // empty')
    PROJECT_DIR=$(echo "$PROJECT_DATA" | "$JQ" -r '.directory // empty')
else
    PROJECT_ID=""
    PROJECT_DIR=""
fi

# T024: Fallback behavior when no project is active
if [ -z "$PROJECT_ID" ]; then
    echo "No project active - launching lazygit in global mode"
    exec "$GHOSTTY" -e "$LAZYGIT" "$@"
    exit 0
fi

# T025: Error handling for missing project directory
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory not found: $PROJECT_DIR" >&2
    exit 1
fi

# T025: Check if directory is a git repository
if [ ! -d "$PROJECT_DIR/.git" ]; then
    echo "Warning: Not a git repository: $PROJECT_DIR" >&2
    echo "Launching lazygit anyway (it may auto-initialize or show error)" >&2
fi

echo "Launching lazygit for project: $PROJECT_ID"
echo "  Repository: $PROJECT_DIR"

# T023: Launch Ghostty with lazygit and set window title via ANSI escape
# The title includes project tag for identification by project-switch-hook.sh

exec "$GHOSTTY" -e bash -c "
    # Set window title with project tag
    printf '\033]2;[PROJECT:$PROJECT_ID] lazygit - $PROJECT_DIR\007'

    # Change to project directory and launch lazygit
    cd '$PROJECT_DIR'
    exec '$LAZYGIT'
"
