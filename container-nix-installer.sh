#!/usr/bin/env bash
# Lightweight Nix installer for containers
# Can use either regular Nix or Determinate Systems installer

set -euo pipefail

# Configuration
NIX_INSTALLER_TYPE="${NIX_INSTALLER_TYPE:-determinate}" # "determinate" or "regular"
NIX_BUILD_GROUP_ID="30000"
NIX_BUILD_GROUP_NAME="nixbld"
NIX_FIRST_BUILD_UID="30001"
NIX_BUILD_USER_COUNT="32"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[nix-installer]${NC} $*"
}

error() {
    echo -e "${RED}[nix-installer]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[nix-installer]${NC} $*"
}

# Check if Nix is already installed
check_existing_nix() {
    if [ -d /nix/store ] && command -v nix &>/dev/null; then
        log "Nix is already installed"
        nix --version
        return 0
    fi
    return 1
}

# Install using Determinate Systems installer
install_determinate_nix() {
    log "Installing Nix using Determinate Systems installer..."
    
    # Download and run the installer
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
        sh -s -- install linux \
            --no-confirm \
            --init none \
            --extra-conf "sandbox = false" \
            --extra-conf "experimental-features = nix-command flakes" \
            --extra-conf "trusted-users = root @wheel" \
            --extra-conf "max-jobs = auto" \
            --extra-conf "cores = 0" \
            --extra-conf "narinfo-cache-negative-ttl = 0"
    
    log "Determinate Nix installation complete"
}

# Install using regular Nix installer
install_regular_nix() {
    log "Installing Nix using regular installer..."
    
    # Create build users (required for multi-user installation)
    create_build_users() {
        log "Creating Nix build users..."
        
        # Create nixbld group
        if ! getent group "$NIX_BUILD_GROUP_NAME" &>/dev/null; then
            groupadd -g "$NIX_BUILD_GROUP_ID" "$NIX_BUILD_GROUP_NAME"
        fi
        
        # Create build users
        for i in $(seq 1 "$NIX_BUILD_USER_COUNT"); do
            username="${NIX_BUILD_GROUP_NAME}${i}"
            uid=$((NIX_FIRST_BUILD_UID + i - 1))
            
            if ! id "$username" &>/dev/null; then
                useradd \
                    --home-dir /var/empty \
                    --comment "Nix build user $i" \
                    --gid "$NIX_BUILD_GROUP_ID" \
                    --groups "$NIX_BUILD_GROUP_NAME" \
                    --no-user-group \
                    --system \
                    --shell /sbin/nologin \
                    --uid "$uid" \
                    "$username"
            fi
        done
    }
    
    # For containers, use single-user installation
    if [ -f /.dockerenv ] || [ -n "${CONTAINER:-}" ]; then
        log "Container detected, using single-user installation"
        
        # Download and run single-user installer
        curl -L https://nixos.org/nix/install | sh -s -- --no-daemon \
            --no-channel-add \
            --no-modify-profile
        
        # Add configuration
        mkdir -p /etc/nix
        cat > /etc/nix/nix.conf <<EOF
sandbox = false
experimental-features = nix-command flakes
trusted-users = root @wheel
max-jobs = auto
cores = 0
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
EOF
    else
        log "Installing multi-user Nix..."
        create_build_users
        
        # Download and run multi-user installer
        curl -L https://nixos.org/nix/install | sh -s -- --daemon
    fi
    
    log "Regular Nix installation complete"
}

# Setup Nix environment
setup_nix_env() {
    log "Setting up Nix environment..."
    
    # Source Nix profile
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    elif [ -f /etc/profile.d/nix.sh ]; then
        . /etc/profile.d/nix.sh
    elif [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    
    # Add channels
    if ! nix-channel --list | grep -q nixpkgs; then
        log "Adding nixpkgs channel..."
        nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
        nix-channel --update
    fi
    
    # Test installation
    log "Testing Nix installation..."
    nix --version
    nix-channel --list
}

# Main installation flow
main() {
    log "Starting Nix installation (type: $NIX_INSTALLER_TYPE)"
    
    # Check if already installed
    if check_existing_nix; then
        warn "Nix is already installed, skipping installation"
        exit 0
    fi
    
    # Check prerequisites
    if ! command -v curl &>/dev/null; then
        error "curl is required but not installed"
        exit 1
    fi
    
    # Install based on type
    case "$NIX_INSTALLER_TYPE" in
        determinate)
            install_determinate_nix
            ;;
        regular)
            install_regular_nix
            ;;
        *)
            error "Unknown installer type: $NIX_INSTALLER_TYPE"
            error "Use 'determinate' or 'regular'"
            exit 1
            ;;
    esac
    
    # Setup environment
    setup_nix_env
    
    log "Nix installation completed successfully!"
    log "Please restart your shell or source the Nix profile to use Nix"
    
    # Provide next steps
    cat <<EOF

${GREEN}Next steps:${NC}
1. Restart your shell or run:
   source /etc/profile.d/nix.sh
   
2. Test Nix:
   nix --version
   nix run nixpkgs#hello
   
3. Install packages:
   nix-env -iA nixpkgs.git
   nix profile install nixpkgs#ripgrep

EOF
}

# Run main function
main "$@"