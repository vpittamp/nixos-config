#!/usr/bin/env bash
# T003/T007: Monitor Detection Utilities
# Detects connected monitors using xrandr and outputs monitor configuration
#
# Usage: detect-monitors.sh
# Output: JSON with monitor information

set -euo pipefail

# Dependencies
XRANDR="${XRANDR:-xrandr}"
JQ="${JQ:-jq}"

# T035: Monitor count detection logic
detect_monitor_count() {
    "$XRANDR" --query | grep -c ' connected' || echo "0"
}

# T036: Primary monitor detection
detect_primary_monitor() {
    "$XRANDR" --query | grep ' connected primary' | awk '{print $1}' | head -1 || echo ""
}

# Parse all connected monitors
detect_all_monitors() {
    "$XRANDR" --query | grep ' connected' | while read -r line; do
        local output=$(echo "$line" | awk '{print $1}')
        local is_primary=false

        if echo "$line" | grep -q 'primary'; then
            is_primary=true
        fi

        # Extract resolution if available
        local resolution=$(echo "$line" | grep -oP '\d+x\d+\+\d+\+\d+' | head -1 || echo "unknown")

        echo "$output,$is_primary,$resolution"
    done
}

# Main execution
main() {
    local monitor_count
    local primary_monitor
    local timestamp

    monitor_count=$(detect_monitor_count)
    primary_monitor=$(detect_primary_monitor)
    timestamp=$(date -Iseconds)

    # If no primary detected, use first monitor
    if [ -z "$primary_monitor" ] && [ "$monitor_count" -gt 0 ]; then
        primary_monitor=$("$XRANDR" --query | grep ' connected' | awk '{print $1}' | head -1)
    fi

    # Build monitors array
    local monitors_json="[]"
    while IFS=',' read -r output is_primary resolution; do
        local monitor_obj
        monitor_obj=$("$JQ" -n \
            --arg output "$output" \
            --argjson isPrimary "$is_primary" \
            --arg resolution "$resolution" \
            '{
                output: $output,
                isPrimary: $isPrimary,
                resolution: $resolution
            }')
        monitors_json=$("$JQ" --argjson mon "$monitor_obj" '. += [$mon]' <<< "$monitors_json")
    done < <(detect_all_monitors)

    # Output final JSON
    "$JQ" -n \
        --argjson count "$monitor_count" \
        --arg primary "$primary_monitor" \
        --argjson monitors "$monitors_json" \
        --arg timestamp "$timestamp" \
        '{
            count: $count,
            primary: $primary,
            monitors: $monitors,
            detectedAt: $timestamp
        }'
}

# Run main function
main
