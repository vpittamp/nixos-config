#!/usr/bin/env bash
# T018: VS Code Project-Aware Launcher
# Launches VS Code with project context and embeds project ID in window title

set -euo pipefail

# Dependencies
JQ="${JQ:-jq}"
CODE="${CODE:-code}"

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
    echo "No project active - launching VS Code in global mode"
    exec "$CODE" "$@"
    exit 0
fi

# T025: Error handling for missing project directory
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Warning: Project directory not found: $PROJECT_DIR" >&2
    echo "Launching VS Code without directory argument" >&2
    exec "$CODE" "$@"
    exit 0
fi

echo "Launching VS Code for project: $PROJECT_ID"
echo "  Directory: $PROJECT_DIR"

# Launch VS Code with project directory
# Note: VS Code will automatically include directory path in title
# The window title will be: "[PROJECT:$PROJECT_ID] $PROJECT_DIR - Visual Studio Code"
# We rely on the project-switch-hook.sh to identify windows by the directory path in the title

# T023: Set window title using wmctrl after launch
# Launch VS Code in background and set title
"$CODE" "$PROJECT_DIR" "$@" &
CODE_PID=$!

# Wait briefly for window to appear
sleep 1

# T026: Window-to-project tracking file for persistent identification
# VS Code overwrites window titles, so we maintain a separate mapping
WINDOW_MAP_FILE="$HOME/.config/i3/window-project-map.json"

# Find VS Code window and register it
if command -v wmctrl &> /dev/null; then
    # Get the newest Code window
    WINDOW_ID=$(wmctrl -lx | grep -i "code" | tail -1 | awk '{print $1}')

    if [ -n "$WINDOW_ID" ]; then
        # Convert hex window ID to decimal for i3 compatibility
        WINDOW_DEC=$((16#${WINDOW_ID#0x}))

        # Set window title with project tag (fallback for title-based matching)
        wmctrl -i -r "$WINDOW_ID" -N "[PROJECT:$PROJECT_ID] $PROJECT_DIR - Visual Studio Code"
        echo "✓ Set window title for VS Code: [PROJECT:$PROJECT_ID]"

        # T026: Register window in tracking file
        # Initialize file if it doesn't exist
        if [ ! -f "$WINDOW_MAP_FILE" ]; then
            echo '{"windows":{}}' > "$WINDOW_MAP_FILE"
        fi

        # Add window to tracking file
        TIMESTAMP=$(date -Iseconds)
        "$JQ" --arg wid "$WINDOW_DEC" \
              --arg pid "$PROJECT_ID" \
              --arg ts "$TIMESTAMP" \
              '.windows[$wid] = {
                  project_id: $pid,
                  wmClass: "Code",
                  registered_at: $ts
              }' "$WINDOW_MAP_FILE" > "$WINDOW_MAP_FILE.tmp" && \
        mv "$WINDOW_MAP_FILE.tmp" "$WINDOW_MAP_FILE"

        echo "✓ Registered window $WINDOW_DEC in tracking file"
    fi
fi

# Bring the window forward (don't wait for CODE_PID to prevent blocking)
wait $CODE_PID 2>/dev/null || true
