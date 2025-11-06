# Temporary wrapper for workspace mode IPC calls
# TODO: Replace with TypeScript CLI integration (add workspace-mode subcommand to i3pm/src/main.ts)
{ pkgs, ... }:

let
  workspaceModeVisual = pkgs.writeShellScriptBin "workspace-mode-visual" ''
    set -euo pipefail

    backend="${WORKSPACE_MODE_VISUAL_BACKEND:-wshowkeys}"
    uid="$(${pkgs.coreutils}/bin/id -u)"
    state_dir="/run/user/${uid}/i3pm"
    state_file="${state_dir}/workspace-mode-keys"

    notify_send="${pkgs.libnotify}/bin/notify-send"
    makoctl="${pkgs.mako}/bin/makoctl"
    mkdir_bin="${pkgs.coreutils}/bin/mkdir"
    printf_bin="${pkgs.coreutils}/bin/printf"
    cat_bin="${pkgs.coreutils}/bin/cat"
    rm_bin="${pkgs.coreutils}/bin/rm"
    setsid_bin="${pkgs.util-linux}/bin/setsid"
    pkill_bin="${pkgs.procps}/bin/pkill"

    ensure_state_dir() {
      "$mkdir_bin" -p "${state_dir}"
    }

    send_notification() {
      if [ "${backend}" = "notification" ]; then
        local body="$1"
        local timeout="${2:-60000}"
        "$notify_send" \
          --app-name "Workspace Mode" \
          --urgency=low \
          --expire-time "${timeout}" \
          --hint string:x-canonical-private-synchronous:workspace-mode \
          "Workspace Mode" "${body}"
      fi
    }

    reset_notification() {
      if [ "${backend}" = "notification" ]; then
        "$makoctl" dismiss --criteria app-name="Workspace Mode" >/dev/null 2>&1 || true
      fi
    }

    subcommand="${1:-}"
    case "${subcommand}" in
      start)
        if [ "${backend}" = "notification" ]; then
          ensure_state_dir
          "$printf_bin" "" > "${state_file}"
          send_notification "Active. Type digits or letters to filter." 60000
        else
          "$pkill_bin" -x wshowkeys >/dev/null 2>&1 || true
          "$setsid_bin" -f ${pkgs.wshowkeys}/bin/wshowkeys \
            -a bottom -m 40 -s '#89b4fa' -F 'monospace 28' -t 60 \
            >/dev/null 2>&1 || true
        fi
        ;;
      append)
        key="${2:-}"
        if [ "${backend}" = "notification" ] && [ -n "${key}" ]; then
          ensure_state_dir
          current="$("$cat_bin" "${state_file}" 2>/dev/null || true)"
          current="${current}${key}"
          "$printf_bin" "%s" "${current}" > "${state_file}"
          send_notification "Keys: ${current}" 60000
        fi
        ;;
      stop)
        if [ "${backend}" = "notification" ]; then
          send_notification "Done." 500
          reset_notification
          "$rm_bin" -f "${state_file}"
        else
          "$pkill_bin" -x wshowkeys >/dev/null 2>&1 || true
        fi
        ;;
      reset)
        if [ "${backend}" = "notification" ]; then
          ensure_state_dir
          "$printf_bin" "" > "${state_file}"
          send_notification "Cleared." 60000
        fi
        ;;
      *)
        echo "Usage: workspace-mode-visual {start|append <key>|stop|reset}" >&2
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [
    workspaceModeVisual
    (pkgs.writeShellScriptBin "i3pm-workspace-mode" ''
      set -euo pipefail

      SOCK="/run/i3-project-daemon/ipc.sock"

      case "$1" in
        digit)
          digit_value="${2:-}"
          if [ -z "$digit_value" ]; then
            echo "digit subcommand requires a value" >&2
            exit 1
          fi
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.digit\",\"params\":{\"digit\":\"$digit_value\"},\"id\":1}" | \
            ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK > /dev/null 2>&1
          ${workspaceModeVisual}/bin/workspace-mode-visual append "$digit_value"
          ;;
        char)
          char_value="${2:-}"
          if [ -z "$char_value" ]; then
            echo "char subcommand requires a value" >&2
            exit 1
          fi
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.char\",\"params\":{\"char\":\"$char_value\"},\"id\":1}" | \
            ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK > /dev/null 2>&1
          ${workspaceModeVisual}/bin/workspace-mode-visual append "$char_value"
          ;;
        execute)
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.execute\",\"params\":{},\"id\":1}" | \
            ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK > /dev/null 2>&1
          ${workspaceModeVisual}/bin/workspace-mode-visual stop
          ;;
        cancel)
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.cancel\",\"params\":{},\"id\":1}" | \
            ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK > /dev/null 2>&1
          ${workspaceModeVisual}/bin/workspace-mode-visual stop
          ;;
        state)
          # Query workspace mode state from daemon (for status bar polling)
          if [ "${2:-}" = "--json" ]; then
            echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.state\",\"params\":{},\"id\":1}" | \
              ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK 2>/dev/null | \
              ${pkgs.jq}/bin/jq -c '.result // {}'
          else
            echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.state\",\"params\":{},\"id\":1}" | \
              ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK 2>/dev/null | \
              ${pkgs.jq}/bin/jq '.result // {}'
          fi
          ;;
        *)
          echo "Usage: $0 {digit <0-9>|char <a-z>|execute|cancel|state [--json]}" >&2
          exit 1
          ;;
      esac
    '')
  ];
}
