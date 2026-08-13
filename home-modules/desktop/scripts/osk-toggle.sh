#!/usr/bin/env bash
# osk-toggle - show/hide the wvkbd on-screen keyboard.
#
# wvkbd runs as a hidden systemd user service (wvkbd.service). Signals:
#   SIGRTMIN  toggle visibility
#   SIGUSR1   hide
#   SIGUSR2   show
#
# wvkbd cannot be asked whether it is visible, but every control path (bar
# chip, edge gesture, launcher auto-raise, CLI) goes through this script, so a
# state file can stand in for the query. That state is what lets the launcher
# behave politely in touch mode:
#
#   auto-show   raise the keyboard for a text surface — but if the user already
#               has it up, remember that it is THEIRS and take no credit
#   auto-hide   drop the keyboard only if auto-show raised it; a keyboard the
#               user opened stays put when the launcher closes
#
# `show`/`hide`/`toggle` are the user-intent verbs and always clear the auto
# mark: a keyboard the user has explicitly touched is theirs to manage, and no
# later auto-hide may take it away.
set -euo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/osk.state"   # "visible"|"hidden" [auto]

read_state() { cat "$STATE" 2>/dev/null || echo "hidden"; }
write_state() { printf '%s\n' "$1" > "$STATE"; }

running() { pgrep -x wvkbd-mobintl >/dev/null 2>&1; }

signal_or_start() {  # $1 = RTMIN|USR1|USR2
  if running; then
    pkill "-$1" -x wvkbd-mobintl
  else
    # Service not started yet: the keyboard is definitionally hidden, so a
    # hide is already done; anything else means start it and make it visible.
    [ "$1" = "USR1" ] && return 0
    systemctl --user start wvkbd.service 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      running && break
      sleep 0.2
    done
    pkill -USR2 -x wvkbd-mobintl 2>/dev/null || true
  fi
}

action="${1:-toggle}"
case "$action" in
  toggle)
    case "$(read_state)" in
      visible*) signal_or_start USR1; write_state hidden ;;
      *)        signal_or_start USR2; write_state visible ;;
    esac
    ;;
  show)  signal_or_start USR2; write_state visible ;;
  hide)  signal_or_start USR1; write_state hidden ;;
  auto-show)
    case "$(read_state)" in
      visible*) : ;;   # user's keyboard, not ours to mark
      *) signal_or_start USR2; write_state "visible auto" ;;
    esac
    ;;
  auto-hide)
    case "$(read_state)" in
      "visible auto") signal_or_start USR1; write_state hidden ;;
      *) : ;;
    esac
    ;;
  status) read_state ;;
  *) echo "usage: osk-toggle [toggle|show|hide|auto-show|auto-hide|status]" >&2; exit 2 ;;
esac
