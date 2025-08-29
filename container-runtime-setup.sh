#!/bin/bash
# Runtime setup script for NixOS containers
# This script applies home-manager and additional packages after container starts

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FLAKE_URL="${NIXOS_FLAKE_URL:-github:yourusername/nixos-config}"
PROFILE="${NIXOS_PROFILE:-essential}"
SETUP_HOME_MANAGER="${SETUP_HOME_MANAGER:-true}"
INSTALL_PACKAGES="${INSTALL_PACKAGES:-true}"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           NixOS Container Runtime Setup                ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo "Profile: $PROFILE"
echo "Flake: $FLAKE_URL"
echo ""

# Function to setup home-manager for a user
setup_user_home() {
    local username="$1"
    local home_dir="$2"
    
    echo -e "${CYAN}Setting up home-manager for $username...${NC}"
    
    # Ensure user directories exist
    mkdir -p "$home_dir"
    mkdir -p "/nix/var/nix/profiles/per-user/$username"
    mkdir -p "/nix/var/nix/gcroots/per-user/$username"
    
    # Set ownership
    if [ "$username" != "root" ]; then
        chown -R "$username:users" "$home_dir"
        chown -R "$username:users" "/nix/var/nix/profiles/per-user/$username"
        chown -R "$username:users" "/nix/var/nix/gcroots/per-user/$username"
    fi
    
    # Apply home-manager configuration
    if [ -f /etc/nixos/flake.nix ]; then
        # Use local flake if mounted
        echo "Using local flake configuration..."
        
        # Build and activate home-manager configuration
        if [ "$username" = "root" ]; then
            HOME="$home_dir" nix run /etc/nixos#homeConfigurations.vpittamp.activationPackage
        else
            su - "$username" -c "nix run /etc/nixos#homeConfigurations.vpittamp-user.activationPackage"
        fi
    else
        # Use remote flake
        echo "Using remote flake: $FLAKE_URL"
        
        if [ "$username" = "root" ]; then
            HOME="$home_dir" nix run "$FLAKE_URL#homeConfigurations.vpittamp.activationPackage"
        else
            su - "$username" -c "nix run $FLAKE_URL#homeConfigurations.vpittamp-user.activationPackage"
        fi
    fi
    
    echo -e "${GREEN}✓ Home-manager setup complete for $username${NC}"
}

# Function to install additional packages based on profile
install_profile_packages() {
    echo -e "${CYAN}Installing packages for profile: $PROFILE${NC}"
    
    local packages=""
    
    # Base packages (minimal)
    packages="tmux git vim fzf ripgrep fd bat curl wget jq"
    
    # Essential packages
    if [[ "$PROFILE" == *"essential"* ]] || [[ "$PROFILE" == "full" ]]; then
        packages="$packages eza zoxide yq tree htop direnv stow gum"
        packages="$packages nodejs_20 tailscale gh azure-cli"
        
        # AI tools (from overlay)
        echo "Installing AI CLI tools..."
        if [ -f /etc/nixos/flake.nix ]; then
            nix profile install /etc/nixos#gemini-cli
            nix profile install /etc/nixos#claude-cli
            nix profile install /etc/nixos#codex-cli
        fi
    fi
    
    # Development packages
    if [[ "$PROFILE" == *"development"* ]] || [[ "$PROFILE" == "full" ]]; then
        packages="$packages python3 go rustc gcc gnumake cmake"
        packages="$packages docker-compose postgresql-client redis mysql-client"
    fi
    
    # Kubernetes packages
    if [[ "$PROFILE" == *"kubernetes"* ]] || [[ "$PROFILE" == "full" ]]; then
        packages="$packages kubectl helm k9s kubectx stern"
        packages="$packages argocd flux kustomize"
    fi
    
    # Install packages
    for pkg in $packages; do
        echo "Installing $pkg..."
        nix profile install "nixpkgs#$pkg" 2>/dev/null || echo "  Warning: Failed to install $pkg"
    done
    
    echo -e "${GREEN}✓ Package installation complete${NC}"
}

# Function to create initialization marker
mark_initialized() {
    echo "$(date)" > /etc/nixos-container-initialized
    echo "Profile: $PROFILE" >> /etc/nixos-container-initialized
    echo -e "${GREEN}✓ Container initialization complete${NC}"
}

# Check if already initialized
if [ -f /etc/nixos-container-initialized ]; then
    echo -e "${YELLOW}Container already initialized. To re-run setup, delete /etc/nixos-container-initialized${NC}"
    exit 0
fi

# Main setup flow
echo -e "${BLUE}Starting runtime setup...${NC}"

# 1. Setup Nix environment
export NIX_REMOTE=""
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# 2. Update Nix channels (optional)
echo "Updating Nix channels..."
nix-channel --update 2>/dev/null || true

# 3. Setup home-manager for users
if [ "$SETUP_HOME_MANAGER" = "true" ]; then
    setup_user_home "root" "/root"
    setup_user_home "code" "/home/code"
    setup_user_home "vpittamp" "/home/vpittamp"
fi

# 4. Install additional packages
if [ "$INSTALL_PACKAGES" = "true" ]; then
    install_profile_packages
fi

# 5. Mark as initialized
mark_initialized

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         Container setup complete!                      ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "To manually install packages:"
echo "  nix profile install nixpkgs#<package>"
echo ""
echo "To update home-manager configuration:"
echo "  home-manager switch --flake /etc/nixos#vpittamp"