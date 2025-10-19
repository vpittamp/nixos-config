#!/usr/bin/env bash
# T019: Ghostty + sesh Project-Aware Launcher
# Launches Ghostty terminal with sesh session manager and project context

set -euo pipefail

# Dependencies
JQ="${JQ:-jq}"
GHOSTTY="${GHOSTTY:-ghostty}"
SESH="${SESH:-sesh}"

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
    echo "No project active - launching Ghostty in global mode"
    exec "$GHOSTTY" "$@"
    exit 0
fi

# T025: Error handling for missing sesh
if ! command -v "$SESH" &> /dev/null; then
    echo "Warning: sesh not found - launching Ghostty without session manager" >&2
    exec "$GHOSTTY" "$@"
    exit 0
fi

echo "Launching Ghostty + sesh for project: $PROJECT_ID"
echo "  Session: $PROJECT_ID"
echo "  Directory: $PROJECT_DIR"

# T023: Launch Ghostty with sesh and set window title via ANSI escape
# The ANSI escape sequence \033]2;TITLE\007 sets the terminal window title
# This title is immediately visible to i3 and can be matched by project-switch-hook.sh

exec "$GHOSTTY" -e bash -c "
    # Set window title with project tag using ANSI escape sequence
    printf '\033]2;[PROJECT:$PROJECT_ID] $PROJECT_ID - Ghostty\007'

    # Launch sesh or create new session if not exists
    if command -v '$SESH' &> /dev/null; then
        exec '$SESH' connect '$PROJECT_ID'
    else
        # Fallback to tmux if sesh fails
        exec tmux new-session -A -s '$PROJECT_ID' -c '$PROJECT_DIR'
    fi
"
