#!/usr/bin/env bash
# CPU usage script for i3blocks
# Displays CPU usage percentage with color coding

# Get CPU usage from /proc/stat
# We calculate usage by reading two snapshots 100ms apart
get_cpu_usage() {
  # Read first snapshot
  read cpu a b c idle1 rest < /proc/stat
  sleep 0.1
  # Read second snapshot
  read cpu a b c idle2 rest < /proc/stat

  # Calculate difference
  total1=$((a + b + c + idle1))
  total2=$((a + b + c + idle2))

  # CPU usage = (total_diff - idle_diff) / total_diff * 100
  total_diff=$((total2 - total1))
  idle_diff=$((idle2 - idle1))

  if [ $total_diff -eq 0 ]; then
    echo "0"
  else
    echo $(( (total_diff - idle_diff) * 100 / total_diff ))
  fi
}

# Get CPU percentage
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1)

# Fallback if top fails
if [ -z "$CPU" ]; then
  CPU=0
fi

# Color based on threshold
if [ "$CPU" -gt 95 ]; then
  COLOR="#f38ba8"  # Red (urgent)
elif [ "$CPU" -gt 80 ]; then
  COLOR="#f9e2af"  # Yellow (warning)
else
  COLOR="#cdd6f4"  # Normal (Catppuccin text)
fi

# Output plain text
echo "CPU: ${CPU}%"
