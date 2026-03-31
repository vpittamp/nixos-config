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
  gameStreaming = import ../shared/game-streaming.nix;
  thinkpadMoonlightClient = gameStreaming.moonlightClients.thinkpad;
  ryzenSunshineHost = gameStreaming.sunshineHosts.ryzen;

  # Firefox 146+ overlay for native Wayland fractional scaling support
  pkgs-unstable = import inputs.nixpkgs-bleeding {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  sunshinePrimaryMonitorEnsure = pkgs.writeShellScriptBin "sunshine-primary-monitor-ensure" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    primary_output="DP-1"
    target_output_index="0"
    runtime_conf="$HOME/.config/sunshine/sunshine-runtime.conf"
    override_dir="$HOME/.config/systemd/user/sunshine.service.d"
    override_file="$override_dir/override.conf"

    log() {
      printf 'sunshine-primary-monitor-ensure: %s\n' "$*" >&2
    }

    fail() {
      log "$1"
      exit 1
    }

    show_environment="$(${pkgs.systemd}/bin/systemctl --user show-environment 2>/dev/null || true)"
    socket_path="$(printf '%s\n' "$show_environment" | ${pkgs.gnused}/bin/sed -n 's/^SWAYSOCK=//p' | ${pkgs.coreutils}/bin/head -n1)"

    if [ -z "$socket_path" ]; then
      fail "Sway socket is unavailable"
    fi

    outputs_json="$(SWAYSOCK="$socket_path" ${pkgs.sway}/bin/swaymsg -t get_outputs -r 2>/dev/null)" \
      || fail "Unable to query Sway outputs"

    if ! printf '%s' "$outputs_json" | ${pkgs.jq}/bin/jq -e --arg name "$primary_output" '
      .[]
      | select(
          .name == $name
          and .active == true
          and ((.power? // true) == true)
          and ((.dpms? // true) == true)
        )
    ' >/dev/null; then
      fail "Primary monitor $primary_output is not active"
    fi

    base_conf="$(
      ${pkgs.systemd}/bin/systemctl --user cat sunshine 2>/dev/null \
        | ${pkgs.gnused}/bin/sed -n 's/^ExecStart="\/run\/wrappers\/bin\/sunshine" "\([^"]*\)"$/\1/p' \
        | ${pkgs.coreutils}/bin/head -n1
    )"

    if [ -z "$base_conf" ]; then
      fail "Unable to resolve Sunshine ExecStart config"
    fi

    if [ ! -f "$base_conf" ]; then
      fail "Sunshine config file not found: $base_conf"
    fi

    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/sunshine" "$override_dir"

    tmp_conf="$(${pkgs.coreutils}/bin/mktemp)"
    tmp_override="$(${pkgs.coreutils}/bin/mktemp)"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp_conf" "$tmp_override"' EXIT

    ${pkgs.gnused}/bin/sed "s/^output_name=.*/output_name=$target_output_index/" "$base_conf" > "$tmp_conf"
    cat > "$tmp_override" <<EOF
[Service]
ExecStart=
ExecStart=/run/wrappers/bin/sunshine $runtime_conf
EOF

    needs_restart=0

    if [ ! -f "$runtime_conf" ] || ! ${pkgs.diffutils}/bin/cmp -s "$tmp_conf" "$runtime_conf"; then
      ${pkgs.coreutils}/bin/mv "$tmp_conf" "$runtime_conf"
      needs_restart=1
    fi

    if [ ! -f "$override_file" ] || ! ${pkgs.diffutils}/bin/cmp -s "$tmp_override" "$override_file"; then
      ${pkgs.coreutils}/bin/mv "$tmp_override" "$override_file"
      needs_restart=1
    fi

    current_exec="$(${pkgs.systemd}/bin/systemctl --user show sunshine -p ExecStart --value 2>/dev/null || true)"
    if ! printf '%s' "$current_exec" | ${pkgs.gnugrep}/bin/grep -F "$runtime_conf" >/dev/null 2>&1; then
      needs_restart=1
    fi

    if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet sunshine; then
      needs_restart=1
    fi

    if [ "$needs_restart" -eq 1 ]; then
      log "restarting Sunshine for $primary_output"
      ${pkgs.systemd}/bin/systemctl --user daemon-reload
      ${pkgs.systemd}/bin/systemctl --user restart sunshine
      ${pkgs.coreutils}/bin/sleep 2
    fi

    ${pkgs.systemd}/bin/systemctl --user is-active --quiet sunshine \
      || fail "Sunshine user service is not active"

    active_since="$(${pkgs.systemd}/bin/systemctl --user show sunshine -p ActiveEnterTimestamp --value 2>/dev/null || true)"
    recent_logs="$(${pkgs.systemd}/bin/journalctl --user -u sunshine --since "''${active_since:-2 minutes ago}" --no-pager 2>/dev/null || true)"

    if printf '%s' "$recent_logs" | ${pkgs.gnugrep}/bin/grep -F "Couldn't find monitor" >/dev/null 2>&1; then
      fail "Sunshine is still targeting a stale monitor"
    fi

    if printf '%s' "$recent_logs" | ${pkgs.gnugrep}/bin/grep -F "Fatal: Unable to find display or encoder during startup." >/dev/null 2>&1; then
      fail "Sunshine failed to initialize capture or encoding"
    fi

    log "ready: Sunshine is targeting monitor index $target_output_index for $primary_output"
  '';
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
    ../modules/services/grafana-alloy.nix      # Feature 129: Unified telemetry collector
    # Feature 117: System service removed - now runs as home-manager user service

    # Bare metal optimizations (KVM, Podman, gaming, printing, TPM, etc.)
    ../modules/services/bare-metal.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix

    # Sunshine game streaming (NVIDIA NVENC hardware encoding)
    ../modules/desktop/sunshine.nix

    # Cachix Deploy for automated deployments
    ../modules/services/cachix-deploy.nix
  ];

  # Firefox 146+ overlay for native Wayland fractional scaling support
  nixpkgs.overlays = [
    (final: prev: {
      firefox = pkgs-unstable.firefox;
      firefox-unwrapped = pkgs-unstable.firefox-unwrapped;

      # Update Google Chrome Stable to latest available without updating entire nixpkgs
      google-chrome = prev.google-chrome.overrideAttrs (old: rec {
        version = "145.0.7632.159";
        src = prev.fetchurl {
          url = "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${version}-1_amd64.deb";
          hash = "sha256-xi7xUT9BSvF7g690gaEsubTwAN181Y08FSPD2+pFJdk=";
        };
      });

      # Chrome 146 beta/dev channel (for testing features behind newer flags)
      google-chrome-beta = prev.callPackage ../pkgs/google-chrome-beta.nix { };
      google-chrome-unstable = prev.callPackage ../pkgs/google-chrome-unstable.nix { };
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
  networking.nftables.enable = true;

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

    # Fingerprint reader support (if USB fingerprint reader is connected)
    # Enroll fingerprint with: fprintd-enroll
    enableFingerprint = true;
  };

  # ========== INCUS VIRTUALIZATION FOR NIXOS VM TESTING ==========
  # Uses NAT bridge networking and directory-backed storage on ext4.
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
    preseed = {
      networks = [
        {
          name = "incusbr0";
          type = "bridge";
          config = {
            "ipv4.address" = "10.42.241.1/24";
            "ipv4.nat" = "true";
            "ipv6.address" = "none";
          };
        }
      ];

      storage_pools = [
        {
          name = "default";
          driver = "dir";
          config = {
            source = "/var/lib/incus/storage-pools/default";
          };
        }
      ];

      profiles = [
        {
          name = "default";
          description = "Default Incus profile for NAT-backed VM testing";
          config = {
            "security.secureboot" = "false";
          };
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
          };
        }
      ];
    };
  };

  # ========== SUNSHINE REMOTE DESKTOP (NVIDIA NVENC) ==========
  # Hardware-accelerated streaming using NVIDIA NVENC (RTX 5070)
  # Supported by NVIDIA open kernel modules
  # Client: Moonlight (available on all platforms)
  # Access: moonlight://<tailscale-ip>
  services.sunshine-streaming = {
    enable = true;
    hostUniqueId = ryzenSunshineHost.uniqueId;
    hardwareType = "nvidia";    # Using NVIDIA NVENC hardware encoding
    captureMethod = "kms";      # Restore the previous direct KMS capture path
    tailscaleOnly = true;       # Only allow via Tailscale for security
    extraSettings = {
      # Allow Moonlight pairing PIN submission from Tailscale peers.
      # Sunshine treats 100.64.0.0/10 CGNAT addresses as LAN.
      origin_pin_allowed = "lan";
      # Avoid Sunshine's tray/X11 path on this Sway session; the inherited
      # DISPLAY socket can block startup and the tray path is not needed here.
      system_tray = "disabled";
      # NVENC quality settings for RTX 5070 (desktop-optimized)
      nvenc_preset = lib.mkForce "p5";  # Higher quality for sharp text
      nvenc_tune = lib.mkForce "hq";    # High quality (enables B-frames, better for static desktop content)
      nvenc_rc = lib.mkForce "vbr";       # Variable bitrate — efficient for mostly-static desktop
      # Higher bitrate for local/Tailscale network streaming
      bitrate = 40000;
      # Include ThinkPad's 1920x1200 (16:10) for native resolution streaming
      resolutions = ''
        [
          1920x1200,
          1920x1080,
          2560x1440,
          3840x2160
        ]
      '';
      # Sunshine routes app audio into its own virtual stereo sink on this
      # host. Point capture at that sink explicitly so the ThinkPad receives
      # the streamed audio instead of silence from the physical monitor path.
      audio_sink = lib.mkForce "sink-sunshine-stereo";
      # Sunshine's KMS path is reliable with the live monitor index but has
      # been flaky with named output selection on this host. In the default
      # layout, monitor 0 is DP-1, which keeps streaming targeted at the
      # practical main display without connect/disconnect scripting.
      output_name = 0;
    };
    desktopAppOverrides.auto-detach = "true";
    pairedClients = [
      {
        name = "thinkpad";
        uuid = thinkpadMoonlightClient.uuid;
        certificate = thinkpadMoonlightClient.certificate;
      }
    ];
  };

  systemd.user.services.sunshine.serviceConfig.UnsetEnvironment = [ "DISPLAY" ];

  # Feature 117: i3 Project Daemon now runs as home-manager user service
  # Daemon lifecycle managed by graphical-session.target (see home-vpittamp.nix)

  # Feature 129: Grafana Alloy - Unified Telemetry Collector
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
      "otel-ai-monitor.service"
      "i3pm-daemon.service"
    ];
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

  # Cachix Deploy Agent - Auto-deploy on git push
  # Token stored in 1Password, manually bootstrapped on first setup
  services.cachix-deploy = {
    enable = true;
    onePassword = {
      enable = true;
      tokenReference = "op://CLI/Cachix Deploy Agent Ryzen/token";
    };
  };

  # Fallback password for initial setup
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";

  # Add user to required groups
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" "video" "seat" "input" "incus-admin" "onepassword" ];

  # ========== BLUETOOTH SUPPORT ==========
  # Realtek RTL8850 USB adapter (0bda:b850) + Jabra Evolve2 85
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
        FastConnectable = true;
        ReconnectAttempts = 7;
        ReconnectIntervals = "1,2,4,8,16,32,64";
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  # Disable USB autosuspend for Realtek BT adapter — prevents intermittent drops
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="b850", ATTR{power/autosuspend_delay_ms}="-1", ATTR{power/control}="on"
  '';

  # Bluetooth manager GUI
  services.blueman.enable = true;

  # ========== FINGERPRINT AUTHENTICATION ==========
  # Fingerprint reader support (USB fingerprint reader)
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

  # No battery-related services for desktop (no TLP, no UPower battery monitoring)

  # Additional packages for desktop
  environment.systemPackages = with pkgs; [
    # Terminal
    ghostty

    # Voxtype - Push-to-talk speech-to-text (Vulkan, works in tmux/CLI)
    (callPackage ../packages/voxtype.nix { })

    # Firefox PWA support
    firefoxpwa
    imagemagick
    librsvg

    # Remote access
    tailscale
    rustdesk
    remmina
    rustdesk-flutter  # Open-source remote desktop
    wayvnc  # VNC server for Wayland remote access
    sunshinePrimaryMonitorEnsure

    # 1Password GUI
    _1password-gui

    # Hardware monitoring tools
    lm_sensors     # Temperature monitoring
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
    nativeMessagingHosts.packages = [ ];
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
    allowedTCPPorts = [ 22 5900 5901 ];  # SSH, VNC DP-1, VNC HDMI-A-1
    interfaces."tailscale0".allowedTCPPorts = lib.mkAfter [ 4320 21116 21118 ];  # OTEL sink and RustDesk direct IP access
    interfaces."tailscale0".allowedUDPPorts = lib.mkAfter [ 21116 21119 ];  # RustDesk direct access transport
    extraInputRules = ''
      iifname "tailscale0" tcp dport { 21116, 21118 } accept comment "RustDesk over Tailscale"
      iifname "tailscale0" udp dport { 21116, 21119 } accept comment "RustDesk over Tailscale"
    '';
    checkReversePath = "loose";  # For Tailscale
    # Incus bridge needs DHCP/DNS from host-side dnsmasq.
    trustedInterfaces = [ "incusbr0" ];
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

    # WirePlumber configuration for Bluetooth audio
    wireplumber.extraConfig = {
      "10-bluez" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "ldac" "aptx" "aptx_hd" ];
        };
      };

      # Jabra Evolve2 85 Bluetooth - auto-prioritize when connected
      "50-jabra-bluetooth" = {
        "monitor.bluez.rules" = [
          {
            matches = [
              { "device.name" = "~bluez_card.*Jabra*"; }
            ];
            actions = {
              update-props = {
                "device.description" = "Jabra Evolve2 85";
                "bluez5.auto-connect" = [ "a2dp_sink" "hfp_hf" ];
              };
            };
          }
          {
            matches = [
              { "node.name" = "~bluez_output.*Jabra*"; }
            ];
            actions = {
              update-props = {
                "node.description" = "Jabra Evolve2 85 Output";
                "priority.driver" = 2000;
                "priority.session" = 2000;
              };
            };
          }
          {
            matches = [
              { "node.name" = "~bluez_input.*Jabra*"; }
            ];
            actions = {
              update-props = {
                "node.description" = "Jabra Evolve2 85 Mic";
                "priority.driver" = 2000;
                "priority.session" = 2000;
              };
            };
          }
        ];
      };
    };
  };

  # Enable rtkit for real-time audio scheduling
  security.rtkit.enable = true;

  systemd.user.services.ryzen-audio-defaults = {
    description = "Restore Ryzen PipeWire card profile and default sink";
    wantedBy = [ "sway-session.target" ];
    partOf = [ "sway-session.target" ];
    after = [ "pipewire.service" "wireplumber.service" "sway-session.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ryzen-audio-defaults" ''
        set -euo pipefail

        export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
        export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"

        attempts=0
        until ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; do
          if [ "$attempts" -ge 40 ]; then
            echo "pactl not ready, skipping Ryzen audio restore" >&2
            exit 0
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        attempts=0
        until ${pkgs.pulseaudio}/bin/pactl list short cards 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q 'alsa_card.pci-0000_11_00.6'; do
          if [ "$attempts" -ge 40 ]; then
            echo "Ryzen audio card not ready, skipping profile restore" >&2
            exit 0
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        ${pkgs.pulseaudio}/bin/pactl set-card-profile alsa_card.pci-0000_11_00.6 pro-audio || true

        attempts=0
        until ${pkgs.pulseaudio}/bin/pactl list short sinks 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q 'alsa_output.pci-0000_11_00.6.pro-output-0'; do
          if [ "$attempts" -ge 40 ]; then
            echo "Ryzen audio sink not ready after profile restore" >&2
            exit 0
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        ${pkgs.pulseaudio}/bin/pactl set-default-sink alsa_output.pci-0000_11_00.6.pro-output-0 || true

        if ${pkgs.pulseaudio}/bin/pactl list short sources 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q 'alsa_input.pci-0000_11_00.6.pro-input-0'; then
          ${pkgs.pulseaudio}/bin/pactl set-default-source alsa_input.pci-0000_11_00.6.pro-input-0 || true
        fi
      '';
    };
  };

  systemd.user.services.ryzen-sunshine-audio-router = {
    description = "Route active app audio through Sunshine during Moonlight sessions";
    wantedBy = [ "sway-session.target" ];
    partOf = [ "sway-session.target" ];
    after = [ "pipewire.service" "wireplumber.service" "sunshine.service" "sway-session.target" ];

    serviceConfig = {
      Restart = "always";
      RestartSec = 2;
      ExecStart = pkgs.writeShellScript "ryzen-sunshine-audio-router" ''
        set -euo pipefail

        export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
        export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"

        PACTL=${pkgs.pulseaudio}/bin/pactl
        PW_DUMP=${pkgs.pipewire}/bin/pw-dump
        JQ=${pkgs.jq}/bin/jq

        physical_sink="alsa_output.pci-0000_11_00.6.pro-output-0"
        sunshine_sink="sink-sunshine-stereo"
        previous_sink="$physical_sink"
        stream_active=0

        sink_exists() {
          local target="$1"
          "$PACTL" list short sinks 2>/dev/null | ${pkgs.gawk}/bin/awk -v target="$target" '$2 == target { found = 1 } END { exit(found ? 0 : 1) }'
        }

        current_default_sink() {
          "$PACTL" info 2>/dev/null | ${pkgs.gawk}/bin/awk -F': ' '/^Default Sink: / { print $2; exit }'
        }

        move_all_sink_inputs() {
          local target="$1"
          "$PACTL" list short sink-inputs 2>/dev/null \
            | ${pkgs.gawk}/bin/awk '{ print $1 }' \
            | while IFS= read -r input_id; do
                [ -n "$input_id" ] || continue
                "$PACTL" move-sink-input "$input_id" "$target" >/dev/null 2>&1 || true
              done
        }

        sunshine_session_active() {
          "$PW_DUMP" | "$JQ" -e '
            any(
              .[];
              .type == "PipeWire:Interface:Node"
              and ((.info.props["application.name"] // "") == "sunshine")
              and ((.info.props["media.class"] // "") == "Stream/Input/Audio")
              and ((.info.props["media.name"] // "") == "sunshine-record")
            )
          ' >/dev/null 2>&1
        }

        attempts=0
        until "$PACTL" info >/dev/null 2>&1; do
          if [ "$attempts" -ge 40 ]; then
            echo "pactl not ready, delaying Sunshine audio router startup" >&2
            exit 1
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        while true; do
          if sunshine_session_active && sink_exists "$sunshine_sink"; then
            current_sink="$(current_default_sink || true)"
            if [ "$stream_active" -eq 0 ]; then
              if [ -n "$current_sink" ] && [ "$current_sink" != "$sunshine_sink" ]; then
                previous_sink="$current_sink"
              else
                previous_sink="$physical_sink"
              fi
            fi

            "$PACTL" set-default-sink "$sunshine_sink" >/dev/null 2>&1 || true
            move_all_sink_inputs "$sunshine_sink"
            stream_active=1
          else
            if [ "$stream_active" -eq 1 ]; then
              restore_sink="$previous_sink"
              if ! sink_exists "$restore_sink"; then
                restore_sink="$physical_sink"
              fi

              if sink_exists "$restore_sink"; then
                "$PACTL" set-default-sink "$restore_sink" >/dev/null 2>&1 || true
                move_all_sink_inputs "$restore_sink"
              fi
            fi

            stream_active=0
          fi

          sleep 2
        done
      '';
    };
  };

  # ========== USB AUTOMOUNT ==========
  # Automatic mounting of USB drives
  services.udisks2.enable = true;
  services.gvfs.enable = true;  # For GUI file managers

  # ========== LIBRECHAT AI CHAT PLATFORM ==========
  # Open-source AI chat UI with MongoDB backend
  # Access at http://localhost:3080
  services.librechat = {
    enable = true;
    enableLocalDB = true;  # Auto-provisions MongoDB

    # Credentials file with secrets (CREDS_KEY, CREDS_IV, JWT_SECRET, JWT_REFRESH_SECRET)
    # Generate with: for v in CREDS_KEY JWT_SECRET JWT_REFRESH_SECRET; do echo "$v=$(openssl rand -hex 32)"; done; echo "CREDS_IV=$(openssl rand -hex 16)"
    credentialsFile = "/etc/librechat/credentials";

    env = {
      HOST = "0.0.0.0";
      ALLOW_REGISTRATION = true;
      # Trust K8s cluster CA for outbound HTTPS to *.cnoe.localtest.me services
      NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
    };

    settings = {
      version = "1.0.8";
      cache = true;
    };
  };

  # System state version
  system.stateVersion = "25.11";
}
