#!/usr/bin/env bash
# ============================================================================
# NixOS Installation Script for Hetzner Cloud Servers
# ============================================================================
# Author: Installation Automation System
# Date: 2025
# Version: 1.0.0
# 
# This script automates the installation of NixOS on Hetzner Cloud servers
# with full desktop environment (KDE Plasma 6) and remote access capabilities.
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration Variables
# ============================================================================

# Git repository containing NixOS configuration
NIXOS_REPO="https://github.com/vpittamp/nixos-config"
NIXOS_BRANCH="m1-installer"

# User configuration
PRIMARY_USER="vpittamp"
PRIMARY_USER_FULLNAME="Vinod Pittampalli"
SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"

# System configuration
HOSTNAME="nixos-hetzner"
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"

# Default passwords (change after installation!)
ROOT_PASSWORD="nixos"
USER_PASSWORD="nixos"

# Disk configuration
DISK="/dev/sda"  # Primary disk on Hetzner (adjust if different)
BOOT_PARTITION="${DISK}1"
ROOT_PARTITION="${DISK}2"
SWAP_PARTITION="${DISK}3"

# Installation paths
MOUNT_POINT="/mnt"
NIXOS_CONFIG_DIR="${MOUNT_POINT}/etc/nixos"

# ============================================================================
# Color Output Functions
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# ============================================================================
# Pre-Installation Checks
# ============================================================================

