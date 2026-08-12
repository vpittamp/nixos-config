#!/usr/bin/env bash
# touch-gestures - edge swipes on the glass, for when there is no keyboard or
# trackpad in reach.
#
# sway's `bindgesture` is built on libinput's *pointer* gesture events, which
# only touchpads emit. A touchscreen produces touch events, so every gesture
# already configured in sway.nix is invisible to a finger on the screen — the
# existing "the on-screen Done pill covers the glass touchscreen, which sway
# bindgesture does not see" comment is that limitation. lisgd fills the gap by
# reading the touch device directly and synthesising swipes from it.
#
# One lisgd child is run per touchscreen, each told the geometry of the output
# that touch-map bound it to, so edge detection is correct on the built-in panel
# and on an external touchscreen at a different resolution. lisgd does not grab
# the device, so gestures are additive: normal tapping and dragging still reach
# applications.
#
# The device set changes when a USB touchscreen is plugged in and when iptsd
# restarts, so this re-derives everything on sway input/output events.
set -uo pipefail

LISGD="${LISGD_BIN:-lisgd}"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/touch-map.state"   # written by touch-map
declare -a CHILDREN=()

log() { printf 'touch-gestures: %s\n' "$*" >&2; }

stop_children() {
  for pid in ${CHILDREN+"${CHILDREN[@]}"}; do
    kill "$pid" 2>/dev/null
    # Reap it. Without the wait the killed lisgd stays a zombie, and this
    # rebinds on every touchscreen hot-plug and every scale change, so they
    # would accumulate for the life of the session.
    wait "$pid" 2>/dev/null
  done
  CHILDREN=()
}
trap 'stop_children; exit 0' TERM INT

# Resolve a sway input identifier to its /dev/input/eventN node. sway's
# identifier is vendor:product:name-with-underscores, which is not a device
# path, so go through the kernel's device list and match on the name.
event_node_for() {
  local sway_name="$1"
  awk -v want="$sway_name" '
    /^N: Name=/ {
      name = $0
      sub(/^N: Name="/, "", name); sub(/"$/, "", name)
      gsub(/ /, "_", name)
    }
    /^H: Handlers=/ && name == want {
      match($0, /event[0-9]+/)
      if (RSTART) { print substr($0, RSTART, RLENGTH); exit }
    }
  ' /proc/bus/input/devices
}

# lisgd converts normalised touch coordinates against the width/height it is
# given, so these only need to be proportional to the mapped output — but using
# that output's real mode keeps the edge bands the same physical size on every
# screen, which is the point of running one child per device.
spawn_for() {
  local ident="$1" out="$2" node w h
  node="$(event_node_for "${ident#*:*:}")"
  [ -z "$node" ] && { log "no event node for '$ident'; skipping"; return; }
  if [ ! -r "/dev/input/$node" ]; then
    log "/dev/input/$node not readable (need the 'input' group); skipping"
    return
  fi

  read -r w h < <(swaymsg -t get_outputs 2>/dev/null | jq -r --arg o "$out" '
    .[] | select(.name == $o)
    | "\(.current_mode.width // .rect.width) \(.current_mode.height // .rect.height)"')
  [ -z "${w:-}" ] && { log "no geometry for output $out; skipping '$ident'"; return; }

  log "binding gestures on $node ('$ident') sized to $out ${w}x${h}"

  # Edge swipes only. The middle of the screen belongs to applications, and a
  # non-edge gesture would fire while scrolling a page or dragging a window.
  #
  # These deliberately mirror the touchpad gestures already in sway.nix so the
  # muscle memory is the same whichever surface is under the hand:
  #   bottom -> up    on-screen keyboard        (4-finger swipe down on the pad)
  #   top    -> down  window switcher           (3-finger swipe up on the pad)
  #   left   -> right browser back              (3-finger swipe right)
  #   right  -> left  browser forward           (3-finger swipe left)
  # browser-nav is scoped to browser windows, so the horizontal pair is a no-op
  # in a terminal rather than a surprise.
  # The two-finger variant toggles touch sizing. It has to be a gesture rather
  # than a keybinding: the whole point is to be reachable when the machine is
  # being used as a tablet, with no keyboard and no trackpad in reach.
  "$LISGD" -d "/dev/input/$node" -w "$w" -h "$h" \
    -g "1,DU,B,*,R,$HOME/.local/bin/osk-toggle" \
    -g "1,UD,T,*,R,show-window-switcher-action toggle" \
    -g "1,LR,L,*,R,$HOME/.local/bin/browser-nav back" \
    -g "1,RL,R,*,R,$HOME/.local/bin/browser-nav forward" \
    -g "2,DU,B,*,R,$HOME/.local/bin/touch-mode toggle" \
    >/dev/null 2>&1 &
  CHILDREN+=($!)
}

# Bindings come from touch-map's published state rather than being re-derived
# here: it owns the device→output decision (including the user's rules file),
# and two independent derivations could disagree, which would show up as edge
# bands sized to the wrong screen. Devices it chose not to map — notably the raw
# Surface digitizer it disables — are simply absent, so they get no gestures.
start_all() {
  stop_children
  local ident out
  if [ ! -r "$STATE_FILE" ]; then
    log "no $STATE_FILE yet; touch-map has not run"
    return
  fi
  while IFS=$'\t' read -r ident out dtype; do
    [ -z "$ident" ] && continue
    # Fingers only. A stylus is mapped to an output by touch-map for the same
    # accuracy reasons, but an edge swipe with the pen is drawing, not a gesture.
    [ "$dtype" = "touch" ] || continue
    spawn_for "$ident" "$out"
  done < "$STATE_FILE"
  [ "${#CHILDREN[@]}" -eq 0 ] && log "no touchscreen to bind gestures on"
}

# Rebind when the mapping itself changes — that covers a touchscreen appearing
# or disappearing *and* a device being moved to another output, both of which
# change the edge geometry.
signature() {
  cat "$STATE_FILE" 2>/dev/null | sort | md5sum
}

sleep 4        # let touch-map publish its first state file
last="$(signature)"
start_all

# Process substitution, not a pipe: a piped `while` runs in a subshell, so the
# CHILDREN array it updated would be discarded each iteration and the previous
# lisgd processes would leak on every rebind.
while read -r _; do
  sleep 1                        # let touch-map settle before reading its result
  cur="$(signature)"
  if [ "$cur" != "$last" ]; then
    last="$cur"
    log "touch mapping changed; rebinding gestures"
    start_all
  fi
done < <(swaymsg -t subscribe -m '["input","output"]' 2>/dev/null)
