#!/usr/bin/env bash
# Test script for validating KDE Plasma optimization configuration
# Task: T039 - Create dry-build test script
# Purpose: Verify configuration compiles without applying changes

set -euo pipefail

echo "=== KDE Plasma Optimization Configuration Test ==="
echo ""

# Detect which configuration to test
# Default to hetzner if not specified
TARGET="${1:-hetzner}"

echo "Testing configuration: $TARGET"
echo ""

# Run dry-build
echo "Running nixos-rebuild dry-build..."
echo "This will check if the configuration compiles without applying changes."
echo ""

if nixos-rebuild dry-build --flake ".#${TARGET}"; then
    echo ""
    echo "✅ Dry-build successful - configuration is valid"
    echo ""
    echo "Configuration can be applied with:"
    echo "  sudo nixos-rebuild switch --flake .#${TARGET}"
    echo ""
    exit 0
else
    echo ""
    echo "✗ Dry-build failed - configuration has errors"
    echo ""
    echo "Please fix the errors above before deploying."
    echo ""
    exit 1
fi
