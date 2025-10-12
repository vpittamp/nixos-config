# Desktop-Enabled KubeVirt Image Configuration
#
# Purpose: Create a qcow2 image with KDE Plasma 6 desktop pre-installed
# This eliminates the need for cloud-init to build the desktop, enabling
# fast VM boot times (2-3 minutes) even without KVM acceleration.
#
# Usage:
#   nixos-generate --format qcow --configuration /etc/nixos/configurations/kubevirt-desktop.nix -o /tmp/kubevirt-desktop-image
#
{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    # QEMU guest optimizations (virtio, etc.)
    (modulesPath + "/profiles/qemu-guest.nix")
    # RustDesk remote desktop service
    ../modules/services/rustdesk.nix
  ];

  # ========== BOOT CONFIGURATION ==========
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
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
  boot.kernelParams = [ "net.ifnames=0" "console=ttyS0" ];
  boot.tmp.cleanOnBoot = true;

  # ========== NETWORKING ==========
  networking.hostName = "nixos-kubevirt-desktop";
  networking.networkmanager.enable = true;
  # NetworkManager handles DHCP, so don't set useDHCP

  # Firewall - open remote access ports
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 3389 5900 5901 ];
    # RustDesk ports managed by rustdesk service
    # Tailscale
    checkReversePath = "loose";
  };

  # ========== CLOUD-INIT ==========
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # ========== SSH ACCESS ==========
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # ========== TAILSCALE ==========
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # ========== RUSTDESK ==========
  services.rustdesk = {
    enable = true;
    user = "nixos";  # Default user for KubeVirt VMs
    enableDirectIpAccess = true;
  };

  # ========== DESKTOP ENVIRONMENT ==========
  # KDE Plasma 6 - modern, feature-rich desktop
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # Remote Desktop Protocol (xrdp)
  services.xrdp = {
    enable = true;
    defaultWindowManager = "startplasma-x11";
    openFirewall = true;
  };

  # Ensure display manager and xrdp start on boot
  systemd.services.display-manager.wantedBy = lib.mkForce [ "multi-user.target" ];
  systemd.services.xrdp.wantedBy = lib.mkForce [ "multi-user.target" ];
  systemd.services.xrdp-sesman.wantedBy = lib.mkForce [ "multi-user.target" ];

  # Audio support - PipeWire (default for Plasma 6)
  # Explicitly disable PulseAudio to avoid conflicts
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ========== USER CONFIGURATION ==========
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    initialPassword = "nixos";
  };

  users.users.root.initialPassword = "nixos";
  security.sudo.wheelNeedsPassword = false;

  # ========== NIX CONFIGURATION ==========
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # Use Attic binary cache for faster builds
    substituters = [
      "http://attic.nix-cache.svc.cluster.local:8080/nixos"
      "https://cache.nixos.org"
    ];
  };

  # ========== SYSTEM PACKAGES ==========
  # Desktop essentials pre-installed
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim git wget curl htop tmux
    # Desktop applications
    firefox
    kdePackages.konsole  # KDE terminal (Qt 6)
    kdePackages.dolphin  # KDE file manager (Qt 6)
    kdePackages.kate     # KDE text editor (Qt 6)
    # Remote access
    tigervnc
    # rustdesk-flutter managed by service module
    tailscale            # Zero-config VPN
    # Development tools
    home-manager
  ];

  # ========== SYSTEM STATE ==========
  system.stateVersion = "24.11";

  # Allow unfree packages (some desktop components may require this)
  nixpkgs.config.allowUnfree = true;
}
