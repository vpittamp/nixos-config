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

    # Desktop environment
    ../modules/desktop/kde-plasma.nix
    ../modules/desktop/remote-access.nix
    ../modules/desktop/wireless-display.nix

    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/speech-to-text-safe.nix # Safe version without network dependencies
    ../modules/services/home-assistant.nix
    ../modules/services/scrypted.nix # Bridge for Circle View cameras and HomeKit devices
    ../modules/services/rustdesk.nix # RustDesk remote desktop with autostart

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

  # Speech-to-text service - safe version enabled
  services.speech-to-text = {
    enable = true;
    model = "base.en"; # Good balance of speed and accuracy
    language = "en";
    enableGlobalShortcut = true;
    voskModelPackage = pkgs.callPackage ../pkgs/vosk-model-en-us-0.22-lgraph.nix { };
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
  # Use firmware from boot partition (requires --impure flag)
  # Made conditional to allow evaluation on non-M1 systems (e.g., for CI/testing)
  hardware.asahi.peripheralFirmwareDirectory =
    if builtins.pathExists /boot/asahi
    then /boot/asahi
    else
      builtins.trace "WARNING: /boot/asahi not found - using dummy for evaluation only (not deployable!)"
        (pkgs.runCommand "dummy-asahi-firmware" { } "mkdir -p $out");

  # Use NetworkManager with wpa_supplicant for WiFi (more stable on Apple Silicon)
  networking.networkmanager = {
    enable = true;
    wifi.backend = "wpa_supplicant"; # Use wpa_supplicant for better stability
  };

  # Disable IWD - conflicts with NetworkManager on Apple Silicon
  networking.wireless.iwd.enable = false;

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

  # Wayland and display scaling configuration
  environment.sessionVariables = {
    # Enable Wayland for compatible applications
    MOZ_ENABLE_WAYLAND = "1"; # Enable Wayland for Firefox
    NIXOS_OZONE_WL = "1"; # Enable Wayland for Electron apps (VSCode, 1Password)

    # Qt scaling - let KDE Plasma handle it under Wayland
    QT_AUTO_SCREEN_SCALE_FACTOR = "1"; # Enable Qt auto-scaling
    PLASMA_USE_QT_SCALING = "1"; # Let Plasma handle Qt scaling

    # IMPORTANT: Don't set GDK_SCALE globally - KDE already handles 1.75x scaling
    # Setting it causes double-scaling for Electron apps
    # Applications should detect scaling from Wayland/KDE directly

    # Cursor size for HiDPI (at 1.75x scaling)
    XCURSOR_SIZE = "42";

    # Java applications need explicit scaling
    _JAVA_OPTIONS = "-Dsun.java2d.uiScale=1.75";

    # Force Electron apps to detect scale from display, not GDK
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

  # Override default session to use Wayland
  services.displayManager.defaultSession = lib.mkForce "plasma"; # Wayland session for KDE Plasma

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

  # Set initial password for user (change after first login!)
  users.users.vpittamp.initialPassword = "nixos";

  # Disable services that don't work well on Apple Silicon
  services.xrdp.enable = lib.mkForce false; # RDP doesn't work well on M1

  # Enable touchegg only for X11 sessions (Wayland has native gestures)
  services.touchegg.enable = lib.mkForce false;

  # Fix DrKonqi coredump processor timeout issue
  systemd.services."drkonqi-coredump-processor@" = {
    serviceConfig = {
      TimeoutStartSec = "30s"; # Reduce from default 5min
      TimeoutStopSec = "10s";
    };
  };

  # RustDesk service configuration
  services.rustdesk = {
    enable = true;
    user = "vpittamp";
    enableDirectIpAccess = true;
  };

  # Additional packages for Apple Silicon
  environment.systemPackages = with pkgs; [
    # Tools that work well on ARM
    neovim
    alacritty

    # Firefox PWA support (same as Hetzner)
    firefoxpwa # Native component for Progressive Web Apps

    # Image processing for PWA icons
    imagemagick # For converting and manipulating images
    librsvg # For SVG to PNG conversion

    # Remote access (rustdesk-flutter managed by service module)
    tailscale         # Zero-config VPN
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
  };

  # System state version
  system.stateVersion = "25.11";
}
