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
    # Visual feedback now handled by eww-workspace-bar (Feature 058)
    ;;
  char)
    char_value="${2:-}"
    if [ -z "${char_value}" ]; then
      echo "char subcommand requires a value" >&2
      exit 1
    fi
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.char\",\"params\":{\"char\":\"${char_value}\"},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    # Visual feedback now handled by eww-workspace-bar (Feature 058)
    ;;
  execute)
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.execute\",\"params\":{},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    # Visual feedback now handled by eww-workspace-bar (Feature 058)
    ;;
  cancel)
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.cancel\",\"params\":{},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    # Visual feedback now handled by eww-workspace-bar (Feature 058)
    ;;
  enter)
    # Feature 072: Notify daemon when entering workspace mode (triggers all-windows preview)
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.enter\",\"params\":{},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
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
  nav)
    # Feature 059: Arrow key navigation for interactive workspace menu
    direction="${2:-}"
    if [ -z "${direction}" ]; then
      echo "nav subcommand requires a direction (up or down)" >&2
      exit 1
    fi
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.nav\",\"params\":{\"direction\":\"${direction}\"},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    ;;
  delete)
    # Feature 059: Delete key to close selected window
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.delete\",\"params\":{},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    ;;
  action)
    # Feature 073: Per-window actions (m=move, f=float, shift-m=mark)
    action_value="${2:-}"
    if [ -z "${action_value}" ]; then
      echo "action subcommand requires an action (m, f, shift-m)" >&2
      exit 1
    fi
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.action\",\"params\":{\"action\":\"${action_value}\"},\"id\":1}" | \
      "${socat_bin}" - UNIX-CONNECT:"${SOCK}" > /dev/null 2>&1
    ;;
  *)
    echo "Usage: $0 {digit <0-9>|char <a-z>|execute|cancel|enter|state [--json]|nav <up|down>|delete|action <m|f|shift-m>}" >&2
    exit 1
    ;;
esac
