#!/usr/bin/env bash
# focus-history-daemon — maintain a browser-style back/forward stack of focused
# windows, so a gesture can jump to the previously-focused window and forward
# again (across workspaces/outputs). sway has no native focus history.
#
# Design: a single FIFO merges two input streams into one event loop —
#   * sway window events  -> "focus <id>" / "close <id>"   (the subscriber)
#   * nav commands         -> "nav back" / "nav forward"    (the focus-history CLI)
# so all state mutation happens in one place with no shared-memory races.
#
# A user-initiated focus truncates any forward history and pushes the window
# (classic history semantics). Our own navigation focus is suppressed from being
# recorded via the `navigating` flag, so back/forward stay coherent. `close`
# events prune dead windows so navigation never lands on a phantom.
set -uo pipefail

FIFO="${XDG_RUNTIME_DIR:-/tmp}/focus-history.fifo"
rm -f "$FIFO"
mkfifo "$FIFO"

# Subscriber: emit focus/close events into the FIFO. --unbuffered is REQUIRED so
# each event is flushed immediately (jq block-buffers to a pipe otherwise).
swaymsg -t subscribe -m '["window"]' 2>/dev/null \
  | jq --unbuffered -rc 'select(.change=="focus" or .change=="close")
                         | "\(.change) \(.container.id // "")"' \
  > "$FIFO" &
SUB_PID=$!
trap 'kill "$SUB_PID" 2>/dev/null; rm -f "$FIFO"' EXIT

declare -a hist=()
pos=-1
navigating=0

# Seed with the currently-focused window so the first "back" has a reference.
seed="$(swaymsg -t get_tree 2>/dev/null \
  | jq -r 'first(.. | objects | select(.focused? == true) | .id) // empty')"
if [ -n "$seed" ]; then hist=("$seed"); pos=0; fi

# Drop every occurrence of $1 from hist and fix up pos.
remove_id() {
  local want="$1" i removed_before=0
  local -a out=()
  for i in "${!hist[@]}"; do
    if [ "${hist[$i]}" = "$want" ]; then
      [ "$i" -le "$pos" ] && removed_before=$((removed_before + 1))
    else
      out+=("${hist[$i]}")
    fi
  done
  hist=("${out[@]}")
  pos=$((pos - removed_before))
  if [ "${#hist[@]}" -eq 0 ]; then
    pos=-1
  else
    [ "$pos" -lt 0 ] && pos=0
    [ "$pos" -ge "${#hist[@]}" ] && pos=$(( ${#hist[@]} - 1 ))
  fi
}

# Loop exits on EOF (the subscriber dying, e.g. sway restart) so systemd restarts
# us with a fresh subscription.
while read -r kind id; do
  case "$kind" in
    focus)
      [ -n "$id" ] || continue
      if [ "$navigating" = 1 ]; then navigating=0; continue; fi
      # User-initiated focus: ignore if it's already the current entry, else
      # truncate forward history and push.
      if [ "$pos" -ge 0 ] && [ "${hist[$pos]}" = "$id" ]; then
        continue
      fi
      hist=("${hist[@]:0:$((pos + 1))}")
      hist+=("$id")
      pos=$((pos + 1))
      ;;
    close)
      [ -n "$id" ] && remove_id "$id"
      ;;
    nav)
      if [ "$id" = back ]; then
        [ "$pos" -gt 0 ] || continue
        pos=$((pos - 1))
      else
        [ "$pos" -lt $(( ${#hist[@]} - 1 )) ] || continue
        pos=$((pos + 1))
      fi
      navigating=1
      swaymsg "[con_id=${hist[$pos]}] focus" >/dev/null 2>&1 || true
      ;;
  esac
done < "$FIFO"
