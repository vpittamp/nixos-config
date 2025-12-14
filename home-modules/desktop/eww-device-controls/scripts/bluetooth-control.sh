#!/usr/bin/env bash
# Bluetooth control wrapper for Eww onclick handlers
# Feature 116: Unified device controls
#
# Usage: bluetooth-control.sh ACTION [TARGET]
#
# Actions:
#   get               Get bluetooth state (JSON)
#   power [on|off|toggle]  Control adapter power
#   connect MAC       Connect to device
#   disconnect MAC    Disconnect device
#   scan [on|off]     Control scanning
#
# Exit codes:
#   0 - Success
#   1 - Error
#   2 - Bluetooth unavailable

set -euo pipefail

ACTION="${1:-get}"
TARGET="${2:-toggle}"

error_json() {
    echo "{\"error\": true, \"message\": \"$1\", \"code\": \"$2\"}"
    exit "${3:-1}"
}

# Check if bluetooth is available
if ! command -v bluetoothctl &>/dev/null; then
    error_json "bluetoothctl not found" "BT_UNAVAILABLE" 2
fi

# Check if adapter exists
if ! bluetoothctl show &>/dev/null; then
    error_json "No Bluetooth adapter found" "BT_UNAVAILABLE" 2
fi

case "$ACTION" in
    get)
        # Get bluetooth state as JSON
        output=$(bluetoothctl show 2>/dev/null) || error_json "Failed to get bluetooth status" "BLUETOOTHCTL_ERROR"

        enabled="false"
        scanning="false"

        if echo "$output" | grep -q "Powered: yes"; then
            enabled="true"
        fi

        if echo "$output" | grep -q "Discovering: yes"; then
            scanning="true"
        fi

        # Get paired devices
        devices_json="["
        first=true
        while IFS= read -r line; do
            if [[ "$line" =~ ^Device[[:space:]]([0-9A-Fa-f:]+)[[:space:]](.+)$ ]]; then
                mac="${BASH_REMATCH[1]}"
                name="${BASH_REMATCH[2]}"

                # Get device info
                info=$(bluetoothctl info "$mac" 2>/dev/null) || continue

                connected="false"
                if echo "$info" | grep -q "Connected: yes"; then
                    connected="true"
                fi

                # Get device type icon
                icon="󰂯"
                name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
                if [[ "$name_lower" == *"airpods"* ]] || [[ "$name_lower" == *"headphone"* ]] || [[ "$name_lower" == *"buds"* ]]; then
                    icon="󰋋"
                elif [[ "$name_lower" == *"keyboard"* ]]; then
                    icon="󰌌"
                elif [[ "$name_lower" == *"mouse"* ]] || [[ "$name_lower" == *"trackpad"* ]]; then
                    icon="󰍽"
                elif [[ "$name_lower" == *"speaker"* ]]; then
                    icon="󰓃"
                fi

                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    devices_json+=","
                fi

                # Escape name for JSON
                escaped_name=$(echo "$name" | sed 's/"/\\"/g')
                devices_json+="{\"mac\": \"$mac\", \"name\": \"$escaped_name\", \"connected\": $connected, \"icon\": \"$icon\"}"
            fi
        done < <(bluetoothctl devices Paired 2>/dev/null)
        devices_json+="]"

        echo "{\"enabled\": $enabled, \"scanning\": $scanning, \"devices\": $devices_json}"
        ;;

    power)
        # Control adapter power
        case "$TARGET" in
            on)
                bluetoothctl power on &>/dev/null || error_json "Failed to power on bluetooth" "BLUETOOTHCTL_ERROR"
                ;;
            off)
                bluetoothctl power off &>/dev/null || error_json "Failed to power off bluetooth" "BLUETOOTHCTL_ERROR"
                ;;
            toggle)
                current=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
                if [[ "$current" == "yes" ]]; then
                    bluetoothctl power off &>/dev/null || error_json "Failed to power off bluetooth" "BLUETOOTHCTL_ERROR"
                else
                    bluetoothctl power on &>/dev/null || error_json "Failed to power on bluetooth" "BLUETOOTHCTL_ERROR"
                fi
                ;;
            *)
                error_json "Invalid power target: $TARGET (use on|off|toggle)" "INVALID_VALUE"
                ;;
        esac
        ;;

    connect)
        # Connect to device
        mac="$TARGET"
        if [[ ! "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            error_json "Invalid MAC address: $mac" "INVALID_VALUE"
        fi

        # Ensure bluetooth is powered on
        bluetoothctl power on &>/dev/null

        # Connect (with timeout)
        timeout 10 bluetoothctl connect "$mac" &>/dev/null || error_json "Failed to connect to $mac" "CONNECT_FAILED"
        ;;

    disconnect)
        # Disconnect from device
        mac="$TARGET"
        if [[ ! "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            error_json "Invalid MAC address: $mac" "INVALID_VALUE"
        fi

        bluetoothctl disconnect "$mac" &>/dev/null || error_json "Failed to disconnect from $mac" "DISCONNECT_FAILED"
        ;;

    scan)
        # Control scanning
        case "$TARGET" in
            on)
                bluetoothctl scan on &>/dev/null &
                disown
                ;;
            off)
                bluetoothctl scan off 2>/dev/null || true
                ;;
            *)
                error_json "Invalid scan target: $TARGET (use on|off)" "INVALID_VALUE"
                ;;
        esac
        ;;

    *)
        error_json "Unknown action: $ACTION" "INVALID_ACTION"
        ;;
esac
