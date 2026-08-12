#!/usr/bin/env bash
# touch-mode - make the screens you actually touch physically bigger.
#
# The controls in this desktop are sized for a pointer: the Quickshell bars are
# 30 and 38 logical pixels, and buttons inside the settings and popup surfaces
# are as small as 22. At the Surface panel's 1.5 scale that last one is about
# 4mm of glass — roughly half the ~9mm that Apple and Google both recommend as a
# minimum touch target. A fingertip misses it more often than it hits it.
#
# Raising the output scale is the one lever that fixes this everywhere at once:
# every logical pixel becomes physically larger, so bars, buttons, popups, and
# ordinary application UI all grow together, with no per-widget changes and
# nothing to keep in sync. It is also instant and reversible, which a Nix option
# is not.
#
# Only outputs with a touchscreen bound to them are scaled — that binding is
# read from touch-map's published state, so an external touchscreen gets touch
# sizing while a plain monitor beside it keeps its normal density.
#
# Usage: touch-mode {on|off|toggle|status} [scale]
set -uo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/touch-map.state"   # written by touch-map
SAVED="${XDG_RUNTIME_DIR:-/tmp}/touch-mode.saved"       # pre-touch-mode scales

# Touch mode enlarges each screen *relative to how it was already configured*,
# rather than driving everything to one absolute scale. A fixed target cannot be
# right for both: the Surface panel sits at 1.5, so 2.0 is a mild 1.33x bump,
# while the Verbatim sits at 1.25, where the same 2.0 is a 1.6x jump that
# overshoots badly. The multiplier keeps the step proportional on any display.
#
# Snapped to quarter steps because arbitrary fractional scales make Qt and XWayland
# clients resample text; the quarter steps are the ones compositors handle cleanly.
TOUCH_SCALE_FACTOR="${TOUCH_MODE_FACTOR:-1.25}"
TOUCH_SCALE_MAX=3.0

log() { printf 'touch-mode: %s\n' "$*" >&2; }

# Outputs that have at least one touchscreen (not a stylus) bound to them.
touched_outputs() {
  [ -r "$STATE_FILE" ] || return 0
  awk -F'\t' '$3 == "touch" { print $2 }' "$STATE_FILE" | sort -u
}

current_scale_of() {
  swaymsg -t get_outputs 2>/dev/null \
    | jq -r --arg o "$1" '.[] | select(.name == $o) | .scale'
}

is_on() { [ -s "$SAVED" ]; }

# Scale this output should take in touch mode: an explicit absolute value if the
# caller gave one, otherwise the current scale stepped up by the factor and
# snapped to the nearest quarter (never below where it already was).
touch_scale_for() {
  local cur="$1" explicit="${2:-}"
  if [ -n "$explicit" ]; then
    printf '%s' "$explicit"
    return
  fi
  awk -v cur="$cur" -v f="$TOUCH_SCALE_FACTOR" -v max="$TOUCH_SCALE_MAX" 'BEGIN {
    s = cur * f
    s = int(s * 4 + 0.5) / 4          # snap to 0.25 steps
    if (s > max) s = max
    if (s < cur) s = cur
    printf "%.2f", s
  }'
}

mode_on() {
  local want="${1:-}" outs any=0
  outs="$(touched_outputs)"
  [ -z "$outs" ] && { log "no touchscreen bound to any output; nothing to scale"; return 1; }

  if is_on; then
    log "already on; turn it off first to change scale"
    return 1
  fi

  : > "$SAVED"
  while read -r out; do
    [ -z "$out" ] && continue
    local cur; cur="$(current_scale_of "$out")"
    [ -z "$cur" ] || [ "$cur" = "null" ] && { log "skipping $out (no live scale)"; continue; }
    local target; target="$(touch_scale_for "$cur" "$want")"
    if [ "$target" = "$cur" ]; then
      log "$out: already at $cur; nothing to enlarge"
      continue
    fi
    # Remember the exact scale we are replacing, so "off" restores the user's
    # own value rather than a guess at what the default was.
    printf '%s\t%s\n' "$out" "$cur" >> "$SAVED"
    swaymsg output "$out" scale "$target" >/dev/null 2>&1 \
      && { log "$out: $cur -> $target"; any=1; } \
      || log "$out: failed to set scale"
  done <<<"$outs"

  [ "$any" -eq 0 ] && { rm -f "$SAVED"; return 1; }
  return 0
}

mode_off() {
  if ! is_on; then
    log "not currently on"
    return 1
  fi
  while IFS=$'\t' read -r out prev; do
    [ -z "$out" ] && continue
    swaymsg output "$out" scale "$prev" >/dev/null 2>&1 \
      && log "$out: restored to $prev" \
      || log "$out: failed to restore scale"
  done < "$SAVED"
  rm -f "$SAVED"
}

case "${1:-toggle}" in
  on)     mode_on "${2:-}" ;;
  off)    mode_off ;;
  toggle) if is_on; then mode_off; else mode_on "${2:-}"; fi ;;
  status)
    if is_on; then
      echo "touch-mode: ON"
      while IFS=$'\t' read -r out prev; do
        printf '  %s now %s (was %s)\n' "$out" "$(current_scale_of "$out")" "$prev"
      done < "$SAVED"
    else
      echo "touch-mode: off"
      while read -r out; do
        [ -n "$out" ] && printf '  %s scale %s (touchscreen bound)\n' "$out" "$(current_scale_of "$out")"
      done <<<"$(touched_outputs)"
    fi
    ;;
  *)
    echo "usage: touch-mode {on|off|toggle|status} [scale]" >&2
    exit 2
    ;;
esac
