#!/bin/bash
set -e

echo "Starting container initialization..."

# Check if Nix is already installed and working
if [ -f "/nix/var/nix/profiles/default/bin/nix" ] && /nix/var/nix/profiles/default/bin/nix --version &>/dev/null; then
    echo "Nix is already installed and working"
else
    echo "Nix not found or not working, installing..."
    
    # Create necessary directories
    mkdir -p /nix/store /nix/var
    
    # Check if we have the installer
    if [ -f "/opt/nix-installer" ]; then
        echo "Using pre-packaged nix-installer..."
        cp /opt/nix-installer /tmp/nix-installer
        chmod +x /tmp/nix-installer
        
        # Install Nix (single-user mode for non-root)
        /tmp/nix-installer install linux --no-confirm --init none || {
            echo "Installation failed, trying repair..."
            # Try to repair if installation exists but is broken
            /tmp/nix-installer repair --no-confirm || true
        }
    else
        echo "Downloading Determinate Nix installer..."
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
            sh -s -- install linux --no-confirm --init none
    fi
    
    # Set up channels
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
    if nix --version &>/dev/null; then
        echo "Setting up Nix channels..."
        nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs || true
        nix-channel --update || true
    fi
fi

# Source Nix environment
if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
elif [ -f /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
fi

# Export environment
export PATH="/nix/var/nix/profiles/default/bin:/home/nixuser/.nix-profile/bin:$PATH"
export NIX_PATH="nixpkgs=/home/nixuser/.nix-defexpr/channels/nixpkgs"
export NIX_CONFIG="experimental-features = nix-command flakes"

echo "Container initialization complete"
echo "Nix version: $(nix --version 2>/dev/null || echo 'Not installed')"

# Execute the command passed to docker run
exec "$@"