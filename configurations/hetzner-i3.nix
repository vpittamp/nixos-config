# Hetzner Cloud Server Configuration with i3wm Desktop
# Testing configuration for i3 window manager deployment (Phase 1)
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Base configuration
    ./base.nix

    # Disk configuration for nixos-anywhere compatibility
    ../disk-config.nix

    # Environment check
    ../modules/assertions/hetzner-check.nix

    # QEMU guest optimizations
    (modulesPath + "/profiles/qemu-guest.nix")

    # Phase 1: Core Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix

    # Phase 2: Desktop Environment - i3wm (NEW)
    ../modules/desktop/i3wm.nix
    ../modules/desktop/xrdp.nix

    # Services
    ../modules/services/onepassword-automation.nix
    ../modules/services/onepassword-password-management.nix
  ];

  # System identification
  networking.hostName = "nixos-hetzner";

  # Boot configuration for Hetzner - GRUB for nixos-anywhere compatibility
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Kernel modules for virtualization
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  # Use predictable network interface names
  boot.kernelParams = [ "net.ifnames=0" ];

  # Simple DHCP networking (works best with Hetzner)
  networking.useDHCP = true;

  # Firewall - open ports for services
  networking.firewall = {
    allowedTCPPorts = [
      22     # SSH
      3389   # RDP (XRDP)
      8080   # Web services
    ];
    # Tailscale
    checkReversePath = "loose";
  };

  # Enable 1Password password management
  services.onepassword-password-management = {
    enable = true;
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
    users.vpittamp = {
      enable = true;
      passwordReference = "op://CLI/NixOS User Password/password";
    };
    updateInterval = "hourly";  # Check for password changes hourly
  };

  # Fallback password for initial setup before 1Password is configured
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";

  # SSH settings for initial access
  services.openssh.settings = {
    PermitRootLogin = "yes";  # For initial setup, disable later
    PasswordAuthentication = true;  # For initial setup
  };

  # Performance tuning for cloud server
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Enable 1Password automation with service account
  services.onepassword-automation = {
    enable = true;
    user = "vpittamp";
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
  };

  # ========== i3WM DESKTOP CONFIGURATION ==========

  # Enable i3 window manager
  services.i3wm = {
    enable = true;
    extraPackages = with pkgs; [
      dmenu
      i3status
      i3lock
      rofi
      alacritty
      firefox  # Browser
      # Note: VS Code is provided by home-manager configuration
      # See: home-modules/tools/vscode.nix
    ];
  };

  # Enable XRDP for i3
  services.xrdp-i3 = {
    enable = true;
    port = 3389;
    openFirewall = true;
  };

  # Audio configuration for XRDP
  # IMPORTANT: PulseAudio works better with XRDP audio redirection
  # Disable PipeWire (may be enabled by base modules)
  services.pipewire.enable = lib.mkForce false;
  services.pipewire.pulse.enable = lib.mkForce false;

  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
  };

  # Additional packages specific to Hetzner i3wm setup
  environment.systemPackages = with pkgs; [
    # System monitoring
    htop
    btop
    iotop
    nethogs
    neofetch

    # Remote access
    tailscale         # Zero-config VPN

    # PulseAudio XRDP module
    pulseaudio-module-xrdp
  ];

  # Enable rtkit for better audio performance
  security.rtkit.enable = true;

  # Ensure user is in required groups
  users.users.vpittamp.extraGroups = lib.mkForce [ "wheel" "networkmanager" "audio" "video" "input" "docker" "libvirtd" ];

  # ========== TAILSCALE ==========
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # System state version
  system.stateVersion = "24.11";
}
