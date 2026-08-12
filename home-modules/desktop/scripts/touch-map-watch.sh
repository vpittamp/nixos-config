#!/usr/bin/env bash
# touch-map-watch - keep touchscreen→output bindings correct as hardware comes
# and goes.
#
# Two things invalidate a touch mapping, and sway hooks neither: plugging a
# monitor in (the digitizer's target output appears or disappears) and plugging
# a USB touchscreen in (a new absolute device shows up with no binding at all).
# So subscribe to both event streams and re-run touch-map.
#
# The re-map itself changes input configuration, which makes sway emit further
# input events. To avoid chasing its own tail this keys off a *signature* — the
# set of active output names plus the set of absolute input device IDs — and
# only re-applies when that signature actually changes. Applying a mapping does
# not change the signature, so the loop converges immediately.
set -uo pipefail

MAPPER="$HOME/.local/bin/touch-map"

signature() {
  {
    swaymsg -t get_outputs 2>/dev/null \
      | jq -r '[.[] | select(.active) | .name] | sort | join(",")'
    swaymsg -t get_inputs 2>/dev/null \
      | jq -r '[.[] | select(.type == "touch" or .type == "tablet_tool") | .identifier] | sort | join(",")'
  } | paste -sd'|' -
}

# Settle first: at login the outputs and the iptsd virtual devices are still
# appearing, and mapping against a half-built device list would bind the pen but
# miss the touchscreen. monitor-layout-watch also lays out displays around now,
# and its result is this script's input, so let it land first.
sleep 2
last="$(signature)"
"$MAPPER"

# A single stream carrying both event types: sway delivers them interleaved and
# we only care that *something* changed, not which.
swaymsg -t subscribe -m '["output","input"]' 2>/dev/null | while read -r _; do
  sleep 0.4                      # debounce hot-plug bursts
  cur="$(signature)"
  if [ "$cur" != "$last" ]; then
    last="$cur"
    "$MAPPER"
  fi
done
