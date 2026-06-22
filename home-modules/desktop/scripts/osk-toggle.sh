#!/usr/bin/env bash
# osk-toggle - show/hide the wvkbd on-screen keyboard.
#
# wvkbd runs as a hidden systemd user service (wvkbd.service) and toggles its
# visibility on SIGRTMIN. This is the trackpad-reachable way to type in clamshell
# mode, where the laptop keyboard (and its keys) are physically closed.
set -euo pipefail

if pgrep -x wvkbd-mobintl >/dev/null 2>&1; then
  # Running -> flip visibility (SIGRTMIN = toggle).
  pkill -RTMIN -x wvkbd-mobintl
else
  # Not running yet (service not started) -> start it and show.
  systemctl --user start wvkbd.service 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    pgrep -x wvkbd-mobintl >/dev/null 2>&1 && break
    sleep 0.2
  done
  pkill -USR2 -x wvkbd-mobintl 2>/dev/null || true
fi
