#!/usr/bin/env bash
# Toggle a single Sway output on/off and restart matching wayvnc

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: toggle-output OUTPUT_NAME" >&2
  exit 1
fi

OUT="$1"

if [[ -z "${SWAYSOCK:-}" ]]; then
  sock="$(sway --get-socketpath 2>/dev/null || true)"
  [[ -n "$sock" ]] && export SWAYSOCK="$sock"
fi

state="$(swaymsg -t get_outputs | jq -r --arg o \"$OUT\" '.[] | select(.name==$o) | .active')"

if [[ "$state" == "true" ]]; then
  swaymsg "output $OUT disable" >/dev/null
  systemctl --user stop "wayvnc@$OUT.service" 2>/dev/null || true
else
  swaymsg "output $OUT enable" >/dev/null
  swaymsg "output $OUT mode 1920x1200@60Hz" >/dev/null 2>&1 || true
  swaymsg "output $OUT scale 1.0" >/dev/null 2>&1 || true
  systemctl --user start "wayvnc@$OUT.service" 2>/dev/null || true
fi

echo "toggled $OUT"
