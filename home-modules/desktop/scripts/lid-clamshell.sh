#!/usr/bin/env bash
# lid-clamshell - manage displays/power when the ThinkPad lid opens or closes.
#
# Connector-agnostic: it operates on "the built-in panel" (eDP-1, a stable name)
# vs "every connected external" (whatever the dock/port assigns — DP-5, DP-6,
# DP-7, HDMI-A-1, ...). It does NOT rely on a fixed monitor profile, because the
# external's connector name changes across docks/ports.
#
# Recognized externals are placed by EDID (make/model), not connector name:
#   Verbatim portable monitor -> top-left origin.
#   Samsung 55" 4K TV         -> right of the Verbatim, top-aligned; its taller
#                                panel extends downward so the built-in panel can
#                                tuck in below it when the lid is open.
# Unrecognized externals tile left-to-right after the recognized ones.
#
# Policy:
#   close + plugged in + external -> clamshell: disable the panel, lay out the
#                                     externals (Verbatim + Samsung stay on).
#   close + on battery + external -> suspend (only run on the external on AC).
#   close + no external           -> drop the now-hidden panel; logind governs.
#   open  + external              -> extended: lay out externals, panel below the
#                                     Samsung (else to the right of the externals).
#   open  + no external           -> just the panel.
#
# logind keeps HandleLidSwitchDocked=ignore so it won't suspend while an external
# is connected; this script owns the battery-vs-AC suspend decision.
set -euo pipefail

action="${1:-close}"
PANEL="eDP-1"

# Per-output enable/disable preferences, written by the Quickshell displays
# dialog via `i3pm display toggle-output`. An external marked disabled here is
# turned off and excluded from the layout — even with the lid closed — so you
# can choose which externals are live in clamshell from the UI.
STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sway/output-states.json"

# Scale applied to unrecognized externals (fallback path).
EXTERNAL_SCALE="1.25"

# Built-in panel scale (eDP-1, native 1920x1200 -> logical 1536x960).
PANEL_SCALE="1.25"

# In extended mode the Verbatim sits parallel to (left of) the built-in panel
# but a little higher: its top edge is raised this many logical px above the
# panel's top edge.
VERBATIM_RAISE="120"

# Verbatim portable monitor: native mode, comfortable scale.
VERBATIM_SCALE="1.25"

# Samsung 55" 4K TV. The link only negotiates 4K at 30Hz; scale 2.5 gives a
# heavily zoomed-in 1536x864 effective desktop (large UI for the big panel).
SAMSUNG_MODE="3840x2160@30Hz"
SAMSUNG_W="3840"
SAMSUNG_H="2160"
SAMSUNG_SCALE="2.5"

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

# "<make> <model>" for an output — used to recognize specific monitors by EDID.
output_edid() {
  swaymsg -t get_outputs 2>/dev/null | jq -r --arg o "$1" '
    .[] | select(.name == $o) | "\(.make) \(.model)"'
}
is_verbatim() { output_edid "$1" | grep -qiE 'verbatim|MT17'; }
is_samsung()  { output_edid "$1" | grep -qi  'samsung'; }

# False (returns 1) only when output-states.json explicitly disables this output;
# unknown or missing outputs default to enabled.
output_enabled() {
  [ -r "$STATE_FILE" ] || return 0
  local v
  # NB: don't use jq's `//` here — it treats `false` as absent, so
  # `.enabled // empty` would swallow an explicit disable. Read the raw value
  # ("true"/"false"/"null") and only treat an explicit "false" as disabled.
  v="$(jq -r --arg o "$1" '.outputs[$o].enabled' "$STATE_FILE" 2>/dev/null)"
  [ "$v" = "false" ] && return 1
  return 0
}

# Integer division (value / scale), used for logical width and height.
logical_width() { awk "BEGIN { printf \"%d\", $1 / $2 }"; }

# Echo "<logical_w> <logical_h>" for an output at a given scale (current/native
# mode divided by scale). Returns non-zero if the output has no usable mode.
logical_dims() {
  local w h
  read -r w h <<<"$(output_mode "$1")"
  [ -n "${w:-}" ] && [ "$w" != "null" ] || return 1
  echo "$(logical_width "$w" "$2") $(logical_width "$h" "$2")"
}