check_prerequisites() {
    log_info "Performing prerequisite checks..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check if we're in the NixOS installer environment
    if ! command -v nixos-install &> /dev/null; then
        log_error "This script must be run from the NixOS installer environment"
        log_info "Please boot from the NixOS ISO first"
        exit 1
    fi
    
    # Check network connectivity
    log_info "Checking network connectivity..."
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "No internet connection detected"
        exit 1
    fi
    
    # Check if disk exists
    if [[ ! -b "$DISK" ]]; then
        log_error "Disk $DISK not found"
        log_info "Available disks:"
        lsblk
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# ============================================================================
# Disk Partitioning
# ============================================================================

partition_disk() {
    log_info "Partitioning disk $DISK..."
    
    # Warning about data loss
    log_warning "THIS WILL DESTROY ALL DATA ON $DISK!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    # Wipe existing partition table
    log_info "Wiping existing partition table..."
    dd if=/dev/zero of="$DISK" bs=512 count=1 conv=notrunc
    
    # Create new GPT partition table
    log_info "Creating GPT partition table..."
    parted -s "$DISK" mklabel gpt
    
    # Create partitions
    log_info "Creating partitions..."
    
    # Boot partition (512MB, EFI System Partition)
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    
    # Root partition (remaining space minus swap)
    parted -s "$DISK" mkpart primary ext4 513MiB -8GiB
    
    # Swap partition (8GB)
    parted -s "$DISK" mkpart primary linux-swap -8GiB 100%
    
    # Wait for kernel to recognize new partitions
    sleep 2
    partprobe "$DISK"
    
    log_success "Disk partitioned successfully"
}

# ============================================================================
# Filesystem Creation
# ============================================================================

format_partitions() {
    log_info "Formatting partitions..."
    
    # Format boot partition
    log_info "Formatting boot partition..."
    mkfs.fat -F 32 -n BOOT "$BOOT_PARTITION"
    
    # Format root partition
    log_info "Formatting root partition..."
    mkfs.ext4 -L nixos "$ROOT_PARTITION"
    
    # Setup swap
    log_info "Setting up swap..."
    mkswap -L swap "$SWAP_PARTITION"
    
    log_success "Partitions formatted successfully"
}

# ============================================================================
# Mount Filesystems
# ============================================================================

mount_filesystems() {
    log_info "Mounting filesystems..."
    
    # Mount root
    mount "$ROOT_PARTITION" "$MOUNT_POINT"
    
    # Create and mount boot
    mkdir -p "${MOUNT_POINT}/boot"
    mount "$BOOT_PARTITION" "${MOUNT_POINT}/boot"
    
    # Enable swap
    swapon "$SWAP_PARTITION"
    
    log_success "Filesystems mounted"
}

# ============================================================================
# Generate Hardware Configuration
# ============================================================================

generate_hardware_config() {
    log_info "Generating hardware configuration..."
    
    # Create nixos config directory
    mkdir -p "$NIXOS_CONFIG_DIR"
    
    # Generate hardware configuration
    nixos-generate-config --root "$MOUNT_POINT"
    
    # Backup generated hardware configuration
    cp "${NIXOS_CONFIG_DIR}/hardware-configuration.nix" \
       "${NIXOS_CONFIG_DIR}/hardware-configuration.nix.generated"
    
    log_success "Hardware configuration generated"
}

# ============================================================================
# Clone Configuration Repository
# ============================================================================

setup_configuration() {
    log_info "Setting up NixOS configuration..."
    
    # Install git temporarily
    nix-env -iA nixos.git
    
    # Clone repository to temporary location
    local temp_dir="/tmp/nixos-config"
    rm -rf "$temp_dir"
    git clone -b "$NIXOS_BRANCH" "$NIXOS_REPO" "$temp_dir"
    
    # Copy configuration files
    cp -r "$temp_dir"/* "$NIXOS_CONFIG_DIR/"
    
    # Preserve generated hardware configuration
    cp "${NIXOS_CONFIG_DIR}/hardware-configuration.nix.generated" \
       "${NIXOS_CONFIG_DIR}/hardware-configuration.nix"
    
    log_success "Configuration repository cloned"
}

# ============================================================================
# Fix Configuration Issues
# ============================================================================

fix_configuration() {
    log_info "Fixing known configuration issues..."
    
    # Fix Qt5 to Qt6 package references
    local config_file="${NIXOS_CONFIG_DIR}/configuration-hetzner-desktop.nix"
    
    if [[ -f "$config_file" ]]; then
        log_info "Fixing KDE package references..."
        
        # Fix KDE packages
        sed -i 's/pkgs\.xdg-desktop-portal-kde/pkgs.kdePackages.xdg-desktop-portal-kde/g' "$config_file"
        sed -i 's/^    kate$/    kdePackages.kate/' "$config_file"
        sed -i 's/^    konsole$/    kdePackages.konsole/' "$config_file"
        sed -i 's/^    dolphin$/    kdePackages.dolphin/' "$config_file"
        sed -i 's/^    ark$/    kdePackages.ark/' "$config_file"
        sed -i 's/^    spectacle$/    kdePackages.spectacle/' "$config_file"
        
        log_success "Package references fixed"
    fi
    
    # Update hostname
    sed -i "s/networking.hostName = .*/networking.hostName = \"$HOSTNAME\";/" "$config_file"
    
    # Ensure SSH is enabled
    if ! grep -q "services.openssh.enable = true" "$config_file"; then
        echo "services.openssh.enable = true;" >> "$config_file"
    fi
}

# ============================================================================
# Create Minimal Bootstrap Configuration
# ============================================================================

create_bootstrap_config() {
    log_info "Creating bootstrap configuration..."
    
    cat > "${NIXOS_CONFIG_DIR}/configuration.nix" <<EOF
# Minimal NixOS configuration for bootstrap
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Networking
  networking.hostName = "$HOSTNAME";
  networking.useDHCP = true;
  
  # SSH for immediate access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };
  
  # Tailscale for secure access
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
  
  # Time zone
  time.timeZone = "$TIMEZONE";
  
  # Locale
  i18n.defaultLocale = "$LOCALE";
  
  # Users
  users.users.root = {
    initialPassword = "$ROOT_PASSWORD";
    openssh.authorizedKeys.keys = [ "$SSH_KEY" ];
  };
  
  users.users.$PRIMARY_USER = {
    isNormalUser = true;
    description = "$PRIMARY_USER_FULLNAME";
    extraGroups = [ "wheel" ];
    initialPassword = "$USER_PASSWORD";
    openssh.authorizedKeys.keys = [ "$SSH_KEY" ];
  };
  
  # Allow sudo without password for wheel
  security.sudo.wheelNeedsPassword = false;
  
  # Essential packages
  environment.systemPackages = with pkgs; [
    vim git tmux wget curl htop
  ];
  
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  system.stateVersion = "24.11";
}
EOF
    
    log_success "Bootstrap configuration created"
}

