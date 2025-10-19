#!/usr/bin/env bash
# Dynamic Multi-App Workspace Project Launcher
# Creates complete project workspaces without NixOS rebuild
#
# Usage: workspace-project.sh <project-definition-file>
#
# Project definition format (JSON):
# {
#   "name": "my-project",
#   "workspaces": [
#     {
#       "number": 2,
#       "apps": [
#         {"command": "ghostty", "args": [], "delay": 0},
#         {"command": "ghostty", "args": ["--class=floating_terminal"], "delay": 500}
#       ]
#     },
#     {
#       "number": 4,
#       "apps": [
#         {"command": "code", "args": ["/path/to/project"], "delay": 0}
#       ]
#     }
#   ]
# }

set -euo pipefail

PROJECT_FILE="${1:-}"
DRY_RUN="${DRY_RUN:-false}"

# Logging
log() { echo "[workspace-project] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# Validate inputs
[[ -z "$PROJECT_FILE" ]] && error "Usage: workspace-project.sh <project-definition-file>"
[[ -f "$PROJECT_FILE" ]] || error "Project file not found: $PROJECT_FILE"

# Check dependencies
command -v jq &>/dev/null || error "jq is required but not installed"
command -v i3-msg &>/dev/null || error "i3-msg is required (i3 not running?)"

# Check if i3 is running
if ! i3-msg -t get_version &>/dev/null; then
    error "i3 is not running or I3SOCK not set"
fi

# Parse project file
PROJECT_NAME=$(jq -r '.name // "unknown"' "$PROJECT_FILE")
log "Loading project: $PROJECT_NAME"

# Validate JSON structure
if ! jq -e '.workspaces | type == "array"' "$PROJECT_FILE" &>/dev/null; then
    error "Invalid project file: missing 'workspaces' array"
fi

# Function to launch app on workspace
launch_app_on_workspace() {
    local workspace="$1"
    local command="$2"
    local args="$3"
    local delay="$4"

    log "  → Launching: $command $args"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute on workspace $workspace: $command $args"
        return 0
    fi

    # Apply delay if specified
    if [[ "$delay" -gt 0 ]]; then
        log "    Waiting ${delay}ms..."
        sleep "$(echo "scale=3; $delay/1000" | bc)"
    fi

    # Switch to workspace
    i3-msg "workspace number $workspace" &>/dev/null

    # Small delay for workspace switch
    sleep 0.1

    # Launch application
    if [[ -n "$args" ]]; then
        i3-msg "exec --no-startup-id $command $args" &>/dev/null
    else
        i3-msg "exec --no-startup-id $command" &>/dev/null
    fi

    # Wait for window to potentially appear
    sleep 0.2
}

# Get total workspace count
WORKSPACE_COUNT=$(jq -r '.workspaces | length' "$PROJECT_FILE")
log "Project has $WORKSPACE_COUNT workspace(s)"

# Process each workspace
jq -c '.workspaces[]' "$PROJECT_FILE" | while read -r workspace; do
    WS_NUM=$(echo "$workspace" | jq -r '.number')
    APP_COUNT=$(echo "$workspace" | jq -r '.apps | length')

    log "Workspace $WS_NUM ($APP_COUNT app(s))"

    # Process each app in this workspace
    echo "$workspace" | jq -c '.apps[]' | while read -r app; do
        CMD=$(echo "$app" | jq -r '.command')
        ARGS=$(echo "$app" | jq -r '.args | join(" ") // ""')
        DELAY=$(echo "$app" | jq -r '.delay // 0')

        launch_app_on_workspace "$WS_NUM" "$CMD" "$ARGS" "$DELAY"
    done
done

log "✓ Project '$PROJECT_NAME' workspace setup complete"

# Optional: Send notification
if command -v notify-send &>/dev/null && [[ "$DRY_RUN" != "true" ]]; then
    notify-send -u low "Project Setup" "Workspace configuration for '$PROJECT_NAME' complete"
fi

exit 0
