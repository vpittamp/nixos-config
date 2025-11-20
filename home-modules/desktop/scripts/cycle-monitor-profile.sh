#!/usr/bin/env bash
# cycle-monitor-profile - Cycle through monitor profiles with Mod+Shift+M
# Feature 084: M1 hybrid mode support

set -euo pipefail

CURRENT_FILE="${HOME}/.config/sway/monitor-profile.current"
PROFILE_DIR="${HOME}/.config/sway/monitor-profiles"

# Detect mode based on hostname
if [[ "$(hostname)" == "nixos-m1" ]]; then
  # M1 hybrid mode profiles
  PROFILES=("local-only" "local+1vnc" "local+2vnc")
else
  # Hetzner headless mode profiles
  PROFILES=("single" "dual" "triple")
fi

# Get current profile
if [[ -f "$CURRENT_FILE" ]]; then
  current=$(cat "$CURRENT_FILE" | tr -d '[:space:]')
else
  current="${PROFILES[0]}"
fi

# Find current index and cycle to next
next_profile="${PROFILES[0]}"
for i in "${!PROFILES[@]}"; do
  if [[ "${PROFILES[$i]}" == "$current" ]]; then
    next_index=$(( (i + 1) % ${#PROFILES[@]} ))
    next_profile="${PROFILES[$next_index]}"
    break
  fi
done

# Apply the new profile
if [[ -x "${HOME}/.local/bin/set-monitor-profile" ]]; then
  "${HOME}/.local/bin/set-monitor-profile" "$next_profile"
elif command -v set-monitor-profile >/dev/null 2>&1; then
  set-monitor-profile "$next_profile"
else
  echo "cycle-monitor-profile: set-monitor-profile not found" >&2
  exit 1
fi

# Send notification
if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 2000 "Monitor Profile" "Switched to: $next_profile"
fi
