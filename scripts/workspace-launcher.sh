#!/usr/bin/env bash
# Dynamic Workspace Launcher
# Launches applications on specific workspaces without NixOS rebuild
#
# Usage: workspace-launcher.sh <app> <workspace> [args...]
#
# Examples:
#   workspace-launcher.sh code 4
#   workspace-launcher.sh ghostty 2
#   workspace-launcher.sh firefox 3 --new-window https://github.com

set -euo pipefail

APP="${1:-}"
WORKSPACE="${2:-1}"
shift 2 || true
ARGS=("$@")

# Logging
log() { echo "[workspace-launcher] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# Validate inputs
[[ -z "$APP" ]] && error "Usage: workspace-launcher.sh <app> <workspace> [args...]"

# Check if i3 is running
if ! i3-msg -t get_version &>/dev/null; then
    error "i3 is not running or I3SOCK not set"
fi

log "Launching '$APP' on workspace $WORKSPACE"

# Step 1: Switch to target workspace
log "Switching to workspace $WORKSPACE..."
i3-msg "workspace number $WORKSPACE" &>/dev/null || error "Failed to switch to workspace $WORKSPACE"

# Small delay to ensure workspace switch completes
sleep 0.1

# Step 2: Launch the application
if [[ ${#ARGS[@]} -gt 0 ]]; then
    log "Executing: $APP ${ARGS[*]}"
    i3-msg "exec --no-startup-id $APP ${ARGS[*]}" &>/dev/null || error "Failed to launch $APP"
else
    log "Executing: $APP"
    i3-msg "exec --no-startup-id $APP" &>/dev/null || error "Failed to launch $APP"
fi

# Step 3: Optional - wait for window to appear and notify
sleep 0.3

# Get window count on this workspace
WINDOW_COUNT=$(i3-msg -t get_tree | jq -r "
  .. | select(.type? == \"workspace\" and .num? == $WORKSPACE)
  | .nodes[] | select(.window_properties?)
" | jq -s 'length')

log "✓ Launched $APP on workspace $WORKSPACE ($WINDOW_COUNT windows)"

# Optional: Send notification
if command -v notify-send &>/dev/null; then
    notify-send -u low "Workspace $WORKSPACE" "Launched: $APP"
fi

exit 0
