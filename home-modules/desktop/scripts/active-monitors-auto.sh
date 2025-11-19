#!/usr/bin/env bash
# Resolve desired active outputs from config file (default: all headless outputs)
# and delegate to active-monitors.

set -euo pipefail

config_dir="${HOME}/.config/sway"
profile_current="$config_dir/monitor-profile.current"

if [[ -f "$profile_current" ]]; then
  profile_name="$(tr -d '\r' < "$profile_current" | head -n1)"
  if [[ -n "$profile_name" ]]; then
    exec "${HOME}/.local/bin/set-monitor-profile" --apply-only "$profile_name"
  fi
fi

config="$config_dir/active-outputs"

if [[ -f "$config" ]]; then
  mapfile -t outputs < <(grep -v '^\s*$' "$config")
else
  outputs=(HEADLESS-1 HEADLESS-2 HEADLESS-3)
fi

if [[ ${#outputs[@]} -eq 0 ]]; then
  echo "active-monitors-auto: no outputs specified; leaving outputs unchanged" >&2
  exit 0
fi

exec "${HOME}/.local/bin/active-monitors" "${outputs[@]}"
