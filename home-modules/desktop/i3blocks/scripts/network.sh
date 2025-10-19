#!/usr/bin/env bash
# Network status script for i3blocks
# Displays network connection status

# Check primary network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$INTERFACE" ]; then
  # No connection
  STATUS="disconnected"
  COLOR="#f38ba8"  # Red
else
  # Connected - check if it's up
  if ip link show "$INTERFACE" | grep -q "state UP"; then
    STATUS="$INTERFACE: up"
    COLOR="#a6e3a1"  # Green (Catppuccin green)
  else
    STATUS="$INTERFACE: down"
    COLOR="#f38ba8"  # Red
  fi
fi

# Output plain text
echo "$STATUS"
