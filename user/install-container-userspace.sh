#!/usr/bin/env bash
# User-space installation script for Home Manager in restricted containers
# This version works without root/sudo by using a user-space Nix installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Container Home Manager Installation (User-space)${NC}"
echo "=================================================="

# Determine profile (default to essential)
PROFILE="${1:-essential}"

# Valid profiles
case "$PROFILE" in
    minimal|essential|development|ai)
        echo -e "${GREEN}Using profile: $PROFILE${NC}"
        ;;
    *)
        echo -e "${RED}Invalid profile: $PROFILE${NC}"
        echo "Available profiles: minimal, essential, development, ai"
        exit 1
        ;;
esac

# Set up environment
export USER="${USER:-code}"
export HOME="${HOME:-/home/$USER}"
export NIX_USER_CONF_FILES="$HOME/.config/nix/nix.conf"

echo "User: $USER"
echo "Home: $HOME"

# Ensure directories exist
mkdir -p "$HOME"
mkdir -p "$HOME/.config/nix"

# Check if nix is installed
if ! command -v nix &> /dev/null; then
    echo -e "${YELLOW}Nix not found. Installing user-space Nix...${NC}"
    
    # Create a local directory for Nix
    export NIX_ROOT="$HOME/.local/nix"
    mkdir -p "$NIX_ROOT"
    
    # Try portable Nix installation
    echo "Attempting portable Nix installation..."
    
    # Download and extract portable Nix
    TEMP_NIX=$(mktemp -d)
    cd "$TEMP_NIX"
    
    # Download static Nix binary
    echo "Downloading Nix static binary..."
    curl -L https://releases.nixos.org/nix/nix-2.18.1/nix-2.18.1-x86_64-linux.tar.xz | tar xJ
    
    # Set up paths
    export PATH="$TEMP_NIX/nix-2.18.1-x86_64-linux/bin:$PATH"
    
    # Create basic Nix configuration
    cat > "$HOME/.config/nix/nix.conf" << 'EOF'
experimental-features = nix-command flakes
sandbox = false
build-users-group = 
trusted-users = root
allowed-users = *
EOF
    
    # Initialize Nix store in user directory
    export NIX_STORE_DIR="$HOME/.nix-store"
    export NIX_STATE_DIR="$HOME/.nix-state"
    export NIX_LOG_DIR="$HOME/.nix-log"
    export NIX_CONF_DIR="$HOME/.config/nix"
    
    mkdir -p "$NIX_STORE_DIR" "$NIX_STATE_DIR" "$NIX_LOG_DIR"
    
    # Check if nix works
    if nix --version &> /dev/null; then
        echo -e "${GREEN}✓ Portable Nix setup successful${NC}"
    else
        echo -e "${RED}Cannot install Nix in this restricted container.${NC}"
        echo ""
        echo "This container has security restrictions that prevent Nix installation."
        echo "Please use a container image with Nix pre-installed:"
        echo "  - nixos/nix:latest"
        echo "  - xtruder/nix-devcontainer:latest"
        echo ""
        echo "Or ask your administrator to:"
        echo "  1. Disable 'no new privileges' flag"
        echo "  2. Allow sudo/root access"
        echo "  3. Use a less restricted security context"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Nix is already installed${NC}"
fi

# Enable flakes
echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"

# Clone the repository to a temporary location
TEMP_DIR=$(mktemp -d)
echo -e "${GREEN}Cloning configuration repository...${NC}"
git clone -b container-ssh --depth 1 https://github.com/vpittamp/nixos-config.git "$TEMP_DIR" 2>/dev/null || {
    echo -e "${RED}Failed to clone repository${NC}"
    exit 1
}

# Navigate to the user directory
cd "$TEMP_DIR/user"

# Backup existing shell files if they exist
BACKUP_SUFFIX=".backup-$(date +%s)"
if [ -f "$HOME/.bashrc" ] || [ -f "$HOME/.profile" ] || [ -f "$HOME/.bash_profile" ]; then
    echo -e "${YELLOW}Backing up existing shell configuration files...${NC}"
    [ -f "$HOME/.bashrc" ] && { mv "$HOME/.bashrc" "$HOME/.bashrc${BACKUP_SUFFIX}"; echo "  Backed up .bashrc"; }
    [ -f "$HOME/.profile" ] && { mv "$HOME/.profile" "$HOME/.profile${BACKUP_SUFFIX}"; echo "  Backed up .profile"; }
    [ -f "$HOME/.bash_profile" ] && { mv "$HOME/.bash_profile" "$HOME/.bash_profile${BACKUP_SUFFIX}"; echo "  Backed up .bash_profile"; }
fi

# Also backup any other files that might conflict
[ -f "$HOME/.gitconfig" ] && { mv "$HOME/.gitconfig" "$HOME/.gitconfig${BACKUP_SUFFIX}"; echo "  Backed up .gitconfig"; }
[ -d "$HOME/.config/nvim" ] && { mv "$HOME/.config/nvim" "$HOME/.config/nvim${BACKUP_SUFFIX}"; echo "  Backed up .config/nvim"; }

# Build and activate the configuration
echo -e "${GREEN}Building configuration...${NC}"
nix run ".#homeConfigurations.container-${PROFILE}.activationPackage" \
    --extra-experimental-features "nix-command flakes" \
    --accept-flake-config

# Source the new environment
if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi

# Clean up
rm -rf "$TEMP_DIR"

echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo "Installed profile: $PROFILE"
echo ""

# Profile-specific messages
case "$PROFILE" in
    ai|essential|development)
        echo "AI tools installed (via native home-manager):"
        echo "  - claude-code (use 'claude' command)"
        echo "  - gemini-cli (use 'gemini' command)"
        echo "  - codex (use 'codex' command)"
        echo "  - aichat (multi-model chat)"
        echo "  - Node.js for MCP servers"
        echo "  - Chromium for browser automation"
        echo ""
        echo "To configure OAuth authentication:"
        echo "  claude login      # For Claude"
        echo "  gemini           # For Gemini (select login option)"
        echo "  codex auth       # For Codex"
        ;;
    minimal)
        echo "Minimal tools installed."
        echo "Does not include AI assistants."
        ;;
esac

echo ""
echo "To reload your environment:"
echo "  source ~/.bashrc"