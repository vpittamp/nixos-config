# Acer Swift Go 16 Configuration
# Intel Core Ultra CPU with Intel Arc integrated graphics
# Physical laptop with Sway/Wayland desktop environment
{ config, lib, pkgs, inputs, ... }:

let
  # Firefox 146+ overlay for native Wayland fractional scaling support
  pkgs-unstable = import inputs.nixpkgs-bleeding {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  imports = [
    # Base configuration
    ./base.nix

    # Hardware
    ../hardware/acer.nix

    # Desktop environment (Sway - Wayland compositor)
    ../modules/desktop/sway.nix

    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/i3-project-daemon.nix
    ../modules/services/speech-to-text-safe.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix
  ];

  # Firefox 146+ overlay for native Wayland fractional scaling support
  nixpkgs.overlays = [
    (final: prev: {
      firefox = pkgs-unstable.firefox;
      firefox-unwrapped = pkgs-unstable.firefox-unwrapped;
    })
  ];

  # System identification
  networking.hostName = "nixos-acer";

  # Enable Sway Wayland compositor
  services.sway.enable = true;

  # i3 Project Management Daemon
  services.i3ProjectDaemon = {
    enable = true;
    user = "vpittamp";
    logLevel = "DEBUG";
  };

  # Display manager - greetd for Wayland/Sway login
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd sway";
        user = "greeter";
      };
    };
  };

  # Speech-to-text service
  services.speech-to-text = {
    enable = true;
    model = "base.en";
    language = "en";
    enableGlobalShortcut = true;
    voskModelPackage = pkgs.callPackage ../pkgs/vosk-model-en-us-0.22-lgraph.nix { };
  };

  # wshowkeys setuid wrapper for workspace mode visual feedback
  security.wrappers.wshowkeys = {
    owner = "root";
    group = "input";
    setuid = true;
    source = "${pkgs.wshowkeys}/bin/wshowkeys";
  };

  # Swap configuration - 16GB swap file (good for 16GB RAM laptop)
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16384; # 16GB swap for hibernation support
    }
  ];

  # Memory management tweaks
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_ratio" = 10;
  };

  # Boot configuration for standard x86_64 UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Increase tmpfs size for kernel builds
  boot.tmp.tmpfsSize = "75%";

  # Kernel parameters for Intel hardware
  boot.kernelParams = [
    # Intel graphics tweaks
    "i915.enable_psr=0"           # Disable Panel Self Refresh (can cause flickering)
    "i915.enable_fbc=1"           # Enable framebuffer compression
    # Power management
    "intel_pstate=active"         # Use Intel P-state driver
  ];

  # Fix intermittent home-manager activation failures during nixos-rebuild
  systemd.services.home-manager-vpittamp = {
    wants = [ "i3-project-daemon.socket" ];
    after = [ "i3-project-daemon.socket" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "2s";
      StartLimitBurst = 3;
      StartLimitIntervalSec = 30;
    };
  };

  # NetworkManager for WiFi
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";  # IWD is generally better on Intel WiFi
  };

  # Enable IWD for WiFi (better for Intel WiFi cards)
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General = {
        EnableNetworkConfiguration = true;
      };
      Settings = {
        AutoConnect = true;
      };
    };
  };

  # Fonts - Nerd Fonts for SwayNC/Eww glyph icons
  fonts = {
    packages = let nerdFonts = pkgs."nerd-fonts"; in [
      nerdFonts.jetbrains-mono
      nerdFonts.fira-code
      nerdFonts.ubuntu
      nerdFonts.symbols-only
    ];
    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font Mono" ];
      sansSerif = [ "Ubuntu Nerd Font" ];
    };
  };

  # Display configuration
  # Swift Go 16 has a 16" WQXGA (2560x1600) display at ~190 PPI
  services.xserver = {
    dpi = 144;  # Good balance for 16" WQXGA

    serverFlagsSection = ''
      Option "DPI" "144 x 144"
    '';

    videoDrivers = [ "modesetting" ];  # Use modesetting for Intel Arc
  };

  # Display scaling configuration for Wayland
  environment.sessionVariables = {
    # Cursor size for HiDPI (at 1.5x scaling)
    XCURSOR_SIZE = "36";

    # Java applications scaling
    _JAVA_OPTIONS = "-Dsun.java2d.uiScale=1.5";

    # Electron apps
    ELECTRON_FORCE_IS_PACKAGED = "true";
  };

  # Touchpad configuration with natural scrolling
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      tapping = true;
      clickMethod = "clickfinger";
      disableWhileTyping = true;
      scrollMethod = "twofinger";
      accelProfile = "adaptive";
      accelSpeed = "0.0";
    };
  };

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU configuration
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  # Hardware acceleration
  hardware.graphics.enable = true;

  # Firmware updates
  hardware.enableRedistributableFirmware = true;

  # Enable fwupd for firmware updates (LVFS)
  services.fwupd.enable = true;

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # 1Password configuration
  services.onepassword = {
    enable = true;
    user = "vpittamp";

    gui.enable = true;

    automation = {
      enable = true;
      tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
    };

    passwordManagement = {
      enable = false;
      users.vpittamp = {
        enable = true;
        passwordReference = "op://CLI/NixOS User Password/password";
      };
      updateInterval = "hourly";
    };

    ssh.enable = true;
  };

  # Firefox with 1Password and PWA support
  programs.firefox-1password = {
    enable = true;
    enablePWA = true;
  };

  # Fallback password for initial setup
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";

  # Add user to required groups
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" "video" "seat" "input" ];

  # Bluetooth support
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
      };
    };
  };

  # Bluetooth manager GUI
  services.blueman.enable = true;

  # UPower for battery monitoring
  services.upower.enable = true;

  # TLP for better laptop power management
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";

      # Intel CPU specific
      CPU_HWP_DYN_BOOST_ON_AC = 1;
      CPU_HWP_DYN_BOOST_ON_BAT = 0;

      # WiFi power saving
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";

      # USB autosuspend
      USB_AUTOSUSPEND = 1;

      # Runtime PM for PCIe
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";

      # Battery charge thresholds (if supported)
      # START_CHARGE_THRESH_BAT0 = 75;
      # STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  # Disable power-profiles-daemon (conflicts with TLP)
  services.power-profiles-daemon.enable = false;

  # Thermald for Intel thermal management
  services.thermald.enable = true;

  # Additional packages for laptop
  environment.systemPackages = with pkgs; [
    # Terminal
    ghostty

    # Brightness control
    brightnessctl

    # Firefox PWA support
    firefoxpwa
    imagemagick
    librsvg

    # Remote access
    tailscale
    remmina

    # 1Password GUI
    _1password-gui

    # Power management utilities
    powertop
    acpi

    # Hardware info
    pciutils
    usbutils
    lshw
  ];

  # Firefox configuration with PWA support
  programs.firefox = {
    enable = lib.mkDefault true;
    nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
  };

  # Tailscale VPN
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    checkReversePath = "loose";  # For Tailscale
  };

  # System state version
  system.stateVersion = "25.11";
}
