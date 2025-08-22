#!/bin/bash
# Build NixOS containers with unified configuration

set -e

# Default values
PROFILE="${1:-essential}"
OUTPUT_FILE="${2:-}"

echo "🔨 Building NixOS container"
echo "📦 Package profile: $PROFILE"

# Set environment variables for the build
export NIXOS_CONTAINER=1
export NIXOS_PACKAGES="$PROFILE"

# Build the container
cd /etc/nixos
CONTAINER_PATH=$(nix build .#container --no-link --print-out-paths)

# Get container size
SIZE=$(du -sh "$CONTAINER_PATH" | cut -f1)
echo "✅ Container built: $CONTAINER_PATH"
echo "📏 Size: $SIZE"

# Copy to output file if specified
if [ -n "$OUTPUT_FILE" ]; then
    cp "$CONTAINER_PATH" "$OUTPUT_FILE"
    echo "📁 Copied to: $OUTPUT_FILE"
fi

echo ""
echo "Available profiles:"
echo "  essential              - Core tools only (~275MB)"
echo "  essential,kubernetes   - Core + K8s tools (~600MB)"
echo "  essential,development  - Core + dev tools (~600MB)"
echo "  full                   - All packages (~1GB)"
echo ""
echo "Usage: $0 [profile] [output-file]"
echo "Example: $0 'essential,kubernetes' ./my-container.tar.gz"