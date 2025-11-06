#!/usr/bin/env bash
set -euo pipefail

backend="${WORKSPACE_MODE_VISUAL_BACKEND:-wshowkeys}"
uid="$(@id@ -u)"
state_dir="/run/user/${uid}/i3pm"
state_file="${state_dir}/workspace-mode-keys"

notify_send="@notify_send@"
makoctl="@makoctl@"
mkdir_bin="@mkdir@"
printf_bin="@printf@"
cat_bin="@cat@"
rm_bin="@rm@"
setsid_bin="@setsid@"
pkill_bin="@pkill@"

ensure_state_dir() {
  "${mkdir_bin}" -p "${state_dir}"
}

send_notification() {
  if [ "${backend}" = "notification" ]; then
    local body="${1}"
    local timeout="${2:-60000}"
    "${notify_send}" \
      --app-name "Workspace Mode" \
      --urgency=low \
      --expire-time "${timeout}" \
      --hint string:x-canonical-private-synchronous:workspace-mode \
      "Workspace Mode" "${body}"
  fi
}

reset_notification() {
  if [ "${backend}" = "notification" ]; then
    "${makoctl}" dismiss --criteria app-name="Workspace Mode" >/dev/null 2>&1 || true
  fi
}

subcommand="${1:-}"
case "${subcommand}" in
  start)
    if [ "${backend}" = "notification" ]; then
      ensure_state_dir
      "${printf_bin}" "" > "${state_file}"
      send_notification "Active. Type digits or letters to filter." 60000
    else
      "${pkill_bin}" -x wshowkeys >/dev/null 2>&1 || true
      "${setsid_bin}" -f "@wshowkeys@" \
        -a bottom -m 40 -s '#89b4fa' -F 'monospace 28' -t 60 \
        >/dev/null 2>&1 || true
    fi
    ;;
  append)
    key="${2:-}"
    if [ "${backend}" = "notification" ] && [ -n "${key}" ]; then
      ensure_state_dir
      current="$("${cat_bin}" "${state_file}" 2>/dev/null || true)"
      current="${current}${key}"
      "${printf_bin}" "%s" "${current}" > "${state_file}"
      send_notification "Keys: ${current}" 60000
    fi
    ;;
  stop)
    if [ "${backend}" = "notification" ]; then
      send_notification "Done." 500
      reset_notification
      "${rm_bin}" -f "${state_file}"
    else
      "${pkill_bin}" -x wshowkeys >/dev/null 2>&1 || true
    fi
    ;;
  reset)
    if [ "${backend}" = "notification" ]; then
      ensure_state_dir
      "${printf_bin}" "" > "${state_file}"
      send_notification "Cleared." 60000
    fi
    ;;
  *)
    echo "Usage: workspace-mode-visual {start|append <key>|stop|reset}" >&2
    exit 1
    ;;
esac
