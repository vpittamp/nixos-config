#!/usr/bin/env bash
# Update PWA scope in the firefoxpwa config
# This script updates the scope for specific PWAs to allow OAuth redirects

set -euo pipefail

CONFIG_FILE="$HOME/.local/share/firefoxpwa/config.json"
BACKUP_FILE="$HOME/.local/share/firefoxpwa/config.json.backup-$(date +%Y%m%d-%H%M%S)"

usage() {
  cat << 'USAGE'
Update PWA scope for OAuth compatibility

Usage: update-pwa-scope.sh [PWA_ID] [SCOPE]

Arguments:
  PWA_ID    The ULID of the PWA to update (e.g., 01K772Z7AY5J36Q3NXHH9RYGC0)
  SCOPE     The new scope value (default: "/")

Examples:
  # Update GitHub Codespaces to allow all domains
  update-pwa-scope.sh 01K772Z7AY5J36Q3NXHH9RYGC0 "/"

  # Restore to domain-specific scope
  update-pwa-scope.sh 01K772Z7AY5J36Q3NXHH9RYGC0 "https://github.com/"

Notes:
  - This updates the runtime config at ~/.local/share/firefoxpwa/config.json
  - For permanent changes, edit /etc/nixos/home-modules/tools/pwa-sites.nix
  - PWA must be restarted for changes to take effect
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

PWA_ID="${1:-01K772Z7AY5J36Q3NXHH9RYGC0}"  # Default to GitHub Codespaces
SCOPE="${2:-/}"  # Default to unrestricted scope

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: firefoxpwa config not found at $CONFIG_FILE"
  echo "Run 'pwa-install-all' first to install PWAs"
  exit 1
fi

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed"
  exit 1
fi

# Verify PWA exists
if ! jq -e ".sites.\"$PWA_ID\"" "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "Error: PWA ID '$PWA_ID' not found in config"
  echo ""
  echo "Available PWA IDs:"
  jq -r '.sites | keys[]' "$CONFIG_FILE" | sed 's/^/  /'
  exit 1
fi

# Get PWA name for display
PWA_NAME=$(jq -r ".sites.\"$PWA_ID\".config.name" "$CONFIG_FILE")

echo "Backing up config to $BACKUP_FILE"
cp "$CONFIG_FILE" "$BACKUP_FILE"

echo "Updating '$PWA_NAME' scope to: $SCOPE"
jq ".sites.\"$PWA_ID\".manifest.scope = \"$SCOPE\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "✓ Scope updated successfully!"
echo ""
echo "To apply changes, restart the PWA:"
echo "  pkill -f 'FFPWA-$PWA_ID'"
echo "  firefoxpwa site launch $PWA_ID"
echo ""
echo "Note: For permanent configuration, edit:"
echo "  /etc/nixos/home-modules/tools/pwa-sites.nix"
echo "  and add: scope = \"$SCOPE\";"
