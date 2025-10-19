#!/usr/bin/env bash
# Network status script for i3blocks
# Displays network connection status

# Check primary network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$INTERFACE" ]; then
  # No connection
  STATUS=" disconnected"
  COLOR="#f38ba8"  # Red (Catppuccin Mocha)
else
  # Connected - check if it's up
  if ip link show "$INTERFACE" | grep -q "state UP"; then
    STATUS=" $INTERFACE"
    COLOR="#a6e3a1"  # Green (Catppuccin Mocha)
  else
    STATUS=" $INTERFACE: down"
    COLOR="#f38ba8"  # Red
  fi
fi

# Output with Pango markup for color
echo "<span foreground='$COLOR'>$STATUS</span>"
