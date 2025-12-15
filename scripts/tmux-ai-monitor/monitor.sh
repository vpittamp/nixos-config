#!/usr/bin/env bash
# tmux-ai-monitor: Detect AI assistant processes in tmux panes
# Part of Feature 117: Improve Notification Progress Indicators
#
# This script polls tmux panes to detect when AI assistants (claude, codex)
# are running as foreground processes. It creates badge files for the EWW
# monitoring panel to display progress indicators.
#
# Badge States:
#   - working: AI is actively processing (pulsating indicator)
#   - stopped + needs_attention: AI finished, window not yet focused (bell icon)
#   - stopped + !needs_attention: AI session idle, ready for more work (muted icon)
#
# Badges persist indefinitely until:
#   - Window is closed
#   - tmux session is terminated
#   - User explicitly dismisses (via notification action)
#
# Usage: monitor.sh [--poll-interval <ms>]
# Default poll interval: 300ms
#
# Environment:
#   POLL_INTERVAL_MS - Override default poll interval
#   XDG_RUNTIME_DIR  - Badge files written to $XDG_RUNTIME_DIR/i3pm-badges/
#
# Dependencies: tmux, jq, swaymsg, ps, grep

set -euo pipefail

# Configuration
POLL_INTERVAL_MS="${POLL_INTERVAL_MS:-300}"
BADGE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# AI process names to detect
AI_PROCESSES=("claude" "codex")

# Process name to notification mapping
declare -A PROCESS_TITLES=(
    ["claude"]="Claude Code Ready"
    ["codex"]="Codex Ready"
)
declare -A PROCESS_SOURCES=(
    ["claude"]="claude-code"
    ["codex"]="codex"
)

# State tracking: window_id -> space-separated list of active pane IDs
declare -A WINDOW_ACTIVE_PANES
# Track last known source per window (for notification title)
declare -A WINDOW_LAST_SOURCE

# Logging helper
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] tmux-ai-monitor: $*" >&2
}

# T008: Initialize badge directory
init_badge_dir() {
    if [[ ! -d "$BADGE_DIR" ]]; then
        mkdir -p "$BADGE_DIR"
        log "Created badge directory: $BADGE_DIR"
    fi
}

# T007: Get Sway window ID from tmux pane
# Strategy: Find tmux client attached to pane's session, trace client to Ghostty
get_window_id_from_pane() {
    local pane_id="$1"

    # Get the session name for this pane
    local session_name
    session_name=$(tmux display-message -t "$pane_id" -p '#{session_name}' 2>/dev/null) || true
    if [[ -z "$session_name" ]]; then
        echo ""
        return 1
    fi

    # Find a tmux client attached to this session
    local client_pid
    client_pid=$(tmux list-clients -t "$session_name" -F '#{client_pid}' 2>/dev/null | head -1) || true
    if [[ -z "$client_pid" ]]; then
        # No client attached to this session
        echo ""
        return 1
    fi

    # Walk up the process tree from client PID to find ghostty
    local current="$client_pid"
    while [[ "$current" != "1" ]] && [[ -n "$current" ]]; do
        local cmd
        cmd=$(ps -p "$current" -o args= 2>/dev/null | head -c 100 || echo "")

        # Check if this is a ghostty process
        if echo "$cmd" | grep -qi ghostty; then
            # Found ghostty - look up its window ID in sway tree
            local window_id
            window_id=$(swaymsg -t get_tree | jq -r --arg pid "$current" \
                '.. | objects | select(.app_id) | select(.pid == ($pid | tonumber)) | .id' 2>/dev/null | head -1)
            if [[ -n "$window_id" ]] && [[ "$window_id" != "null" ]]; then
                echo "$window_id"
                return 0
            fi
        fi

        # Move to parent process
        current=$(ps -o ppid= -p "$current" 2>/dev/null | tr -d ' ')
    done

    # Detection failed
    echo ""
    return 1
}

# Check if a process name is an AI assistant
is_ai_process() {
    local process_name="$1"
    for ai in "${AI_PROCESSES[@]}"; do
        if [[ "$process_name" == "$ai" ]]; then
            return 0
        fi
    done
    return 1
}

