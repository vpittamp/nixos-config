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
#   cast-extend off        remove it (its workspaces move back automatically)
#   cast-extend send       move the focused workspace to the cast output
#   cast-extend status     print the cast output's current state
#
# The stream itself is driven by `cast` (desktop/casting.nix), which automates
# Chrome's Cast screen over CDP: `cast extend` runs this script, then starts
# the mirror with the output pinned to the headless one (cast-portal-chooser,
# no portal menu). Manual path: Chrome -> menu -> Cast -> Sources -> Cast
# screen.
#
# Notes:
# - `off` destroys the output with `output <name> unplug` (sway 1.12), falling
#   back to `disable` on a sway that lacks it. It used to only ever disable,
#   which left the object behind to be re-enabled and drift into the layout.
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
  1. Run: cast extend   (starts the Chrome cast session for you; the output
     and a lone receiver are picked automatically)
  2. Move windows over with: cast-extend send
Stop with: cast stop
EOF
}

# Outputs `off` may disable: the recorded one if it is still live, otherwise
# every active HEADLESS-*.
#
# The state file is a hint, not the truth. It lives in $XDG_RUNTIME_DIR and is
# lost to a runtime-dir clean or an `on` that died before writing it, and the
# old code answered a missing file by refusing to do anything at all. That
# stranded the cast output ENABLED: nothing re-parks it at +$PARK_X once
# cast-extend has stopped tracking it, so it drifted into the layout beside the
# real monitors as a fourth screen, complete with its own bars and a workspace.
# `cast stop` discards this script's exit status, so the failure was silent.
# Sway's output list is the only thing that knows what is actually live.
reclaimable() {
  local name
  name="$(live_recorded)"
  if [ -n "$name" ]; then
    printf '%s\n' "$name"
    return 0
  fi
  # Only ever reclaim a headless output while a real one is also active — on a
  # headless host the desktop itself lives on one of these, and disabling the
  # last output would take the session down with it.
  list_outputs | jq -r '
    [.[] | select(.active == true)] as $active
    | if ($active | map(select(.name | startswith("HEADLESS-") | not)) | length) > 0
      then $active[] | select(.name | startswith("HEADLESS-")) | .name
      else empty
      end'
}

cmd_off() {
  local names name disabled=0

  names="$(reclaimable)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # Destroy it outright where sway can (1.12+). Merely disabling leaves the
    # output object in the layout to be re-enabled later — which is how one
    # came back as an unparked fourth screen. `disable` stays as the fallback
    # for a sway without `unplug`; its workspaces move back either way.
    if swaymsg output "$name" unplug >/dev/null 2>&1; then
      echo "Cast output $name removed; its workspaces moved back to real outputs."
    else
      swaymsg output "$name" disable >/dev/null
      echo "Cast output $name disabled; its workspaces moved back to real outputs."
    fi
    disabled=$((disabled + 1))
  done <<EOF
$names
EOF

  rm -f "$STATE_FILE"
  # Idempotent on purpose: `cast stop` calls this on every stop, including the
  # mirror-mode ones that never made an output.
  [ "$disabled" -gt 0 ] || echo "No cast output to disable."
}

cmd_send() {
  local name
  name="$(live_recorded)"
  [ -n "$name" ] || die "no active cast output — run: cast-extend on"
  swaymsg move workspace to output "$name" >/dev/null
  echo "Focused workspace moved to $name."
}

cmd_status() {
  local report
  # Report every HEADLESS-*, not just the recorded one — an output that outlived
  # its state file is exactly the case worth seeing, and the old version
  # answered it with "no cast output" while one sat enabled in the layout.
  report="$(list_outputs | jq -r --arg recorded "$(recorded)" --argjson park "$PARK_X" '
    .[] | select(.name | startswith("HEADLESS-"))
    | "\(.name): \(if .active then "enabled" else "disabled" end)"
      + ", \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh / 1000)Hz"
      + ", pos \(.rect.x),\(.rect.y)"
      + (if .name == $recorded then "" else "  [untracked]" end)
      + (if .active and .rect.x != $park then "  [not parked — stop it with: cast stop]" else "" end)')"

  if [ -z "$report" ]; then
    echo "no cast output (start one with: cast-extend on)"
    return 0
  fi
  printf '%s\n' "$report"
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
