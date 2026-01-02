# Lenovo ThinkPad Configuration
# Intel Core Ultra 7 155U (Meteor Lake) with Intel Arc integrated graphics
# Physical laptop with Sway/Wayland desktop environment
#
# BARE METAL ADVANTAGES over Hetzner VM / M1 / WSL2:
# - Full KVM virtualization with virt-manager
# - Hardware video encoding/decoding (Intel QuickSync)
# - TPM 2.0 for secure boot and encryption
# - Native suspend/hibernate to disk
# - Fingerprint reader support
# - Full PipeWire with low-latency audio
# - Printing and scanning support
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
    ../hardware/thinkpad.nix

    # nixos-hardware modules for Intel laptops
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd

    # ThinkPad-specific optimizations (TrackPoint, etc.)
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad

    # Desktop environment (Sway - Wayland compositor)
    ../modules/desktop/sway.nix

    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/otel-ai-collector.nix  # Feature 123: AI telemetry collector (legacy, replaced by Alloy)
    ../modules/services/grafana-alloy.nix      # Feature 129: Unified OTEL collector
    ../modules/services/grafana-beyla.nix      # Feature 129: eBPF auto-instrumentation
    ../modules/services/arize-phoenix.nix      # Feature 129 Enhancement: GenAI tracing
    ../modules/services/pyroscope-agent.nix    # Feature 129: Continuous profiling
    ../modules/services/litellm-proxy.nix      # Feature 123: LiteLLM proxy for full OTEL traces
    # Feature 117: System service removed - now runs as home-manager user service
    ../modules/services/speech-to-text-safe.nix

    # Bare metal optimizations (KVM, Podman, printing, TPM, etc.)
    ../modules/services/bare-metal.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix

    # Sunshine game streaming (Intel Quick Sync hardware encoding)
    ../modules/desktop/sunshine.nix
  ];

  # Firefox 146+ overlay for native Wayland fractional scaling support
  nixpkgs.overlays = [
    (final: prev: {
      firefox = pkgs-unstable.firefox;
      firefox-unwrapped = pkgs-unstable.firefox-unwrapped;
    })
  ];

  # System identification
  networking.hostName = "thinkpad";

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
    # (Hetzner: headless server, WSL2: use Windows printing)
    enablePrinting = true;

    # Fingerprint reader (ThinkPad has built-in fingerprint sensor)
    # Enable after enrolling fingerprint with: fprintd-enroll
    enableFingerprint = true;

    # No gaming on laptop (battery life)
    enableGaming = false;
  };

  # ========== SUNSHINE REMOTE DESKTOP (Quick Sync) ==========
  # Hardware-accelerated game streaming with Intel Arc Quick Sync encoder
  # Client: Moonlight (available on all platforms)
  # Access: moonlight://<tailscale-ip>
  services.sunshine-streaming = {
    enable = true;
    hardwareType = "intel";
    captureMethod = "kms";  # Direct KMS capture for lowest latency
    tailscaleOnly = true;   # Only allow via Tailscale for security
    extraSettings = {
      # Intel Arc supports HEVC but not AV1 in Sunshine yet
      av1_mode = 0;
      # Moderate bitrate for laptop (balance quality/bandwidth)
      bitrate = 30000;
    };
  };

  # Feature 117: i3 Project Daemon now runs as home-manager user service
  # Daemon lifecycle managed by graphical-session.target (see home-vpittamp.nix)

  # Feature 129: Grafana Alloy - Unified Telemetry Collector
  # Replaces otel-ai-collector with comprehensive observability:
  # - OTLP receiver on 4318, forwards to otel-ai-monitor on 4320
  # - System metrics via node exporter → Mimir
  # - Journald logs → Loki
  # - All telemetry exported to K8s LGTM stack via cnoe.localtest.me:8443
  services.grafana-alloy = {
    enable = true;
    # Endpoints default to *.cnoe.localtest.me:8443 (local K8s cluster)
    enableNodeExporter = true;
    enableJournald = true;
    journaldUnits = [
      "grafana-alloy.service"
      "grafana-beyla.service"
      "otel-ai-monitor.service"
      "i3pm-daemon.service"
    ];

    # Feature 132: Langfuse AI Observability
    # Export traces to Langfuse for specialized LLM tracing and analytics
    langfuse = {
      enable = true;
      # Local Langfuse via cnoe.localtest.me ingress
      endpoint = "https://langfuse.cnoe.localtest.me:8443/api/public/otel";
      credentialSource = "1password";  # Use 1Password for local dev
      onePasswordRefs = {
        publicKey = "op://CLI/Langfuse/public_key";
        secretKey = "op://CLI/Langfuse/secret_key";
      };
      # Fallback: environment file for system services (1Password not available)
      environmentFile = "/etc/langfuse/credentials";
      batchTimeout = "10s";
      batchSize = 100;
    };
  };

  # Feature 123 (legacy): Disable otel-ai-collector - replaced by grafana-alloy
  services.otel-ai-collector = {
    enable = false;
  };

  # Feature 129: Grafana Beyla - eBPF Auto-Instrumentation
  services.grafana-beyla = {
    enable = true;
    openPorts = "4320,8080";  # otel-ai-monitor and i3pm ports
    executableNames = "(claude|gemini|codex|node|python3)";
    serviceName = "thinkpad-services";
  };


  # Arize Phoenix - GenAI Observability (Local)
  services.arize-phoenix.enable = false;  # Disabled: port 4317 conflicts with Alloy

  # Feature 123: LiteLLM Proxy for full OTEL tracing of Claude API calls
  # DISABLED: Incompatible with Claude Code Max subscription (OAuth authentication)
  # LiteLLM requires API keys, but Max uses OAuth tokens
  # Native Claude Code OTEL telemetry is captured by otel-ai-collector instead
  services.litellm-proxy.enable = false;

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

  # Swap configured in hardware/thinkpad.nix (uses dedicated partition)

  # ========== HIBERNATION SUPPORT ==========
  # Full suspend-to-disk (not available on Hetzner VM or WSL2)
  boot.resumeDevice = "/var/lib/swapfile";
  # Note: After installation, get swap offset with: filefrag -v /var/lib/swapfile
  # Then add: boot.kernelParams = [ "resume_offset=XXXXX" ];

  # Memory management tweaks
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_ratio" = 10;
    # Laptop-optimized writeback (less aggressive)
    "vm.laptop_mode" = 5;
  };

  # Boot configuration for standard x86_64 UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Increase tmpfs size for kernel builds
  boot.tmp.tmpfsSize = "75%";

  # Kernel parameters for Intel Core Ultra (Meteor Lake)
  boot.kernelParams = [
    # Intel graphics tweaks for Meteor Lake
    "i915.enable_psr=0"           # Disable Panel Self Refresh (can cause flickering)
    "i915.enable_fbc=1"           # Enable framebuffer compression
    # Power management
    "intel_pstate=active"         # Use Intel P-state driver
    # Meteor Lake specific
    "i915.force_probe=*"          # Force probe for newer Intel GPUs if needed
  ];

  # Feature 117: i3-project-daemon now runs as home-manager user service
  # No systemd dependency needed - user service binds to graphical-session.target
  systemd.services.home-manager-vpittamp = {
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
  # ThinkPad display - adjust DPI based on actual panel resolution
  services.xserver = {
    dpi = 120;  # Adjust based on your panel

    serverFlagsSection = ''
      Option "DPI" "120 x 120"
    '';

    videoDrivers = [ "modesetting" ];  # Use modesetting for Intel Arc
  };

  # Display scaling configuration for Wayland
  environment.sessionVariables = {
    # Cursor size for HiDPI
    XCURSOR_SIZE = "24";

    # Java applications scaling
    _JAVA_OPTIONS = "-Dsun.java2d.uiScale=1.0";

    # Electron apps
    ELECTRON_FORCE_IS_PACKAGED = "true";

    # ========== VA-API HARDWARE VIDEO ACCELERATION ==========
    # Intel Arc (Meteor Lake) uses the iHD VA-API driver
    LIBVA_DRIVER_NAME = "iHD";

    # Enable Wayland for Electron apps
    NIXOS_OZONE_WL = "1";
  };

  # Touchpad configuration with natural scrolling (ThinkPad trackpad + TrackPoint)
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

  # ========== THUNDERBOLT/USB4 SUPPORT (Feature 115) ==========
  # Enable bolt daemon for Thunderbolt device authorization
  # Allows docking stations and external displays via Thunderbolt
  services.hardware.bolt.enable = true;

  # Fingerprint reader support (Elan 04f3:0c8c MOC Sensor)
  # Enroll fingerprint with: fprintd-enroll
  # Verify with: fprintd-verify
  services.fprintd.enable = true;

  # PAM integration for fingerprint authentication
  # Keep separate from fprintd to avoid login conflicts
  # Reference: https://github.com/NixOS/nixpkgs/issues/171136
  security.pam.services = {
    # Sudo with fingerprint (fingerprint OR password)
    sudo.fprintAuth = true;

    # Screen lock (swaylock)
    swaylock.fprintAuth = true;

    # Polkit for GUI privilege escalation
    polkit-1.fprintAuth = true;

    # Login fingerprint - enable cautiously (can cause issues with some display managers)
    # greetd.fprintAuth = true;
  };

  # Polkit rules for fingerprint and 1Password integration
  security.polkit.extraConfig = lib.mkAfter ''
    // Allow wheel users to enroll fingerprints without password
    polkit.addRule(function(action, subject) {
      if (action.id == "net.reactivated.fprint.device.enroll" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });

    // Allow 1Password CLI to use biometric unlock via polkit
    polkit.addRule(function(action, subject) {
      if (action.id == "com.1password.1Password.unlock" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.AUTH_SELF;
      }
    });
  '';

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

  # Bluetooth support (common in ThinkPads)
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

      # Battery charge thresholds (ThinkPad specific - uncomment if supported)
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

    # AI Voice Typing - https://vibetyper.com
    # Voice-to-text with AI refinement (X11 fully supported, Wayland experimental)
    (callPackage ../packages/vibetyper.nix { })

    # Brightness control
    brightnessctl

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

    # Power management utilities
    powertop
    acpi
    tlp               # TLP CLI

    # ThinkPad specific tools
    tpacpi-bat        # ThinkPad ACPI battery control
    thinkfan          # ThinkPad fan control (optional, TLP handles most)

    # Hardware info
    pciutils
    usbutils
    lshw

    # ========== BARE METAL EXCLUSIVE PACKAGES ==========
    # These require physical hardware (not available on Hetzner/M1/WSL)

    # Hardware video acceleration (Intel QuickSync)
    intel-gpu-tools   # Intel GPU debugging (intel_gpu_top)
    libva-utils       # VA-API verification (vainfo)
    vdpauinfo         # VDPAU verification

    # Disk encryption and security
    cryptsetup        # LUKS disk encryption
    yubikey-manager   # YubiKey management (if you have one)

    # Hardware monitoring
    s-tui             # Stress test + monitoring TUI
    stress-ng         # CPU stress testing

    # Laptop-specific power tools
    acpid             # ACPI daemon
    upower            # Power device info

    # USB device management
    udiskie           # Automount USB drives

    # Webcam (if present)
    v4l-utils         # Video4Linux utilities
    cameractrls       # Webcam controls

    # ========== SCREEN RECORDING (Feature 115) ==========
    # Hardware-accelerated screen recording with Intel QuickSync
    wf-recorder       # Wayland screen recorder with VAAPI support
    grim              # Screenshot utility for Wayland
    slurp             # Region selection for screenshots/recording
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
  # Full PipeWire with low-latency and Bluetooth codecs
  # (Hetzner: audio streaming only, M1: limited codec support)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;  # For pro audio applications

    # Low-latency audio configuration
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

    # WirePlumber configuration for better Bluetooth
    wireplumber.extraConfig = {
      "10-bluez" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "ldac" "aptx" "aptx_hd" ];
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

  # ========== ACPI EVENTS ==========
  # Handle lid close, power button, etc.
  services.acpid = {
    enable = true;
    handlers = {
      lid-close = {
        event = "button/lid.*";
        action = ''
          case "$3" in
            close) systemctl suspend ;;
          esac
        '';
      };
    };
  };

  # System state version
  system.stateVersion = "25.11";
}
