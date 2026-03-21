#!/usr/bin/env bash
# Watch the Wayland clipboard and mirror text clipboard updates into tmux.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/clipboard-sync"
state_file="$state_dir/last-system-clipboard.sha256"

mkdir -p "$state_dir"

watch_handler() {
  local tmp hash previous_hash

  case "${CLIPBOARD_STATE:-data}" in
    data|sensitive) ;;
    nil|clear)
      "$script_dir/clipboard-tmux-load.sh" --clear
      rm -f "$state_file"
      exit 0
      ;;
    *)
      exit 0
      ;;
  esac

  if [[ "${CLIPBOARD_STATE:-data}" == "sensitive" ]]; then
    rm -f "$state_file"
  fi

  tmp=$(mktemp -t clipboard-watch-handler-XXXXXX)
  trap 'rm -f "${tmp:-}"' EXIT

  cat >"$tmp"

  if [[ ! -s "$tmp" ]]; then
    exit 0
  fi

  hash=$(sha256sum "$tmp" | awk '{print $1}')
  previous_hash=""
  if [[ -f "$state_file" ]]; then
    previous_hash=$(<"$state_file")
  fi

  if [[ "$hash" == "$previous_hash" ]]; then
    exit 0
  fi

  printf '%s\n' "$hash" >"$state_file"
  "$script_dir/clipboard-tmux-load.sh" <"$tmp"
}

if [[ "${1:-}" == "--handle-watch-event" ]]; then
  watch_handler
  exit 0
fi

# Seed tmux with the current clipboard on service start.
"$script_dir/clipboard-import-current.sh" || true

exec wl-paste --type text/plain --watch "$0" --handle-watch-event
