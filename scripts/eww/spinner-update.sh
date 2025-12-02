#!/usr/bin/env bash
# Feature 107: Spinner animation update script
# Called by Eww defpoll to update spinner_frame variable independently
# from the main monitoring_data deflisten stream.
#
# This reduces CPU usage from 5-10% (full data refresh every 50ms)
# to <1% (single variable update every 120ms).

FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# Calculate frame index based on current time (120ms per frame)
# Using milliseconds for smooth animation
MS=$(date +%s%3N)
IDX=$(( (MS / 120) % 10 ))

echo "${FRAMES[$IDX]}"
