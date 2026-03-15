#!/usr/bin/env bash

set -euo pipefail

mode="${1:-normal}"

title="QuickShell Native Notifications"
body="QuickShell now owns org.freedesktop.Notifications on this Sway session."

notify_send_bin="${NOTIFY_SEND_BIN:-}"
if [[ -z "$notify_send_bin" ]]; then
  notify_send_bin="$(command -v notify-send || true)"
fi
if [[ -z "$notify_send_bin" && -x /run/current-system/sw/bin/notify-send ]]; then
  notify_send_bin="/run/current-system/sw/bin/notify-send"
fi
if [[ -z "$notify_send_bin" ]]; then
  libnotify_path="$(nix eval --raw nixpkgs#libnotify.outPath 2>/dev/null || true)"
  if [[ -n "$libnotify_path" && -x "$libnotify_path/bin/notify-send" ]]; then
    notify_send_bin="$libnotify_path/bin/notify-send"
  fi
fi
if [[ -z "$notify_send_bin" ]]; then
  echo "notify-send not found" >&2
  exit 127
fi

case "$mode" in
  normal)
    exec "$notify_send_bin" \
      -a "QuickShell Runtime Shell" \
      -i "preferences-system-notifications" \
      -u normal \
      -A "open=Open Notification Rail" \
      -A "dismiss=Dismiss" \
      "$title" \
      "$body"
    ;;
  critical)
    exec "$notify_send_bin" \
      -a "QuickShell Runtime Shell" \
      -i "dialog-warning" \
      -u critical \
      -A "ack=Mark Read" \
      -A "dismiss=Dismiss" \
      "$title" \
      "Critical path test. This should bypass DND and remain until dismissed."
    ;;
  *)
    echo "usage: $0 [normal|critical]" >&2
    exit 2
    ;;
esac
