#!/usr/bin/env bash
# notify.sh: Send desktop notifications when AI assistant completes
# Part of Feature 117: Improve Notification Progress Indicators
#
# Called by monitor.sh when an AI assistant process exits (badge transitions
# from "working" to "stopped"). Sends a desktop notification with "Return to
# Window" action that focuses the correct terminal.
#
# Usage: notify.sh <window_id> <source> [project_name]
#   window_id    - Sway window ID for the terminal
#   source       - AI assistant source (claude-code, codex)
#   project_name - Project name (optional, "Awaiting input" if empty)
#
# Environment:
#   XDG_RUNTIME_DIR - Badge files at $XDG_RUNTIME_DIR/i3pm-badges/
#
# Dependencies: notify-send, swaymsg, jq

set -euo pipefail

# Configuration
BADGE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"

# T028: Source to notification title mapping
declare -A SOURCE_TITLES=(
    ["claude-code"]="Claude Code Ready"
    ["codex"]="Codex Ready"
)

# Logging helper
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] notify.sh: $*" >&2
}

# T026: Focus window and clear badge
focus_window_and_clear_badge() {
    local window_id="$1"

    # Get the workspace number for this window
    local workspace
    workspace=$(swaymsg -t get_tree | jq -r --arg id "$window_id" \
        '.. | objects | select(.type == "workspace") as $ws |
         $ws | .. | objects | select(.id == ($id | tonumber)) |
         $ws.num' 2>/dev/null | head -1)

    if [[ -n "$workspace" ]] && [[ "$workspace" != "null" ]]; then
        # Switch to workspace first (triggers i3pm project context switch)
        swaymsg "workspace number $workspace" 2>/dev/null
        log "Switched to workspace $workspace"
    fi

    # Focus the window via swaymsg
    if swaymsg "[con_id=$window_id] focus" 2>/dev/null; then
        log "Focused window $window_id"
    else
        log "Failed to focus window $window_id (may be closed)"
        # Show brief error notification
        notify-send -u low -t 3000 "Terminal unavailable" "The terminal window was closed"
    fi

    # Clear the badge file
    local badge_file="$BADGE_DIR/$window_id.json"
    if [[ -f "$badge_file" ]]; then
        rm -f "$badge_file"
        log "Cleared badge for window $window_id"
    fi
}

# T023-T029: Main notification function
send_notification() {
    local window_id="$1"
    local source="$2"
    local project_name="${3:-}"

    # T028: Get notification title from source
    local title="${SOURCE_TITLES[$source]:-$source Ready}"

    # T029: Build concise notification body
    local body
    if [[ -n "$project_name" ]]; then
        body="$project_name"
    else
        body="Awaiting input"
    fi

    log "Sending notification for window $window_id (source: $source, project: ${project_name:-none})"

    # Send notification with action using notify-send
    # -w waits for notification to be closed or action to be clicked
    # Action format: "action_id=Action Label"
    local action_result
    action_result=$(notify-send \
        -i "robot" \
        -u normal \
        -w \
        -A "return=Return to Window" \
        "$title" \
        "$body" 2>/dev/null || echo "")

    # T026: Handle action click
    if [[ "$action_result" == "return" ]]; then
        log "User clicked 'Return to Window' action"
        focus_window_and_clear_badge "$window_id"
    else
        log "Notification dismissed without action (result: ${action_result:-none})"
    fi
}

# Main
main() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: notify.sh <window_id> <source> [project_name]" >&2
        exit 1
    fi

    local window_id="$1"
    local source="$2"
    local project_name="${3:-}"

    send_notification "$window_id" "$source" "$project_name"
}

main "$@"
