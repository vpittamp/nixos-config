# NixOS Installation on Hetzner Cloud - Complete Guide

## Overview

This documentation provides comprehensive instructions for installing NixOS on Hetzner Cloud servers with a full KDE Plasma 6 desktop environment and remote access capabilities. This setup is ideal for development workstations, remote desktops, or powerful cloud-based computing environments.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Installation Methods](#installation-methods)
4. [Step-by-Step Manual Installation](#step-by-step-manual-installation)
5. [Automated Installation](#automated-installation)
6. [Post-Installation Configuration](#post-installation-configuration)
7. [Remote Access Setup](#remote-access-setup)
8. [Troubleshooting](#troubleshooting)
9. [Security Considerations](#security-considerations)
10. [Maintenance and Updates](#maintenance-and-updates)

## Prerequisites

### Hetzner Cloud Server Requirements
- **Server Type**: CCX33 or higher recommended for desktop environment
- **RAM**: Minimum 8GB (16GB+ recommended for KDE Plasma)
- **Storage**: 80GB+ SSD
- **Network**: Public IPv4 address
- **Location**: Any Hetzner datacenter

### Local Requirements
- SSH client
- Web browser for Hetzner Cloud Console
- RDP client (for remote desktop access)
- Optional: Tailscale account for secure networking

### Required Information
- SSH public key for passwordless access
- GitHub repository with NixOS configuration (optional)
- Tailscale auth key (optional)

## Architecture Overview

### System Components
```
┌─────────────────────────────────────────┐
│         Hetzner Cloud Server            │
├─────────────────────────────────────────┤
│  NixOS (Unstable/24.11)                 │
│  ├── KDE Plasma 6 Desktop               │
│  ├── xrdp (Remote Desktop)              │
│  ├── SSH Server                         │
│  ├── Tailscale VPN                      │
│  ├── Docker & Kubernetes Tools          │
│  └── Development Environment            │
└─────────────────────────────────────────┘
```

### Network Access Methods
1. **Direct SSH**: Public IP on port 22
2. **Tailscale SSH**: Secure VPN access
3. **RDP**: Port 3389 for full desktop
4. **VNC**: Optional, port 5900
5. **Hetzner Console**: Web-based emergency access

## Installation Methods

### Method 1: ISO Mount Installation (Recommended)
- Mount NixOS ISO via Hetzner Cloud Console
- Use automated script or manual installation
- Most reliable for initial setup

### Method 2: nixos-anywhere (Advanced)
- Deploy directly from existing Linux
- Requires careful network configuration
- Can be unreliable on Hetzner

### Method 3: Conversion from Ubuntu/Debian
- Start with Ubuntu 24.04
- Convert to NixOS using nixos-infect
- Useful for specific scenarios

## Step-by-Step Manual Installation

### Phase 1: Server Preparation

#### 1.1 Create Hetzner Server
```bash
# Via Hetzner Cloud Console or CLI
hcloud server create \
  --name nixos-hetzner \
  --type ccx33 \
  --image ubuntu-24.04 \
  --datacenter fsn1-dc14
```

#### 1.2 Mount NixOS ISO
1. Open Hetzner Cloud Console
2. Select your server
3. Go to "ISO Images" tab
4. Mount "NixOS 24.11 minimal"
5. Reboot server into ISO

#### 1.3 Connect via Console
1. Open "Console" tab in Hetzner
2. Wait for NixOS installer to boot
3. You'll see: `nixos@nixos:~$`

### Phase 2: Disk Partitioning

#### 2.1 Identify Disk
```bash
# List available disks
lsblk

# Usually /dev/sda on Hetzner
DISK=/dev/sda
```

#### 2.2 Partition Disk
```bash
# Create GPT partition table
sudo parted $DISK mklabel gpt

# Create boot partition (512MB, EFI)
sudo parted $DISK mkpart ESP fat32 1MiB 513MiB
sudo parted $DISK set 1 esp on

# Create root partition (remaining - 8GB for swap)
sudo parted $DISK mkpart primary ext4 513MiB -8GiB

# Create swap partition (8GB)
sudo parted $DISK mkpart primary linux-swap -8GiB 100%
```

#### 2.3 Format Partitions
```bash
# Format boot partition
sudo mkfs.fat -F 32 -n BOOT /dev/sda1

# Format root partition
sudo mkfs.ext4 -L nixos /dev/sda2

# Setup swap
sudo mkswap -L swap /dev/sda3
```

#### 2.4 Mount Filesystems
```bash
# Mount root
sudo mount /dev/sda2 /mnt

# Mount boot
sudo mkdir -p /mnt/boot
sudo mount /dev/sda1 /mnt/boot

# Enable swap
sudo swapon /dev/sda3
```

### Phase 3: NixOS Installation

#### 3.1 Generate Configuration
```bash
# Generate hardware configuration
sudo nixos-generate-config --root /mnt

# This creates:
# - /mnt/etc/nixos/configuration.nix
# - /mnt/etc/nixos/hardware-configuration.nix
```

#### 3.2 Edit Configuration
```bash
sudo nano /mnt/etc/nixos/configuration.nix
```

Add essential configuration:
```nix
{
  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Networking
  networking.hostName = "nixos-hetzner";
  networking.useDHCP = true;
  
  # SSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";
  
  # Users
  users.users.root.initialPassword = "nixos";
  users.users.vpittamp = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";
  };
  
  # Essential packages
  environment.systemPackages = with pkgs; [
    vim git wget curl
  ];
  
  system.stateVersion = "24.11";
}
```

#### 3.3 Install NixOS
```bash
# Run installation
sudo nixos-install

# Set root password when prompted
# Enter: nixos (or your preferred password)
```

#### 3.4 Reboot
```bash
# Unmount ISO in Hetzner Console first!
sudo reboot
```

### Phase 4: Post-Installation Setup

#### 4.1 SSH Access
```bash
# From your local machine
ssh root@<server-ip>
# Password: nixos
```

#### 4.2 Clone Configuration Repository
```bash
# Install git
nix-env -iA nixos.git

# Clone your configuration
cd /etc/nixos
git init
git remote add origin https://github.com/vpittamp/nixos-config
git fetch origin m1-installer
git checkout -b m1-installer origin/m1-installer
```

#### 4.3 Fix Package Issues
```bash
# Fix Qt5 to Qt6 migrations
sed -i 's/pkgs\.xdg-desktop-portal-kde/pkgs.kdePackages.xdg-desktop-portal-kde/g' configuration-hetzner-desktop.nix
sed -i 's/^    kate$/    kdePackages.kate/' configuration-hetzner-desktop.nix
sed -i 's/^    konsole$/    kdePackages.konsole/' configuration-hetzner-desktop.nix
sed -i 's/^    dolphin$/    kdePackages.dolphin/' configuration-hetzner-desktop.nix
sed -i 's/^    ark$/    kdePackages.ark/' configuration-hetzner-desktop.nix
sed -i 's/^    spectacle$/    kdePackages.spectacle/' configuration-hetzner-desktop.nix
```

#### 4.4 Apply Full Configuration
```bash
# Stage changes in git (required for flakes)
git add -A
git commit -m "Fix KDE package references"

# Rebuild with full configuration
nixos-rebuild switch --flake .#nixos-hetzner
```

#### 4.5 Start Desktop Services
```bash
# Start display manager
systemctl start display-manager

# Start RDP service
systemctl start xrdp
```

## Automated Installation

### Using the Installation Script

```bash
# Boot into NixOS ISO
# Download and run the script
curl -O https://raw.githubusercontent.com/vpittamp/nixos-config/m1-installer/scripts/install-nixos-hetzner.sh
chmod +x install-nixos-hetzner.sh
sudo ./install-nixos-hetzner.sh
```

The script will:
1. Partition and format disk
2. Install base NixOS
3. Configure networking and SSH
4. Setup users and passwords
5. Prepare post-install scripts

## Post-Installation Configuration

### Setup Tailscale
```bash
# Start Tailscale
sudo tailscale up

# Authenticate (follow the link)
# Your machine will get a Tailscale IP (100.x.x.x)
```

### Change Default Passwords
```bash
# Change root password
sudo passwd root

# Change user password
sudo passwd vpittamp
```

### Configure Home Manager
```bash
# Switch to user
su - vpittamp

# Apply home-manager configuration
home-manager switch --flake github:vpittamp/nixos-config#container-essential
```

## Remote Access Setup

### RDP Connection (Windows)

#### From Windows 11
1. Press `Win + R`
2. Type `mstsc` and press Enter
3. Enter server details:
   - Computer: `<server-ip>` or `<tailscale-ip>`
   - Username: `vpittamp`
4. Click "Connect"
5. Enter password when prompted

#### Connection Settings
- Display: Full screen or custom resolution
- Local Resources: Enable clipboard, drives if needed
- Experience: Adjust for network speed

### SSH Access

#### Direct SSH
```bash
ssh vpittamp@<server-ip>
```

#### SSH with Key
```bash
# Add your public key to authorized_keys
ssh-copy-id vpittamp@<server-ip>
```

#### SSH via Tailscale
```bash
# After Tailscale setup
ssh vpittamp@<tailscale-hostname>
```

### VNC Access (Optional)
```bash
# Install VNC viewer on local machine
# Connect to: <server-ip>:5900
```

## Troubleshooting

### Common Issues and Solutions

#### Issue: SSH Connection Refused
**Symptoms**: Cannot SSH after installation
**Solution**:
```bash
# Via Hetzner Console
systemctl status sshd
systemctl start sshd
systemctl enable sshd
```

#### Issue: RDP Authentication Error (0x204)
**Symptoms**: RDP connects but authentication fails
**Solution**:
```bash
# Set user password
sudo passwd vpittamp

# Restart xrdp
sudo systemctl restart xrdp xrdp-sesman
```

#### Issue: Network Not Working
**Symptoms**: No internet connectivity
**Solution**:
```bash
# Check interface name
ip a

# If interface is enp1s0 instead of eth0
# Edit configuration to use:
networking.useDHCP = true;  # Let DHCP auto-configure
```

#### Issue: Display Manager Not Starting
**Symptoms**: KDE desktop doesn't appear
**Solution**:
```bash
# Check status
systemctl status display-manager

# Start manually
systemctl start display-manager

# Check logs
journalctl -u display-manager -e
```

#### Issue: Build Failures (Qt5/Qt6)
**Symptoms**: Package not found errors during rebuild
**Solution**:
```bash
# Update package references
# Qt5 packages → kdePackages.packageName
# Example: kate → kdePackages.kate
```

#### Issue: Flake Build Requires Git Staging
**Symptoms**: "Git tree is dirty" error
**Solution**:
```bash
# Stage all changes
git add -A
git commit -m "Configuration update"

# Then rebuild
nixos-rebuild switch --flake .#nixos-hetzner
```

### Emergency Recovery

#### Boot into Rescue Mode
1. Mount NixOS ISO via Hetzner Console
2. Reboot server
3. Mount existing installation:
```bash
sudo mount /dev/sda2 /mnt
sudo mount /dev/sda1 /mnt/boot
sudo nixos-enter
```

#### Fix Configuration Issues
```bash
# Inside chroot
cd /etc/nixos
# Edit configuration files
nano configuration.nix
# Rebuild
nixos-rebuild boot
```

## Security Considerations

### Immediate Security Steps
1. **Change all default passwords**
2. **Disable root SSH login** after setup
3. **Setup SSH key authentication**
4. **Configure firewall rules**
5. **Enable fail2ban**

### Firewall Configuration
```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 
    22    # SSH (consider changing port)
    3389  # RDP (restrict to specific IPs if possible)
  ];
};
```

### SSH Hardening
```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };
};
```

## Maintenance and Updates

### System Updates
```bash
# Update flake inputs
cd /etc/nixos
nix flake update

# Rebuild system
sudo nixos-rebuild switch --flake .#nixos-hetzner
```

### Garbage Collection
```bash
# Remove old generations
sudo nix-collect-garbage -d

# Keep last 7 days
sudo nix-collect-garbage --delete-older-than 7d
```

### Backup Configuration
```bash
# Push to git repository
cd /etc/nixos
git add -A
git commit -m "Configuration backup $(date +%Y-%m-%d)"
git push origin m1-installer
```

## Performance Optimization

### For Headless Desktop
```nix
# Use virtual display for better performance
services.xserver.videoDrivers = [ "modesetting" "fbdev" ];
```

### Memory Management
```nix
# Adjust for available RAM
boot.kernel.sysctl = {
  "vm.swappiness" = 10;
  "vm.vfs_cache_pressure" = 50;
};
```

## Additional Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Hetzner Cloud Documentation](https://docs.hetzner.com/cloud/)
- [KDE Plasma Documentation](https://docs.kde.org/)
- [xrdp Configuration](https://github.com/neutrinolabs/xrdp)

## Support and Debugging

### Useful Commands
```bash
# System status
systemctl status

# Check logs
journalctl -xe

# Network status
ip a
ss -tlpn

# Disk usage
df -h
ncdu /

# Running services
systemctl list-units --state=running
```

### Log Locations
- System logs: `journalctl`
- SSH logs: `journalctl -u sshd`
- RDP logs: `journalctl -u xrdp`
- Display manager: `journalctl -u display-manager`

---

## Quick Reference Card

```bash
# Essential Commands
ssh root@<ip>                      # Initial SSH access
nixos-rebuild switch --flake .#x   # Apply configuration
systemctl start xrdp               # Start RDP service
tailscale up                       # Setup Tailscale
passwd <user>                      # Change password

# Troubleshooting
journalctl -xe                     # View system logs
systemctl status <service>         # Check service status
nixos-rebuild dry-build            # Test configuration
ip a                              # Check network interfaces

# Git Operations (required for flakes)
git add -A                        # Stage all changes
git commit -m "message"           # Commit changes
git push                          # Backup to repository
```

---

*Last updated: 2025 | Tested with NixOS 24.11 and Hetzner Cloud CCX33*