#!/usr/bin/env bash
# Date/time script for i3blocks
# Displays current date and time in ISO 8601 format

# Get current date and time
DATETIME=$(date '+%Y-%m-%d %H:%M')

# Output with Pango markup for color (Catppuccin Mocha text color)
echo "<span foreground='#cdd6f4'> $DATETIME</span>"
