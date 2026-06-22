#!/usr/bin/env bash
# focus-history back|forward — ask the focus-history daemon to step backward or
# forward through the window focus history (bound to a 4-finger swipe). Writes a
# nav command to the daemon's FIFO; a no-op (never blocks the gesture) if the
# daemon isn't running.
set -uo pipefail

dir="${1:-back}"
case "$dir" in
  back | forward) ;;
  *) echo "usage: focus-history {back|forward}" >&2; exit 1 ;;
esac

FIFO="${XDG_RUNTIME_DIR:-/tmp}/focus-history.fifo"
[ -p "$FIFO" ] || exit 0   # daemon not running

# Non-blocking guarded write so a wedged daemon can't hang the gesture exec.
timeout 0.5 bash -c "printf 'nav %s\n' \"\$1\" > \"\$2\"" _ "$dir" "$FIFO" 2>/dev/null || true