# Lay out every connected external, recognizing the Verbatim and Samsung by EDID:
#   Verbatim -> top-left origin.
#   Samsung  -> right of the Verbatim, top-aligned.
#   others   -> tiled left-to-right after the recognized monitors.
# Echoes "<panel_x> <panel_y>": where the built-in panel goes in extended mode
# (below the Samsung when present, else to the right of the externals, at y=0).
place_externals() {
  local out verb="" sam="" others=() w h
  while read -r out; do
    [ -n "$out" ] || continue
    # Honor the UI enable/disable preference: a disabled external is turned off
    # and dropped from the layout (so the others retile to fill the gap).
    if ! output_enabled "$out"; then
      swaymsg "output $out disable" >/dev/null 2>&1 || true
      continue
    fi
    if   is_verbatim "$out"; then verb="$out"
    elif is_samsung  "$out"; then sam="$out"
    else others+=("$out"); fi
  done < <(external_outputs)

  local edge=0 panel_x=0 panel_y=0 sam_x=0

  # Verbatim at the origin.
  if [ -n "$verb" ]; then
    read -r w h <<<"$(output_mode "$verb")"
    if [ -n "${w:-}" ] && [ "$w" != "null" ]; then
      swaymsg "output $verb enable mode ${w}x${h} position 0 0 scale $VERBATIM_SCALE" >/dev/null 2>&1 || true
      edge="$(logical_width "$w" "$VERBATIM_SCALE")"
    fi
  fi

  # Samsung 4K TV: forced mode + scale, placed to the right of the Verbatim.
  if [ -n "$sam" ]; then
    sam_x="$edge"
    swaymsg "output $sam enable mode $SAMSUNG_MODE position $sam_x 0 scale $SAMSUNG_SCALE" >/dev/null 2>&1 || true
    edge=$(( sam_x + $(logical_width "$SAMSUNG_W" "$SAMSUNG_SCALE") ))
    # Panel tucks in below the Samsung when the lid is open.
    panel_x="$sam_x"
    panel_y="$(logical_width "$SAMSUNG_H" "$SAMSUNG_SCALE")"
  else
    panel_x="$edge"
    panel_y=0
  fi

  # Any unrecognized externals tile to the far right at the top.
  for out in "${others[@]:-}"; do
    [ -n "$out" ] || continue
    read -r w h <<<"$(output_mode "$out")"
    [ -n "${w:-}" ] && [ "$w" != "null" ] || continue
    swaymsg "output $out enable mode ${w}x${h} position $edge 0 scale $EXTERNAL_SCALE" >/dev/null 2>&1 || true
    edge=$(( edge + $(logical_width "$w" "$EXTERNAL_SCALE") ))
    # With no Samsung anchor, keep the panel to the right of these too.
    [ -n "$sam" ] || panel_x="$edge"
  done

  echo "$panel_x $panel_y"
}

layout_clamshell() {
  # Externals own the screen; panel off so workspaces migrate onto an external.
  place_externals >/dev/null
  swaymsg "output $PANEL disable" >/dev/null 2>&1 || true
}

