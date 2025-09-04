#!/usr/bin/env bash
# Simple container installation script for Home Manager configuration
# This script can be run directly in containers or via curl

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Container Home Manager Installation${NC}"
echo "===================================="

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

echo "User: $USER"
echo "Home: $HOME"

# Ensure home directory exists
mkdir -p "$HOME"

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
        echo "AI tools installed:"
        echo "  - claude-code (use 'claude' command)"
        echo "  - Node.js for MCP servers"
        echo "  - Chromium for browser automation"
        echo ""
        echo "To use claude-code:"
        echo "  export ANTHROPIC_API_KEY='your-key-here'"
        echo "  claude"
        ;;
    minimal)
        echo "Minimal tools installed."
        echo "Does not include AI assistants."
        ;;
esac

echo ""
echo "To reload your environment:"
echo "  source ~/.bashrc"