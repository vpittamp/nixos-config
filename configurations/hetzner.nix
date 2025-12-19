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
    ../modules/services/onepassword.nix  # Consolidated 1Password module (with feature flags)
    ../modules/services/otel-ai-collector.nix  # Feature 123: AI telemetry collector
    ../modules/services/beyla.nix              # Feature 110: eBPF auto-instrumentation
    # Feature 117: System service removed - now runs as home-manager user service
    ../modules/services/keyd.nix  # Feature 050: CapsLock -> F9 for workspace mode
    ../modules/services/sway-tree-monitor.nix  # Feature 064: Sway tree diff monitor

    # Phase 2: Wayland/Sway Desktop Environment (Feature 045 modules reused)
    ../modules/desktop/sway.nix       # Sway compositor (from Feature 045)
    ../modules/desktop/wayvnc.nix     # VNC server for headless Wayland (from Feature 045)
    ../modules/desktop/sunshine.nix   # Sunshine streaming (software encoding for headless)
    ../modules/desktop/firefox-1password.nix  # Firefox with 1Password (consolidated, with PWA support)

    # Services
    ../modules/services/speech-to-text-safe.nix
    ../modules/services/tailscale-audio.nix
  ];

  # System identification
  networking.hostName = "hetzner";

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

  # Enable wayvnc VNC server for remote access (fallback, lower quality)
  services.wayvnc.enable = true;

  # ========== SUNSHINE REMOTE DESKTOP (Software Encoding) ==========
  # Software-encoded streaming for headless server (no GPU)
  # Better than VNC due to video codec compression, but higher CPU usage
  # Client: Moonlight (available on all platforms)
  # Access: moonlight://<tailscale-ip>
  services.sunshine-streaming = {
    enable = true;
    hardwareType = "software";
    captureMethod = "wlroots";  # Use wlroots screencopy for headless Sway
    tailscaleOnly = true;       # Only allow via Tailscale for security
    extraSettings = {
      # Software encoding - optimize for low latency
      sw_preset = "superfast";
      sw_tune = "zerolatency";
      # Lower bitrate for cloud server bandwidth
      bitrate = 15000;
      # Limit to 1080p for software encoding performance
      resolutions = "[1920x1080]";
      fps = "[30, 60]";
    };
  };

  # Enable dotool for keyboard/mouse automation (no daemon required)
  # Simpler and faster than ydotool - uses direct uinput access
  services.udev.extraRules = ''
    # Allow input group to access uinput for dotool
    KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess"
  '';

  # Display manager: greetd with auto-login for headless operation
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # Auto-login vpittamp user and start Sway compositor with environment variables
        # Note: greetd doesn't load environment.sessionVariables, so we export them explicitly
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
  # These are critical for Sway to run without physical displays
  environment.sessionVariables = {
    # Use headless wlroots backend (no physical display required)
    WLR_BACKENDS = "headless";

    # Number of outputs for headless backend (three displays for multi-monitor workflow)
    # This controls output creation at the wlroots backend level
    WLR_HEADLESS_OUTPUTS = "3";

    # Disable libinput (no physical input devices in headless mode)
    WLR_LIBINPUT_NO_DEVICES = "1";

    # Use pixman software rendering (no GPU acceleration in cloud VMs)
    WLR_RENDERER = "pixman";

    # Force software cursor composition so remote viewers always see the true pointer
    WLR_NO_HARDWARE_CURSORS = "1";

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
  # Required for Sway session to continue running after SSH disconnection
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/vpittamp 0644 root root - -"
  ];

  # Feature 117: i3 Project Daemon now runs as home-manager user service
  # No systemd dependency needed - user service binds to graphical-session.target

  # Feature 123: OpenTelemetry Collector for AI assistant telemetry
  # Receives OTLP from Claude Code on 4318, forwards to otel-ai-monitor on 4320
  # Also exports to K8s OTel stack via Tailscale for persistence (ClickHouse/Grafana)
  # Dashboard: https://grafana.tail286401.ts.net/d/otel-traces
  services.otel-ai-collector = {
    enable = true;
    enableDebugExporter = false;  # Less verbose for server
    enableFileExporter = true;    # Raw telemetry for analysis
    enableK8sExporter = true;     # Export to K8s OTel Collector via Tailscale
    # k8sExporterEndpoint defaults to http://otel-collector.tail286401.ts.net:4318
  };

  # Beyla eBPF auto-instrumentation (Feature 110)
  # Monitors Claude Code, Gemini CLI, and Codex for low-level system events
  services.beyla = {
    enable = true;
    monitorAiAssistants = true;
    otlpEndpoint = "https://otel-collector.tail286401.ts.net";
  };

  systemd.services.home-manager-vpittamp = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "2s";
      StartLimitBurst = 3;
      StartLimitIntervalSec = 30;
    };
  };

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

  # Enable 1Password password management
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

  # Enable 1Password automation with service account
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

  # Stream audio over Tailscale to Surface laptop (update destinationAddress with your MagicDNS entry or Tailscale IP)
  services.tailscaleAudio = {
    enable = true;
    destinationAddress = "100.122.146.117";
    destinationPort = 4010;
    sessionName = "hetzner";
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
