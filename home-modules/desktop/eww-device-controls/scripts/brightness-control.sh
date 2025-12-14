#!/usr/bin/env bash
# Brightness control wrapper for Eww onclick handlers
# Feature 116: Unified device controls
#
# Usage: brightness-control.sh ACTION [VALUE] [--device DEVICE]
#
# Actions:
#   get           Get current brightness (JSON)
#   set VALUE     Set brightness to VALUE (0-100)
#   up [STEP]     Increase by STEP (default: 5)
#   down [STEP]   Decrease by STEP (default: 5)
#
# Options:
#   --device DEVICE  Target device (display|keyboard)
#                    Default: display
#
# Exit codes:
#   0 - Success
#   1 - Error
#   2 - Device unavailable

set -euo pipefail

ACTION="${1:-get}"
VALUE="${2:-5}"
DEVICE_TYPE="display"

# Save original positional args before parsing
ORIG_VALUE="$VALUE"

# Parse --device flag from args 3+
shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)
            DEVICE_TYPE="${2:-display}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Restore VALUE
VALUE="$ORIG_VALUE"

# Find brightness device
find_device() {
    local type="$1"

    if [[ "$type" == "display" ]]; then
        # Find display backlight device
        if [[ -d /sys/class/backlight ]]; then
            for device in /sys/class/backlight/*; do
                if [[ -d "$device" ]]; then
                    basename "$device"
                    return 0
                fi
            done
        fi
    elif [[ "$type" == "keyboard" ]]; then
        # Find keyboard backlight device
        if [[ -d /sys/class/leds ]]; then
            for device in /sys/class/leds/*kbd*; do
                if [[ -d "$device" ]]; then
                    basename "$device"
                    return 0
                fi
            done
            for device in /sys/class/leds/*keyboard*; do
                if [[ -d "$device" ]]; then
                    basename "$device"
                    return 0
                fi
            done
        fi
    fi

    return 1
}

error_json() {
    echo "{\"error\": true, \"message\": \"$1\", \"code\": \"$2\"}"
    exit "${3:-1}"
}

# Get device name
DEVICE=$(find_device "$DEVICE_TYPE") || error_json "No $DEVICE_TYPE brightness device found" "BRIGHTNESS_UNAVAILABLE" 2

case "$ACTION" in
    get)
        # Get current brightness as JSON using machine-readable format
        # Format: device,class,current,percent,max
        output=$(brightnessctl -d "$DEVICE" -m 2>/dev/null) || error_json "Failed to get brightness" "BRIGHTNESSCTL_ERROR"
        brightness=$(echo "$output" | cut -d',' -f4 | tr -d '%')
        max=$(echo "$output" | cut -d',' -f5)

        echo "{\"brightness\": $brightness, \"device\": \"$DEVICE\", \"max\": $max}"
        ;;

    set)
        # Set brightness (0-100)
        if [[ ! "$VALUE" =~ ^[0-9]+$ ]] || [[ "$VALUE" -lt 0 ]] || [[ "$VALUE" -gt 100 ]]; then
            error_json "Invalid brightness value: $VALUE (must be 0-100)" "INVALID_VALUE"
        fi

        # Set minimum of 5% to avoid completely dark screen
        if [[ "$DEVICE_TYPE" == "display" ]] && [[ "$VALUE" -lt 5 ]]; then
            VALUE=5
        fi

        brightnessctl -d "$DEVICE" set "${VALUE}%" 2>/dev/null || error_json "Failed to set brightness" "BRIGHTNESSCTL_ERROR"
        ;;

    up)
        # Increase brightness by STEP (default 5)
        step="${VALUE:-5}"
        brightnessctl -d "$DEVICE" set "${step}%+" 2>/dev/null || error_json "Failed to increase brightness" "BRIGHTNESSCTL_ERROR"
        ;;

    down)
        # Decrease brightness by STEP (default 5)
        step="${VALUE:-5}"
        # Prevent going below 5% for display
        if [[ "$DEVICE_TYPE" == "display" ]]; then
            current=$(brightnessctl -d "$DEVICE" -m 2>/dev/null | cut -d',' -f4 | tr -d '%')
            new_val=$((current - step))
            if [[ $new_val -lt 5 ]]; then
                brightnessctl -d "$DEVICE" set "5%" 2>/dev/null || error_json "Failed to set brightness" "BRIGHTNESSCTL_ERROR"
            else
                brightnessctl -d "$DEVICE" set "${step}%-" 2>/dev/null || error_json "Failed to decrease brightness" "BRIGHTNESSCTL_ERROR"
            fi
        else
            brightnessctl -d "$DEVICE" set "${step}%-" 2>/dev/null || error_json "Failed to decrease brightness" "BRIGHTNESSCTL_ERROR"
        fi
        ;;

    *)
        error_json "Unknown action: $ACTION" "INVALID_ACTION"
        ;;
esac
