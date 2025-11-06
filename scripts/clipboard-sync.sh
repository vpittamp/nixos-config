#!/usr/bin/env bash
# Synchronize clipboard contents across Wayland, X11, OSC52 terminals, and auxiliary bridges.
# Reads stdin into a temporary file to remain binary-safe, then fans out to the
# available clipboard backends. Designed for use by Elephant/Walker, tmux, and
# general shell workflows.

set -euo pipefail

tmp=$(mktemp -t clipboard-sync-XXXXXX)
cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT

cat >"$tmp"

# Exit cleanly on empty input
if [[ ! -s "$tmp" ]]; then
  exit 0
fi

# Detect mimetype when possible (used for Wayland image copies)
mime=""
if command -v file >/dev/null 2>&1; then
  mime=$(file --brief --mime-type "$tmp" 2>/dev/null || true)
fi

copy_wayland() {
  # Prefer explicit mime when dealing with images
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then
    if [[ "$mime" =~ ^image/ ]]; then
      wl-copy --type "$mime" <"$tmp"
      wl-copy --primary --type "$mime" <"$tmp"
    else
      wl-copy <"$tmp"
      wl-copy --primary <"$tmp"
    fi
  elif command -v wl-copy >/dev/null 2>&1; then
    # Fallback: wl-copy via x11 bridge (e.g., wl-clipboard-x11)
    wl-copy <"$tmp"
  fi
}

copy_x11() {
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard <"$tmp"
    xclip -selection primary <"$tmp"
  fi
}

copy_pbcopy() {
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy <"$tmp"
  fi
}

copy_clip_exe() {
  if command -v clip.exe >/dev/null 2>&1; then
    # clip.exe cannot handle NUL bytes; strip them defensively
    tr -d '\0' <"$tmp" | clip.exe
  fi
}

copy_osc52() {
  if ! command -v base64 >/dev/null 2>&1; then
    return
  fi

  # Only attempt OSC52 when inside tmux/screen/SSH to avoid polluting local terminals.
  if [[ -z "${TMUX:-}${SSH_TTY:-}" ]]; then
    return
  fi

  # Avoid sending excessively large payloads (limit to 1 MiB)
  if [[ $(stat --format='%s' "$tmp" 2>/dev/null || wc -c <"$tmp") -gt 1048576 ]]; then
    return
  fi

  if payload=$(base64 -w0 "$tmp" 2>/dev/null); then
    osc=$'\e]52;c;'"$payload"$'\a'
    target="/dev/tty"
    if [[ -n "${TMUX:-}" ]]; then
      target=$(tmux display -p '#{client_tty}' 2>/dev/null || echo "/dev/tty")
    elif [[ -n "${SSH_TTY:-}" ]]; then
      target="${SSH_TTY}"
    fi
    printf '%b' "$osc" >"$target" 2>/dev/null || true
  fi
}

copy_wayland
copy_x11
copy_pbcopy
copy_clip_exe
copy_osc52
