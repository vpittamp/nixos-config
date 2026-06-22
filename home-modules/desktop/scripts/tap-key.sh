#!/usr/bin/env bash
# tap-key KEY... — inject one key chord per argument via dotool (uinput), so a
# trackpad gesture can press keys with no physical keyboard. Main use: submit
# dictated text with `enter` while in clamshell/trackpad mode.
#
# Key names are dotool/Linux names, lowercase: enter, esc, tab, left, right,
# backspace, space, ... (NOT X11 keysyms like Return). Combine with '+', e.g.
# `tap-key ctrl+c`.
set -uo pipefail

[ "$#" -ge 1 ] || { echo "usage: tap-key KEY [KEY...]" >&2; exit 1; }

for k in "$@"; do
  printf 'key %s\n' "$k"
done | dotool
