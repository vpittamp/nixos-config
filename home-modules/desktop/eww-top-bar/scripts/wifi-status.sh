#!/usr/bin/env bash
# WiFi status monitoring for Eww top bar
#
# Feature 061: US2 - WiFi widget with signal strength and color coding
#
# Queries NetworkManager via nmcli and outputs JSON with WiFi connection status
#
# Output format:
# {
#   "connected": true,
#   "ssid": "MyNetwork",
#   "signal": 84,
#   "color": "#a6e3a1",
#   "icon": ""
# }
#
# Color mapping (FR-010):
#   >70%: Green (#a6e3a1)
#   40-70%: Yellow (#f9e2af)
#   <40%: Orange (#fab387)
#   Disconnected: Gray (#6c7086)
#
# Exit codes:
#   0 - Always

set -euo pipefail

# Check if nmcli is available
if ! command -v nmcli &>/dev/null; then
    echo '{"connected":false,"ssid":null,"signal":null,"color":"#6c7086","icon":""}'
    exit 0
fi

# Get active WiFi connection
ACTIVE=$(nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' || echo "")

if [ -z "$ACTIVE" ]; then
    # Not connected to WiFi
    echo '{"connected":false,"ssid":null,"signal":null,"color":"#6c7086","icon":""}'
    exit 0
fi

# Parse connection details
SSID=$(echo "$ACTIVE" | cut -d: -f2)
SIGNAL=$(echo "$ACTIVE" | cut -d: -f3)

# Determine color based on signal strength (FR-010)
if [ "$SIGNAL" -gt 70 ]; then
    COLOR="#a6e3a1"  # Green - strong signal
elif [ "$SIGNAL" -gt 40 ]; then
    COLOR="#f9e2af"  # Yellow - medium signal
else
    COLOR="#fab387"  # Orange - weak signal
fi

# Use Nerd Font WiFi icon
ICON=""  # nf-md-wifi

# Output JSON
echo "{\"connected\":true,\"ssid\":\"$SSID\",\"signal\":$SIGNAL,\"color\":\"$COLOR\",\"icon\":\"$ICON\"}"
exit 0
