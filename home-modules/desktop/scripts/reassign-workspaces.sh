#!/usr/bin/env bash
# reassign-workspaces - Re-apply workspace output assignments for active project
#
# Usage: reassign-workspaces

usage() {
    cat <<EOF
Usage: reassign-workspaces

Re-apply workspace output assignments for the currently active project.

This is useful after:
  - Connecting/disconnecting external monitors
  - Changing display configuration
  - Monitor detection changes

Examples:
    reassign-workspaces

Keybinding: Win+Shift+M
EOF
}

DAEMON_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

rpc_request() {
    local method="$1"
    local params_json="${2:-{}}"
    local request response error_json

    request=$(jq -nc \
        --arg method "$method" \
        --argjson params "$params_json" \
        '{jsonrpc:"2.0", method:$method, params:$params, id:1}')

    [[ -S "$DAEMON_SOCKET" ]] || {
        echo "Daemon socket not found: $DAEMON_SOCKET" >&2
        exit 1
    }

    response=$(printf '%s\n' "$request" | socat - UNIX-CONNECT:"$DAEMON_SOCKET")
    error_json=$(jq -c '.error // empty' <<< "$response")
    if [[ -n "$error_json" ]]; then
        echo "Daemon request failed: $error_json" >&2
        exit 1
    fi

    jq -c '.result' <<< "$response"
}

main() {
    if [ "${1:-}" = "--help" ]; then
        usage
        exit 0
    fi

    local result success assigned_count
    result=$(rpc_request "reassign_workspaces" '{}')
    success=$(jq -r '.success // false' <<< "$result")
    assigned_count=$(jq -r '.assignments_made // 0' <<< "$result")

    if [[ "$success" != "true" ]]; then
        jq -r '.errors[]?' <<< "$result" >&2
        exit 1
    fi

    echo "Reassigned $assigned_count workspace(s)"
}

main "$@"
