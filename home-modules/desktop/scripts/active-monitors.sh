#!/usr/bin/env bash
# active-monitors - Toggle which headless outputs are active and sync wayvnc units
# Usage: active-monitors HEADLESS-1 [HEADLESS-2 ...]
#
# Designed for hetzner-sway (headless wlroots backend with virtual outputs).
# Steps:
#   1) Enable the requested outputs (create/enable + set layout)
#   2) Disable any other active outputs
#   3) Start/stop matching wayvnc@<output>.service units if they exist
#   4) Output changes automatically trigger sway-config-manager to reassign
#      workspaces using its fallback logic.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: active-monitors OUTPUT [OUTPUT...]

Examples:
  active-monitors HEADLESS-1 HEADLESS-2   # two monitors
  active-monitors HEADLESS-1 HEADLESS-3   # skip secondary

Notes:
  - Requires running inside a Sway session (swaymsg must work).
  - WayVNC units are started/stopped to match selected outputs when present.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

SWAYMSG_BIN="$(command -v swaymsg || true)"
if [[ -z "$SWAYMSG_BIN" ]]; then
  echo "swaymsg not found; ensure Sway is installed and in PATH." >&2
  exit 1
fi

# Capture current outputs (active + all known)
outputs_json="$("$SWAYMSG_BIN" -t get_outputs)"
mapfile -t active_outputs < <(printf '%s' "$outputs_json" | jq -r '.[] | select(.active == true) | .name')
mapfile -t all_outputs < <(printf '%s' "$outputs_json" | jq -r '.[] | .name')

want=("$@")

# Deduplicate requested outputs
declare -A seen
want_unique=()
for o in "${want[@]}"; do
  if [[ -z "${seen[$o]+x}" ]]; then
    seen["$o"]=1
    want_unique+=("$o")
  fi
done
want=("${want_unique[@]}")

# Disable outputs that are currently active but not requested
for out in "${active_outputs[@]}"; do
  skip=false
  for w in "${want[@]}"; do
    [[ "$out" == "$w" ]] && skip=true && break
  done
  if ! $skip; then
    "$SWAYMSG_BIN" "output $out disable" >/dev/null || true
    systemctl --user stop "wayvnc@$out.service" 2>/dev/null || true
  fi
done

# Enable requested outputs and position them horizontally (1920x1200 @60Hz)
pos_x=0
for out in "${want[@]}"; do
  "$SWAYMSG_BIN" "output $out enable" >/dev/null || true
  "$SWAYMSG_BIN" "output $out mode 1920x1200@60Hz position ${pos_x},0 scale 1.0" >/dev/null || true
  systemctl --user start "wayvnc@$out.service" 2>/dev/null || true
  pos_x=$((pos_x + 1920))
done

echo "Active outputs set to: ${want[*]}"

# Sway emits an output change event for the daemon; no extra trigger needed.
exit 0
