#!/bin/bash
# Dynamic container entrypoint that can apply configurations at runtime
# This allows for a lighter base image with runtime customization

set -e

# Environment variables for configuration
RUNTIME_SETUP="${RUNTIME_SETUP:-auto}"  # auto, always, never
NIXOS_PROFILE="${NIXOS_PROFILE:-essential}"
FLAKE_PATH="${FLAKE_PATH:-/etc/nixos}"
HOME_MANAGER_USER="${HOME_MANAGER_USER:-root}"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}NixOS Container Starting...${NC}"
echo "Runtime setup: $RUNTIME_SETUP"
echo "Profile: $NIXOS_PROFILE"

# Function to apply home-manager configuration
apply_home_manager() {
    local user="$1"
    local home_dir="$2"
    
    echo "Applying home-manager for $user..."
    
    if [ -f "$FLAKE_PATH/flake.nix" ]; then
        # Check if home-manager is already activated
        if [ ! -f "$home_dir/.config/home-manager/applied" ]; then
            echo "Activating home-manager configuration..."
            
            # Create necessary directories
            mkdir -p "$home_dir/.config/home-manager"
            mkdir -p "/nix/var/nix/profiles/per-user/$user"
            
            # Apply the configuration
            if [ "$user" = "root" ]; then
                HOME="$home_dir" nix run "$FLAKE_PATH#homeConfigurations.vpittamp.activationPackage" 2>&1 | \
                    grep -v "warning:" || true
            else
                su - "$user" -c "nix run $FLAKE_PATH#homeConfigurations.vpittamp-user.activationPackage" 2>&1 | \
                    grep -v "warning:" || true
            fi
            
            # Mark as applied
            touch "$home_dir/.config/home-manager/applied"
            echo -e "${GREEN}✓ Home-manager activated for $user${NC}"
        else
            echo "Home-manager already activated for $user"
        fi
    else
        echo -e "${YELLOW}Warning: No flake found at $FLAKE_PATH${NC}"
    fi
}

# Function to install profile packages dynamically
install_profile_packages() {
    echo "Installing packages for profile: $NIXOS_PROFILE"
    
    # Check if packages are already installed
    if [ -f /etc/nixos-packages-installed ]; then
        installed_profile=$(cat /etc/nixos-packages-installed)
        if [ "$installed_profile" = "$NIXOS_PROFILE" ]; then
            echo "Packages already installed for profile: $NIXOS_PROFILE"
            return
        fi
    fi
    
    # Source the package list from overlay
    if [ -f "$FLAKE_PATH/overlays/packages.nix" ]; then
        echo "Using flake overlay for package selection..."
        
        # Export profile for overlay to use
        export NIXOS_PACKAGES="$NIXOS_PROFILE"
        
        # Install packages based on profile
        case "$NIXOS_PROFILE" in
            minimal)
                nix profile install nixpkgs#{tmux,git,vim,fzf,ripgrep,fd,bat}
                ;;
            essential)
                nix profile install nixpkgs#{tmux,git,vim,fzf,ripgrep,fd,bat,eza,zoxide,direnv,htop}
                # Install AI tools if available in flake
                nix build "$FLAKE_PATH#gemini-cli" && nix profile install ./result
                nix build "$FLAKE_PATH#claude-cli" && nix profile install ./result
                ;;
            full)
                # Install all packages from overlay
                nix develop "$FLAKE_PATH" --command echo "Full profile packages installed"
                ;;
        esac
    fi
    
    # Mark as installed
    echo "$NIXOS_PROFILE" > /etc/nixos-packages-installed
    echo -e "${GREEN}✓ Packages installed${NC}"
}

# Main execution
main() {
    # Setup Nix environment
    export NIX_REMOTE=""
    export PATH="/nix/var/nix/profiles/default/bin:$PATH:/usr/local/bin"
    
    # Determine if we should run setup
    should_setup=false
    
    case "$RUNTIME_SETUP" in
        always)
            should_setup=true
            ;;
        auto)
            # Setup if not already done
            if [ ! -f /etc/container-initialized ]; then
                should_setup=true
            fi
            ;;
        never)
            should_setup=false
            ;;
    esac
    
    if [ "$should_setup" = true ]; then
        echo -e "${BLUE}Running runtime setup...${NC}"
        
        # Apply home-manager if flake is available
        if [ -d "$FLAKE_PATH" ]; then
            apply_home_manager "root" "/root"
            
            # Apply for other users if they exist
            if id code >/dev/null 2>&1; then
                apply_home_manager "code" "/home/code"
            fi
            
            if id vpittamp >/dev/null 2>&1; then
                apply_home_manager "vpittamp" "/home/vpittamp"
            fi
        fi
        
        # Install profile packages
        install_profile_packages
        
        # Mark as initialized
        touch /etc/container-initialized
        echo -e "${GREEN}✓ Runtime setup complete${NC}"
    fi
    
    # Setup SSH if enabled
    if [ "${CONTAINER_SSH_ENABLED:-false}" = "true" ]; then
        echo "Starting SSH daemon..."
        mkdir -p /run/sshd
        /usr/sbin/sshd -D &
    fi
    
    # Execute the main command or sleep
    if [ $# -gt 0 ]; then
        exec "$@"
    else
        echo -e "${BLUE}Container ready. Sleeping...${NC}"
        exec sleep infinity
    fi
}

# Run main function with all arguments
main "$@"