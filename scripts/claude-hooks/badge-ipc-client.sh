#!/usr/bin/env bash
# badge-ipc-client.sh - Helper script for badge IPC calls
# Feature 095: Visual Notification Badges in Monitoring Panel

set -euo pipefail

# IPC socket path - Feature 117: User socket only (daemon runs as user service)
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

# Usage information
usage() {
    cat <<EOF
Usage: badge-ipc <command> [args]

Commands:
    create <window_id> [source]  Create badge or increment existing (source defaults to "generic")
    clear <window_id>            Clear badge for window
    get-state                    Get all badge state
    create-current [source]      Create badge for currently focused window

Examples:
    badge-ipc create 12345 claude-code
    badge-ipc clear 12345
    badge-ipc get-state
    badge-ipc create-current build-failure
EOF
    exit 1
}

# Helper: Send JSON-RPC request to daemon
send_jsonrpc() {
    local method="$1"
    local params="$2"

    # Check socket exists
    if [ ! -S "$SOCKET_PATH" ]; then
        echo "Error: Daemon socket not found: $SOCKET_PATH" >&2
        echo "Is the daemon running? Check: systemctl --user status i3-project-event-listener" >&2
        exit 1
    fi

    # Build JSON-RPC request
    local request
    request=$(jq -nc \
        --arg method "$method" \
        --argjson params "$params" \
        '{jsonrpc: "2.0", method: $method, params: $params, id: 1}')

    # Send request and capture response
    # Feature 107: Added -w 1 to prevent nc from hanging indefinitely
    # The daemon sends response but doesn't close connection; -w 1 adds 1s timeout
    local response
    if ! response=$(echo "$request" | nc -w 1 -U "$SOCKET_PATH" 2>&1); then
        echo "Error: Failed to communicate with daemon" >&2
        exit 1
    fi

    # Check for JSON-RPC error
    local error
    error=$(echo "$response" | jq -r '.error.message // empty')
    if [ -n "$error" ]; then
        echo "Error: $error" >&2
        exit 1
    fi

    # Return result
    echo "$response" | jq -r '.result'
}

# Create badge or increment existing
# Feature 107: Added --state parameter for working/stopped state
cmd_create() {
    local window_id=""
    local source="generic"
    local state="stopped"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --state)
                state="${2:-stopped}"
                shift 2
                ;;
            *)
                if [ -z "$window_id" ]; then
                    window_id="$1"
                else
                    source="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$window_id" ]; then
        echo "Error: window_id required" >&2
        echo "Usage: badge-ipc create <window_id> [source] [--state working|stopped]" >&2
        exit 1
    fi

    # Validate window_id is a number
    if ! [[ "$window_id" =~ ^[0-9]+$ ]]; then
        echo "Error: window_id must be a number" >&2
        exit 1
    fi

    # Validate state
    if [[ "$state" != "working" && "$state" != "stopped" ]]; then
        echo "Error: state must be 'working' or 'stopped'" >&2
        exit 1
    fi

    local params
    params=$(jq -nc \
        --argjson window_id "$window_id" \
        --arg source "$source" \
        --arg state "$state" \
        '{window_id: $window_id, source: $source, state: $state}')

    local result
    result=$(send_jsonrpc "create_badge" "$params")

    # Display result
    echo "$result" | jq '{
        success: .success,
        window_id: .badge.window_id,
        count: .badge.count,
        source: .badge.source
    }'
}

# Clear badge for window
cmd_clear() {
    local window_id="${1:-}"

    if [ -z "$window_id" ]; then
        echo "Error: window_id required" >&2
        echo "Usage: badge-ipc clear <window_id>" >&2
        exit 1
    fi

    # Validate window_id is a number
    if ! [[ "$window_id" =~ ^[0-9]+$ ]]; then
        echo "Error: window_id must be a number" >&2
        exit 1
    fi

    local params
    params=$(jq -nc --argjson window_id "$window_id" '{window_id: $window_id}')

    local result
    result=$(send_jsonrpc "clear_badge" "$params")

    # Display result
    echo "$result" | jq '{success: .success, cleared_count: .cleared_count}'
}

# Get all badge state
cmd_get_state() {
    local params='{}'
    local result
    result=$(send_jsonrpc "get_badge_state" "$params")

    # Display result (already in Eww format)
    echo "$result"
}

# Create badge for currently focused window
cmd_create_current() {
    local source="${1:-generic}"

    # Get focused window ID from Sway
    local window_id
    window_id=$(swaymsg -t get_tree | jq -r '.. | select(.focused? == true) | .id')

    if [ -z "$window_id" ] || [ "$window_id" = "null" ]; then
        echo "Error: No focused window found" >&2
        exit 1
    fi

    echo "Creating badge for focused window $window_id (source: $source)" >&2

    # Call cmd_create with the focused window ID
    cmd_create "$window_id" "$source"
}

# Parse command
case "${1:-}" in
    create)
        shift
        cmd_create "$@"
        ;;
    clear)
        shift
        cmd_clear "$@"
        ;;
    get-state)
        cmd_get_state
        ;;
    create-current)
        shift
        cmd_create_current "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Error: Unknown command '${1:-}'" >&2
        usage
        ;;
esac
