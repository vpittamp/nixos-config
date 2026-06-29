#!/usr/bin/env bash
# dictation - mic-aware front-end for voxtype toggle/streaming transcription.
#
# Why this exists:
#   - voxtype records from the PipeWire *default* source. We want to prefer a
#     connected Jabra (or any Bluetooth headset) mic when available, falling
#     back to the built-in mic otherwise.
#   - In clamshell mode the laptop keyboard (and its Copilot key) is closed, so
#     dictation must be triggerable from the Magic Trackpad. This script is the
#     single entry point bound to a sway gesture and the Quickshell bar button;
#     both just call `dictation toggle`.
#
# Usage: dictation {toggle|start|stop|cancel|status}
#
# Note: voxtype errors out if its configured device is missing, which is why we
# steer the *default* source here instead of hard-coding a device in config.toml.
set -euo pipefail

cmd="${1:-toggle}"

# voxtype creates a transient "...voxtype-wrapped" playback sink during a
# dictation session and makes it the PipeWire default; when the session ends the
# wrapper disappears but the *configured* default still points at it, so
# WirePlumber falls back to the highest-priority device (the USB-C dock) and the
# user's chosen output (Jabra / TV / headphones) is silently lost. We work around
# this generically — independent of whatever voxtype does internally — by saving
# the real default output sink when dictation starts and restoring it when it
# stops. Uses pw-metadata (pactl is not installed here); no-ops if unavailable.
DICT_SINK_STATE="${XDG_RUNTIME_DIR:-/tmp}/dictation-prev-default-sink"

# Extract a sink name for a metadata key, but only when it is a REAL output
# (bluez_output/alsa_output) — never voxtype's own alsa_playback wrapper.
_default_sink_for_key() {
  pw-metadata -n default 2>/dev/null \
    | grep -F "'$1'" \
    | grep -oE '(bluez_output|alsa_output)[^"]+' \
    | head -1
}

save_default_sink() {
  command -v pw-metadata >/dev/null 2>&1 || return 0
  local name
  name="$(_default_sink_for_key default.configured.audio.sink)"
  # Fall back to the active sink if the configured one is already a wrapper/empty.
  [ -n "$name" ] || name="$(_default_sink_for_key default.audio.sink)"
  [ -n "$name" ] || return 0
  printf '%s' "$name" > "$DICT_SINK_STATE" 2>/dev/null || true
}

restore_default_sink() {
  command -v pw-metadata >/dev/null 2>&1 || return 0
  [ -r "$DICT_SINK_STATE" ] || return 0
  local saved cur
  saved="$(cat "$DICT_SINK_STATE" 2>/dev/null || true)"
  [ -n "$saved" ] || return 0
  cur="$(_default_sink_for_key default.audio.sink)"
  # Only act if voxtype left a different (or wrapped/empty) sink as the default.
  if [ "$cur" != "$saved" ]; then
    pw-metadata 0 default.configured.audio.sink "{\"name\":\"$saved\"}" >/dev/null 2>&1 || true
    pw-metadata 0 default.audio.sink "{\"name\":\"$saved\"}" >/dev/null 2>&1 || true
  fi
}

voxtype_class() {
  local status cls
  status="$(voxtype status --format json 2>/dev/null || true)"
  if command -v jq >/dev/null 2>&1; then
    cls="$(printf '%s' "$status" | jq -r '.class // ""' 2>/dev/null || true)"
  else
    cls="$(printf '%s' "$status" | sed -n 's/.*"class"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi
  printf '%s' "$cls"
}

pick_jabra_mic() {
  command -v pactl >/dev/null 2>&1 || return 0

  # Prefer a Jabra/Bluetooth mic ONLY if it is already exposed as a source (i.e.
  # the headset is already in a mic-capable HFP mode, or connected via the USB
  # dongle). We deliberately do NOT force the headset's card into HFP: that
  # collapses A2DP stereo to mono and, with no restore, leaves the headset stuck
  # in call mode afterwards — which is what made the headset seem "muted". When
  # the Jabra mic is available, WirePlumber's priority rules already make it the
  # default source, so usually there is nothing to switch here.
  local src
  src="$(pactl list sources short 2>/dev/null | awk '{print $2}' \
        | grep -iE 'jabra|bluez_input' | head -1 || true)"
  if [ -n "$src" ]; then
    pactl set-default-source "$src" 2>/dev/null || true
  fi

  # Never dictate into a muted mic: unmute the source we are about to record
  # from (does not touch any playback/output sink).
  pactl set-source-mute @DEFAULT_SOURCE@ 0 2>/dev/null || true
}

stop_dictation() {
  voxtype record stop || true

  # Parakeet streaming sometimes logs that SIGUSR2 closed capture but keeps
  # reporting "streaming" for a long time. Fall back to cancel only for that
  # stale streaming state; do not cancel normal Whisper "transcribing" work.
  sleep 1.25
  case "$(voxtype_class)" in
    streaming)
      voxtype record cancel || true
      ;;
  esac

  # Undo any default-output-sink change voxtype made during the session.
  restore_default_sink
}

case "$cmd" in
  toggle)
    # If Voxtype is already listening, this toggle is a stop request. Avoid the
    # mic-selection path here so ending a streaming session feels immediate.
    case "$(voxtype_class)" in
      recording|streaming)
        stop_dictation
        ;;
      *)
        save_default_sink
        pick_jabra_mic
        voxtype record toggle
        ;;
    esac
    ;;
  start)
    save_default_sink
    pick_jabra_mic
    voxtype record "$cmd"
    ;;
  stop|cancel)
    if [ "$cmd" = "stop" ]; then
      stop_dictation
    else
      voxtype record cancel || true
    fi
    ;;
  status)
    voxtype status --format json
    ;;
  *)
    echo "usage: dictation {toggle|start|stop|cancel|status}" >&2
    exit 1
    ;;
esac
