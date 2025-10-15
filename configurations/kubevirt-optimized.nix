# KubeVirt Optimized Desktop Image - Fast Build with Essential Features
#
# This configuration builds a streamlined desktop VM image with:
# - Core system configuration (essential modules only)
# - NO home-manager integration (applied at runtime instead)
# - RustDesk + Tailscale + XRDP for remote access
# - Basic KDE Plasma desktop (minimal packages)
# - Fast build time: ~15-20 minutes (vs 60+ minutes for full image)
#
# Build Command:
#   nix build .#nixos-kubevirt-optimized-image
#
# Post-deployment:
#   Apply home-manager configuration after VM is running
#   nix run home-manager/master -- switch --flake .#vpittamp
#
{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    # Base NixOS configuration
    ./base.nix

    # QEMU guest optimizations (virtio, etc.)
    (modulesPath + "/profiles/qemu-guest.nix")

    # Essential system modules only
    ../modules/services/networking.nix
    ../modules/desktop/kde-plasma.nix
    ../modules/desktop/remote-access.nix
    ../modules/desktop/xrdp-with-sound.nix
    ../modules/desktop/rdp-display.nix
    ../modules/services/rustdesk.nix

    # VM-specific optimizations
    ../modules/desktop/kde-plasma-vm.nix
  ];

  # ========== BOOT CONFIGURATION ==========
  boot.loader.grub = {
    enable = true;
    device = lib.mkDefault "/dev/vda";
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
  boot.kernelParams = [
    "net.ifnames=0"
    "console=ttyS0"
    # Performance optimizations for VM
    "mitigations=off"  # Disable CPU vulnerability mitigations for better performance
    "elevator=noop"    # Use noop I/O scheduler for virtualized block devices
  ];
  boot.tmp.cleanOnBoot = true;

  # VM performance tuning
  boot.kernel.sysctl = {
    # Increase swappiness for desktop responsiveness
    "vm.swappiness" = 10;
    # Improve file system performance
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
    # Network performance tuning
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 67108864";
    "net.ipv4.tcp_wmem" = "4096 65536 67108864";
  };

  # ========== NETWORKING ==========
  networking.hostName = "nixos-kubevirt-vm";
  networking.networkmanager.enable = true;

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
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # ========== TAILSCALE WITH AUTH KEY AUTOMATION ==========
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    # Auth key will be provided via cloud-init or External Secrets
    # Example cloud-init usage:
    #   runcmd:
    #     - tailscale up --auth-key=${TAILSCALE_AUTH_KEY} --hostname=nixos-vm
  };

  # ========== RUSTDESK ==========
  services.rustdesk = {
    enable = true;
    user = "vpittamp";  # Use vpittamp user
    enableDirectIpAccess = true;
    permanentPassword = "nixos123";  # Will be overridden by Azure Key Vault in production
    enableSystemService = true;  # Run as system service (starts before user login)
  };

  # ========== DESKTOP ENVIRONMENT ==========
  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Disable SDDM for headless operation (XRDP starts session on-demand)
  services.displayManager.sddm.enable = lib.mkForce false;
  services.displayManager.defaultSession = lib.mkForce "plasmax11";

  # XRDP configuration
  services.xrdp = {
    enable = true;
    defaultWindowManager = lib.mkForce "startplasma-x11";
    openFirewall = true;
  };

  # Ensure services start on boot
  systemd.services.display-manager.wantedBy = lib.mkForce [ "multi-user.target" ];
  systemd.services.xrdp.wantedBy = lib.mkForce [ "multi-user.target" ];
  systemd.services.xrdp-sesman.wantedBy = lib.mkForce [ "multi-user.target" ];

  # Audio configuration (PulseAudio for XRDP compatibility)
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
  security.rtkit.enable = true;

  # Graphics configuration (software rendering)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # ========== USER CONFIGURATION ==========
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" ];
    password = "nixos123";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHmXFP33EvyB3vZQktX+FvxdzfUVclE6bk0dd3nMAq84 hetzner-nixos"
    ];
  };

  users.users.vpittamp = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" "docker" "libvirtd" ];
    password = "nixos123";  # Override via cloud-init in production
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHmXFP33EvyB3vZQktX+FvxdzfUVclE6bk0dd3nMAq84 hetzner-nixos"
    ];
  };

  users.users.root.password = "nixos123";
  security.sudo.wheelNeedsPassword = false;

  # ========== FILESYSTEM ==========
  # Let nixos-generators handle filesystem config
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

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

  # ========== SYSTEM PACKAGES (MINIMAL) ==========
  # Keep only essentials - user packages via home-manager at runtime
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim git wget curl htop
    # System monitoring
    btop
    # Desktop essentials
    firefox
    kdePackages.konsole
    kdePackages.dolphin
    # Audio utilities
    pulseaudio pavucontrol
    # Remote access
    tailscale
    # Home-manager for runtime configuration
    home-manager
  ];

  # ========== SYSTEM STATE ==========
  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;
}
