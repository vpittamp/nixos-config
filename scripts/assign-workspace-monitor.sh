#!/usr/bin/env bash
# T008: Workspace-to-Monitor Assignment Script
# Assigns workspaces to monitors based on priority and monitor count
#
# Usage: assign-workspace-monitor.sh
# Reads monitor configuration from detect-monitors.sh and applies assignments

set -euo pipefail

# Dependencies
I3MSG="${I3MSG:-i3-msg}"
DETECT_MONITORS="${DETECT_MONITORS:-$(dirname "$0")/detect-monitors.sh}"

# Get monitor configuration
MONITOR_CONFIG=$("$DETECT_MONITORS")

# Extract values
MONITOR_COUNT=$(echo "$MONITOR_CONFIG" | jq -r '.count')
PRIMARY_MONITOR=$(echo "$MONITOR_CONFIG" | jq -r '.primary')
MONITORS=($(echo "$MONITOR_CONFIG" | jq -r '.monitors[].output'))

# Log for debugging
echo "Monitor count: $MONITOR_COUNT"
echo "Primary monitor: $PRIMARY_MONITOR"
echo "Monitors: ${MONITORS[*]}"

# T037-T039: Implement assignment logic based on monitor count
case $MONITOR_COUNT in
    0)
        echo "Error: No monitors detected" >&2
        exit 1
        ;;

    1)
        # T037: 1-monitor assignment - all workspaces on primary
        echo "Assigning all workspaces to single monitor: ${MONITORS[0]}"
        for ws in {1..9}; do
            # First, switch to workspace to ensure it exists, then assign to output
            "$I3MSG" "workspace number $ws" > /dev/null 2>&1 || true
            "$I3MSG" "move workspace to output ${MONITORS[0]}" > /dev/null 2>&1 || true
        done
        # Return to workspace 1
        "$I3MSG" "workspace number 1" > /dev/null 2>&1 || true
        ;;

    2)
        # T038: 2-monitor assignment - WS 1-2 on primary, 3-9 on secondary
        echo "Assigning workspaces to 2 monitors"

        # Determine secondary monitor
        SECONDARY_MONITOR="${MONITORS[1]}"
        if [ "$SECONDARY_MONITOR" = "$PRIMARY_MONITOR" ]; then
            # If somehow secondary is same as primary, use first non-primary
            for mon in "${MONITORS[@]}"; do
                if [ "$mon" != "$PRIMARY_MONITOR" ]; then
                    SECONDARY_MONITOR="$mon"
                    break
                fi
            done
        fi

        # High priority workspaces (1-2) on primary
        for ws in 1 2; do
            "$I3MSG" "workspace number $ws" > /dev/null 2>&1 || true
            "$I3MSG" "move workspace to output $PRIMARY_MONITOR" > /dev/null 2>&1 || true
        done

        # Lower priority workspaces (3-9) on secondary
        for ws in {3..9}; do
            "$I3MSG" "workspace number $ws" > /dev/null 2>&1 || true
            "$I3MSG" "move workspace to output $SECONDARY_MONITOR" > /dev/null 2>&1 || true
        done

        # Return to workspace 1
        "$I3MSG" "workspace number 1" > /dev/null 2>&1 || true
        ;;

    *)
        # T039: 3+ monitor assignment - WS 1-2 on primary, 3-5 on secondary, 6-9 on tertiary
        echo "Assigning workspaces to 3+ monitors"

        # Determine secondary and tertiary monitors (exclude primary)
        SECONDARY_MONITOR=""
        TERTIARY_MONITOR=""
        for mon in "${MONITORS[@]}"; do
            if [ "$mon" != "$PRIMARY_MONITOR" ]; then
                if [ -z "$SECONDARY_MONITOR" ]; then
                    SECONDARY_MONITOR="$mon"
                elif [ -z "$TERTIARY_MONITOR" ]; then
                    TERTIARY_MONITOR="$mon"
                    break
                fi
            fi
        done

        echo "Secondary monitor: $SECONDARY_MONITOR"
        echo "Tertiary monitor: $TERTIARY_MONITOR"

        # High priority workspaces (1-2) on primary
        for ws in 1 2; do
            "$I3MSG" "workspace number $ws" > /dev/null 2>&1 || true
            "$I3MSG" "move workspace to output $PRIMARY_MONITOR" > /dev/null 2>&1 || true
        done

        # Medium priority workspaces (3-5) on secondary
        for ws in {3..5}; do
            "$I3MSG" "workspace number $ws" > /dev/null 2>&1 || true
            "$I3MSG" "move workspace to output $SECONDARY_MONITOR" > /dev/null 2>&1 || true
        done

        # Lower priority workspaces (6-9) on tertiary
        for ws in {6..9}; do
            "$I3MSG" "workspace number $ws" > /dev/null 2>&1 || true
            "$I3MSG" "move workspace to output $TERTIARY_MONITOR" > /dev/null 2>&1 || true
        done

        # Return to workspace 1
        "$I3MSG" "workspace number 1" > /dev/null 2>&1 || true
        ;;
esac

echo "Workspace assignment complete"
