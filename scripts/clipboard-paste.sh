#!/usr/bin/env bash
# Emit the current system clipboard contents to stdout, with fallbacks for
# Wayland, X11, macOS, and Windows/WSL bridges. Used to feed tmux buffers so
# prefix + ] can paste Walker/Elephant entries seamlessly.

set -euo pipefail

# Source Wayland environment from tmux global env if not set
# This handles the case where run-shell is called from a session without Wayland vars
if [[ -z "${WAYLAND_DISPLAY:-}" ]] && [[ -n "${TMUX:-}" ]]; then
  wayland_from_tmux=$(tmux show-environment -g WAYLAND_DISPLAY 2>/dev/null | cut -d= -f2 || true)
  if [[ -n "$wayland_from_tmux" ]]; then
    export WAYLAND_DISPLAY="$wayland_from_tmux"
  fi
fi

if [[ -z "${XDG_RUNTIME_DIR:-}" ]] && [[ -n "${TMUX:-}" ]]; then
  xdg_from_tmux=$(tmux show-environment -g XDG_RUNTIME_DIR 2>/dev/null | cut -d= -f2 || true)
  if [[ -n "$xdg_from_tmux" ]]; then
    export XDG_RUNTIME_DIR="$xdg_from_tmux"
  fi
fi

read_clipboard() {
  # Wayland: prefer text/plain to avoid pasting HTML or image data from browser copies
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-paste >/dev/null 2>&1; then
    # Try text/plain first (handles browser copies with multiple MIME types)
    # Fall back to untyped paste if text/plain not available
    wl-paste --type text/plain 2>/dev/null || wl-paste --no-newline 2>/dev/null || wl-paste
    return
  fi

  # Fallback for wl-paste without WAYLAND_DISPLAY (might work via X11 bridge)
  if command -v wl-paste >/dev/null 2>&1; then
    wl-paste --type text/plain 2>/dev/null || wl-paste --no-newline 2>/dev/null || wl-paste
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
