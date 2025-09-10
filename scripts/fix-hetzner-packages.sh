#!/usr/bin/env bash
# ============================================================================
# Package Fix Utility for NixOS on Hetzner
# ============================================================================
# This script fixes common package issues when migrating configurations
# particularly Qt5 to Qt6 migrations for KDE Plasma packages
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration directory
NIXOS_DIR="${1:-/etc/nixos}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_warning "Not running as root, some operations may require sudo"
fi

# Function to fix Qt5 to Qt6 package references
fix_qt_packages() {
    local file="$1"
    local changes_made=false
    
    log_info "Checking $file for Qt5 package references..."
    
    # List of packages that need to be updated
    declare -A package_fixes=(
        ["xdg-desktop-portal-kde"]="kdePackages.xdg-desktop-portal-kde"
        ["kate"]="kdePackages.kate"
        ["konsole"]="kdePackages.konsole"
        ["dolphin"]="kdePackages.dolphin"
        ["ark"]="kdePackages.ark"
        ["spectacle"]="kdePackages.spectacle"
        ["okular"]="kdePackages.okular"
        ["gwenview"]="kdePackages.gwenview"
        ["kdeconnect"]="kdePackages.kdeconnect"
        ["plasma-nm"]="kdePackages.plasma-nm"
        ["plasma-pa"]="kdePackages.plasma-pa"
        ["kwalletmanager"]="kdePackages.kwalletmanager"
        ["ksystemlog"]="kdePackages.ksystemlog"
        ["partitionmanager"]="kdePackages.partitionmanager"
    )
    
    # Check and fix each package
    for old_pkg in "${!package_fixes[@]}"; do
        new_pkg="${package_fixes[$old_pkg]}"
        
        # Check if the old package reference exists
        if grep -q "pkgs\.$old_pkg\|^[[:space:]]*$old_pkg$" "$file"; then
            log_info "  Found $old_pkg, replacing with $new_pkg"
            
            # Replace pkgs.package format
            sed -i "s/pkgs\.$old_pkg/$new_pkg/g" "$file"
            
            # Replace standalone package name (in lists)
            sed -i "s/^[[:space:]]*$old_pkg$/ /' $new_pkg'/g" "$file"
            
            changes_made=true
        fi
    done
    
    if $changes_made; then
        log_success "Fixed Qt package references in $file"
    else
        log_info "  No Qt5 package references found to fix"
    fi
}

# Function to fix deprecated service options
fix_deprecated_options() {
    local file="$1"
    local changes_made=false
    
    log_info "Checking $file for deprecated options..."
    
    # List of deprecated options and their replacements
    declare -A option_fixes=(
        ["services.xserver.displayManager.sddm.enable"]="services.displayManager.sddm.enable"
        ["services.xserver.displayManager.sddm.wayland.enable"]="services.displayManager.sddm.wayland.enable"
        ["services.xserver.displayManager.defaultSession"]="services.displayManager.defaultSession"
        ["services.xserver.desktopManager.plasma6.enable"]="services.desktopManager.plasma6.enable"
        ["hardware.pulseaudio"]="services.pulseaudio"
    )
    
    for old_opt in "${!option_fixes[@]}"; do
        new_opt="${option_fixes[$old_opt]}"
        
        if grep -q "$old_opt" "$file"; then
            log_info "  Found deprecated option: $old_opt"
            log_info "  Replacing with: $new_opt"
            
            sed -i "s/$old_opt/$new_opt/g" "$file"
            changes_made=true
        fi
    done
    
    if $changes_made; then
        log_success "Fixed deprecated options in $file"
    else
        log_info "  No deprecated options found to fix"
    fi
}

# Function to ensure essential services are configured
ensure_essential_services() {
    local file="$1"
    
    log_info "Ensuring essential services are configured in $file..."
    
    # Check for SSH
    if ! grep -q "services.openssh.enable" "$file"; then
        log_warning "SSH service not found, adding it..."
        echo -e "\n  # SSH service (added by fix script)\n  services.openssh.enable = true;" >> "$file"
    fi
    
    # Check for networking
    if ! grep -q "networking.useDHCP" "$file"; then
        log_warning "DHCP not configured, adding it..."
        echo -e "\n  # Networking (added by fix script)\n  networking.useDHCP = true;" >> "$file"
    fi
    
    log_success "Essential services check complete"
}

