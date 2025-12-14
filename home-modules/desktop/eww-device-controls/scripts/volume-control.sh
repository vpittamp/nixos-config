#!/usr/bin/env bash
# Volume control wrapper for Eww onclick handlers
# Feature 116: Unified device controls
#
# Usage: volume-control.sh ACTION [VALUE]
#
# Actions:
#   get           Get current volume (JSON)
#   set VALUE     Set volume to VALUE (0-100)
#   up [STEP]     Increase volume by STEP (default: 5)
#   down [STEP]   Decrease volume by STEP (default: 5)
#   mute          Toggle mute
#   device ID     Switch to device ID
#
# Exit codes:
#   0 - Success
#   1 - Error

set -euo pipefail

ACTION="${1:-get}"
VALUE="${2:-5}"

error_json() {
    echo "{\"error\": true, \"message\": \"$1\", \"code\": \"$2\"}"
    exit 1
}

case "$ACTION" in
    get)
        # Get current volume as JSON
        output=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || error_json "Failed to get volume" "WPCTL_ERROR"

        # Parse: "Volume: 0.75" or "Volume: 0.75 [MUTED]"
        volume=$(echo "$output" | grep -oP 'Volume: \K[\d.]+' | awk '{print int($1*100)}')
        muted="false"
        [[ "$output" == *"[MUTED]"* ]] && muted="true"

        echo "{\"volume\": $volume, \"muted\": $muted}"
        ;;

    set)
        # Set volume (0-100)
        if [[ ! "$VALUE" =~ ^[0-9]+$ ]] || [[ "$VALUE" -lt 0 ]] || [[ "$VALUE" -gt 100 ]]; then
            error_json "Invalid volume value: $VALUE (must be 0-100)" "INVALID_VALUE"
        fi

        # Convert to decimal (wpctl uses 0.0-1.0)
        decimal=$(awk "BEGIN {printf \"%.2f\", $VALUE/100}")
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$decimal" 2>/dev/null || error_json "Failed to set volume" "WPCTL_ERROR"
        ;;

    up)
        # Increase volume by STEP (default 5)
        step="${VALUE:-5}"
        wpctl set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ "${step}%+" 2>/dev/null || error_json "Failed to increase volume" "WPCTL_ERROR"
        ;;

    down)
        # Decrease volume by STEP (default 5)
        step="${VALUE:-5}"
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "${step}%-" 2>/dev/null || error_json "Failed to decrease volume" "WPCTL_ERROR"
        ;;

    mute)
        # Toggle mute
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null || error_json "Failed to toggle mute" "WPCTL_ERROR"
        ;;

    device)
        # Switch output device
        device_id="$VALUE"
        if [[ ! "$device_id" =~ ^[0-9]+$ ]]; then
            error_json "Invalid device ID: $device_id" "INVALID_VALUE"
        fi
        wpctl set-default "$device_id" 2>/dev/null || error_json "Failed to set default device" "WPCTL_ERROR"
        ;;

    *)
        error_json "Unknown action: $ACTION" "INVALID_ACTION"
        ;;
esac
