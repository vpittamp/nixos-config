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
    echo -e "${RED}✗${NC} Nix is not installed or not in PATH"
    exit 1
fi
echo -e "${GREEN}✓${NC} Nix is available"

# Set up environment variables
export USER="${USER:-$(whoami)}"
export HOME="${HOME:-/home/$USER}"
export NIX_PATH="${NIX_PATH:-nixpkgs=channel:nixos-unstable}"

# Create necessary directories
mkdir -p "$HOME/.config/home-manager"
mkdir -p "$HOME/.config/nix"

# Configure nix for user
cat > "$HOME/.config/nix/nix.conf" << 'EOF'
experimental-features = nix-command flakes
trusted-users = root @wheel
max-jobs = auto
cores = 0
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

echo -e "${GREEN}Fetching configuration from GitHub...${NC}"

# Get SHA256 for deterministic fetching
echo -e "${GREEN}Getting configuration hash...${NC}"
REPO_URL="https://github.com/vpittamp/nixos-config"
BRANCH="container-ssh"
TARBALL_URL="$REPO_URL/archive/$BRANCH.tar.gz"

# Calculate sha256 for the tarball
SHA256=$(nix-prefetch-url --unpack "$TARBALL_URL" 2>/dev/null || \
         curl -sL "$TARBALL_URL" | nix hash file --base32 --type sha256 /dev/stdin)

if [ -z "$SHA256" ]; then
    echo -e "${RED}✗${NC} Failed to get configuration hash"
    exit 1
fi

echo -e "${GREEN}✓${NC} Configuration hash: $SHA256"

echo -e "${GREEN}Installing user packages configuration...${NC}"

# Create a minimal home.nix that imports only user packages
cat > "$HOME/.config/home-manager/home.nix" << EOF
{ config, pkgs, lib, ... }:

let
  # Fetch configuration from GitHub with sha256 for pure evaluation
  nixosConfig = builtins.fetchTarball {
    url = "$TARBALL_URL";
    sha256 = "$SHA256";
  };
  
  # Import user packages from the fetched repo
  userPackages = import "\${nixosConfig}/user/packages.nix" { inherit pkgs lib; };
  
  # For containers, use minimal or essential profile
  packageProfile = if (builtins.getEnv "CONTAINER_PROFILE") == "minimal" 
    then userPackages.minimal
    else userPackages.essential;
in
{
  # Basic home-manager configuration
  home.username = "$USER";
  home.homeDirectory = "$HOME";
  home.stateVersion = "24.05";
  
  # Install user packages (safe for containers)
  home.packages = packageProfile;
  
  # Basic program configurations
  programs.home-manager.enable = true;
  programs.git.enable = true;
  programs.bash.enable = true;
  
  # Basic bash configuration
  programs.bash = {
    enableCompletion = true;
    sessionVariables = {
      EDITOR = "vim";
    };
  };
  
  # Enable direnv for better development experience
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
EOF

echo -e "${GREEN}Applying configuration...${NC}"

# Set environment variable to indicate we're in a container
export NIXOS_CONTAINER=1
export CONTAINER_PROFILE="${CONTAINER_PROFILE:-essential}"

# Apply the configuration with backup flag for safety
home-manager switch -b backup

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