# Get project name from i3pm context (if available)
get_project_name() {
    local window_id="$1"
    # Try to get project name from i3pm project context
    # For now, use a simple approach - read from window marks or env
    local project_name
    project_name=$(swaymsg -t get_tree | jq -r --arg wid "$window_id" \
        '.. | objects | select(.id == ($wid | tonumber)) | .marks[]? | select(startswith("i3pm_project:"))' 2>/dev/null | head -1 | sed 's/i3pm_project://')

    if [[ -n "$project_name" ]]; then
        echo "$project_name"
    else
        echo ""
    fi
}

# Write badge file for "working" state
# Preserves session start time for tracking session duration
write_working_badge() {
    local window_id="$1"
    local source="$2"
    local badge_file="$BADGE_DIR/$window_id.json"

    # Preserve session_started if badge already exists
    local session_started=""
    if [[ -f "$badge_file" ]]; then
        session_started=$(jq -r '.session_started // empty' "$badge_file" 2>/dev/null || echo "")
    fi
    if [[ -z "$session_started" ]]; then
        session_started=$(date +%s.%N)
    fi

    cat > "$badge_file" <<EOF
{
  "window_id": $window_id,
  "state": "working",
  "source": "$source",
  "needs_attention": false,
  "session_started": $session_started,
  "timestamp": $(date +%s.%N)
}
EOF
    log "Created working badge for window $window_id (source: $source)"
}

# Write badge file for "stopped" state with needs_attention flag
# Preserves session_started and increments completion count
write_stopped_badge() {
    local window_id="$1"
    local source="$2"
    local badge_file="$BADGE_DIR/$window_id.json"

    # Preserve session_started and increment count from existing badge
    local session_started=""
    local count=0
    if [[ -f "$badge_file" ]]; then
        session_started=$(jq -r '.session_started // empty' "$badge_file" 2>/dev/null || echo "")
        count=$(jq -r '.count // 0' "$badge_file" 2>/dev/null || echo "0")
    fi
    if [[ -z "$session_started" ]]; then
        session_started=$(date +%s.%N)
    fi
    count=$((count + 1))

    cat > "$badge_file" <<EOF
{
  "window_id": $window_id,
  "state": "stopped",
  "source": "$source",
  "needs_attention": true,
  "count": $count,
  "session_started": $session_started,
  "timestamp": $(date +%s.%N)
}
EOF
    log "Created stopped badge for window $window_id (source: $source, count: $count)"

    # Get project name for notification
    local project_name
    project_name=$(get_project_name "$window_id")

    # Send notification via notify.sh
    if [[ -x "$SCRIPT_DIR/notify.sh" ]]; then
        "$SCRIPT_DIR/notify.sh" "$window_id" "$source" "${project_name:-}" &
    fi
}

# Update state for a single pane
update_pane_state() {
    local pane_pid="$1"
    local pane_id="$2"
    local process_name="$3"

    # Get window ID for this pane via tmux client -> Ghostty -> Sway
    # Note: || true prevents set -e from exiting on non-zero return
    local window_id
    window_id=$(get_window_id_from_pane "$pane_id") || true

    if [[ -z "$window_id" ]]; then
        # Can't determine window - skip this pane
        return
    fi

    if is_ai_process "$process_name"; then
        # AI process running - add pane to active set
        local source="${PROCESS_SOURCES[$process_name]:-$process_name}"

        # Check if pane already tracked
        if [[ ! " ${WINDOW_ACTIVE_PANES[$window_id]:-} " =~ " $pane_id " ]]; then
            WINDOW_ACTIVE_PANES[$window_id]="${WINDOW_ACTIVE_PANES[$window_id]:-} $pane_id"
            WINDOW_LAST_SOURCE[$window_id]="$source"
            write_working_badge "$window_id" "$source"
        fi
    else
        # Not an AI process - remove pane from active set if present
        if [[ " ${WINDOW_ACTIVE_PANES[$window_id]:-} " =~ " $pane_id " ]]; then
            # Remove this pane from the active set
            WINDOW_ACTIVE_PANES[$window_id]="${WINDOW_ACTIVE_PANES[$window_id]// $pane_id/}"
            WINDOW_ACTIVE_PANES[$window_id]="${WINDOW_ACTIVE_PANES[$window_id]//$pane_id /}"
            WINDOW_ACTIVE_PANES[$window_id]="${WINDOW_ACTIVE_PANES[$window_id]//$pane_id/}"

            # Check if ALL panes in this window are now inactive
            local active_panes="${WINDOW_ACTIVE_PANES[$window_id]:-}"
            active_panes="${active_panes// /}"  # Trim whitespace

            if [[ -z "$active_panes" ]]; then
                # All AI processes exited - write stopped badge
                local source="${WINDOW_LAST_SOURCE[$window_id]:-unknown}"
                write_stopped_badge "$window_id" "$source"
            fi
        fi
    fi
}

