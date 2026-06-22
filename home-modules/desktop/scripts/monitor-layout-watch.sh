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

# True when two active outputs' horizontal ranges overlap — i.e. the displays
# are mirrored/stacked instead of tiled side-by-side. This is the signature of
# the "reverted to duplicate" state: a sway reload (or anything that re-runs the
# static output config) drops every output to position 0,0. Edges that merely
# touch (extended layout) do NOT count as overlap.
mirrored() {
  swaymsg -t get_outputs 2>/dev/null | jq -e '
    [ .[] | select(.active) | {a: .rect.x, b: (.rect.x + .rect.width)} ]
    | sort_by(.a) as $r
    | [ range(0; ($r | length) - 1) as $i | ($r[$i].b > $r[$i+1].a) ]
    | any
  ' >/dev/null 2>&1
}

apply_layout() {
  "$HOME/.local/bin/lid-clamshell" auto
}

# Settle, record the initial monitor set, and lay it out once (covers login).
sleep 1
last="$(current_set)"
apply_layout

# React to subsequent output events: a changed monitor set (hot-plug/unplug) OR
# a mirrored/overlapping layout (e.g. a sway reload reset every output to 0,0).
# Re-applying changes positions, which emits more output events — but by then the
# set is stable and the layout is no longer mirrored, so it converges (no loop).
swaymsg -t subscribe -m '["output"]' 2>/dev/null | while read -r _; do
  sleep 0.4                      # let outputs settle / debounce bursts
  cur="$(current_set)"
  if [ "$cur" != "$last" ] || mirrored; then
    last="$cur"
    apply_layout
  fi
done
