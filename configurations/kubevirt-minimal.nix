# Minimal KubeVirt Base Image Configuration
# Uses nixos-generators kubevirt format via built-in kubevirt.nix module
#
# Build: nix build .#kubevirt-minimal-qcow2
# Size target: ~500MB compressed
#
# Features:
# - QEMU guest agent (auto-enabled by kubevirt.nix)
# - Cloud-init support (auto-enabled by kubevirt.nix)
# - OpenSSH server (auto-enabled by kubevirt.nix)
# - Serial console on ttyS0 (auto-enabled by kubevirt.nix)
# - Cachix binary cache for fast nixos-rebuild (via base.nix)
# - Tailscale for remote access
# - Virtio drivers for KubeVirt performance
#
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # KubeVirt module - enables QEMU guest agent, cloud-init, SSH, serial console
    # Also configures GRUB on /dev/vda with auto-resize root filesystem
    (modulesPath + "/virtualisation/kubevirt.nix")
  ];

  # ========== IDENTIFICATION ==========
  networking.hostName = "nixos-kubevirt-minimal";
  system.stateVersion = "24.11";

  # ========== BOOT OPTIMIZATIONS ==========
  # Add virtio kernel modules for KubeVirt performance
  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net" "virtio_balloon"
  ];
  boot.kernelParams = [ "net.ifnames=0" "console=ttyS0" ];

  # ========== NETWORKING ==========
  networking.useDHCP = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];  # SSH
  };

  # ========== USER CONFIGURATION ==========
  users.users = {
    root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0gmlXX6rWgC+4XW6FYBuN8gSOp7H/U+s8UeALbTnmG vpittamp@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7 1password-git-signing"
      ];
    };

    vpittamp = {
      isNormalUser = true;
      description = "Vinod Pittampalli";
      extraGroups = [ "wheel" ];
      initialPassword = "nixos123";  # Change on first login or via cloud-init
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0gmlXX6rWgC+4XW6FYBuN8gSOp7H/U+s8UeALbTnmG vpittamp@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7 1password-git-signing"
      ];
    };
  };

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # ========== SSH CONFIGURATION ==========
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
  };

  # ========== TAILSCALE ==========
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # ========== NIX CONFIGURATION ==========
  nix = {
    package = pkgs.nixVersions.latest;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "vpittamp" "@wheel" ];
      auto-optimise-store = true;

      # Use Cachix for faster builds (configured in base.nix)
      # Inherits substituters from base configuration
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # ========== MINIMAL PACKAGES ==========
  # Keep base image as small as possible
  # Additional packages installed via nixos-rebuild
  environment.systemPackages = with pkgs; [
    vim
    git        # Required for flake operations
    curl
    htop
    tmux       # For persistent sessions during rebuilds
    jq         # For parsing JSON outputs
  ];

  # ========== SIZE OPTIMIZATIONS ==========
  # Disable documentation to reduce image size
  documentation.enable = false;
  documentation.nixos.enable = false;
  documentation.man.enable = false;

  # Disable fonts (not needed for headless base image)
  fonts.fontconfig.enable = false;

  # ========== DISK SIZE ==========
  # 10GB is enough for base + space for nixos-rebuild
  virtualisation.diskSize = 10 * 1024;  # MiB

  # ========== TIME & LOCALE ==========
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
}