# Poll all tmux panes and update state
poll_tmux_panes() {
    # tmux list-panes -a -F format: pane_pid|pane_id|pane_current_command
    local pane_info
    if ! pane_info=$(tmux list-panes -a -F '#{pane_pid}|#{pane_id}|#{pane_current_command}' 2>/dev/null); then
        # tmux not running or no sessions
        return
    fi

    # Track which panes we've seen this poll
    declare -A seen_panes

    while IFS='|' read -r pane_pid pane_id process_name; do
        if [[ -n "$pane_pid" ]] && [[ -n "$pane_id" ]] && [[ -n "$process_name" ]]; then
            seen_panes["$pane_id"]=1
            update_pane_state "$pane_pid" "$pane_id" "$process_name"
        fi
    done <<< "$pane_info"

    # Clean up panes that no longer exist (handles closed panes)
    for window_id in "${!WINDOW_ACTIVE_PANES[@]}"; do
        local active_panes="${WINDOW_ACTIVE_PANES[$window_id]:-}"
        local remaining=""

        for pane_id in $active_panes; do
            if [[ -n "${seen_panes[$pane_id]:-}" ]]; then
                remaining="$remaining $pane_id"
            fi
        done

        remaining="${remaining## }"  # Trim leading space

        if [[ "$remaining" != "$active_panes" ]]; then
            WINDOW_ACTIVE_PANES[$window_id]="$remaining"

            # If all panes removed, write stopped badge
            if [[ -z "$remaining" ]]; then
                local source="${WINDOW_LAST_SOURCE[$window_id]:-unknown}"
                write_stopped_badge "$window_id" "$source"
            fi
        fi
    done
}

# Clear needs_attention for a window when focused
clear_needs_attention() {
    local window_id="$1"
    local badge_file="$BADGE_DIR/$window_id.json"

    if [[ -f "$badge_file" ]]; then
        # Only update if needs_attention is currently true
        local needs_attention
        needs_attention=$(jq -r '.needs_attention // false' "$badge_file" 2>/dev/null || echo "false")

        if [[ "$needs_attention" == "true" ]]; then
            # Update needs_attention to false, preserving all other fields
            local updated
            updated=$(jq '.needs_attention = false' "$badge_file" 2>/dev/null)
            if [[ -n "$updated" ]]; then
                echo "$updated" > "$badge_file"
                log "Cleared needs_attention for window $window_id (focus)"
            fi
        fi
    fi
}

# Window focus listener - runs as background process
# Clears needs_attention when a badged window receives focus
focus_listener() {
    log "Starting focus listener"

    # Subscribe to window focus events from sway
    swaymsg -t subscribe '["window"]' --monitor 2>/dev/null | while read -r event; do
        # Extract change type and container ID
        local change container_id
        change=$(echo "$event" | jq -r '.change // empty' 2>/dev/null || echo "")
        container_id=$(echo "$event" | jq -r '.container.id // empty' 2>/dev/null || echo "")

        # Only process focus events
        if [[ "$change" == "focus" ]] && [[ -n "$container_id" ]]; then
            # Check if this window has a badge with needs_attention
            clear_needs_attention "$container_id"
        fi
    done

    log "Focus listener terminated"
}

# Main polling loop
main() {
    log "Starting tmux-ai-monitor (poll interval: ${POLL_INTERVAL_MS}ms)"

    # Initialize badge directory (T008)
    init_badge_dir

    # Start focus listener in background
    focus_listener &
    FOCUS_LISTENER_PID=$!
    log "Started focus listener (PID: $FOCUS_LISTENER_PID)"

    # Cleanup on exit
    trap 'log "Shutting down..."; kill $FOCUS_LISTENER_PID 2>/dev/null || true; exit 0' SIGTERM SIGINT EXIT

    # Convert ms to seconds for sleep (with fractional support)
    local sleep_seconds
    sleep_seconds=$(echo "scale=3; $POLL_INTERVAL_MS / 1000" | bc)

    while true; do
        poll_tmux_panes
        sleep "$sleep_seconds"
    done
}

# Run main loop
main "$@"
