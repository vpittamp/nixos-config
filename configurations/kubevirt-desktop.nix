# Desktop-Enabled KubeVirt Image Configuration (Minimal Base Image)
#
# Strategy: Two-Image Approach
# =============================
# 1. THIS FILE (kubevirt-desktop.nix): Minimal base image with core services
#    - Fast-booting base image (~2-3 GB, 2-3 min boot time)
#    - Includes: KDE Plasma 6, X11, XRDP, RustDesk, Tailscale, cloud-init
#    - Generic "nixos" user for initial access
#    - Built via nixos-generate, deployed as qcow2 image in KubeVirt
#
# 2. vm-hetzner.nix: Full production configuration (applied at runtime)
#    - Full Hetzner-equivalent with home-manager integration
#    - Includes: 1Password, Speech-to-Text, Firefox PWA, all user customizations
#    - Uses "vpittamp" user with full home-manager profile
#    - Applied via: sudo nixos-rebuild switch --flake github:vpittamp/nixos-config#vm-hetzner
#
# Workflow:
#   1. Boot from this minimal base image (fast initial deployment)
#   2. SSH into VM and run nixos-rebuild to switch to vm-hetzner configuration
#   3. Full production environment matches Hetzner workstation exactly
#
# Build Command:
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

  # Disable SDDM display manager for headless operation
  # Critical: This prevents auto-starting a console KDE session on boot
  # XRDP will start the KDE session on-demand when you connect
  services.displayManager.sddm.enable = lib.mkForce false;

  # Use X11 session by default for XRDP compatibility (not Wayland)
  services.displayManager.defaultSession = lib.mkForce "plasmax11";

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

  # Audio configuration for XRDP (matching Hetzner configuration)
  # IMPORTANT: PulseAudio works better with XRDP audio redirection
  # Disable PipeWire and use PulseAudio instead for proper RDP audio
  services.pipewire.pulse.enable = lib.mkForce false;
  services.pipewire.enable = lib.mkForce false;

  services.pulseaudio = {
    enable = lib.mkForce true;
    package = pkgs.pulseaudioFull;
    extraModules = [ pkgs.pulseaudio-module-xrdp ];
    extraConfig = ''
      .ifexists module-xrdp-sink.so
      load-module module-xrdp-sink
      .endif
      .ifexists module-xrdp-source.so
      load-module module-xrdp-source
      .endif
    '';
  };

  # Enable rtkit for better audio performance
  security.rtkit.enable = true;

  # ========== USER CONFIGURATION ==========
  users.users.nixos = {
    isNormalUser = true;
    # Match Hetzner user groups (excluding docker/libvirtd which aren't needed in VM)
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" ];
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
  # Desktop essentials pre-installed (matching Hetzner configuration)
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim git wget curl htop tmux
    # System monitoring (matching Hetzner)
    btop
    iotop
    nethogs
    neofetch
    # Desktop applications
    firefox
    kdePackages.konsole  # KDE terminal (Qt 6)
    kdePackages.dolphin  # KDE file manager (Qt 6)
    kdePackages.kate     # KDE text editor (Qt 6)
    # Audio utilities (matching Hetzner)
    pulseaudio  # For pactl, pacmd, and other audio management tools
    pavucontrol # GUI audio control
    alsa-utils  # For alsamixer and other ALSA utilities
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
