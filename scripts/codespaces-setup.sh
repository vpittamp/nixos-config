#!/usr/bin/env bash
# Codespaces Home Manager Setup Script
# This script prepares a fresh Codespaces environment for home-manager activation

set -e

echo "🔧 Setting up Codespaces environment for home-manager..."

# Check if nix profile has any packages installed
if nix profile list 2>/dev/null | grep -q "home-manager-path"; then
    echo "⚠️  Found existing nix profile packages. Cleaning up..."

    # Remove all packages from the profile
    while nix profile list 2>/dev/null | grep -qE "Index:|home-manager-path"; do
        echo "🗑️  Removing existing profile packages..."
        nix profile remove home-manager-path 2>/dev/null || true

        # Also remove by index if needed
        nix profile list 2>/dev/null | grep "^[0-9]" | awk '{print $1}' | while read -r index; do
            echo "🗑️  Removing package at index $index..."
            nix profile remove "$index" 2>/dev/null || true
        done
    done

    echo "✅ Cleaned up nix profile"
fi

# Check current profile state
echo "📋 Current nix profile state:"
nix profile list 2>/dev/null || echo "  (empty profile - good!)"

# Run home-manager activation
echo ""
echo "🏠 Activating home-manager configuration..."
home-manager switch --flake github:vpittamp/nixos-config#code --impure

echo ""
echo "✅ Setup complete! You may need to restart your shell or source ~/.profile"
echo ""
echo "To verify installation:"
echo "  which kubectl helm az idpbuilder"
