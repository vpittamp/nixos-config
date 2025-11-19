#!/usr/bin/env bash
# monitor-profile-menu - Interactive monitor profile picker.

set -euo pipefail

PROFILE_DIR="${HOME}/.config/sway/monitor-profiles"
SET_CMD="${HOME}/.local/bin/set-monitor-profile"
PROMPT="Monitor Profile"

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "monitor-profile-menu: no profiles directory at $PROFILE_DIR" >&2
  exit 1
fi

mapfile -t profiles < <(find "$PROFILE_DIR" -maxdepth 1 \( -type f -o -type l \) -name '*.json' | sort)

if [[ ${#profiles[@]} -eq 0 ]]; then
  echo "monitor-profile-menu: no profiles found" >&2
  exit 1
fi

format_entries() {
  for file in "$@"; do
    name=$(basename "$file" .json)
    desc=$(jq -r '.description // ""' "$file" 2>/dev/null)
    if [[ -n "$desc" && "$desc" != "null" ]]; then
      printf '%s\t%s\n' "$name" "$desc"
    else
      printf '%s\n' "$name"
    fi
  done
}

selection=""
if command -v walker >/dev/null 2>&1; then
  selection=$(format_entries "${profiles[@]}" | walker --dmenu)
elif command -v rofi >/dev/null 2>&1; then
  selection=$(format_entries "${profiles[@]}" | rofi -dmenu -p "$PROMPT")
elif command -v wofi >/dev/null 2>&1; then
  selection=$(format_entries "${profiles[@]}" | wofi --dmenu --prompt "$PROMPT")
elif command -v fzf >/dev/null 2>&1; then
  selection=$(format_entries "${profiles[@]}" | fzf --prompt "$PROMPT> ")
else
  echo "Select profile:" >&2
  mapfile -t names < <(format_entries "${profiles[@]}" | awk -F '\t' '{print $1}')
  select entry in "${names[@]}"; do
    selection="$entry"
    break
  done
fi

selection="${selection%%$'\t'*}"
selection="${selection%% *}"

if [[ -z "$selection" ]]; then
  exit 0
fi

exec "$SET_CMD" "$selection"
