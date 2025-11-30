#!/usr/bin/env bash
# T027: Automatic Window Registration
# Called by i3 for_window rule to register project-scoped windows
# This ensures windows launched via rofi/desktop files are tracked

set -euo pipefail

# Dependencies (will be injected by Nix)
JQ="${JQ:-jq}"
I3MSG="${I3MSG:-i3-msg}"

# Configuration
WINDOW_MAP_FILE="${WINDOW_MAP_FILE:-$HOME/.config/i3/window-project-map.json}"
STATE_FILE="${STATE_FILE:-$HOME/.config/i3/current-project}"
PROJECT_FILE="${PROJECT_FILE:-$HOME/.config/i3-projects/projects.json}"

WM_CLASS="$1"

# Get current project
if [ ! -f "$STATE_FILE" ]; then
    # No active project, nothing to register
    exit 0
fi

PROJECT_ID=$("$JQ" -r '.project_id // empty' "$STATE_FILE" 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
    # No active project
    exit 0
fi

# Check if this wmClass is project-scoped in current project
if [ ! -f "$PROJECT_FILE" ]; then
    exit 0
fi

IS_PROJECT_SCOPED=$("$JQ" -r --arg pid "$PROJECT_ID" --arg wmClass "$WM_CLASS" '
    .projects[$pid].workspaces[]? |
    .applications[]? |
    select(.wmClass == $wmClass and .projectScoped == true) |
    .projectScoped
' "$PROJECT_FILE" | head -1)

if [ "$IS_PROJECT_SCOPED" != "true" ]; then
    # This app is not project-scoped
    exit 0
fi

# Find the newest window with this wmClass
WINDOW_ID=$("$I3MSG" -t get_tree | "$JQ" -r --arg wmClass "$WM_CLASS" '
    [.. |
     select(type == "object") |
     select(has("window")) |
     select(.window != null) |
     select(.window_properties.class == $wmClass)] |
    sort_by(.id) |
    .[-1].window // empty
' 2>/dev/null)

if [ -z "$WINDOW_ID" ] || [ "$WINDOW_ID" = "null" ]; then
    # No window found
    exit 0
fi

# Initialize tracking file if needed
if [ ! -f "$WINDOW_MAP_FILE" ]; then
    echo '{"windows":{}}' > "$WINDOW_MAP_FILE"
fi

# Check if already registered
ALREADY_REGISTERED=$("$JQ" --arg wid "$WINDOW_ID" '.windows | has($wid)' "$WINDOW_MAP_FILE")

if [ "$ALREADY_REGISTERED" = "true" ]; then
    # Already registered, skip
    exit 0
fi

# Register window
TIMESTAMP=$(date -Iseconds)
"$JQ" --arg wid "$WINDOW_ID" \
      --arg pid "$PROJECT_ID" \
      --arg wmClass "$WM_CLASS" \
      --arg ts "$TIMESTAMP" \
      '.windows[$wid] = {
          project_id: $pid,
          wmClass: $wmClass,
          registered_at: $ts
      }' "$WINDOW_MAP_FILE" > "$WINDOW_MAP_FILE.tmp" && \
mv "$WINDOW_MAP_FILE.tmp" "$WINDOW_MAP_FILE"

# Log registration (optional)
LOG_FILE="${LOG_FILE:-$HOME/.config/i3/window-registration.log}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Registered window $WINDOW_ID (wmClass: $WM_CLASS) for project: $PROJECT_ID" >> "$LOG_FILE"

