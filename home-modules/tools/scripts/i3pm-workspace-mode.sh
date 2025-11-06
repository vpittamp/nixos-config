#!/usr/bin/env bash
set -euo pipefail

SOCK="/run/i3-project-daemon/ipc.sock"
workspace_visual="@workspace_visual_bin@"
socat_bin="@socat@"
jq_bin="@jq@"

case "$1" in
  digit)
    digit_value="${2:-}"
    if [ -z "${digit_value}" ]; then
      echo "digit subcommand requires a value" >&2
      exit 1
    fi
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.digit\",\"params\":{\"digit\":\"${digit_value}\"},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    "${workspace_visual}" append "${digit_value}"
    ;;
  char)
    char_value="${2:-}"
    if [ -z "${char_value}" ]; then
      echo "char subcommand requires a value" >&2
      exit 1
    fi
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.char\",\"params\":{\"char\":\"${char_value}\"},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    "${workspace_visual}" append "${char_value}"
    ;;
  execute)
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.execute\",\"params\":{},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    "${workspace_visual}" stop
    ;;
  cancel)
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.cancel\",\"params\":{},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    "${workspace_visual}" stop
    ;;
  state)
    if [ "${2:-}" = "--json" ]; then
      echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.state\",\"params\":{},\"id\":1}" | \
        "${socat_bin}" - UNIX-CONNECT:"${SOCK}" 2>/dev/null | \
        "${jq_bin}" -c '.result // {}'
    else
      echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.state\",\"params\":{},\"id\":1}" | \
        "${socat_bin}" - UNIX-CONNECT:"${SOCK}" 2>/dev/null | \
        "${jq_bin}" '.result // {}'
    fi
    ;;
  *)
    echo "Usage: $0 {digit <0-9>|char <a-z>|execute|cancel|state [--json]}" >&2
    exit 1
    ;;
esac
