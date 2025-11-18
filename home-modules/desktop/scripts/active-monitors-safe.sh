#!/usr/bin/env bash
# Wrapper to call active-monitors with a guaranteed SWAYSOCK

set -euo pipefail

if ! command -v sway >/dev/null 2>&1; then
  echo "sway not found" >&2
  exit 1
fi

if [[ -z "${SWAYSOCK:-}" ]]; then
  sock="$(sway --get-socketpath 2>/dev/null || true)"
  if [[ -n "$sock" ]]; then
    export SWAYSOCK="$sock"
  fi
fi

exec "${HOME}/.local/bin/active-monitors" "$@"