# Function to validate configuration
validate_configuration() {
    local config_dir="$1"
    
    log_info "Validating NixOS configuration..."
    
    cd "$config_dir"
    
    # Check if it's a flake-based configuration
    if [[ -f "flake.nix" ]]; then
        log_info "Flake configuration detected"
        
        # Check if git repo is initialized
        if [[ ! -d ".git" ]]; then
            log_warning "Git repository not initialized, initializing..."
            git init
        fi
        
        # Check for unstaged changes
        if git diff --quiet && git diff --cached --quiet; then
            log_info "No unstaged changes"
        else
            log_warning "Unstaged changes detected, staging them..."
            git add -A
            git commit -m "Auto-commit by fix script $(date +%Y-%m-%d-%H:%M:%S)" || true
        fi
        
        # Dry build to test configuration
        log_info "Running dry build to test configuration..."
        if sudo nixos-rebuild dry-build --flake .#nixos-hetzner 2>/dev/null; then
            log_success "Configuration validation successful!"
        else
            log_error "Configuration validation failed. Check the errors above."
            return 1
        fi
    else
        # Traditional configuration
        log_info "Traditional configuration detected"
        
        if sudo nixos-rebuild dry-build 2>/dev/null; then
            log_success "Configuration validation successful!"
        else
            log_error "Configuration validation failed. Check the errors above."
            return 1
        fi
    fi
}

# Main function
main() {
    echo "======================================"
    echo "NixOS Package Fix Utility"
    echo "======================================"
    echo ""
    
    # Check if configuration directory exists
    if [[ ! -d "$NIXOS_DIR" ]]; then
        log_error "Configuration directory $NIXOS_DIR not found"
        exit 1
    fi
    
    cd "$NIXOS_DIR"
    
    # Find all .nix files
    log_info "Scanning for NixOS configuration files..."
    mapfile -t nix_files < <(find . -name "*.nix" -type f)
    
    if [[ ${#nix_files[@]} -eq 0 ]]; then
        log_error "No .nix files found in $NIXOS_DIR"
        exit 1
    fi
    
    log_info "Found ${#nix_files[@]} configuration files"
    echo ""
    
    # Process each file
    for file in "${nix_files[@]}"; do
        # Skip hardware-configuration.nix as it's auto-generated
        if [[ "$file" == *"hardware-configuration.nix"* ]]; then
            continue
        fi
        
        echo "Processing: $file"
        echo "----------------------------------------"
        
        # Create backup
        cp "$file" "$file.backup.$(date +%Y%m%d-%H%M%S)"
        
        # Apply fixes
        fix_qt_packages "$file"
        fix_deprecated_options "$file"
        
        # Only check essential services in main configuration files
        if [[ "$file" == *"configuration"*.nix ]]; then
            ensure_essential_services "$file"
        fi
        
        echo ""
    done
    
    # Validate the configuration
    echo "======================================"
    echo "Validation"
    echo "======================================"
    validate_configuration "$NIXOS_DIR"
    
    echo ""
    log_success "Package fix utility completed!"
    echo ""
    echo "Next steps:"
    echo "1. Review the changes made to your configuration"
    echo "2. Run: sudo nixos-rebuild switch --flake .#nixos-hetzner"
    echo "3. If using traditional config: sudo nixos-rebuild switch"
    echo ""
    echo "Backups of original files have been created with .backup.* extension"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [nixos-config-directory]"
        echo ""
        echo "Fixes common package issues in NixOS configuration files,"
        echo "particularly Qt5 to Qt6 migrations for KDE Plasma packages."
        echo ""
        echo "Default directory: /etc/nixos"
        echo ""
        echo "Examples:"
        echo "  $0                    # Fix files in /etc/nixos"
        echo "  $0 /path/to/config    # Fix files in specified directory"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac