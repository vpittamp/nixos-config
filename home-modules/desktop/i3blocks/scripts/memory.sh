#!/usr/bin/env bash
# Memory usage script for i3blocks
# Displays memory usage percentage with color coding

# Read memory info from /proc/meminfo
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

# Calculate used memory
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))

# Calculate percentage
if [ "$MEM_TOTAL" -eq 0 ]; then
  MEM_PERCENT=0
else
  MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
fi

# Color based on usage
if [ "$MEM_PERCENT" -gt 95 ]; then
  COLOR="#f38ba8"  # Red (urgent)
elif [ "$MEM_PERCENT" -gt 80 ]; then
  COLOR="#f9e2af"  # Yellow (warning)
else
  COLOR="#cdd6f4"  # Normal (Catppuccin text)
fi

# Output plain text
echo "MEM: ${MEM_PERCENT}%"
