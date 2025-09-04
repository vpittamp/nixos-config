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

# Install home-manager
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update

# Install home-manager command
nix-shell '<home-manager>' -A install 2>/dev/null || {
    # Alternative installation method
    nix run home-manager/master -- init --switch
}

echo -e "${GREEN}Fetching configuration from GitHub...${NC}"

# Clone the configuration (using your repo)
REPO_URL="https://github.com/vpittamp/nixos-config.git"
BRANCH="container-ssh"
TEMP_DIR="/tmp/nixos-config-$$"

git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$TEMP_DIR" 2>/dev/null || {
    echo -e "${YELLOW}Using curl fallback...${NC}"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    curl -L "https://github.com/vpittamp/nixos-config/archive/$BRANCH.tar.gz" | tar xz --strip-components=1
}

echo -e "${GREEN}Installing user packages configuration...${NC}"

# Create a minimal home.nix that imports only user packages
cat > "$HOME/.config/home-manager/home.nix" << EOF
{ config, pkgs, lib, ... }:

let
  # Import user packages from the repo
  userPackages = import $TEMP_DIR/user/packages.nix { inherit pkgs lib; };
  
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

# Backup existing files if they exist
if [ -f "$HOME/.bashrc" ] || [ -f "$HOME/.profile" ] || [ -f "$HOME/.bash_profile" ]; then
    echo -e "${YELLOW}Backing up existing shell configuration files...${NC}"
    [ -f "$HOME/.bashrc" ] && mv "$HOME/.bashrc" "$HOME/.bashrc.backup"
    [ -f "$HOME/.profile" ] && mv "$HOME/.profile" "$HOME/.profile.backup"
    [ -f "$HOME/.bash_profile" ] && mv "$HOME/.bash_profile" "$HOME/.bash_profile.backup"
fi

# Apply the configuration
home-manager switch

# Clean up
rm -rf "$TEMP_DIR"

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