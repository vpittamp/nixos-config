#!/usr/bin/env bash
# Export current Plasma settings into a Nix fragment using plasma-manager's rc2nix helper.
# Usage: scripts/plasma-rc2nix.sh > plasma-export.nix
set -euo pipefail

if ! command -v nix >/dev/null 2>&1; then
  echo "nix command not found" >&2
  exit 1
fi

exec nix run github:nix-community/plasma-manager -- rc2nix "$@"
