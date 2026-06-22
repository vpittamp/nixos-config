#!/usr/bin/env bash
# dictation - mic-aware front-end for voxtype push-to-talk transcription.
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

case "$cmd" in
  toggle|start)
    pick_jabra_mic
    voxtype record "$cmd"
    ;;
  stop|cancel)
    voxtype record "$cmd"
    ;;
  status)
    voxtype status --format json
    ;;
  *)
    echo "usage: dictation {toggle|start|stop|cancel|status}" >&2
    exit 1
    ;;
esac
