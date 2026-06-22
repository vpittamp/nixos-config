#!/usr/bin/env bash
# monitor-layout-watch - re-apply the connector-agnostic display layout whenever
# the set of connected monitors changes (hot-plug / unplug).
#
# Why: sway has no "on output change" config hook, and the lid bindswitch only
# fires on lid open/close. So a monitor plugged in mid-session (lid unchanged)
# is just auto-enabled by sway at position 0,0 — stacked on the laptop panel,
# which looks like a *mirrored* display. This watches sway's output events and,
# when the set of active monitors actually changes, re-runs the lid-clamshell
# handler for the current lid state (which tiles externals left-to-right).
#
# It keys off the *set of active output names*, not every output property, so
# the re-layout it performs (which itself emits output events) does not loop.
set -uo pipefail

LID_GLOB='/proc/acpi/button/lid/*/state'

current_set() {
  swaymsg -t get_outputs 2>/dev/null \
    | jq -r '[.[] | select(.active) | .name] | sort | join(",")'
}

apply_layout() {
  if grep -qi closed $LID_GLOB 2>/dev/null; then
    "$HOME/.local/bin/lid-clamshell" close
  else
    "$HOME/.local/bin/lid-clamshell" open
  fi
}

# Settle, record the initial monitor set, and lay it out once (covers login).
sleep 1
last="$(current_set)"
apply_layout

# React to subsequent monitor connect/disconnect events.
swaymsg -t subscribe -m '["output"]' 2>/dev/null | while read -r _; do
  sleep 0.4                      # let the new output settle / debounce bursts
  cur="$(current_set)"
  if [ "$cur" != "$last" ]; then
    last="$cur"
    apply_layout
  fi
done
