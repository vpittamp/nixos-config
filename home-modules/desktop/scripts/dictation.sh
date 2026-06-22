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

  # 1. A Jabra/Bluetooth mic source already exposed -> just make it default.
  local src
  src="$(pactl list sources short 2>/dev/null | awk '{print $2}' \
        | grep -iE 'jabra|bluez_input' | head -1 || true)"

  # 2. Jabra connected but only in A2DP (no source): switch its card to the
  #    HFP head-unit profile (prefer wideband mSBC) to expose the mic.
  if [ -z "$src" ]; then
    local card
    card="$(pactl list cards short 2>/dev/null | awk '{print $2}' \
          | grep -iE 'jabra|bluez_card' | head -1 || true)"
    if [ -n "$card" ]; then
      pactl set-card-profile "$card" headset-head-unit-msbc 2>/dev/null \
        || pactl set-card-profile "$card" headset-head-unit 2>/dev/null || true
      sleep 0.3
      src="$(pactl list sources short 2>/dev/null | awk '{print $2}' \
            | grep -iE 'jabra|bluez_input' | head -1 || true)"
    fi
  fi

  # 3. Found a Jabra mic -> prefer it. Otherwise leave the default (built-in).
  if [ -n "$src" ]; then
    pactl set-default-source "$src" 2>/dev/null || true
  fi
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
