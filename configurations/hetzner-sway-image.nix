# Hetzner Sway QCOW2 image configuration (Feature 007-number-7-short)
# Based on hetzner-sway.nix but without disko for nixos-generators compatibility
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Base configuration (shared with hetzner i3 config)
    ./base.nix

    # Skip disk-config.nix (nixos-generators handles disk layout)
    # Skip hetzner-check.nix (not needed for QCOW2 image)

    # QEMU guest optimizations
    (modulesPath + "/profiles/qemu-guest.nix")

    # Phase 1: Core Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix  # Consolidated 1Password module (with feature flags)
    # Feature 117: System service removed - now runs as home-manager user service
    ../modules/services/keyd.nix
    ../modules/services/sway-tree-monitor.nix

    # Phase 2: Wayland/Sway Desktop Environment
    ../modules/desktop/sway.nix
    ../modules/desktop/wayvnc.nix
    ../modules/desktop/firefox-1password.nix  # Firefox with 1Password (consolidated, with PWA support)

    # Services
    ../modules/services/speech-to-text-safe.nix
    ../modules/services/tailscale-audio.nix
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

  # Disk size for QCOW2 image
  virtualisation.diskSize = 50 * 1024;  # 50GB in MB

  # Memory size for build VM (needs more memory for large closure)
  virtualisation.memorySize = 4096;  # 4GB for build process

  # ========== HEADLESS WAYLAND CONFIGURATION (Feature 046) ==========

  # Enable Sway compositor
  programs.sway.enable = true;

  # Enable wayvnc VNC server for remote access
  services.wayvnc.enable = true;

  # Enable dotool for keyboard/mouse automation
  services.udev.extraRules = ''
    # Allow input group to access uinput for dotool
    KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess"
  '';

  # Display manager: greetd with auto-login for headless operation
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.writeShellScript "sway-with-env" ''
          export WLR_BACKENDS=headless
          export WLR_HEADLESS_OUTPUTS=3
          export WLR_LIBINPUT_NO_DEVICES=1
          export WLR_RENDERER=pixman
          export XDG_SESSION_TYPE=wayland
          export XDG_CURRENT_DESKTOP=sway
          export QT_QPA_PLATFORM=wayland
          export GDK_BACKEND=wayland
          export GSK_RENDERER=cairo
          export WLR_NO_HARDWARE_CURSORS=1
          exec ${pkgs.sway}/bin/sway
        ''}";
        user = "vpittamp";
      };
    };
  };

  # Environment variables for headless Wayland operation
  environment.sessionVariables = {
    WLR_BACKENDS = "headless";
    WLR_HEADLESS_OUTPUTS = "3";
    WLR_LIBINPUT_NO_DEVICES = "1";
    WLR_RENDERER = "pixman";
    WLR_NO_HARDWARE_CURSORS = "1";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "sway";
    QT_QPA_PLATFORM = "wayland";
    GDK_BACKEND = "wayland";
    GSK_RENDERER = "cairo";
  };

  # XDG portals for Wayland dialogs and file pickers
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
    config.common.default = [ "wlr" "gtk" ];
  };

  # User lingering for persistent session after SSH logout
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/vpittamp 0644 root root - -"
  ];

  # Feature 117: i3 Project Daemon now runs as home-manager user service
  # Daemon lifecycle managed by graphical-session.target (see home-vpittamp.nix)

  # Sway Tree Diff Monitor (Feature 064) - Real-time window state monitoring
  services.sway-tree-monitor = {
    enable = true;
    bufferSize = 500;  # Circular buffer size (default)
    logLevel = "INFO";
  };

  # Firewall - open additional ports for services
  networking.firewall = {
    allowedTCPPorts = [
      22     # SSH
      5900   # VNC (wayvnc)
      8080   # Web services
    ];
    interfaces."tailscale0".allowedTCPPorts = [
      5900   # VNC via Tailscale - HEADLESS-1
      5901   # VNC via Tailscale - HEADLESS-2
      5902   # VNC via Tailscale - HEADLESS-3
    ];
    # Tailscale
    checkReversePath = "loose";
  };

  # Consolidated 1Password configuration
  services.onepassword = {
    enable = true;
    user = "vpittamp";

    # GUI disabled for headless server
    gui.enable = false;

    # Enable automation for service account operations
    automation = {
      enable = true;
      tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
    };

    # Enable automatic password management
    passwordManagement = {
      enable = true;
      users.vpittamp = {
        enable = true;
        passwordReference = "op://CLI/NixOS User Password/password";
      };
      updateInterval = "hourly";
    };

    # SSH agent integration
    ssh.enable = true;
  };

  # Firefox with 1Password and PWA support
  programs.firefox-1password = {
    enable = true;
    enablePWA = true;  # Enable PWA support
  };

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
    dotool        # Keyboard/mouse automation for Wayland (simpler than ydotool, no daemon)

    # Terminal emulators
    ghostty       # Scratchpad terminal (Feature 062)

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

  # wshowkeys setuid wrapper for workspace mode visual feedback
  security.wrappers.wshowkeys = {
    owner = "root";
    group = "input";
    setuid = true;
    source = "${pkgs.wshowkeys}/bin/wshowkeys";
  };

  # Stream audio over Tailscale to Surface laptop
  services.tailscaleAudio = {
    enable = true;
    destinationAddress = "100.122.146.117";
    destinationPort = 4010;
    sessionName = "hetzner-sway";
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
