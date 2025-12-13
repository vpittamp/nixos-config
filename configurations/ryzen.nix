# AMD Ryzen Desktop Configuration
# AMD Ryzen 5 7600X3D (Zen 4 with 3D V-Cache) - 6 cores, 4.1GHz base, 96MB L3
# NVIDIA GeForce RTX 5070 (GB205, Blackwell architecture)
# Physical desktop with Sway/Wayland desktop environment
#
# BARE METAL ADVANTAGES over Hetzner VM / M1 / WSL2:
# - Full KVM virtualization with virt-manager and GPU passthrough
# - Hardware video encoding/decoding (NVENC/NVDEC)
# - TPM 2.0 for secure boot and encryption
# - Native Vulkan with NVIDIA driver
# - Full PipeWire with low-latency audio
# - Printing support
#
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
    ../hardware/ryzen.nix

    # nixos-hardware modules for AMD CPU + NVIDIA GPU desktop
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-cpu-amd-zenpower
    inputs.nixos-hardware.nixosModules.common-pc
    inputs.nixos-hardware.nixosModules.common-pc-ssd

    # Desktop environment (Sway - Wayland compositor)
    ../modules/desktop/sway.nix

    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/i3-project-daemon.nix
    ../modules/services/speech-to-text-safe.nix

    # Bare metal optimizations (KVM, Podman, gaming, printing, TPM, etc.)
    ../modules/services/bare-metal.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix
  ];

  # Firefox 146+ overlay for native Wayland fractional scaling support
  nixpkgs.overlays = [
    (final: prev: {
      firefox = pkgs-unstable.firefox;
      firefox-unwrapped = pkgs-unstable.firefox-unwrapped;
    })
    # Disable flaky tests for i3ipc Python package
    # The test_scratchpad test fails with ConnectionResetError in sandboxed builds
    (final: prev: {
      python3 = prev.python3.override {
        packageOverrides = python-final: python-prev: {
          i3ipc = python-prev.i3ipc.overridePythonAttrs (old: {
            doCheck = false;
          });
        };
      };
      python3Packages = final.python3.pkgs;
      python311 = prev.python311.override {
        packageOverrides = python-final: python-prev: {
          i3ipc = python-prev.i3ipc.overridePythonAttrs (old: {
            doCheck = false;
          });
        };
      };
      python311Packages = final.python311.pkgs;
    })
  ];

  # System identification
  networking.hostName = "ryzen";

  # Enable Sway Wayland compositor
  services.sway.enable = true;

  # ========== BARE METAL FEATURES ==========
  # These are NOT possible on Hetzner VM, M1/Asahi, or WSL2
  services.bare-metal = {
    enable = true;

    # Full KVM virtualization with virt-manager
    # (Hetzner: no nested KVM, M1: ARM only, WSL2: no KVM)
    enableVirtualization = true;

    # Podman rootless containers (complement to Docker)
    enablePodman = true;

    # Printing support with CUPS
    enablePrinting = true;

    # No gaming needed
    enableGaming = false;

    # No fingerprint reader on desktop
    enableFingerprint = false;
  };

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
        # Use --unsupported-gpu flag for NVIDIA GPUs with Wayland
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd 'sway --unsupported-gpu'";
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

  # Swap configuration - 16GB swap (desktop with 32GB RAM, no hibernation needed)
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16384; # 16GB swap
    }
  ];

  # Memory management tweaks for desktop workstation
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_ratio" = 10;
    # Higher max memory map count for development workloads
    "vm.max_map_count" = 1048576;
  };

  # Boot configuration for standard x86_64 UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Increase tmpfs size for kernel builds
  boot.tmp.tmpfsSize = "75%";

  # Kernel parameters for AMD Ryzen 7600X3D
  boot.kernelParams = [
    # AMD-specific
    "amd_pstate=active"           # Use AMD P-State driver for Zen 4
    # Performance settings for desktop
    "mitigations=off"             # Optional: disable CPU mitigations for max performance
                                  # Remove this line if security is priority
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

  # NetworkManager for ethernet (desktop)
  networking.networkmanager = {
    enable = true;
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

  # Display configuration for desktop
  # Adjust DPI based on your monitor
  services.xserver = {
    dpi = 96;  # Standard DPI, adjust for your monitor

    serverFlagsSection = ''
      Option "DPI" "96 x 96"
    '';

    videoDrivers = [ "nvidia" ];  # NVIDIA GPU driver
  };

  # ========== NVIDIA GPU CONFIGURATION ==========
  hardware.nvidia = {
    # Use the stable driver (580.x supports RTX 5070)
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Modesetting is required for Wayland
    modesetting.enable = true;

    # Enable power management (experimental but recommended for newer cards)
    powerManagement.enable = true;

    # Use the open source kernel modules (recommended for RTX 30+ series)
    # RTX 5070 (Blackwell) should work with open modules
    open = true;

    # Enable the nvidia-settings GUI
    nvidiaSettings = true;
  };

  # Display scaling configuration for Wayland
  environment.sessionVariables = {
    # Cursor size
    XCURSOR_SIZE = "24";

    # Java applications scaling
    _JAVA_OPTIONS = "-Dsun.java2d.uiScale=1.0";

    # Electron apps
    ELECTRON_FORCE_IS_PACKAGED = "true";

    # ========== NVIDIA WAYLAND ENVIRONMENT ==========
    # Required for NVIDIA on Wayland
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";

    # Enable Wayland for Electron apps
    NIXOS_OZONE_WL = "1";

    # For hardware cursors on NVIDIA Wayland
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU configuration - performance for desktop
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";

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

  # No battery-related services for desktop (no TLP, no UPower battery monitoring)

  # Additional packages for desktop
  environment.systemPackages = with pkgs; [
    # Terminal
    ghostty

    # Firefox PWA support
    firefoxpwa
    imagemagick
    librsvg

    # Remote access
    tailscale
    remmina
    wayvnc  # VNC server for Wayland remote access

    # 1Password GUI
    _1password-gui

    # Hardware monitoring tools
    lm_sensors     # Temperature monitoring
    zenmonitor     # AMD Ryzen monitoring
    corectrl       # AMD GPU/CPU control panel

    # Hardware info
    pciutils
    usbutils
    lshw

    # ========== BARE METAL EXCLUSIVE PACKAGES ==========
    # These require physical hardware (not available on Hetzner/M1/WSL)

    # NVIDIA GPU tools
    nvtopPackages.nvidia  # NVIDIA GPU monitoring TUI
    libva-utils    # VA-API verification (vainfo)
    vdpauinfo      # VDPAU verification
    vulkan-tools   # Vulkan verification (vulkaninfo)
    clinfo         # OpenCL verification
    cudaPackages.cuda_nvcc  # CUDA compiler (optional, for CUDA development)

    # Disk encryption and security
    cryptsetup     # LUKS disk encryption
    yubikey-manager  # YubiKey management (if you have one)

    # Hardware monitoring
    s-tui          # Stress test + monitoring TUI
    stress-ng      # CPU stress testing

    # USB device management
    udiskie        # Automount USB drives

    # ========== SCREEN RECORDING (Feature 115) ==========
    # Hardware-accelerated screen recording with NVIDIA NVENC
    wf-recorder       # Wayland screen recorder with NVENC support
    grim              # Screenshot utility for Wayland
    slurp             # Region selection for screenshots/recording

    # ========== WEBCAM SUPPORT (Feature 115) ==========
    # V4L2 support for USB webcams
    v4l-utils         # Video4Linux utilities
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
    extraUpFlags = [ "--ssh" "--accept-routes" ];
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 5900 ];  # SSH and VNC
    checkReversePath = "loose";  # For Tailscale
  };

  # ========== ADVANCED AUDIO (BARE METAL) ==========
  # Full PipeWire with low-latency for gaming
  # (Hetzner: audio streaming only, M1: limited support)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;  # Required for 32-bit games
    pulse.enable = true;
    jack.enable = true;

    # Low-latency audio configuration (good for gaming)
    extraConfig.pipewire = {
      "92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 256;
          "default.clock.min-quantum" = 32;
          "default.clock.max-quantum" = 1024;
        };
      };
    };
  };

  # Enable rtkit for real-time audio scheduling
  security.rtkit.enable = true;

  # ========== USB AUTOMOUNT ==========
  # Automatic mounting of USB drives
  services.udisks2.enable = true;
  services.gvfs.enable = true;  # For GUI file managers

  # System state version
  system.stateVersion = "25.11";
}
