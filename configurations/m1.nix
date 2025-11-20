# M1 MacBook Pro Configuration
# Apple Silicon variant with desktop environment
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Base configuration
    ./base.nix

    # Environment check
    ../modules/assertions/m1-check.nix

    # Hardware
    ../hardware/m1.nix

    # Apple Silicon support - CRITICAL for hardware functionality
    inputs.nixos-apple-silicon.nixosModules.default

    # Desktop environment (Sway - Feature 045 migration from KDE Plasma)
    # Sway Wayland compositor for keyboard-driven productivity with i3pm integration
    ../modules/desktop/sway.nix
    # ../modules/desktop/remote-access.nix  # DISABLED: RDP/XRDP replaced with wayvnc
    # ../modules/desktop/wireless-display.nix  # DISABLED: Miracast/X11-specific

    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/i3-project-daemon.nix       # Feature 037: Project management daemon
    ../modules/desktop/wayvnc.nix                   # Feature 084: VNC for virtual displays
    ../modules/services/onepassword-automation.nix  # Service account automation
    ../modules/services/onepassword-password-management.nix
    ../modules/services/speech-to-text-safe.nix # Safe version without network dependencies
    ../modules/services/home-assistant.nix
    ../modules/services/scrypted.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix
    ../modules/desktop/firefox-pwa-1password.nix
  ];

  # Provide DisplayLink binaries automatically by fetching from Synaptics.
  # This honours the upstream hash while sparing an extra manual nix-prefetch
  # step; keep in mind that enabling this implies acceptance of Synaptics' EULA.
  # DISABLED: Version mismatch - zip contains 6.1.0-17 but nix expects 6.2.0-30
  # nixpkgs.overlays = [
  #   (final: prev: {
  #     displaylink = prev.displaylink.overrideAttrs (old: {
  #       src = prev.fetchurl {
  #         name = "displaylink-610.zip";
  #         url = "https://www.synaptics.com/sites/default/files/exe_files/2024-10/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.1-EXE.zip";
  #         sha256 = "sha256-RJgVrX+Y8Nvz106Xh+W9N9uRLC2VO00fBJeS8vs7fKw=";
  #       };
  #       meta = old.meta // { available = true; };
  #     });
  #   })
  # ];

  # System identification
  networking.hostName = "nixos-m1";

  # Enable Sway Wayland compositor (Feature 045)
  services.sway.enable = true;

  # i3 Project Management Daemon (Feature 037)
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

  # Speech-to-text service - safe version enabled
  services.speech-to-text = {
    enable = true;
    model = "base.en"; # Good balance of speed and accuracy
    language = "en";
    enableGlobalShortcut = true;
    voskModelPackage = pkgs.callPackage ../pkgs/vosk-model-en-us-0.22-lgraph.nix { };
  };

  # wshowkeys setuid wrapper for workspace mode visual feedback (Feature 042)
  # Provides on-screen overlay showing keypresses when navigating workspaces
  security.wrappers.wshowkeys = {
    owner = "root";
    group = "input";
    setuid = true;
    source = "${pkgs.wshowkeys}/bin/wshowkeys";
  };

  # Swap configuration - 8GB swap file for memory pressure relief
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8192; # 8GB swap
    }
  ];

  # Memory management tweaks for better performance
  boot.kernel.sysctl = {
    "vm.swappiness" = 10; # Reduce swap usage unless necessary
    "vm.vfs_cache_pressure" = 50; # Balance between caching and reclaiming memory
    "vm.dirty_background_ratio" = 5; # Start writing dirty pages earlier
    "vm.dirty_ratio" = 10; # Force synchronous I/O earlier
  };

  # System activation script for VSCode Tailscale extension workaround
  system.activationScripts.vscodeSSHConfigWorkaround = ''
    # Ensure SSH config is accessible for VSCode Tailscale extension
    # The extension incorrectly looks for /~/.ssh/config instead of expanding ~

    # Create user's SSH directory if it doesn't exist
    mkdir -p /home/vpittamp/.ssh

    # Ensure the SSH config exists with correct permissions
    if [ ! -f /home/vpittamp/.ssh/config ]; then
      touch /home/vpittamp/.ssh/config
      chown vpittamp:users /home/vpittamp/.ssh/config
      chmod 600 /home/vpittamp/.ssh/config
    fi

    # Create a secondary location that some tools might check
    # This handles the case where the extension might be looking for $HOME/.ssh/config
    # but with incorrect path resolution
    if [ -f /home/vpittamp/.ssh/config ]; then
      # Ensure the config has the right permissions
      chmod 600 /home/vpittamp/.ssh/config
      chown vpittamp:users /home/vpittamp/.ssh/config
    fi
  '';

  # WiFi firmware workaround for BCM4378 stability issues
  # This disables power management features that can cause firmware crashes
  boot.kernelParams = [ "brcmfmac.feature_disable=0x82000" ];

  # Fix intermittent home-manager activation failures during nixos-rebuild
  # The checkLinkTargets phase occasionally fails with "broken pipe" errors
  # due to race conditions in find/xargs pipelines. Retry automatically.
  systemd.services.home-manager-vpittamp = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "2s";
      StartLimitBurst = 3;
      StartLimitIntervalSec = 30;
    };
  };

  # WiFi recovery service - reload module if it fails on boot
  systemd.services.wifi-recovery = {
    description = "WiFi module recovery for BCM4378";
    after = [ "network-pre.target" ];
    before = [ "network.target" "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.kmod}/bin/modprobe brcmfmac";
      ExecStartPre = [
        "-${pkgs.kmod}/bin/modprobe -r brcmfmac"
        "${pkgs.coreutils}/bin/sleep 2"
      ];
    };
  };

  # Boot configuration for Apple Silicon
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5; # Keep only 5 generations to prevent EFI space issues
  boot.loader.efi.canTouchEfiVariables = false; # Different on Apple Silicon

  # Increase tmpfs size for kernel builds - default is 50% of RAM, increase to 75%
  boot.tmp.tmpfsSize = "75%";

  # Apple Silicon specific settings
  boot.initrd.availableKernelModules = [
    "brcmfmac"
    "xhci_pci" # USB 3.0
    "usbhid" # USB HID devices
    "usb_storage" # USB storage
    "nvme" # NVMe SSD support
  ];

  # Fix keyboard layout for US keyboards on Apple Silicon
  boot.extraModprobeConfig = ''
    options hid_apple iso_layout=0
  '';

  # Allow unprivileged control of panel + keyboard backlights
  services.udev.packages = [ pkgs.brightnessctl ];
  # Use firmware from boot partition (requires --impure flag)
  # Made conditional to allow evaluation on non-M1 systems (e.g., for CI/testing)
  hardware.asahi.peripheralFirmwareDirectory =
    let path = /boot/asahi; in
    if builtins.pathExists path then path
    else builtins.throw "Missing /boot/asahi; copy firmware with asahi-fwextract before building the M1 system";

  # Ensure the real firmware payloads are extracted so Wi-Fi/BT work on Apple Silicon.
  hardware.asahi.extractPeripheralFirmware = true;

  # Use NetworkManager with wpa_supplicant for WiFi (more stable on Apple Silicon)
  networking.networkmanager = {
    enable = true;
    wifi.backend = "wpa_supplicant"; # Use wpa_supplicant for better stability
  };

  # Disable IWD - conflicts with NetworkManager on Apple Silicon
  networking.wireless.iwd.enable = false;

  # Provide Nerd Fonts so SwayNC/Eww glyph icons render correctly
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

  # Display configuration for Retina display
  # Wayland handles HiDPI much better than X11
  services.xserver = {
    dpi = 180; # Still useful for XWayland applications

    # Keep X11 server config for XWayland apps
    serverFlagsSection = ''
      Option "DPI" "180 x 180"
    '';

    # Add DisplayLink (USB graphics) stack for external monitor docks
    # DISABLED: displaylink has version mismatch issues
    videoDrivers = lib.mkForce [ "modesetting" "fbdev" ];
  };

  # Display scaling configuration
  # Note: Wayland environment variables (MOZ_ENABLE_WAYLAND, NIXOS_OZONE_WL, QT_QPA_PLATFORM)
  # are now configured in modules/desktop/sway.nix (FR-004)
  environment.sessionVariables = {
    # Cursor size for HiDPI (at 2x scaling for Retina)
    XCURSOR_SIZE = "48";  # 24 * 2 for Retina display

    # Java applications need explicit scaling for Retina
    _JAVA_OPTIONS = "-Dsun.java2d.uiScale=2.0";

    # Force Electron apps to detect scale from display
    ELECTRON_FORCE_IS_PACKAGED = "true";
  };

  # Touchpad configuration with natural scrolling (Apple-style)
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true; # Reverse scroll direction (Apple-style)
      tapping = true; # Tap to click
      clickMethod = "clickfinger"; # Two-finger right-click
      disableWhileTyping = true;
      scrollMethod = "twofinger";
      # Additional Wayland-friendly settings
      accelProfile = "adaptive"; # Better acceleration curve
      accelSpeed = "0.0"; # Default acceleration
    };
  };

  # Override default session to use Sway (configured in modules/desktop/sway.nix)
  # services.displayManager.defaultSession is set by Sway module

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # CPU configuration for Apple M1
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";

  # Hardware acceleration support
  hardware.graphics.enable = true;

  # Asahi GPU driver configuration (optional - uncomment if needed)
  # hardware.asahi.useExperimentalGPUDriver = true;
  # hardware.asahi.experimentalGPUInstallMode = "replace";  # Use Asahi Mesa

  # Firmware updates
  hardware.enableRedistributableFirmware = true;



  # Automatic garbage collection to prevent space issues
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Enable 1Password password management
  services.onepassword-password-management = {
    enable = false;
    users.vpittamp = {
      enable = true;
      passwordReference = "op://CLI/NixOS User Password/password";
    };
    updateInterval = "hourly";  # Check for password changes hourly
  };

  # 1Password Automation for service account operations
  services.onepassword-automation = {
    enable = true;
    user = "vpittamp";
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
  };

  # Fallback password for initial setup before 1Password is configured
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";

  # Add user to required groups for Wayland/Sway (video for DRM access, seat for seatd, input for wshowkeys)
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" "video" "seat" "input" ];

  # Bluetooth support
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;  # Power on bluetooth controller on boot
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;  # Enable experimental features (better device support)
      };
    };
  };

  # Bluetooth manager GUI
  services.blueman.enable = true;

  # UPower for battery monitoring (required by swaybar-enhanced battery indicator)
  services.upower.enable = true;

  # Disable X11-specific services (migrated to Sway/Wayland - Feature 045)
  services.xrdp.enable = lib.mkForce false; # RDP replaced with wayvnc for Wayland
  services.touchegg.enable = lib.mkForce false; # Sway has native Wayland gestures

  # Fix DrKonqi coredump processor timeout issue
  systemd.services."drkonqi-coredump-processor@" = {
    serviceConfig = {
      TimeoutStartSec = "30s"; # Reduce from default 5min
      TimeoutStopSec = "10s";
    };
  };

  # RustDesk service configuration
  # DISABLED: Module doesn't exist yet - RustDesk installed as user package instead
  # services.rustdesk = {
  #   enable = true;
  #   user = "vpittamp";
  #   enableDirectIpAccess = true;
  # };

  # Additional packages for Apple Silicon
  environment.systemPackages = with pkgs; [
    # Tools that work well on ARM
    ghostty

    # Local brightness/backlight controls used by Sway keybindings
    brightnessctl

    # Firefox PWA support (same as Hetzner)
    firefoxpwa # Native component for Progressive Web Apps

    # Image processing for PWA icons
    imagemagick # For converting and manipulating images
    librsvg # For SVG to PNG conversion

    # Remote access (rustdesk-flutter managed by service module)
    tailscale         # Zero-config VPN
    remmina           # VNC/RDP client for connecting to Hetzner

    # 1Password GUI - needed for git-credential-1password helper
    _1password-gui    # Contains op-ssh-sign and git-credential-1password

    # Testing framework (Feature 069/070) - DISABLED: __noChroot conflicts with sandbox
    # (pkgs.callPackage ../home-modules/tools/sway-test/default.nix { })
  ];

  # Firefox configuration with PWA support (same as Hetzner)
  programs.firefox = {
    enable = lib.mkDefault true;
    nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
  };

  # Note: PWA installation and management:
  # - The firefoxpwa package and Firefox native messaging are configured
  # - To install PWAs: firefoxpwa site install <url>
  # - To list PWAs: firefoxpwa profile list
  # - For declarative PWA management, use home-manager with firefox-pwas-managed.nix module
  # - Desktop entries will be created in ~/.local/share/applications/

  # ========== TAILSCALE ==========
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];  # SSH (RustDesk ports managed by rustdesk service)
    # Tailscale
    checkReversePath = "loose";
    # Feature 084: VNC ports restricted to Tailscale network only
    interfaces."tailscale0".allowedTCPPorts = [ 5900 5901 ];
  };

  # System state version
  system.stateVersion = "25.11";
}
