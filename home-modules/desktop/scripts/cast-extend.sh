#!/usr/bin/env bash
# cast-extend - wireless "extended display" over Chromecast (Google Cast).
#
# Google Cast has no extended-display mode (Chrome's Cast screen only mirrors an
# existing output), so this emulates one: it creates a Sway HEADLESS output —
# a real desktop surface that is invisible locally — which Chrome's
# "Cast -> Sources -> Cast screen" can capture and stream to the receiver
# fullscreen. Windows moved there live only on the receiver.
#
# Usage:
#   cast-extend on [WxH]   create/enable the cast output (default 1920x1080@60)
#   cast-extend off        disable it (its workspaces move back automatically)
#   cast-extend send       move the focused workspace to the cast output
#   cast-extend status     print the cast output's current state
#
# Then: Chrome -> menu -> Cast -> Sources -> Cast screen, pick the HEADLESS-*
# entry in the walker chooser, and select your Chromecast receiver.
#
# Notes:
# - Sway cannot destroy runtime-created outputs; `off` disables it (a Sway
#   restart removes it entirely).
# - The output is parked at x=+100000 so it never overlaps real monitors.
# - Headless outputs already in use (e.g. wayvnc on headless hosts) are never
#   recycled: only disabled HEADLESS-* outputs are reused.
set -euo pipefail

PARK_X=100000
STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/cast-extend.output"

die() { echo "cast-extend: $*" >&2; exit 1; }

list_outputs() { swaymsg -t get_outputs; }

headless_names() {
  list_outputs | jq -r '.[] | select(.name | startswith("HEADLESS-")) | .name'
}

# First HEADLESS-* output that exists but is disabled (safe to recycle).
find_reusable() {
  list_outputs | jq -r '[.[] | select(.name | startswith("HEADLESS-")) | select(.active == false)] | .[0].name // empty'
}

recorded() {
  [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || true
}

# Recorded output name, or "" (and drops the stale state file) if it is gone.
live_recorded() {
  local name
  name="$(recorded)"
  if [ -n "$name" ] && headless_names | grep -qx "$name"; then
    echo "$name"
  else
    rm -f "$STATE_FILE"
  fi
}

cmd_on() {
  local mode="${1:-1920x1080}"
  command -v jq >/dev/null 2>&1 || die "jq is required"

  local name
  name="$(live_recorded)"
  if [ -z "$name" ]; then
    name="$(find_reusable)"
  fi
  if [ -z "$name" ]; then
    local before
    before="$(list_outputs | jq '[.[].name]')"
    swaymsg create_output >/dev/null
    sleep 0.5
    name="$(list_outputs | jq -r --argjson before "$before" '
      [.[] | select(.name | startswith("HEADLESS-"))
        | select(.name as $n | ($before | index($n)) | not)] | .[0].name // empty')"
  fi
  [ -n "$name" ] || die "failed to create a headless output"

  # Note: `swaymsg --` — swaymsg's own getopt would otherwise eat `--custom`.
  swaymsg -- output "$name" enable mode --custom "${mode}@60Hz" scale 1 pos $PARK_X 0 >/dev/null
  echo "$name" > "$STATE_FILE"
  cat <<EOF
Cast output ready: $name ($mode, parked at +$PARK_X; invisible locally)
  1. Chrome -> menu -> Cast -> Sources -> Cast screen
  2. Pick "$name" in the screen-share menu, then your Chromecast receiver
  3. Move windows over with: cast-extend send
Stop with: cast-extend off
EOF
}

cmd_off() {
  local name
  name="$(live_recorded)"
  [ -n "$name" ] || die "no active cast output (nothing to stop)"
  swaymsg output "$name" disable >/dev/null
  rm -f "$STATE_FILE"
  echo "Cast output $name disabled; its workspaces moved back to real outputs."
}

cmd_send() {
  local name
  name="$(live_recorded)"
  [ -n "$name" ] || die "no active cast output — run: cast-extend on"
  swaymsg move workspace to output "$name" >/dev/null
  echo "Focused workspace moved to $name."
}

cmd_status() {
  local name
  name="$(live_recorded)"
  if [ -z "$name" ]; then
    echo "no cast output (start one with: cast-extend on)"
    return 0
  fi
  list_outputs | jq -r --arg name "$name" '
    .[] | select(.name == $name)
    | "\(.name): \(if .active then "enabled" else "disabled" end), \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh / 1000)Hz, pos \(.rect.x),\(.rect.y)"'
}

case "${1:-}" in
  on)     cmd_on "${2:-}" ;;
  off)    cmd_off ;;
  send)   cmd_send ;;
  status) cmd_status ;;
  *)
    sed -n '2,20p' "$0"
    exit 1
    ;;
esac
