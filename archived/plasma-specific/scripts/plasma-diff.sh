#!/usr/bin/env bash
# Show what changed in the plasma snapshot compared to git HEAD
#
# Usage:
#   scripts/plasma-diff.sh                     # Show full diff
#   scripts/plasma-diff.sh --summary          # Show summary only
#   scripts/plasma-diff.sh --config-files     # Show which config files changed
#
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="$(dirname "$SCRIPT_DIR")"
SNAPSHOT_FILE="home-modules/desktop/generated/plasma-rc2nix.nix"

cd "$NIXOS_DIR"

# Check if file has changes
if ! git diff --quiet "$SNAPSHOT_FILE" 2>/dev/null; then
  HAS_CHANGES=true
else
  HAS_CHANGES=false
fi

# Parse command line arguments
MODE="${1:-full}"

case "$MODE" in
  --summary)
    if [[ "$HAS_CHANGES" == "false" ]]; then
      echo "No changes in plasma snapshot"
      exit 0
    fi

    echo "=== Plasma Snapshot Changes Summary ==="
    echo ""
    echo "Changed config files:"
    git diff "$SNAPSHOT_FILE" | grep -E '^\+\s+\w+rc = \{|^\-\s+\w+rc = \{' | sed 's/[+-]\s*//' | sort -u | sed 's/ = {//' || echo "  (none)"
    echo ""
    echo "Stats:"
    git diff --numstat "$SNAPSHOT_FILE" | awk '{print "  +" $1 " lines added, -" $2 " lines removed"}'
    echo ""
    echo "Run 'scripts/plasma-diff.sh' to see full diff"
    ;;

  --config-files)
    if [[ "$HAS_CHANGES" == "false" ]]; then
      echo "No changes"
      exit 0
    fi

    echo "Config files that changed:"
    git diff "$SNAPSHOT_FILE" | grep -E '^\+\s+\w+rc = \{|^\-\s+\w+rc = \{' | sed 's/[+-]\s*//' | sort -u | sed 's/ = {//'
    ;;

  --help|-h)
    echo "Usage: scripts/plasma-diff.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (none)           Show full diff"
    echo "  --summary        Show summary of changes"
    echo "  --config-files   List changed config files"
    echo "  --help           Show this help"
    ;;

  *)
    if [[ "$HAS_CHANGES" == "false" ]]; then
      echo "No changes in plasma snapshot since last commit"
      exit 0
    fi

    echo "=== Plasma Snapshot Diff ==="
    echo ""
    git diff "$SNAPSHOT_FILE"
    ;;
esac
