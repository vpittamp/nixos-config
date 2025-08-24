#!/bin/bash
set -e

# Script to activate NixOS home-manager configuration in devcontainer
echo "NixOS Configuration Activation Script"
echo "======================================"

# Check if we should activate
if [ "${NIXOS_CONFIG_ACTIVATE}" != "true" ]; then
    echo "NIXOS_CONFIG_ACTIVATE not set to true, skipping activation"
    exit 0
fi

# Configuration source - can be a local path or GitHub repo
NIXOS_CONFIG_SOURCE="${NIXOS_CONFIG_SOURCE:-/etc/nixos}"
NIXOS_CONFIG_GITHUB="${NIXOS_CONFIG_GITHUB:-}"

# If GitHub repo is specified, clone it
if [ -n "$NIXOS_CONFIG_GITHUB" ]; then
    echo "Using NixOS configuration from GitHub: $NIXOS_CONFIG_GITHUB"
    
    # Clone to a temporary location
    CONFIG_DIR="/tmp/nixos-config"
    if [ -d "$CONFIG_DIR" ]; then
        echo "Updating existing configuration..."
        cd "$CONFIG_DIR"
        git pull
    else
        echo "Cloning configuration..."
        git clone "$NIXOS_CONFIG_GITHUB" "$CONFIG_DIR"
    fi
    
    # Use the cloned directory
    NIXOS_CONFIG_SOURCE="$CONFIG_DIR"
    cd "$CONFIG_DIR"
elif [ -d "$NIXOS_CONFIG_SOURCE" ]; then
    echo "Using local NixOS configuration from: $NIXOS_CONFIG_SOURCE"
    cd "$NIXOS_CONFIG_SOURCE"
else
    echo "Warning: No NixOS configuration found."
    echo "Set NIXOS_CONFIG_GITHUB to a GitHub repo URL or mount config to $NIXOS_CONFIG_SOURCE"
    exit 0
fi

# Check if flake.nix exists
if [ ! -f "$NIXOS_CONFIG_SOURCE/flake.nix" ]; then
    echo "Warning: flake.nix not found in $NIXOS_CONFIG_SOURCE. This script requires a flake-based configuration."
    exit 0
fi

# Get the current user
USER=${USER:-$(whoami)}
echo "Activating configuration for user: $USER"

# Set package selection from environment
export NIXOS_PACKAGES="${NIXOS_PACKAGES:-essential}"
echo "Using package set: $NIXOS_PACKAGES"

# Already in the correct directory from earlier cd command

# Check if the flake has the expected home configuration
echo "Checking flake configuration..."
if nix flake show --json 2>/dev/null | grep -q "homeConfigurations.$USER"; then
    echo "Found home configuration for $USER"
    
    # Build the home-manager activation package
    echo "Building home-manager activation package..."
    echo "This may take a few minutes on first run..."
    
    # Build the activation package
    if nix build .#homeConfigurations.$USER.activationPackage --no-link --print-out-paths; then
        ACTIVATION_PATH=$(nix build .#homeConfigurations.$USER.activationPackage --no-link --print-out-paths 2>/dev/null)
        
        if [ -n "$ACTIVATION_PATH" ] && [ -x "$ACTIVATION_PATH/activate" ]; then
            echo "Running home-manager activation..."
            
            # Create necessary directories
            mkdir -p $HOME/.config
            mkdir -p $HOME/.local/state/nix/profiles
            
            # Run the activation
            $ACTIVATION_PATH/activate || {
                echo "Warning: Some activation steps failed, but continuing..."
            }
            
            echo "Home-manager activation complete!"
            
            # Source the new environment
            if [ -f "$HOME/.bashrc" ]; then
                source "$HOME/.bashrc"
            fi
            
            # Update PATH to include home-manager managed programs
            export PATH="$HOME/.nix-profile/bin:$PATH"
            
            echo "Environment updated with home-manager packages"
        else
            echo "Error: Could not find activation script at $ACTIVATION_PATH"
        fi
    else
        echo "Error: Failed to build home-manager activation package"
        echo "You may need to update flake inputs or check for errors in your configuration"
    fi
else
    echo "Warning: No home configuration found for $USER in flake"
    echo "Available configurations:"
    nix flake show --json 2>/dev/null | jq -r '.homeConfigurations | keys[]' 2>/dev/null || echo "Could not list configurations"
fi

# Alternative: Try to use home-manager directly if installed
if command -v home-manager >/dev/null 2>&1; then
    echo "home-manager command is available as fallback"
fi

echo "Activation script complete"