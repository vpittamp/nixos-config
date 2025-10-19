#!/usr/bin/env bash
# T021: yazi Project-Aware Launcher
# Launches yazi file manager with project context and embeds project ID in window title

set -euo pipefail

# Dependencies
JQ="${JQ:-jq}"
YAZI="${YAZI:-yazi}"
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
    echo "No project active - launching yazi in global mode"
    exec "$GHOSTTY" -e "$YAZI" "$@"
    exit 0
fi

# T025: Error handling for missing project directory
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory not found: $PROJECT_DIR" >&2
    exit 1
fi

echo "Launching yazi for project: $PROJECT_ID"
echo "  Directory: $PROJECT_DIR"

# T023: Launch Ghostty with yazi and set window title via ANSI escape
# The title includes project tag for identification by project-switch-hook.sh

exec "$GHOSTTY" -e bash -c "
    # Set window title with project tag
    printf '\033]2;[PROJECT:$PROJECT_ID] yazi - $PROJECT_DIR\007'

    # Launch yazi in project directory
    cd '$PROJECT_DIR'
    exec '$YAZI'
"
