#!/usr/bin/env bash
# Date/time script for i3blocks
# Displays current date and time in ISO 8601 format

# Get current date and time
DATETIME=$(date '+%Y-%m-%d %H:%M')

# Output JSON with color (Catppuccin Mocha text color)
cat <<EOF
{
  "full_text": " $DATETIME",
  "color": "#cdd6f4",
  "separator": false,
  "separator_block_width": 15
}
EOF
