#!/usr/bin/env bash
# Flake-based home-manager installation for containers
# More reproducible and simpler than channel-based approach

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Flake-based Home Manager Container Installation${NC}"
echo "================================================="

# Check if we're in a container
if [ -f /.dockerenv ] || [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    echo -e "${GREEN}✓${NC} Container environment detected"
else
    echo -e "${YELLOW}⚠${NC} Not in a container, but continuing anyway..."
fi

# Check if nix is available
if ! command -v nix &> /dev/null; then
    echo -e "${RED}✗${NC} Nix is not installed"
    echo "Installing Nix with Determinate Systems installer..."
    
    # Use Determinate Systems installer for better container support
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
    
    # Source nix
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    
    if ! command -v nix &> /dev/null; then
        echo -e "${RED}✗${NC} Nix installation failed"
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} Nix is available"
fi

# Enable flakes if not already enabled
echo -e "${GREEN}Configuring Nix with flakes support...${NC}"
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf << 'EOF'
experimental-features = nix-command flakes
# Use binary caches
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
# Performance settings
max-jobs = auto
cores = 0
connect-timeout = 5
fallback = true
EOF

# Set up environment
export USER="${USER:-$(whoami)}"
export HOME="${HOME:-/home/$USER}"

# Determine profile
PROFILE="${1:-essential}"
echo -e "${GREEN}Using profile: $PROFILE${NC}"

# GitHub repository with flake - use the actual repo path
FLAKE_REF="github:vpittamp/nixos-config/container-ssh?dir=user"
FLAKE_URL="${FLAKE_REF}#homeConfigurations.container-${PROFILE}.activationPackage"

echo -e "${GREEN}Installing Home Manager configuration...${NC}"
echo "Using flake: ${FLAKE_URL}"

# Backup existing shell files
if [ -f "$HOME/.bashrc" ] || [ -f "$HOME/.profile" ] || [ -f "$HOME/.bash_profile" ]; then
    echo -e "${YELLOW}Backing up existing shell configuration files...${NC}"
    [ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$HOME/.bashrc.backup-$(date +%s)" 2>/dev/null || true
    [ -f "$HOME/.profile" ] && cp "$HOME/.profile" "$HOME/.profile.backup-$(date +%s)" 2>/dev/null || true  
    [ -f "$HOME/.bash_profile" ] && cp "$HOME/.bash_profile" "$HOME/.bash_profile.backup-$(date +%s)" 2>/dev/null || true
fi

# Build the configuration first
echo -e "${GREEN}Building configuration...${NC}"
RESULT=$(nix build "$FLAKE_URL" --no-link --print-out-paths 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}✗${NC} Failed to build configuration"
    echo "$RESULT"
    exit 1
fi

# Extract the actual path from the output (last line)
ACTIVATION_PATH=$(echo "$RESULT" | tail -n1)

# Create a wrapper script that sets USER and HOME before activation
echo -e "${GREEN}Creating activation wrapper...${NC}"
cat > /tmp/activate-home-manager.sh << EOF
#!/usr/bin/env bash
export USER="$USER"
export HOME="$HOME"
"$ACTIVATION_PATH/activate"
EOF
chmod +x /tmp/activate-home-manager.sh

# Run the activation with proper environment
echo -e "${GREEN}Activating home-manager configuration...${NC}"
/tmp/activate-home-manager.sh

# Clean up
rm -f /tmp/activate-home-manager.sh

# Source the new configuration
if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi

echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo "Available profiles:"
echo "  - minimal: Basic tools only"
echo "  - essential: Common development tools (default)"
echo "  - development: Full development environment"
echo "  - ai: AI assistants (claude-code, etc)"
echo ""
echo "To install a different profile, run:"
echo "  curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-flake.sh | bash -s <profile>"
echo ""
echo "Or if you have the script locally:"
echo "  ./install-flake.sh <profile>"
echo ""
echo "To update your configuration later:"
echo "  nix run github:vpittamp/nixos-config/container-ssh?dir=user#homeConfigurations.container-<profile>.activationPackage"