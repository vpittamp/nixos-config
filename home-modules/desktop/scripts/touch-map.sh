#!/usr/bin/env bash
# touch-map - bind every touchscreen / stylus to the output it physically is.
#
# Why this exists: sway maps an absolute pointing device (touchscreen, pen) to
# the *entire output layout* unless told otherwise. With only the built-in panel
# that happens to look correct. The moment a second monitor is attached, the
# laptop's 2256px-wide glass is stretched across the full multi-monitor desktop:
# touching the right edge of the built-in screen lands the cursor somewhere on
# the external monitor. The same is true in reverse for an external USB
# touchscreen (e.g. the Verbatim panel) — its digitizer would drive the whole
# desktop instead of its own glass. `map_to_output` is the fix, but it must be
# re-applied on every hot-plug because the output may not exist at login.
#
# Sway has no "on output change" hook, so touch-map-watch drives this script off
# the IPC event stream. Everything here is idempotent: it computes the desired
# device→output binding from scratch each run and applies it, so it converges no
# matter what order the events arrive in.
#
# Usage: touch-map [--dry-run]   (prints the plan without applying it)
set -uo pipefail

RULES_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sway/touch-mapping.json"
# Where the resolved device→output bindings are published. sway's get_inputs
# does not report which output a device is mapped to, so anything that needs to
# know (touch-gestures, sizing its edge bands to the right screen) would
# otherwise have to re-derive it and could disagree with what was actually
# applied. Runtime dir, because it describes the live session, not config.
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/touch-map.state"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log() { printf 'touch-map: %s\n' "$*" >&2; }

