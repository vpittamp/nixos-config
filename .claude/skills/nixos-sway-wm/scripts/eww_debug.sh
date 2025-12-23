#!/usr/bin/env bash
# EWW debugging helper script
# Usage: eww_debug.sh [bar-name] [command]
#
# Examples:
#   eww_debug.sh top-bar state       # Show variable state
#   eww_debug.sh monitoring-panel logs   # Show logs
#   eww_debug.sh workspace-bar active    # Show active windows

set -euo pipefail

BAR_NAME="${1:-top-bar}"
COMMAND="${2:-state}"

# Determine config directory
case "$BAR_NAME" in
    top-bar)
        CONFIG_DIR="$HOME/.config/eww/eww-top-bar"
        ;;
    monitoring-panel)
        CONFIG_DIR="$HOME/.config/eww-monitoring-panel"
        ;;
    workspace-bar)
        CONFIG_DIR="$HOME/.config/eww-workspace-bar"
        ;;
    device-controls)
        CONFIG_DIR="$HOME/.config/eww/eww-device-controls"
        ;;
    *)
        echo "Unknown bar: $BAR_NAME"
        echo "Available: top-bar, monitoring-panel, workspace-bar, device-controls"
        exit 1
        ;;
esac

case "$COMMAND" in
    state)
        echo "=== EWW State ($BAR_NAME) ==="
        eww --config "$CONFIG_DIR" state 2>/dev/null || echo "EWW daemon not running"
        ;;
    logs)
        echo "=== EWW Logs ($BAR_NAME) ==="
        eww --config "$CONFIG_DIR" logs 2>/dev/null || echo "EWW daemon not running"
        ;;
    active)
        echo "=== Active Windows ($BAR_NAME) ==="
        eww --config "$CONFIG_DIR" active-windows 2>/dev/null || echo "No active windows"
        ;;
    reload)
        echo "=== Reloading ($BAR_NAME) ==="
        eww --config "$CONFIG_DIR" reload 2>/dev/null
        echo "Reloaded"
        ;;
    restart)
        echo "=== Restarting ($BAR_NAME) ==="
        case "$BAR_NAME" in
            top-bar)
                systemctl --user restart eww-top-bar
                ;;
            monitoring-panel)
                systemctl --user restart eww-monitoring-panel
                ;;
            workspace-bar)
                systemctl --user restart sway-workspace-panel
                ;;
            *)
                echo "No systemd service for $BAR_NAME"
                ;;
        esac
        echo "Restarted"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Available: state, logs, active, reload, restart"
        exit 1
        ;;
esac
