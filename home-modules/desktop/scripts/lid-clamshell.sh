#!/usr/bin/env bash
# lid-clamshell - manage displays/power when the ThinkPad lid opens or closes.
#
# Clamshell policy (matches the user's intent):
#   close + plugged in + external connected -> external becomes the sole/primary
#                                              display (laptop panel disabled),
#                                              machine stays awake.
#   close + on battery + external connected -> suspend (only run on the external
#                                              when power is plugged in).
#   close + no external                     -> drop the now-hidden laptop panel;
#                                              logind's lid policy (suspend on
#                                              battery / lock on AC) governs.
#   open                                    -> restore the extended dual-monitor
#                                              layout, or laptop-only.
#
# Display changes go through the i3pm daemon (single owner) so the active profile
# stays consistent and the daemon never fights the change by re-applying a stale
# profile. logind keeps HandleLidSwitchDocked=ignore so it does not suspend out
# from under us while an external display is connected; this script owns the
# battery-vs-AC suspend decision instead.
set -euo pipefail

action="${1:-close}"

# True when any active output other than the built-in panel is present.
ext_present() {
  swaymsg -t get_outputs \
    | jq -e 'any(.[]; .name != "eDP-1" and .active and (.name | test("^(DP|HDMI)-")))' \
    >/dev/null 2>&1
}

# True when mains or USB-C PD power is supplying the machine (any non-battery
# power supply reporting online=1). A USB-C dock charges via a ucsi-source PSY,
# so checking only /sys/.../AC/online would miss dock power.
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

case "$action" in
  close)
    if ext_present; then
      if plugged_in; then
        i3pm display apply clamshell >/dev/null 2>&1
      else
        systemctl suspend
      fi
    else
      swaymsg 'output eDP-1 disable' >/dev/null 2>&1 || true
    fi
    ;;
  open)
    if ext_present; then
      i3pm display apply extended >/dev/null 2>&1
    else
      swaymsg 'output eDP-1 enable' >/dev/null 2>&1 || true
      i3pm display apply local-only >/dev/null 2>&1 || true
    fi
    ;;
  *)
    echo "usage: lid-clamshell {close|open}" >&2
    exit 1
    ;;
esac