layout_extended() {
  # Built-in panel is the anchor (lid open). Recognized externals are placed
  # relative to it by EDID:
  #   Samsung  -> directly above the panel (same x, top-aligned column).
  #   Verbatim -> parallel to the panel on its left, raised VERBATIM_RAISE px.
  #   others   -> tiled left-to-right to the right of the panel, panel-top aligned.
  # Connector-agnostic: identity is by EDID, never by DP-x connector name.
  local out verb="" sam="" others=()
  while read -r out; do
    [ -n "$out" ] || continue
    # Honor the UI enable/disable preference.
    if ! output_enabled "$out"; then
      swaymsg "output $out disable" >/dev/null 2>&1 || true
      continue
    fi
    if   is_verbatim "$out"; then verb="$out"
    elif is_samsung  "$out"; then sam="$out"
    else others+=("$out"); fi
  done < <(external_outputs)

  # Logical sizes (used to compute origins so nothing lands at negative coords).
  local pw ph; read -r pw ph <<<"$(logical_dims "$PANEL" "$PANEL_SCALE")" || { pw=1536; ph=960; }
  local vw=0; [ -n "$verb" ] && vw="$(logical_dims "$verb" "$VERBATIM_SCALE" | cut -d' ' -f1)"
  local sh=0; [ -n "$sam" ] && sh="$(logical_width "$SAMSUNG_H" "$SAMSUNG_SCALE")"

  # Panel origin: reserve room above it (Samsung column and/or the Verbatim
  # raise) and to its left (the Verbatim).
  local top_gap=0
  [ -n "$sam" ] && top_gap="$sh"
  [ -n "$verb" ] && [ "$VERBATIM_RAISE" -gt "$top_gap" ] && top_gap="$VERBATIM_RAISE"
  local panel_x=0; [ -n "$verb" ] && panel_x="$vw"
  local panel_y="$top_gap"

  swaymsg "output $PANEL enable mode 1920x1200 position $panel_x $panel_y scale $PANEL_SCALE" >/dev/null 2>&1 || true

  # Samsung directly above the panel.
  if [ -n "$sam" ]; then
    swaymsg "output $sam enable mode $SAMSUNG_MODE position $panel_x $(( panel_y - sh )) scale $SAMSUNG_SCALE" >/dev/null 2>&1 || true
  fi

  # Verbatim parallel to the panel on its left, sitting VERBATIM_RAISE px higher.
  if [ -n "$verb" ]; then
    local vnw vnh; read -r vnw vnh <<<"$(output_mode "$verb")"
    if [ -n "${vnw:-}" ] && [ "$vnw" != "null" ]; then
      swaymsg "output $verb enable mode ${vnw}x${vnh} position $(( panel_x - vw )) $(( panel_y - VERBATIM_RAISE )) scale $VERBATIM_SCALE" >/dev/null 2>&1 || true
    fi
  fi

  # Any other externals tile to the right of the panel, aligned with its top.
  local edge=$(( panel_x + pw )) ow oh
  for out in "${others[@]:-}"; do
    [ -n "$out" ] || continue
    read -r ow oh <<<"$(output_mode "$out")"
    [ -n "${ow:-}" ] && [ "$ow" != "null" ] || continue
    swaymsg "output $out enable mode ${ow}x${oh} position $edge $panel_y scale $EXTERNAL_SCALE" >/dev/null 2>&1 || true
    edge=$(( edge + $(logical_width "$ow" "$EXTERNAL_SCALE") ))
  done
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

run_auto() {
  # Re-apply the correct layout for the current lid state. Used by sway's
  # exec_always (every reload re-runs the static output config, which would
  # otherwise stack all outputs at 0,0 = mirrored) and by the hot-plug watcher.
  if grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null; then
    run_close
  else
    run_open
  fi
}

# Apply a named display preset: set each connected output's enabled flag in
# output-states.json by EDID role (connector names are unstable, so presets are
# expressed in roles, not DP-x names), then re-apply the layout. The built-in
# panel always stays enabled here — the lid governs whether it is actually on.
#   all      -> Verbatim + Samsung on
#   verbatim -> Verbatim on, Samsung off
#   samsung  -> Samsung on, Verbatim off
#   laptop   -> both externals off (built-in panel only)
apply_preset() {
  local preset="${1:-}" want_verb want_sam
  case "$preset" in
    all)      want_verb=true;  want_sam=true ;;
    verbatim) want_verb=true;  want_sam=false ;;
    samsung)  want_verb=false; want_sam=true ;;
    laptop)   want_verb=false; want_sam=false ;;
    *) echo "unknown preset: '$preset' (want all|verbatim|samsung|laptop)" >&2; return 1 ;;
  esac

  local pairs out enabled
  pairs="$PANEL true"$'\n'
  while read -r out; do
    [ -n "$out" ] || continue
    if   is_verbatim "$out"; then enabled="$want_verb"
    elif is_samsung  "$out"; then enabled="$want_sam"
    else enabled="true"; fi   # leave unrecognized externals on
    pairs+="$out $enabled"$'\n'
  done < <(external_outputs)

  local existing='{}'
  [ -r "$STATE_FILE" ] && existing="$(cat "$STATE_FILE" 2>/dev/null || echo '{}')"
  mkdir -p "$(dirname "$STATE_FILE")"
  if printf '%s' "$pairs" | jq -R -s --argjson existing "$existing" '
        (split("\n") | map(select(length > 0))) as $lines
        | reduce $lines[] as $line
            ( ($existing.outputs // {});
              ($line | split(" ")) as $kv
              | .[$kv[0]] = { enabled: ($kv[1] == "true") } )
        | { version: "1.0", outputs: . }
      ' > "$STATE_FILE.tmp" 2>/dev/null; then
    mv "$STATE_FILE.tmp" "$STATE_FILE"
  else
    rm -f "$STATE_FILE.tmp"
    echo "failed to write $STATE_FILE" >&2
    return 1
  fi

  run_auto
}

case "$action" in
  close)  run_close ;;
  open)   run_open ;;
  auto)   run_auto ;;
  preset) apply_preset "${2:-}" ;;
  *)
    echo "usage: lid-clamshell {close|open|auto|preset <all|verbatim|samsung|laptop>}" >&2
    exit 1
    ;;
esac
