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
# Detect the actual user and home directory
if [ -n "${USER}" ] && [ -n "${HOME}" ]; then
    # Use provided values
    export USER="${USER}"
    export HOME="${HOME}"
else
    # Auto-detect from current user
    export USER="$(whoami)"
    export HOME="$(eval echo ~$USER)"
fi

echo "User: $USER"
echo "Home: $HOME"
echo "UID: $(id -u)"
echo "GID: $(id -g)"

# Ensure home directory exists and is writable
if [ ! -d "$HOME" ]; then
    echo -e "${YELLOW}Home directory doesn't exist, creating...${NC}"
    mkdir -p "$HOME" 2>/dev/null || {
        echo -e "${RED}Cannot create home directory (running as non-root?)${NC}"
        # Use temp directory as fallback
        export HOME="/tmp/nixuser-$USER"
        mkdir -p "$HOME"
        echo "Using temporary home: $HOME"
    }
fi

# Detect and set up Nix environment
echo -e "${GREEN}Detecting Nix installation...${NC}"

# Common Nix locations in different containers
NIX_LOCATIONS=(
    "/usr/bin/nix"                          # nixpkgs/nix
    "/root/.nix-profile/bin/nix"            # nixos/nix (as root)
    "$HOME/.nix-profile/bin/nix"            # xtruder/nix-devcontainer, user installs
    "/nix/var/nix/profiles/default/bin/nix" # system-wide install
    "/home/nixuser/.nix-profile/bin/nix"    # custom images
    "/home/code/.nix-profile/bin/nix"       # xtruder specific
)

# Find nix
NIX_FOUND=""
for nix_path in "${NIX_LOCATIONS[@]}"; do
    if [ -f "$nix_path" ]; then
        NIX_FOUND="$nix_path"
        echo "  Found nix at: $nix_path"
        break
    fi
done

# If not found in standard locations, search PATH
if [ -z "$NIX_FOUND" ] && command -v nix &> /dev/null; then
    NIX_FOUND=$(command -v nix)
    echo "  Found nix in PATH: $NIX_FOUND"
fi

# If still not found, search filesystem
if [ -z "$NIX_FOUND" ]; then
    echo "  Searching for nix installation..."
    NIX_FOUND=$(find / -name nix -type f -executable 2>/dev/null | grep -E "bin/nix$" | head -1)
fi

if [ -z "$NIX_FOUND" ]; then
    echo -e "${RED}✗ Nix not found in container${NC}"
    echo ""
    echo "This container doesn't have Nix installed."
    echo "Please use one of these container images:"
    echo "  • nixos/nix:latest (recommended)"
    echo "  • nixpkgs/nix-flakes:latest"
    echo "  • xtruder/nix-devcontainer:latest"
    echo ""
    echo "Or build a custom image with Nix included."
    exit 1
fi

# Set up PATH
export PATH="$(dirname "$NIX_FOUND"):$PATH"

# Source appropriate Nix profiles
if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
elif [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
elif [ -f /etc/profile.d/nix.sh ]; then
    . /etc/profile.d/nix.sh
fi

# Verify nix works
if ! nix --version &> /dev/null; then
    echo -e "${RED}✗ Nix found but not working properly${NC}"
    echo "  Nix location: $NIX_FOUND"
    echo "  PATH: $PATH"
    echo "  Try running: $(dirname "$NIX_FOUND")/nix --version"
    exit 1
fi

echo -e "${GREEN}✓ Nix is available: $(nix --version)${NC}"

# Enable flakes
mkdir -p "$HOME/.config/nix" 2>/dev/null || {
    echo -e "${YELLOW}Cannot create .config/nix directory, skipping user config${NC}"
}

if [ -w "$HOME/.config/nix" ]; then
    if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
        echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
    fi
else
    echo -e "${YELLOW}Nix config directory not writable, using system config${NC}"
    export NIX_CONFIG="experimental-features = nix-command flakes"
fi

# Clone the repository to a temporary location
# For non-root users, ensure temp directory is accessible
TEMP_DIR=$(mktemp -d -p "${TMPDIR:-/tmp}" nixos-config.XXXXXX)
echo -e "${GREEN}Cloning configuration repository...${NC}"

# Check if git is available, if not use nix run
if command -v git &> /dev/null; then
    git clone -b container-ssh --depth 1 https://github.com/vpittamp/nixos-config.git "$TEMP_DIR" 2>/dev/null || {
        echo -e "${RED}Failed to clone repository${NC}"
        exit 1
    }
else
    echo "Git not found, using nix run..."
    nix run nixpkgs#git -- clone -b container-ssh --depth 1 https://github.com/vpittamp/nixos-config.git "$TEMP_DIR" || {
        echo -e "${RED}Failed to clone repository${NC}"
        exit 1
    }
fi

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

# For non-root users, we need to handle activation differently
if [ "$(id -u)" -eq 0 ]; then
    # Running as root (shouldn't happen with our setup)
    nix run ".#homeConfigurations.container-${PROFILE}.activationPackage" \
        --extra-experimental-features "nix-command flakes" \
        --accept-flake-config
else
    # Running as non-root user
    echo "Running as non-root user (UID: $(id -u))..."
    
    # Build the configuration first
    echo "Building home-manager configuration..."
    nix build ".#homeConfigurations.container-${PROFILE}.activationPackage" \
        --extra-experimental-features "nix-command flakes" \
        --accept-flake-config \
        --no-link \
        --print-out-paths > /tmp/activation-path.txt || {
            echo -e "${RED}Failed to build configuration${NC}"
            exit 1
        }
    
    # Run the activation
    ACTIVATION_PATH=$(cat /tmp/activation-path.txt)
    echo "Activating configuration from: $ACTIVATION_PATH"
    "$ACTIVATION_PATH/activate" || {
        echo -e "${YELLOW}Activation completed with warnings${NC}"
    }
fi

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
        echo "To configure API keys:"
        echo "  export ANTHROPIC_API_KEY='your-key-here'  # For Claude"
        echo "  export GEMINI_API_KEY='your-key-here'     # For Gemini"
        echo "  export OPENAI_API_KEY='your-key-here'     # For GPT/Codex"
        ;;
    minimal)
        echo "Minimal tools installed."
        echo "Does not include AI assistants."
        ;;
esac

echo ""
echo "To reload your environment:"
echo "  source ~/.bashrc"