#!/bin/sh
# NixOS Installation Script for Hetzner Cloud

set -e

echo "=== NixOS Installation Script for Hetzner Cloud ==="
echo

# Partition the disk
echo "1. Partitioning disk /dev/sda..."
parted /dev/sda -- mklabel msdos
parted /dev/sda -- mkpart primary 1MB -8GB
parted /dev/sda -- mkpart primary linux-swap -8GB 100%

# Format partitions
echo "2. Formatting partitions..."
mkfs.ext4 -L nixos /dev/sda1
mkswap -L swap /dev/sda2

# Mount partitions
echo "3. Mounting partitions..."
mount /dev/disk/by-label/nixos /mnt
swapon /dev/sda2

# Generate hardware configuration
echo "4. Generating hardware configuration..."
nixos-generate-config --root /mnt

# Download our configuration
echo "5. Downloading configuration..."
curl -o /mnt/etc/nixos/configuration.nix https://raw.githubusercontent.com/PittampalliOrg/nix-config/main/configuration-simple.nix 2>/dev/null || {
    echo "Could not download from GitHub, using local config"
    cat > /mnt/etc/nixos/configuration.nix << 'EOF'
# Simple NixOS configuration for Hetzner Cloud
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Boot loader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  
  # Use predictable interface names (eth0)
  boot.kernelParams = [ "net.ifnames=0" ];

  # Hostname
  networking.hostName = "nixos-hetzner";
  
  # Simple DHCP for all interfaces
  networking.useDHCP = true;

  # Time zone
  time.timeZone = "UTC";

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # Root user SSH key
  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
    ];
  };

  # User account
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
    ];
  };

  # Allow sudo without password
  security.sudo.wheelNeedsPassword = false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    tmux
    htop
    tailscale
  ];

  # Enable Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.05";
}
EOF
}

echo
echo "6. Configuration preview:"
echo "========================="
grep -E "networking|hostName|useDHCP" /mnt/etc/nixos/configuration.nix | head -5
echo "..."
echo

# Install NixOS
echo "7. Installing NixOS (this will take a few minutes)..."
nixos-install --no-root-passwd

echo
echo "=== Installation Complete! ==="
echo "Remove the ISO from Hetzner console and reboot."
echo "You'll be able to SSH as root or vpittamp with your key."
echo
echo "After reboot, run: tailscale up"