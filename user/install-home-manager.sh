#!/usr/bin/env bash
# Portable home-manager installation script for containers
# Works with xtruder/nix-devcontainer and similar nix-enabled containers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Home-Manager Container Installation${NC}"
echo "======================================"

# Check if we're in a container
if [ -f /.dockerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    echo -e "${GREEN}✓${NC} Container environment detected"
else
    echo -e "${YELLOW}⚠${NC} Not in a container, but continuing anyway..."
fi

# Check if nix is available
if ! command -v nix &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Nix is not installed, installing now..."
    
    # Try single-user installation (works in containers)
    if sh <(curl -L https://nixos.org/nix/install) --no-daemon 2>&1 | grep -q "Installation finished"; then
        echo -e "${GREEN}✓${NC} Nix installed successfully"
        
        # Source nix profile
        if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
            . "$HOME/.nix-profile/etc/profile.d/nix.sh"
        fi
        
        # Verify installation
        if ! command -v nix &> /dev/null; then
            echo -e "${RED}✗${NC} Nix installation succeeded but nix command not found"
            echo "Please run: . $HOME/.nix-profile/etc/profile.d/nix.sh"
            exit 1
        fi
    else
        echo -e "${RED}✗${NC} Failed to install Nix"
        echo "Please install Nix manually: https://nixos.org/download.html"
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} Nix is available"
fi

# Set up environment variables
export USER="${USER:-$(whoami)}"
export HOME="${HOME:-/home/$USER}"
export NIX_PATH="${NIX_PATH:-nixpkgs=channel:nixos-unstable}"

# Create necessary directories
mkdir -p "$HOME/.config/home-manager"
mkdir -p "$HOME/.config/nix"

# Configure nix for user with binary caches
cat > "$HOME/.config/nix/nix.conf" << 'EOF'
experimental-features = nix-command flakes
trusted-users = root @wheel
max-jobs = auto
cores = 0
# Use binary caches to avoid building from source in containers
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
# Fallback to building if substitutes fail
fallback = true
# Don't build if substitute is available
prefer-online = true
EOF

echo -e "${GREEN}Setting up Home Manager...${NC}"

# Backup existing shell files BEFORE installing home-manager
if [ -f "$HOME/.bashrc" ] || [ -f "$HOME/.profile" ] || [ -f "$HOME/.bash_profile" ]; then
    echo -e "${YELLOW}Backing up existing shell configuration files...${NC}"
    [ -f "$HOME/.bashrc" ] && mv "$HOME/.bashrc" "$HOME/.bashrc.pre-hm-backup"
    [ -f "$HOME/.profile" ] && mv "$HOME/.profile" "$HOME/.profile.pre-hm-backup"
    [ -f "$HOME/.bash_profile" ] && mv "$HOME/.bash_profile" "$HOME/.bash_profile.pre-hm-backup"
fi

# Check if home-manager is already installed
if command -v home-manager &> /dev/null; then
    echo -e "${GREEN}✓${NC} Home-manager already installed"
else
    # Install home-manager
    nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
    nix-channel --update
    
    # Install home-manager command with backup flag
    nix-shell '<home-manager>' -A install -- -b backup 2>/dev/null || {
        echo -e "${YELLOW}⚠${NC} Initial install method failed, trying alternative..."
        nix run home-manager/master -- init --switch -b backup
    }
fi

echo -e "${GREEN}Installing user packages configuration...${NC}"

# Create a home.nix that imports the complete container configuration
REPO_URL="https://github.com/vpittamp/nixos-config"
BRANCH="container-ssh"

cat > "$HOME/.config/home-manager/home.nix" << EOF
{ config, pkgs, lib, ... }:

let
  # Fetch configuration from GitHub 
  nixosConfig = builtins.fetchTarball {
    url = "$REPO_URL/archive/$BRANCH.tar.gz";
  };
in
{
  # Import the complete container home configuration
  imports = [ "\${nixosConfig}/user/container-home.nix" ];
  
  # Override username and home directory to use current values
  home.username = lib.mkForce "$USER";
  home.homeDirectory = lib.mkForce "$HOME";
}
EOF

echo -e "${GREEN}Applying configuration...${NC}"

# Set environment variable to indicate we're in a container
export NIXOS_CONTAINER=1
export CONTAINER_PROFILE="${CONTAINER_PROFILE:-essential}"

# Apply the configuration with backup flag for safety
# Use --impure to avoid hash mismatch issues with fetchTarball
home-manager switch -b backup --impure

# Source the new configuration
if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo "Available package profiles:"
echo "  - minimal: Basic tools (vim, git, tmux, curl, jq, fzf, ripgrep)"
echo "  - essential: Common development tools (default)"
echo "  - development: Full development environment"
echo ""
echo "To change profile, set CONTAINER_PROFILE and re-run:"
echo "  export CONTAINER_PROFILE=minimal"
echo "  home-manager switch"