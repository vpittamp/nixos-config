#!/usr/bin/env bash
# CPU usage script for i3blocks
# Displays CPU usage percentage with color coding

# Get CPU percentage
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1)

# Fallback if top fails
if [ -z "$CPU" ]; then
  CPU=0
fi

# Color based on threshold (Catppuccin Mocha)
if [ "$CPU" -gt 95 ]; then
  COLOR="#f38ba8"  # Red (urgent)
elif [ "$CPU" -gt 80 ]; then
  COLOR="#f9e2af"  # Yellow (warning)
else
  COLOR="#a6e3a1"  # Green (normal)
fi

# Output JSON with color
cat <<EOF
{
  "full_text": " CPU: ${CPU}%",
  "color": "$COLOR",
  "separator": true,
  "separator_block_width": 15
}
EOF