# An output is "internal" if it's the panel physically attached to the machine.
# Connector name is the reliable signal: eDP/LVDS/DSI are laptop panels, and
# everything else (HDMI/DP/USB-C DisplayLink) is external. Matching on the
# connector rather than a hardcoded "eDP-1" keeps this correct on hosts where
# the panel enumerates differently.
is_internal_output() {
  case "$1" in
    eDP-*|LVDS-*|DSI-*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- gather current state ---------------------------------------------------

outputs_json="$(swaymsg -t get_outputs 2>/dev/null)" || { log "sway not reachable"; exit 1; }
inputs_json="$(swaymsg -t get_inputs 2>/dev/null)" || { log "sway not reachable"; exit 1; }

# Only *active* outputs can be mapped to. A disabled output (lid closed, or
# switched off in the displays dialog) still appears in get_outputs, and mapping
# to it would send touches into a void.
mapfile -t active_outputs < <(jq -r '.[] | select(.active) | .name' <<<"$outputs_json")
[ "${#active_outputs[@]}" -eq 0 ] && { log "no active outputs; nothing to map"; exit 0; }

internal_output=""
external_outputs=()
for o in "${active_outputs[@]}"; do
  if is_internal_output "$o"; then
    [ -z "$internal_output" ] && internal_output="$o"
  else
    external_outputs+=("$o")
  fi
done

# Absolute pointing devices: touchscreens and pens. Both need mapping — a pen
# that isn't mapped drifts exactly like an unmapped finger.
mapfile -t touch_ids < <(
  jq -r '.[] | select(.type == "touch" or .type == "tablet_tool") | .identifier' <<<"$inputs_json" | sort -u
)

# Device type travels with the binding: consumers need to tell a finger from a
# pen (edge gestures belong on a touchscreen, not on a stylus).
type_of() {
  jq -r --arg id "$1" 'first(.[] | select(.identifier == $id) | .type) // "unknown"' <<<"$inputs_json"
}
[ "${#touch_ids[@]}" -eq 0 ] && { log "no touch or stylus devices present"; exit 0; }

# --- suppress the raw digitizer when iptsd is providing a virtual twin -------
#
# On Surface hardware the kernel exposes the raw IPTS digitizer *and* iptsd
# publishes calibrated "IPTSD Virtual ..." uinput devices built from the same
# hardware. libinput binds both, so a single finger is reported twice: once by
# the raw node (which advertises no INPUT_PROP_DIRECT and behaves pointer-like,
# producing cursor jumps) and once by the good virtual node. Disabling the raw
# twin is what makes touch land where the finger is.
#
# This is deliberately conditional rather than a hardcoded device ID in the sway
# config: the raw node is only redundant *because* the virtual one exists. If
# iptsd is not running, the raw digitizer is left enabled and the screen still
# responds — degraded rather than dead. Crucially that also has to hold when
# iptsd dies *mid-session*: the raw node must be switched back on, or a crashed
# iptsd would leave a permanently unresponsive touchscreen.
#
# The twin must be matched per device, not globally. Both identifiers start with
# the same vendor:product, so one digitizer's virtual twin can never be taken as
# cover for silencing a different, unrelated digitizer.
is_raw_digitizer() {
  [[ "$1" == *IPTS* && "$1" != *IPTSD_Virtual* ]]
}

has_virtual_twin_for() {
  # sway identifiers are vendor:product:name — compare only the first two fields.
  local vendor_product; vendor_product="$(cut -d: -f1,2 <<<"$1")"
  local id
  for id in "${touch_ids[@]}"; do
    [[ "$id" == "$vendor_product":*IPTSD_Virtual_Touchscreen* ]] && return 0
  done
  return 1
}

# How many real touchscreens (fingers, not pens) this machine has. A raw
# digitizer that iptsd supersedes is not counted: a device plus its own virtual
# twin would read as two screens, defeating the single-touchscreen fail-safe on
# exactly the hardware that needs it.
touchscreen_count=0
for _id in "${touch_ids[@]}"; do
  [ "$(type_of "$_id")" = "touch" ] || continue
  if is_raw_digitizer "$_id" && has_virtual_twin_for "$_id"; then
    continue
  fi
  touchscreen_count=$((touchscreen_count + 1))
done

# --- decide the target output for one device --------------------------------
#
# Precedence: an explicit user rule wins; otherwise the built-in digitizer goes
# to the built-in panel and anything else is treated as an external touchscreen.
#
# A malformed rules file must not take the touchscreen down with it, but it must
# not be silent either: a rule that never matches because of a typo looks
# identical to no rule at all, and the heuristic often produces the same answer,
# which is exactly how a broken lookup can pass a careless test. So the file is
# validated once, loudly, and then treated as absent.
rules_ok=0
if [ -r "$RULES_FILE" ]; then
  if jq -e 'type == "object" and ((.rules // []) | type == "array")' "$RULES_FILE" >/dev/null 2>&1; then
    rules_ok=1
  else
    log "WARNING: $RULES_FILE is not valid JSON (or .rules is not an array); ignoring it"
  fi
fi

rule_lookup() {
  local id="$1" field="$2" out err
  [ "$rules_ok" -eq 1 ] || return 1
  # `.match` has to be bound BEFORE piping into test(): inside `test(...)` the
  # input is $id, so a bare `.match` there indexes the *string* and jq aborts
  # with "Cannot index string with string". Binding it first keeps the rule
  # object in scope.
  err="$(mktemp)"
  out="$(jq -r --arg id "$id" --arg field "$field" '
    (.rules // [])
    | map(select(.match as $m | $id | test($m)))
    | first
    | if . == null then empty else (.[$field] // empty) end
  ' "$RULES_FILE" 2>"$err" | grep -v '^$')"
  if [ -s "$err" ]; then
    log "WARNING: rule lookup failed for '$id': $(tr -d '\n' < "$err")"
  fi
  rm -f "$err"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

target_output_for() {
  local id="$1" want

  # 1. Explicit rule from touch-mapping.json.
  if want="$(rule_lookup "$id" output)" && [ -n "$want" ]; then
    case "$want" in
      internal) [ -n "$internal_output" ] && { printf '%s' "$internal_output"; return 0; } ;;
      external) [ "${#external_outputs[@]}" -gt 0 ] && { printf '%s' "${external_outputs[0]}"; return 0; } ;;
      *)
        # A literal output name is only honoured while that output is actually
        # active, so a rule written for a monitor that is currently unplugged
        # falls through to the heuristic instead of mapping into a void.
        for o in "${active_outputs[@]}"; do
          [ "$o" = "$want" ] && { printf '%s' "$o"; return 0; }
        done
        ;;
    esac
  fi

  # 2. A digitizer we recognise as built-in belongs to the built-in panel.
  #
  # Note this is a *name* test on purpose. The bus is not usable evidence: the
  # ThinkPad's built-in touchscreen enumerates on USB
  # (pci0000:00/.../usb3/3-1/...), exactly like a plugged-in USB panel would, so
  # "USB means external" is precisely backwards there.
  case "$id" in
    *IPTS*|*IPTSD*|*N-trig*|*ELAN*|*Wacom*|*SYNAPTICS*|*SYNA*|*SiS*|*Silicon_Integrated*)
      [ -n "$internal_output" ] && { printf '%s' "$internal_output"; return 0; } ;;
  esac

  # 3. A machine with exactly one touchscreen: that touchscreen is the machine's
  #    own screen. This is the fail-safe that matters most. Guessing "external"
  #    for an unrecognised digitizer makes the laptop's own glass drive a
  #    different monitor the moment anything is plugged in — the built-in screen
  #    stops responding where you touch it, which is far worse than an external
  #    panel needing a one-line rule. Only when a second touchscreen shows up is
  #    there real evidence that one of them is not the built-in one.
  if [ "$touchscreen_count" -le 1 ]; then
    [ -n "$internal_output" ] && { printf '%s' "$internal_output"; return 0; }
  fi

  # 4. Several touchscreens and this one is not the recognised built-in, so it
  #    is an external panel. With exactly one external monitor this is
  #    unambiguous (the Verbatim case). With several, the first is a guess —
  #    that is what touch-mapping.json is for, and the guess is logged so it is
  #    visible rather than silently wrong.
  if [ "${#external_outputs[@]}" -gt 0 ]; then
    [ "${#external_outputs[@]}" -gt 1 ] && \
      log "note: '$id' assigned to ${external_outputs[0]} (${#external_outputs[@]} externals active; add a rule to $RULES_FILE to pin it)"
    printf '%s' "${external_outputs[0]}"
    return 0
  fi

  # 4. No external monitor: an external digitizer with no screen of its own is
  #    better bound to the only display than left spanning nothing.
  [ -n "$internal_output" ] && { printf '%s' "$internal_output"; return 0; }
  return 1
}

