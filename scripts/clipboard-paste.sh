#!/usr/bin/env bash
# Emit the current system clipboard contents to stdout, with fallbacks for
# Wayland, X11, macOS, and Windows/WSL bridges. Used to feed tmux buffers so
# prefix + ] can paste Walker/Elephant entries seamlessly.

set -euo pipefail

read_clipboard() {
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-paste >/dev/null 2>&1; then
    wl-paste
    return
  fi

  if command -v wl-paste >/dev/null 2>&1; then
    wl-paste
    return
  fi

  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard -out
    return
  fi

  if command -v pbpaste >/dev/null 2>&1; then
    pbpaste
    return
  fi

  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe Get-Clipboard
    return
  fi

  if command -v clip.exe >/dev/null 2>&1; then
    # clip.exe cannot output the clipboard directly; win32yank.exe is preferred,
    # but if unavailable we have no better option.
    printf ''  # No-op fallback
    return
  fi

  printf ''
}

read_clipboard
