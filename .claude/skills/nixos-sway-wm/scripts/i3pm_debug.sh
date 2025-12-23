#!/usr/bin/env bash
# i3pm daemon debugging helper script
# Usage: i3pm_debug.sh [command]
#
# Examples:
#   i3pm_debug.sh status    # Daemon health status
#   i3pm_debug.sh socket    # Check socket
#   i3pm_debug.sh windows   # List tracked windows
#   i3pm_debug.sh events    # Watch live events

set -euo pipefail

COMMAND="${1:-status}"
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

rpc_call() {
    local method="$1"
    local params="${2:-{}}"
    local request="{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}"

    if [[ ! -S "$SOCKET" ]]; then
        echo "Error: Socket not found at $SOCKET"
        echo "Is the daemon running? Check: systemctl --user status i3-project-event-listener"
        exit 1
    fi

    echo "$request" | timeout 5s socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null
}

case "$COMMAND" in
    status)
        echo "=== i3pm Daemon Status ==="
        rpc_call "health" | jq '.' 2>/dev/null || echo "Daemon not responding"
        ;;
    socket)
        echo "=== Socket Status ==="
        if [[ -S "$SOCKET" ]]; then
            echo "Socket exists: $SOCKET"
            ls -la "$SOCKET"
            echo ""
            echo "Testing connection..."
            rpc_call "ping" | jq '.' 2>/dev/null && echo "Connection OK" || echo "Connection failed"
        else
            echo "Socket NOT found: $SOCKET"
            echo ""
            echo "Daemon status:"
            systemctl --user status i3-project-event-listener --no-pager || true
        fi
        ;;
    windows)
        echo "=== Tracked Windows ==="
        rpc_call "window_tree" | jq '.result.tree' 2>/dev/null || echo "Failed to get window tree"
        ;;
    projects)
        echo "=== Projects ==="
        rpc_call "project_list" | jq '.result.projects' 2>/dev/null || echo "Failed to get projects"
        ;;
    active)
        echo "=== Active Project ==="
        rpc_call "project_get_active" | jq '.' 2>/dev/null || echo "No active project"
        ;;
    events)
        echo "=== Live Events (Ctrl+C to stop) ==="
        i3pm daemon events 2>/dev/null || echo "Cannot connect to event stream"
        ;;
    logs)
        echo "=== Daemon Logs (last 50 lines) ==="
        journalctl --user -u i3-project-event-listener -n 50 --no-pager
        ;;
    restart)
        echo "=== Restarting Daemon ==="
        systemctl --user restart i3-project-event-listener
        sleep 1
        systemctl --user status i3-project-event-listener --no-pager
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo ""
        echo "Available commands:"
        echo "  status   - Daemon health status"
        echo "  socket   - Check socket connectivity"
        echo "  windows  - List tracked windows"
        echo "  projects - List all projects"
        echo "  active   - Show active project"
        echo "  events   - Watch live events"
        echo "  logs     - Show daemon logs"
        echo "  restart  - Restart daemon"
        exit 1
        ;;
esac
