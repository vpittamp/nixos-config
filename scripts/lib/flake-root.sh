#!/usr/bin/env bash
# Feature 106: Portable Flake Root Discovery
#
# This script provides a sourced library for discovering the flake root directory.
# Used by development and test scripts that need to reference repository files.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/flake-root.sh"
#   cd "$FLAKE_ROOT"
#   # ... do stuff relative to FLAKE_ROOT
#
# Or call the function directly:
#   source .../lib/flake-root.sh
#   ROOT=$(get_flake_root)

# Function: get_flake_root
# Returns the absolute path to the flake/repository root
# Priority: FLAKE_ROOT env var > git discovery > /etc/nixos fallback
get_flake_root() {
  # Priority 1: Environment variable (for CI/CD and manual override)
  if [[ -n "${FLAKE_ROOT:-}" ]]; then
    echo "$FLAKE_ROOT"
    return 0
  fi

  # Priority 2: Git repository detection
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
  if [[ -n "$git_root" ]]; then
    echo "$git_root"
    return 0
  fi

  # Priority 3: Default fallback (for deployed systems without git)
  echo "/etc/nixos"
}

# Auto-export FLAKE_ROOT when this script is sourced
# This allows scripts to just source this file and use $FLAKE_ROOT directly
if [[ -z "${FLAKE_ROOT:-}" ]]; then
  FLAKE_ROOT=$(get_flake_root)
fi
export FLAKE_ROOT
