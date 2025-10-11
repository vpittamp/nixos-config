# Minimal KubeVirt Base Image Configuration
#
# Purpose: Create a minimal bootable qcow2 image for KubeVirt VMs
# This image is designed to be a starting point that can be customized
# post-deployment using nixos-rebuild with the full vm-hetzner flake.
#
# Key differences from standard NixOS images:
# - No GRUB (KubeVirt boots via hypervisor)
# - virtio drivers for KubeVirt virtual hardware
# - Cloud-init support for dynamic configuration
# - SSH enabled for remote access
# - Minimal package set to reduce image size
#
# Usage:
#   nixos-generate --format qcow --configuration /etc/nixos/configurations/kubevirt-minimal.nix
#
{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    # QEMU guest optimizations (virtio, etc.)
    (modulesPath + "/profiles/qemu-guest.nix")
    # Minimal base profile
    (modulesPath + "/profiles/minimal.nix")
  ];

  # ========== BOOT CONFIGURATION ==========
  # CRITICAL: KubeVirt VMs boot via hypervisor, not GRUB
  boot.loader = {
    grub.enable = false;
    systemd-boot.enable = false;
    timeout = 0;
  };

  # Kernel modules for KubeVirt (virtio devices)
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
  ];

  boot.kernelModules = [ "kvm-intel" ];

  # Use predictable network interface names and serial console
  boot.kernelParams = [ "net.ifnames=0" "console=ttyS0" ];

  # Clean up temp on boot
  boot.tmp.cleanOnBoot = true;

  # ========== FILESYSTEM ==========
  # Let nixos-generator's qcow format handle filesystem configuration
  # It will create /dev/disk/by-label/nixos on /dev/vda1

  # ========== NETWORKING ==========
  networking.hostName = "nixos-kubevirt";
  networking.useDHCP = true;  # Works best with KubeVirt pod networking

  # Firewall - open SSH only
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # ========== CLOUD-INIT ==========
  # Essential for KubeVirt dynamic configuration
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # ========== SSH ACCESS ==========
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";  # For initial setup
      PasswordAuthentication = true;
    };
  };

  # ========== USER CONFIGURATION ==========
  # Create default user (cloud-init can override)
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";  # Change via cloud-init
  };

  users.users.root.initialPassword = "nixos";

  # Allow sudo without password
  security.sudo.wheelNeedsPassword = false;

  # ========== NIX CONFIGURATION ==========
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # ========== MINIMAL PACKAGES ==========
  # Keep base image small - install more via nixos-rebuild later
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
  ];

  # ========== SYSTEM STATE ==========
  system.stateVersion = "24.11";
}
