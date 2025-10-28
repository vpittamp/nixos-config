# Hetzner Cloud Sway Configuration (Feature 046)
# Headless Wayland with Sway tiling window manager, VNC remote access
# Parallel to hetzner.nix (i3/X11) - does NOT modify existing hetzner config
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Base configuration (shared with hetzner i3 config)
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
    ../modules/services/i3-project-daemon.nix  # Feature 037: System service for cross-namespace /proc access

    # Phase 2: Wayland/Sway Desktop Environment (Feature 045 modules reused)
    ../modules/desktop/sway.nix       # Sway compositor (from Feature 045)
    ../modules/desktop/wayvnc.nix     # VNC server for headless Wayland (from Feature 045)

    # Services
    ../modules/services/onepassword-automation.nix
    ../modules/services/onepassword-password-management.nix
    ../modules/services/speech-to-text-safe.nix
  ];

  # System identification
  networking.hostName = "nixos-hetzner-sway";

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

  # ========== HEADLESS WAYLAND CONFIGURATION (Feature 046) ==========

  # Enable Sway compositor
  programs.sway.enable = true;

  # Enable wayvnc VNC server for remote access
  services.wayvnc.enable = true;

  # Display manager: greetd with auto-login for headless operation
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # Auto-login vpittamp user and start Sway compositor
        command = "${pkgs.sway}/bin/sway";
        user = "vpittamp";
      };
    };
  };

  # Environment variables for headless Wayland operation
  # These are critical for Sway to run without physical displays
  environment.sessionVariables = {
    # Use headless wlroots backend (no physical display required)
    WLR_BACKENDS = "headless";

    # Disable libinput (no physical input devices in headless mode)
    WLR_LIBINPUT_NO_DEVICES = "1";

    # Use pixman software rendering (no GPU acceleration in cloud VMs)
    WLR_RENDERER = "pixman";

    # Wayland-specific environment variables
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "sway";

    # Qt and GTK Wayland support
    QT_QPA_PLATFORM = "wayland";
    GDK_BACKEND = "wayland";

    # GTK4 software rendering (CRITICAL for Walker in headless mode)
    # Forces Cairo CPU rendering instead of GPU-accelerated rendering
    GSK_RENDERER = "cairo";
  };

  # User lingering for persistent session after SSH logout
  # Required for Sway session to continue running after SSH disconnection
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/vpittamp 0644 root root - -"
  ];

  # i3 Project Daemon (Feature 037) - System service for cross-namespace access
  # NOTE: Daemon is Sway-compatible (Feature 045), no code changes needed
  services.i3ProjectDaemon = {
    enable = true;
    user = "vpittamp";
    logLevel = "DEBUG";  # Temporary for testing
  };

  # Firewall - open additional ports for services
  networking.firewall = {
    allowedTCPPorts = [
      22     # SSH
      5900   # VNC (wayvnc)
      8080   # Web services
    ];
    interfaces."tailscale0".allowedTCPPorts = [
      5900   # VNC via Tailscale (more secure)
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

  # Additional packages specific to headless Sway
  environment.systemPackages = with pkgs; [
    # Wayland utilities
    wl-clipboard  # Clipboard utilities for Wayland (Feature 043 dependency)
    wlr-randr     # Output management for wlroots compositors
    wayvnc        # VNC server (already in system, adding CLI tool)

    # System monitoring
    htop
    btop
    iotop
    nethogs
    neofetch

    # Remote access
    tailscale         # Zero-config VPN
  ];

  # Performance tuning for cloud server
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Display manager: greetd (already configured above, no SDDM needed)
  services.displayManager.sddm.enable = lib.mkForce false;

  # Enable 1Password automation with service account
  services.onepassword-automation = {
    enable = true;
    user = "vpittamp";
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
  };

  # Enable Speech-to-Text services using safe module
  services.speech-to-text = {
    enable = true;
    model = "base.en";  # Good balance of speed and accuracy
    language = "en";
    enableGlobalShortcut = true;
    voskModelPackage = pkgs.callPackage ../pkgs/vosk-model-en-us-0.22-lgraph.nix {};
  };

  # Audio configuration for Wayland/Sway
  # Use PipeWire (modern Wayland-native audio server)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

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
