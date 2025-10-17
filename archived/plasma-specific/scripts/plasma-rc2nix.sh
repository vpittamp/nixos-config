#!/usr/bin/env bash
# Export current Plasma settings into a Nix fragment using plasma-manager's rc2nix helper.
#
# Usage:
#   scripts/plasma-rc2nix.sh                    # Export to generated/plasma-rc2nix.nix
#   scripts/plasma-rc2nix.sh --stdout          # Print to stdout (old behavior)
#
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="$NIXOS_DIR/home-modules/desktop/generated/plasma-rc2nix.nix"

if ! command -v nix >/dev/null 2>&1; then
  echo "Error: nix command not found" >&2
  exit 1
fi

# Check if --stdout flag is provided
if [[ "${1:-}" == "--stdout" ]]; then
  exec nix run github:nix-community/plasma-manager -- rc2nix
fi

# Export to file with user feedback
echo "Exporting Plasma configuration via rc2nix..." >&2
echo "Output: $OUTPUT_FILE" >&2

# Create backup of existing file if it exists
if [[ -f "$OUTPUT_FILE" ]]; then
  BACKUP_FILE="$OUTPUT_FILE.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$OUTPUT_FILE" "$BACKUP_FILE"
  echo "Backed up existing file to: $BACKUP_FILE" >&2
fi

# Run rc2nix and save to output file
if nix run github:nix-community/plasma-manager -- rc2nix > "$OUTPUT_FILE"; then
  echo "✓ Export complete!" >&2
  echo "" >&2
  echo "Next steps:" >&2
  echo "  1. Review changes: git diff $OUTPUT_FILE" >&2
  echo "  2. Adopt settings: Edit plasma-config.nix with useful settings" >&2
  echo "  3. Stage changes: git add $OUTPUT_FILE" >&2
else
  echo "Error: rc2nix export failed" >&2
  # Restore backup if export failed
  if [[ -f "$BACKUP_FILE" ]]; then
    mv "$BACKUP_FILE" "$OUTPUT_FILE"
    echo "Restored backup file" >&2
  fi
  exit 1
fi
