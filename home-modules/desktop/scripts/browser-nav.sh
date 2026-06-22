#!/usr/bin/env bash
# browser-nav back|forward — trackpad history navigation for the focused window.
#
# Sway/libinput has no built-in "swipe to go back" for browsers, so a 3-finger
# horizontal swipe is bound to this script (see sway.nix bindgesture). It injects
# the standard Alt+Left / Alt+Right history shortcut via dotool (uinput), but
# ONLY when a browser-class window is focused — so the same gesture is a no-op in
# a terminal/editor instead of (e.g.) moving the cursor by word.
#
# Direction follows the macOS convention: swipe RIGHT -> go back, swipe LEFT ->
# go forward (the gesture binding maps swipe:3:right -> back, swipe:3:left ->
# forward).
set -uo pipefail

dir="${1:-back}"

# app_id (Wayland) or X11 class of the currently-focused window.
app="$(swaymsg -t get_tree 2>/dev/null \
  | jq -r 'first(.. | objects | select(.focused? == true)
           | (.app_id // .window_properties.class // ""))')"

shopt -s nocasematch
case "$app" in
  *chrome*|*chromium*|*brave*|*edge*|*vivaldi*|*firefox*|FFPWA-*|*epiphany*)
    case "$dir" in
      forward) printf 'key alt+Right\n' | dotool ;;
      *)       printf 'key alt+Left\n'  | dotool ;;
    esac
    ;;
  *)
    : # not a browser — ignore the gesture
    ;;
esac
