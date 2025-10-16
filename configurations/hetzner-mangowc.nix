# Hetzner Cloud Server Configuration with MangoWC Desktop
# Lightweight Wayland-based development workstation
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

    # Phase 2: Desktop Environment (MangoWC instead of KDE Plasma)
    ../modules/desktop/mangowc.nix
    ../modules/desktop/wayland-remote-access.nix
    ../modules/services/audio-network.nix

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

  # ========== MANGOWC DESKTOP CONFIGURATION ==========

  # Enable MangoWC Wayland compositor
  services.mangowc = {
    enable = true;
    user = "vpittamp";
    resolution = "1920x1080";

    # Workspace configuration
    workspaces = [
      { id = 1; layout = "tile"; name = "Main"; }
      { id = 2; layout = "scroller"; name = "Code"; }
      { id = 3; layout = "monocle"; name = "Focus"; }
      { id = 4; layout = "tile"; }
      { id = 5; layout = "tile"; }
      { id = 6; layout = "tile"; }
      { id = 7; layout = "tile"; }
      { id = 8; layout = "tile"; }
      { id = 9; layout = "tile"; }
    ];

    # Custom keybindings (adds to defaults)
    keybindings = {
      # Browser launch
      "SUPER,b" = "spawn,firefox";
    };

    # Appearance settings
    appearance = {
      borderWidth = 4;
      borderRadius = 6;
      rootColor = "0x201b14ff";
      focusColor = "0xc9b890ff";
      unfocusedColor = "0x444444ff";
    };

    # Autostart applications
    autostart = ''
      # Wallpaper (placeholder - will use rootColor until image is added)
      # swaybg -i /etc/nixos/assets/wallpapers/default.png &

      # Optional: Status bar
      # waybar &

      # Optional: Notification daemon
      # mako &
    '';
  };

  # Enable WayVNC remote desktop
  services.wayvnc = {
    enable = true;
    port = 5900;
    address = "0.0.0.0";
    enablePAM = true;
    enableAuth = true;
    maxFPS = 120;
    enableGPU = true;  # Will fallback to CPU if GPU unavailable
  };

  # Enable PipeWire network audio for remote desktop
  services.pipewire.networkAudio = {
    enable = true;
    port = 4713;
    address = "0.0.0.0";
  };

  # ========== END MANGOWC CONFIGURATION ==========

  # Firewall - open ports for services
  networking.firewall = {
    allowedTCPPorts = [
      22     # SSH
      5900   # VNC (wayvnc)
      4713   # PipeWire network audio
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

  # Additional packages specific to Hetzner
  environment.systemPackages = with pkgs; [
    # System monitoring
    htop
    btop
    iotop
    nethogs
    neofetch

    # Browser
    firefox

    # Wayland utilities (additional to those from mangowc.nix)
    wev          # Wayland event viewer (debugging)
    wlr-randr    # Display configuration

    # Optional: Status bar and notifications
    # waybar       # Status bar
    # mako         # Notification daemon
    # cliphist     # Clipboard history

    # Remote access
    tailscale    # Zero-config VPN
  ];

  # Performance tuning for cloud server
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Enable 1Password automation with service account
  services.onepassword-automation = {
    enable = true;
    user = "vpittamp";
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
  };

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
