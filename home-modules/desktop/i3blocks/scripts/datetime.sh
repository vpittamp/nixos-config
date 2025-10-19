#!/usr/bin/env bash
# Date/time script for i3blocks
# Displays current date and time in ISO 8601 format

# Get current date and time
DATETIME=$(date '+%Y-%m-%d %H:%M')

# Output plain text
echo "$DATETIME"
