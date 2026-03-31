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
  rustdeskConnectRyzen = pkgs.writeShellScriptBin "rustdesk-connect-ryzen" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    host_ip="$(${pkgs.tailscale}/bin/tailscale ip -4 ryzen 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)"

    if [ -z "$host_ip" ]; then
      host_ip="$(getent ahostsv4 ryzen | ${pkgs.gawk}/bin/awk 'NR == 1 { print $1 }')"
    fi

    if [ -z "$host_ip" ]; then
      echo "Unable to resolve ryzen to a Tailscale IPv4 address" >&2
      exit 1
    fi

    exec ${pkgs.rustdesk}/bin/rustdesk --connect "$host_ip"
  '';
  moonlightRyzenDesktop = pkgs.writeShellScriptBin "moonlight-ryzen-desktop" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    phase() {
      printf 'moonlight-ryzen-desktop: %s\n' "$*" >&2
    }

    fail() {
      phase "$1"
      exit 1
    }

    socket_path="''${SWAYSOCK:-}"
    if [ -z "$socket_path" ]; then
      socket_path="$(${pkgs.systemd}/bin/systemctl --user show-environment 2>/dev/null | ${pkgs.gnused}/bin/sed -n 's/^SWAYSOCK=//p')"
    fi
    if [ -z "$socket_path" ]; then
      socket_path="$(${pkgs.findutils}/bin/find /run/user/$(${pkgs.coreutils}/bin/id -u) -maxdepth 1 -name 'sway-ipc.*.sock' | ${pkgs.coreutils}/bin/head -n1)"
    fi

    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    lock_file="$runtime_dir/moonlight-ryzen-desktop.lock"

    ${pkgs.coreutils}/bin/mkdir -p "$runtime_dir"

    run_moonlight() {
      export SDL_VIDEODRIVER=wayland
      exec ${pkgs.moonlight-qt}/bin/moonlight \
        stream \
        --resolution 1920x1200 \
        --fps 60 \
        --bitrate 10000 \
        --packet-size 1024 \
        --video-codec H.264 \
        --frame-pacing \
        --audio-config stereo \
        --display-mode windowed \
        --no-absolute-mouse \
        --capture-system-keys always \
        ryzen \
        Desktop
    }

    focus_existing_stream() {
      if [ -z "$socket_path" ]; then
        return 1
      fi

      if ! SWAYSOCK="$socket_path" ${pkgs.sway}/bin/swaymsg -t get_tree -r \
        | ${pkgs.jq}/bin/jq -e '
          .. | objects | select((.app_id? // "") == "com.moonlight_stream.Moonlight")
        ' >/dev/null 2>&1; then
        return 1
      fi

      phase "existing Moonlight session detected; focusing current stream"
      SWAYSOCK="$socket_path" ${pkgs.sway}/bin/swaymsg '[app_id="com.moonlight_stream.Moonlight"] focus' >/dev/null 2>&1 || true
      return 0
    }

    cleanup_stale_stream() {
      phase "cleaning up stale Moonlight session"
      while IFS= read -r stale_pid; do
        [ -n "$stale_pid" ] || continue
        ${pkgs.coreutils}/bin/kill "$stale_pid" >/dev/null 2>&1 || true
      done < <(${pkgs.procps}/bin/pgrep -f '${pkgs.moonlight-qt}/bin/moonlight[[:space:]]+stream([[:space:]].*)?[[:space:]]+ryzen[[:space:]]+Desktop([[:space:]]|$)' || true)

      while IFS= read -r stale_pid; do
        [ -n "$stale_pid" ] || continue
        if [ "$stale_pid" != "$$" ]; then
          ${pkgs.coreutils}/bin/kill "$stale_pid" >/dev/null 2>&1 || true
        fi
      done < <(${pkgs.procps}/bin/pgrep -f '/run/current-system/sw/bin/moonlight-ryzen-desktop' || true)

      attempts=0
      while ${pkgs.procps}/bin/pgrep -f '${pkgs.moonlight-qt}/bin/moonlight[[:space:]]+stream([[:space:]].*)?[[:space:]]+ryzen[[:space:]]+Desktop([[:space:]]|$)' >/dev/null 2>&1; do
        if [ "$attempts" -ge 20 ]; then
          fail "stale Moonlight processes would not exit"
        fi
        attempts=$((attempts + 1))
        ${pkgs.coreutils}/bin/sleep 0.25
      done
    }

    acquire_launch_lock() {
      exec 9>"$lock_file"
      if ${pkgs.util-linux}/bin/flock -n 9; then
        return 0
      fi

      focus_existing_stream && exit 0
      cleanup_stale_stream

      exec 9>"$lock_file"
      ${pkgs.util-linux}/bin/flock -n 9 || fail "another Ryzen Desktop launch is already in progress"
    }

    acquire_launch_lock

    if ${pkgs.procps}/bin/pgrep -f '${pkgs.moonlight-qt}/bin/moonlight[[:space:]]+stream([[:space:]].*)?[[:space:]]+ryzen[[:space:]]+Desktop([[:space:]]|$)' >/dev/null 2>&1; then
      focus_existing_stream && exit 0
      cleanup_stale_stream
    fi

    phase "checking ryzen host"
    ${pkgs.openssh}/bin/ssh \
      -o BatchMode=yes \
      -o ConnectTimeout=5 \
      ryzen \
      /run/current-system/sw/bin/sunshine-primary-monitor-ensure \
      || fail "ryzen host is not stream-ready"

    phase "validating desktop stream"
    available_apps="$(${pkgs.moonlight-qt}/bin/moonlight list ryzen 2>&1)" \
      || {
        printf '%s\n' "$available_apps" >&2
        fail "Moonlight could not query Sunshine applications"
      }

    if [ -n "$available_apps" ] && ! printf '%s\n' "$available_apps" | ${pkgs.gnugrep}/bin/grep -Fx "Desktop" >/dev/null 2>&1; then
      printf '%s\n' "$available_apps" >&2
      phase "Moonlight list did not include Desktop; continuing with direct Desktop stream"
    fi

    if [ -z "$socket_path" ]; then
      phase "starting stream"
      run_moonlight
    fi

    original_workspace="$(${pkgs.sway}/bin/swaymsg -s "$socket_path" -t get_workspaces -r | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')"
    moonlight_workspace="12: Ryzen Desktop"

    restore_workspace() {
      if [ -n "''${original_workspace:-}" ]; then
        ${pkgs.sway}/bin/swaymsg -s "$socket_path" workspace "$original_workspace" >/dev/null 2>&1 || true
      fi
    }

    trap 'restore_workspace' EXIT INT TERM

    # Avoid inheriting terminal/project launcher identity into Moonlight itself.
    while IFS= read -r var_name; do
      unset "$var_name"
    done < <(${pkgs.coreutils}/bin/env | ${pkgs.gawk}/bin/awk -F= '/^I3PM_/ { print $1 }')

    phase "starting stream"
    export SDL_VIDEODRIVER=wayland
    ${pkgs.moonlight-qt}/bin/moonlight \
      stream \
      --resolution 1920x1200 \
      --fps 60 \
      --bitrate 10000 \
      --packet-size 1024 \
      --video-codec H.264 \
      --frame-pacing \
      --audio-config stereo \
      --display-mode windowed \
      --no-absolute-mouse \
      --capture-system-keys always \
      ryzen \
      Desktop &
    moonlight_pid=$!

    attempts=0
    until ${pkgs.sway}/bin/swaymsg -s "$socket_path" -t get_tree -r | ${pkgs.jq}/bin/jq -e '
      .. | objects | select((.app_id? // "") == "com.moonlight_stream.Moonlight")
    ' >/dev/null 2>&1; do
      if ! ${pkgs.coreutils}/bin/kill -0 "$moonlight_pid" >/dev/null 2>&1; then
        wait "$moonlight_pid"
        exit $?
      fi
      if [ "$attempts" -ge 40 ]; then
        break
      fi
      attempts=$((attempts + 1))
      ${pkgs.coreutils}/bin/sleep 0.25
    done

    # Move Moonlight to its workspace and remove borders (no forced fullscreen)
    ${pkgs.sway}/bin/swaymsg -s "$socket_path" '[app_id="com.moonlight_stream.Moonlight"] border none' >/dev/null 2>&1 || true
    ${pkgs.sway}/bin/swaymsg -s "$socket_path" '[app_id="com.moonlight_stream.Moonlight"] move container to workspace "'"$moonlight_workspace"'"' >/dev/null 2>&1 || true
    ${pkgs.sway}/bin/swaymsg -s "$socket_path" workspace "$moonlight_workspace" >/dev/null 2>&1 || true
    ${pkgs.sway}/bin/swaymsg -s "$socket_path" '[app_id="com.moonlight_stream.Moonlight"] focus' >/dev/null 2>&1 || true

    wait "$moonlight_pid"
  '';
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

    # Kernel-level key remapper (Copilot F23→Compose for voxtype)
    ../modules/services/keyd.nix

    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/otel-ai-collector.nix  # Feature 123: AI telemetry collector (legacy, replaced by Alloy)
    ../modules/services/grafana-alloy.nix      # Feature 129: Unified OTEL collector
    ../modules/services/arize-phoenix.nix      # Feature 129 Enhancement: GenAI tracing
    ../modules/services/pyroscope-agent.nix    # Feature 129: Continuous profiling
    ../modules/services/litellm-proxy.nix      # Feature 123: LiteLLM proxy for full OTEL traces
    # Feature 117: System service removed - now runs as home-manager user service

    # Bare metal optimizations (KVM, Podman, printing, TPM, etc.)
    ../modules/services/bare-metal.nix
    ./thinkpad-lid-policy.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix

    # Sunshine game streaming (Intel Quick Sync hardware encoding)
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

  # Cachix Deploy Agent - Auto-deploy on git push
  # Token stored in 1Password, manually bootstrapped on first setup
  services.cachix-deploy = {
    enable = true;
    onePassword = {
      enable = true;
      tokenReference = "op://CLI/Cachix Deploy Agent Thinkpad/token";
    };
  };

  # Fallback password for initial setup
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";

  # Add user to required groups
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" "video" "seat" "input" "onepassword" ];

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

    # Voxtype - Push-to-talk speech-to-text (Vulkan, works in tmux/CLI)
    (callPackage ../packages/voxtype.nix { })

    # Brightness control
    brightnessctl

    # Firefox PWA support
    firefoxpwa
    imagemagick
    librsvg

    # Remote access
    tailscale
    rustdesk
    rustdeskConnectRyzen
    moonlight-qt
    moonlightRyzenDesktop
    remmina
    rustdesk-flutter  # Open-source remote desktop
    wayvnc  # VNC server for Wayland remote access
    wlvncc  # Wayland-native VNC client (for Ryzen HDMI-A-1 → HEADLESS-1 proxy)

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
    # Keep plain SSH over the tailnet so tagged infrastructure devices like
    # ryzen can still reach this user-owned workstation.
    extraUpFlags = [ "--accept-routes" ];
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

      # Jabra Evolve2 85 USB dongle - auto-prioritize when connected
      "50-jabra-usb" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "device.vendor.id" = "2830"; }  # 0x0b0e = 2830 decimal (GN Audio/Jabra)
            ];
            actions = {
              update-props = {
                "device.description" = "Jabra Evolve2 85";
                "priority.driver" = 2000;
                "priority.session" = 2000;
              };
            };
          }
          {
            matches = [
              { "node.name" = "~alsa_output.usb-0b0e_Jabra*"; }
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
              { "node.name" = "~alsa_input.usb-0b0e_Jabra*"; }
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

  systemd.user.services.thinkpad-audio-defaults = {
    description = "Restore ThinkPad internal speaker when Bluetooth is not active";
    wantedBy = [ "sway-session.target" ];
    partOf = [ "sway-session.target" ];
    after = [ "pipewire.service" "wireplumber.service" "sway-session.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "thinkpad-audio-defaults" ''
        set -euo pipefail

        export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
        export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"

        speaker_sink='alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink'

        attempts=0
        until ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; do
          if [ "$attempts" -ge 40 ]; then
            echo "pactl not ready, skipping ThinkPad audio restore" >&2
            exit 0
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        attempts=0
        until ${pkgs.pulseaudio}/bin/pactl list short sinks 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "$speaker_sink"; do
          if [ "$attempts" -ge 40 ]; then
            echo "ThinkPad speaker sink not ready, skipping audio restore" >&2
            exit 0
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        if ${pkgs.pulseaudio}/bin/pactl list short sinks 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q '^bluez_output\.'; then
          exit 0
        fi

        ${pkgs.pulseaudio}/bin/pactl set-default-sink "$speaker_sink" || true
        ${pkgs.pulseaudio}/bin/pactl set-sink-mute "$speaker_sink" false || true
      '';
    };
  };

  # Enable rtkit for real-time audio scheduling
  security.rtkit.enable = true;

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
