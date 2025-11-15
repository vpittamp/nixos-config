#!/usr/bin/env bash
# Volume status monitoring for Eww top bar
#
# Feature 061: US3 - Volume control with auto-detection of PipeWire/PulseAudio
#
# Queries audio system and outputs JSON with volume and mute status
#
# Output format:
# {
#   "volume": 75,
#   "muted": false,
#   "icon": "🔊"
# }
#
# Icon mapping (FR-019):
#   67-100%: High (🔊)
#   34-66%: Medium (🔉)
#   1-33%: Low (🔈)
#   0% or muted: Muted (🔇)
#
# Exit codes:
#   0 - Always

set -euo pipefail

VOLUME=0
MUTED=false

# Try PipeWire first (wpctl)
if command -v wpctl &>/dev/null; then
    # Get default sink volume
    VOL_OUTPUT=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "")

    if [ -n "$VOL_OUTPUT" ]; then
        # Parse output like "Volume: 0.75" or "Volume: 0.75 [MUTED]"
        VOLUME=$(echo "$VOL_OUTPUT" | grep -oP 'Volume: \K[0-9.]+' | awk '{print int($1 * 100)}')

        if echo "$VOL_OUTPUT" | grep -q "MUTED"; then
            MUTED=true
        fi
    fi
# Fallback to PulseAudio (pactl)
elif command -v pactl &>/dev/null; then
    # Get default sink info
    SINK=$(pactl get-default-sink 2>/dev/null || echo "")

    if [ -n "$SINK" ]; then
        VOL_OUTPUT=$(pactl get-sink-volume "$SINK" 2>/dev/null || echo "")
        MUTE_OUTPUT=$(pactl get-sink-mute "$SINK" 2>/dev/null || echo "")

        # Parse volume (e.g., "Volume: front-left: 65536 /  100% / 0.00 dB")
        VOLUME=$(echo "$VOL_OUTPUT" | grep -oP '\d+%' | head -1 | tr -d '%')

        # Parse mute state
        if echo "$MUTE_OUTPUT" | grep -q "yes"; then
            MUTED=true
        fi
    fi
fi

# Determine icon based on volume level (FR-019)
if [ "$MUTED" = true ] || [ "$VOLUME" -eq 0 ]; then
    ICON="🔇"  # Muted
elif [ "$VOLUME" -gt 66 ]; then
    ICON="🔊"  # High
elif [ "$VOLUME" -gt 33 ]; then
    ICON="🔉"  # Medium
else
    ICON="🔈"  # Low
fi

# Output JSON
echo "{\"volume\":$VOLUME,\"muted\":$MUTED,\"icon\":\"$ICON\"}"
exit 0
