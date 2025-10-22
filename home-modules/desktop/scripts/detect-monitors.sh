#!/usr/bin/env bash
# detect-monitors - Force monitor detection and workspace distribution on i3 startup
#
# This script runs on i3 startup/reload to ensure all monitors are properly detected.
# Unlike reassign-workspaces.sh, this doesn't require an active project.

# Wait for i3 to be ready and for RDP outputs to initialize
# RDP outputs may take a few seconds to become active after boot
MAX_RETRIES=10
RETRY_DELAY=1
expected_count=0

for ((i=1; i<=MAX_RETRIES; i++)); do
    sleep $RETRY_DELAY

    # Query all outputs
    OUTPUTS=$(i3-msg -t get_outputs | jq -r '.[] | select(.active == true) | .name' | grep -v "^__")
    OUTPUT_COUNT=$(echo "$OUTPUTS" | wc -l)

    echo "Attempt $i: Detected $OUTPUT_COUNT active output(s)"

    # Check if we have multiple monitors (expected for RDP with multi-monitor)
    if [ "$OUTPUT_COUNT" -gt 1 ]; then
        echo "Multiple monitors detected, proceeding with workspace assignment"
        break
    fi

    # On last attempt, proceed anyway with whatever we have
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "Warning: Only $OUTPUT_COUNT monitor(s) detected after $MAX_RETRIES attempts"
        echo "Proceeding with workspace assignment anyway..."
    fi
done

# Default workspace distribution based on monitor count
case $OUTPUT_COUNT in
    1)
        # Single monitor - all workspaces on primary
        PRIMARY=$(echo "$OUTPUTS" | head -1)
        echo "Single monitor mode: $PRIMARY"
        for ws in {1..10}; do
            i3-msg "workspace $ws output $PRIMARY" >/dev/null 2>&1
        done
        ;;
    2)
        # Dual monitor - 1-2 on primary, 3-9 on secondary
        PRIMARY=$(echo "$OUTPUTS" | sed -n '1p')
        SECONDARY=$(echo "$OUTPUTS" | sed -n '2p')
        echo "Dual monitor mode: $PRIMARY (WS 1-2), $SECONDARY (WS 3-10)"

        i3-msg "workspace 1 output $PRIMARY" >/dev/null 2>&1
        i3-msg "workspace 2 output $PRIMARY" >/dev/null 2>&1

        for ws in {3..10}; do
            i3-msg "workspace $ws output $SECONDARY" >/dev/null 2>&1
        done
        ;;
    *)
        # Triple+ monitor - 1-2 on primary, 3-5 on secondary, 6-10 on tertiary
        PRIMARY=$(echo "$OUTPUTS" | sed -n '1p')
        SECONDARY=$(echo "$OUTPUTS" | sed -n '2p')
        TERTIARY=$(echo "$OUTPUTS" | sed -n '3p')

        if [ -z "$TERTIARY" ]; then
            # Fallback to dual monitor if third not available
            TERTIARY=$SECONDARY
        fi

        echo "Triple+ monitor mode: $PRIMARY (WS 1-2), $SECONDARY (WS 3-5), $TERTIARY (WS 6-10)"

        i3-msg "workspace 1 output $PRIMARY" >/dev/null 2>&1
        i3-msg "workspace 2 output $PRIMARY" >/dev/null 2>&1

        i3-msg "workspace 3 output $SECONDARY" >/dev/null 2>&1
        i3-msg "workspace 4 output $SECONDARY" >/dev/null 2>&1
        i3-msg "workspace 5 output $SECONDARY" >/dev/null 2>&1

        for ws in {6..10}; do
            i3-msg "workspace $ws output $TERTIARY" >/dev/null 2>&1
        done
        ;;
esac

echo "Monitor detection complete"