# --- apply ------------------------------------------------------------------

apply() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'would: swaymsg input %q %s\n' "$1" "$2"
    return 0
  fi
  # `--` is required: a calibration matrix for a flipped or 180°-rotated panel
  # starts with a negative number, and swaymsg parses a leading "-1" as one of
  # its own options ("invalid option -- '1'") instead of passing it through.
  # Without this, exactly the matrices anyone would actually need are the ones
  # that silently fail.
  swaymsg -- input "$1" $2 >/dev/null 2>&1 \
    || log "failed: input '$1' $2"
}

# Built up as devices are resolved, then published atomically at the end so a
# reader never sees a half-written state file.
state_tmp=""
if [ "$DRY_RUN" -eq 0 ]; then
  state_tmp="$(mktemp "${STATE_FILE}.XXXXXX")" || state_tmp=""
fi

for id in "${touch_ids[@]}"; do
  if is_raw_digitizer "$id"; then
    if has_virtual_twin_for "$id"; then
      # Superseded by iptsd's calibrated twin — silence it and move on.
      log "disabling raw digitizer '$id' (superseded by iptsd virtual device)"
      apply "$id" "events disabled"
      continue
    fi
    # No twin: iptsd is not running (or has died). Undo any disable we applied
    # earlier, otherwise a crashed iptsd leaves the screen permanently dead, and
    # fall through so the raw device still gets mapped to an output.
    log "no iptsd twin for '$id'; enabling raw digitizer as fallback"
    apply "$id" "events enabled"
  fi

  if out="$(target_output_for "$id")" && [ -n "$out" ]; then
    log "mapping '$id' -> $out"
    apply "$id" "map_to_output $out"
    [ -n "$state_tmp" ] && printf '%s\t%s\t%s\n' "$id" "$out" "$(type_of "$id")" >> "$state_tmp"
  else
    log "no output candidate for '$id'; leaving unmapped"
  fi

  # Optional axis correction for panels whose digitizer is rotated or mirrored
  # relative to the picture. Only some external touchscreens need this, so it is
  # purely opt-in via a rule; the six numbers are libinput's calibration matrix.
  if matrix="$(rule_lookup "$id" calibration_matrix)" && [ -n "$matrix" ]; then
    log "calibrating '$id' -> [$matrix]"
    apply "$id" "calibration_matrix $matrix"
  fi
done

if [ -n "$state_tmp" ]; then
  mv -f "$state_tmp" "$STATE_FILE" 2>/dev/null || rm -f "$state_tmp"
fi
