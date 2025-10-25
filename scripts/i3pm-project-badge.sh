#!/usr/bin/env bash

# Display a compact I3PM project badge for prompts and tmux status bars.
# When the terminal inherits I3PM_* environment variables, this script
# prints the project icon and name, trimmed to fit tight UI real estate.

set -euo pipefail

mode="plain"
max_len="${I3PM_PROJECT_BADGE_MAX_LEN:-22}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tmux)
      mode="tmux"
      shift
      ;;
    --plain)
      mode="plain"
      shift
      ;;
    --max-len)
      shift || break
      max_len="$1"
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: i3pm-project-badge.sh [--tmux] [--plain] [--max-len N]

Reads I3PM_* environment variables and prints a compact badge.
Set I3PM_PROJECT_BADGE_MAX_LEN to override the default length (22 chars).
EOF
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if ! [[ "$max_len" =~ ^[0-9]+$ ]]; then
  max_len=22
fi

icon="${I3PM_PROJECT_ICON:-}"
name="${I3PM_PROJECT_DISPLAY_NAME:-${I3PM_PROJECT_NAME:-}}"

if [[ -z "$name" ]]; then
  exit 0
fi

badge="$name"
if [[ -n "$icon" ]]; then
  badge="$icon $badge"
fi

if (( ${#badge} > max_len )); then
  truncate_to=$(( max_len - 1 ))
  badge="${badge:0:truncate_to}…"
fi

if [[ "$mode" == "tmux" ]]; then
  # catppuccin-inspired colors that match tmux status palette.
  printf '#[fg=colour223 bg=colour240 bold] %s #[fg=colour248 bg=colour237]' "$badge"
else
  printf '%s' "$badge"
fi
