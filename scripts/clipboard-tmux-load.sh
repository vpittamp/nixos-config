#!/usr/bin/env bash
# Load stdin into the mirrored tmux clipboard buffer for all local tmux servers.
# This keeps tmux paste in sync with the desktop clipboard without depending on
# the currently focused tmux client.

set -euo pipefail

BUFFER_NAME="${TMUX_CLIPBOARD_BUFFER_NAME:-__system_clipboard}"
CLEAR_BUFFER=0

if [[ "${1:-}" == "--clear" ]]; then
  CLEAR_BUFFER=1
  shift
fi

tmp=$(mktemp -t clipboard-tmux-load-XXXXXX)
cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT

if [[ "$CLEAR_BUFFER" -eq 0 ]]; then
  cat >"$tmp"

  # Treat empty payloads as "nothing to mirror".
  if [[ ! -s "$tmp" ]]; then
    exit 0
  fi
fi

declare -A seen_sockets=()
sockets=()

add_socket() {
  local socket_path="$1"

  if [[ -z "$socket_path" || ! -S "$socket_path" ]]; then
    return
  fi

  if [[ -n "${seen_sockets[$socket_path]:-}" ]]; then
    return
  fi

  seen_sockets["$socket_path"]=1
  sockets+=("$socket_path")
}

if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
  current_socket=$(tmux display-message -p '#{socket_path}' 2>/dev/null || true)
  add_socket "$current_socket"
fi

uid=$(id -u)
tmux_roots=()

add_tmux_root() {
  local root="$1"

  if [[ -z "$root" ]]; then
    return
  fi

  for existing in "${tmux_roots[@]:-}"; do
    if [[ "$existing" == "$root" ]]; then
      return
    fi
  done

  tmux_roots+=("$root")
}

add_tmux_root "${TMUX_TMPDIR:-}/tmux-${uid}"
add_tmux_root "${XDG_RUNTIME_DIR:-}/tmux-${uid}"
add_tmux_root "${TMPDIR:-/tmp}/tmux-${uid}"

for tmux_root in "${tmux_roots[@]}"; do
  if [[ -d "$tmux_root" ]]; then
    while IFS= read -r socket_path; do
      add_socket "$socket_path"
    done < <(find "$tmux_root" -maxdepth 2 -type s 2>/dev/null | sort)
  fi
done

if [[ ${#sockets[@]} -eq 0 ]]; then
  exit 0
fi

for socket_path in "${sockets[@]}"; do
  if [[ "$CLEAR_BUFFER" -eq 1 ]]; then
    tmux -S "$socket_path" set-buffer -b "$BUFFER_NAME" "" >/dev/null 2>&1 || true
    continue
  fi

  # Keep a deterministic named buffer for mirrored clipboard content. tmux key
  # bindings explicitly paste this buffer so internal buffer history stays clean.
  tmux -S "$socket_path" load-buffer -b "$BUFFER_NAME" "$tmp" >/dev/null 2>&1 || true
done
