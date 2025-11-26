#!/usr/bin/env bash
# Feature 096: Screenshot capture helper using grim
# Usage: capture-screenshot.sh <output-file> [window-selector]
#
# Examples:
#   capture-screenshot.sh notification.png                    # Full monitoring panel
#   capture-screenshot.sh form.png "eww-monitoring-panel"    # Specific eww window

set -euo pipefail

OUTPUT_FILE="${1:-screenshot.png}"
SELECTOR="${2:-eww-monitoring-panel}"

# Get window geometry from sway tree
get_window_geometry() {
    local app_id="$1"
    swaymsg -t get_tree | jq -r --arg app_id "$app_id" \
        '.. | select(.app_id? == $app_id) | .rect | "\(.x),\(.y) \(.width)x\(.height)"' | head -1
}

# Capture full output (fallback)
capture_full_output() {
    local output="${1:-HEADLESS-1}"
    grim -o "$output" "$OUTPUT_FILE"
    echo "Captured full output $output to $OUTPUT_FILE"
}

# Capture specific window region
capture_window() {
    local geometry
    geometry=$(get_window_geometry "$SELECTOR")

    if [[ -z "$geometry" || "$geometry" == "null" ]]; then
        echo "Warning: Window '$SELECTOR' not found, capturing full output" >&2
        capture_full_output
        return 1
    fi

    grim -g "$geometry" "$OUTPUT_FILE"
    echo "Captured $SELECTOR ($geometry) to $OUTPUT_FILE"
}

# Main logic
if [[ "$SELECTOR" == "full" ]]; then
    capture_full_output "${3:-HEADLESS-1}"
else
    capture_window
fi
