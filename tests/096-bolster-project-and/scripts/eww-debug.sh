#!/usr/bin/env bash
# Feature 096 T083: Eww troubleshooting helper script
#
# Usage: ./eww-debug.sh [command]
#
# Commands:
#   restart   - Kill, restart daemon with debug, show logs
#   state     - Show current eww state (all variables)
#   logs      - Follow eww logs
#   vars      - Show CRUD-related variables
#   inspect   - Open GTK Inspector for style debugging

set -euo pipefail

EWW_CONFIG="$HOME/.config/eww-monitoring-panel"
EWW="eww --config $EWW_CONFIG"

usage() {
    cat <<EOF
Eww Monitoring Panel Debug Helper (Feature 096 T083)

Usage: $0 [command]

Commands:
  restart   - Kill daemon, restart with debug mode, and follow logs
  state     - Show all current eww variable states
  logs      - Follow eww logs (tail -f equivalent)
  vars      - Show CRUD-related variables (editing, creating, notifications)
  inspect   - Open GTK Inspector for CSS debugging

Examples:
  $0 restart    # Restart eww with debug mode
  $0 vars       # Check notification states
  $0 inspect    # Debug CSS issues with GTK Inspector

EOF
}

cmd_restart() {
    echo "=== Restarting Eww Monitoring Panel in debug mode ==="

    # Kill existing daemon
    $EWW kill 2>/dev/null || true
    sleep 1

    # Start daemon with debug
    $EWW daemon --debug &
    DAEMON_PID=$!
    sleep 2

    echo "Daemon started (PID: $DAEMON_PID)"
    echo "=== Following logs (Ctrl+C to exit) ==="
    $EWW logs
}

cmd_state() {
    echo "=== Current Eww State ==="
    $EWW state | sort
}

cmd_logs() {
    echo "=== Following Eww Logs ==="
    $EWW logs
}

cmd_vars() {
    echo "=== CRUD-Related Variables ==="
    echo ""
    echo "--- Editing State ---"
    echo "editing_project_name: $($EWW get editing_project_name 2>/dev/null || echo 'N/A')"
    echo "edit_form_error: $($EWW get edit_form_error 2>/dev/null || echo 'N/A')"
    echo ""
    echo "--- Creating State ---"
    echo "project_creating: $($EWW get project_creating 2>/dev/null || echo 'N/A')"
    echo "worktree_creating: $($EWW get worktree_creating 2>/dev/null || echo 'N/A')"
    echo "create_form_error: $($EWW get create_form_error 2>/dev/null || echo 'N/A')"
    echo ""
    echo "--- Delete State ---"
    echo "project_deleting: $($EWW get project_deleting 2>/dev/null || echo 'N/A')"
    echo "delete_project_name: $($EWW get delete_project_name 2>/dev/null || echo 'N/A')"
    echo ""
    echo "--- Notification State ---"
    echo "save_in_progress: $($EWW get save_in_progress 2>/dev/null || echo 'N/A')"
    echo "success_notification: $($EWW get success_notification 2>/dev/null || echo 'N/A')"
    echo "success_notification_visible: $($EWW get success_notification_visible 2>/dev/null || echo 'N/A')"
    echo "error_notification: $($EWW get error_notification 2>/dev/null || echo 'N/A')"
    echo "error_notification_visible: $($EWW get error_notification_visible 2>/dev/null || echo 'N/A')"
    echo "warning_notification: $($EWW get warning_notification 2>/dev/null || echo 'N/A')"
    echo "warning_notification_visible: $($EWW get warning_notification_visible 2>/dev/null || echo 'N/A')"
    echo ""
    echo "--- Validation State ---"
    echo "validation_state: $($EWW get validation_state 2>/dev/null || echo 'N/A')"
}

cmd_inspect() {
    echo "=== Opening GTK Inspector ==="
    echo "Note: Set GTK_DEBUG=interactive before running for full inspector"
    echo ""
    echo "To enable GTK Inspector:"
    echo "  1. Run: GTK_DEBUG=interactive eww --config $EWW_CONFIG open monitoring-panel"
    echo "  2. Or press Ctrl+Shift+I in the eww window"
    echo ""
    echo "Useful Inspector tabs:"
    echo "  - CSS: View and edit styles live"
    echo "  - Objects: Inspect widget hierarchy"
    echo "  - Visual: See widget bounds and margins"
}

# Main command dispatch
case "${1:-help}" in
    restart)
        cmd_restart
        ;;
    state)
        cmd_state
        ;;
    logs)
        cmd_logs
        ;;
    vars)
        cmd_vars
        ;;
    inspect)
        cmd_inspect
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