# ============================================================================
# Install NixOS
# ============================================================================

install_nixos() {
    log_info "Installing NixOS (this will take a while)..."
    
    # Run installation
    nixos-install --no-root-passwd
    
    log_success "NixOS installed successfully!"
}

# ============================================================================
# Post-Installation Setup
# ============================================================================

post_install_setup() {
    log_info "Performing post-installation setup..."
    
    # Create setup script for after reboot
    cat > "${MOUNT_POINT}/root/complete-setup.sh" <<'SETUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

echo "Completing NixOS setup..."

# Wait for network
sleep 10

# Update system
cd /etc/nixos

# Clone latest configuration if not already present
if [[ ! -d ".git" ]]; then
    git init
    git remote add origin https://github.com/vpittamp/nixos-config
    git fetch origin m1-installer
    git checkout -b m1-installer origin/m1-installer
fi

# Apply full configuration
echo "Applying full desktop configuration..."
nixos-rebuild switch --flake .#nixos-hetzner

# Start desktop services
systemctl start display-manager
systemctl start xrdp

# Setup Tailscale
echo "Setting up Tailscale..."
tailscale up

echo "Setup complete!"
echo ""
echo "==================================="
echo "IMPORTANT: Change default passwords!"
echo "Run: passwd root"
echo "Run: passwd vpittamp"
echo "==================================="
echo ""
echo "RDP Access:"
echo "- Server: $(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -n1)"
echo "- Port: 3389"
echo "- Username: vpittamp"
echo "- Password: nixos (change this!)"
SETUP_SCRIPT
    
    chmod +x "${MOUNT_POINT}/root/complete-setup.sh"
    
    log_success "Post-installation setup prepared"
}

# ============================================================================
# Main Installation Flow
# ============================================================================

main() {
    echo "======================================"
    echo "NixOS Hetzner Installation Script"
    echo "======================================"
    echo ""
    
    # Run installation steps
    check_prerequisites
    partition_disk
    format_partitions
    mount_filesystems
    generate_hardware_config
    
    # Choose installation method
    echo ""
    echo "Select installation method:"
    echo "1) Minimal bootstrap (recommended for first install)"
    echo "2) Full configuration from repository"
    read -p "Choice (1 or 2): " install_choice
    
    case "$install_choice" in
        1)
            create_bootstrap_config
            ;;
        2)
            setup_configuration
            fix_configuration
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    install_nixos
    post_install_setup
    
    echo ""
    log_success "Installation complete!"
    echo ""
    echo "======================================="
    echo "NEXT STEPS:"
    echo "======================================="
    echo "1. Reboot: reboot"
    echo "2. Login as root (password: $ROOT_PASSWORD)"
    echo "3. Run: /root/complete-setup.sh"
    echo "4. Change passwords for root and $PRIMARY_USER"
    echo "5. Connect via RDP or SSH"
    echo "======================================="
    echo ""
    echo "SSH Access:"
    echo "- Use your SSH key or password"
    echo "- Root login is temporarily enabled"
    echo ""
    echo "After Tailscale setup:"
    echo "- Use Tailscale IP for secure access"
    echo "======================================="
}

# ============================================================================
# Error Handler
# ============================================================================

error_handler() {
    log_error "An error occurred on line $1"
    log_info "Installation failed. Please check the logs and try again."
    
    # Cleanup
    umount -R "$MOUNT_POINT" 2>/dev/null || true
    swapoff "$SWAP_PARTITION" 2>/dev/null || true
    
    exit 1
}

trap 'error_handler $LINENO' ERR

# ============================================================================
# Script Entry Point
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi