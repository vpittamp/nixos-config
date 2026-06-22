#!/usr/bin/env bash
# lid-clamshell - manage displays/power when the ThinkPad lid opens or closes.
#
# Connector-agnostic: it operates on "the built-in panel" (eDP-1, a stable name)
# vs "every connected external" (whatever the dock/port assigns — DP-5, DP-6,
# DP-7, HDMI-A-1, ...). It does NOT rely on a fixed monitor profile, because the
# external's connector name changes across docks/ports.
#
# Policy:
#   close + plugged in + external -> clamshell: disable the panel, tile all
#                                     externals left-to-right (stays awake).
#   close + on battery + external -> suspend (only run on the external on AC).
#   close + no external           -> drop the now-hidden panel; logind governs.
#   open  + external              -> extended: tile externals, panel to the right.
#   open  + no external           -> just the panel.
#
# logind keeps HandleLidSwitchDocked=ignore so it won't suspend while an external
# is connected; this script owns the battery-vs-AC suspend decision.
set -euo pipefail

action="${1:-close}"
EXTERNAL_SCALE="1.25"
PANEL="eDP-1"

# Names of currently-connected external physical outputs (not the built-in
# panel, not a virtual VNC HEADLESS output).
external_outputs() {
  swaymsg -t get_outputs 2>/dev/null | jq -r --arg panel "$PANEL" '
    .[] | select(.name != $panel
                 and (.name | test("^HEADLESS") | not)
                 and (.name | test("^(DP|HDMI|DVI|VGA)"))) | .name'
}

# True when mains or USB-C PD power is supplying the machine (any non-battery
# power supply reporting online=1; a USB-C dock charges via a ucsi-source PSY).
plugged_in() {
  local online type dir
  for online in /sys/class/power_supply/*/online; do
    [ -r "$online" ] || continue
    dir="${online%/online}"
    type="$(cat "$dir/type" 2>/dev/null || true)"
    [ "$type" = "Battery" ] && continue
    [ "$(cat "$online" 2>/dev/null || echo 0)" = "1" ] && return 0
  done
  return 1
}

# Echo "<native_width> <native_height>" for an output (current mode, else largest).
output_mode() {
  swaymsg -t get_outputs 2>/dev/null | jq -r --arg o "$1" '
    .[] | select(.name == $o)
        | (.current_mode // (.modes | max_by(.width * .height)))
        | "\(.width) \(.height)"'
}

logical_width() { awk "BEGIN { printf \"%d\", $1 / $2 }"; }

# Enable + tile every connected external left-to-right at EXTERNAL_SCALE.
# Echoes the next free x coordinate (right edge of the last external).
tile_externals() {
  local x=0 out w h lw
  while read -r out; do
    [ -n "$out" ] || continue
    read -r w h <<<"$(output_mode "$out")"
    [ -n "${w:-}" ] && [ "$w" != "null" ] || continue
    swaymsg "output $out enable mode ${w}x${h} position $x 0 scale $EXTERNAL_SCALE" >/dev/null 2>&1 || true
    lw="$(logical_width "$w" "$EXTERNAL_SCALE")"
    x=$((x + lw))
  done < <(external_outputs)
  echo "$x"
}

layout_clamshell() {
  # Externals own the screen; panel off so workspaces migrate onto an external.
  tile_externals >/dev/null
  swaymsg "output $PANEL disable" >/dev/null 2>&1 || true
}

layout_extended() {
  # Externals left-to-right, then the panel to their right.
  local x
  x="$(tile_externals)"
  swaymsg "output $PANEL enable mode 1920x1200 position $x 0 scale 1.25" >/dev/null 2>&1 || true
}

run_close() {
  if [ -n "$(external_outputs)" ]; then
    if plugged_in; then
      layout_clamshell
    else
      systemctl suspend
    fi
  else
    swaymsg "output $PANEL disable" >/dev/null 2>&1 || true
  fi
}

run_open() {
  if [ -n "$(external_outputs)" ]; then
    layout_extended
  else
    swaymsg "output $PANEL enable position 0 0 scale 1.25" >/dev/null 2>&1 || true
  fi
}

case "$action" in
  close) run_close ;;
  open)  run_open ;;
  auto)
    # Re-apply the correct layout for the current lid state. Used by sway's
    # exec_always (every reload re-runs the static output config, which would
    # otherwise stack all outputs at 0,0 = mirrored) and by the hot-plug watcher.
    if grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null; then
      run_close
    else
      run_open
    fi
    ;;
  *)
    echo "usage: lid-clamshell {close|open|auto}" >&2
    exit 1
    ;;
esac
