# Microsoft Surface Laptop 2 (Model 1769) Configuration
# Intel Core i5-8250U (Kaby Lake R) with UHD 620 integrated graphics
# Physical laptop with Sway/Wayland desktop environment — mirrors
# configurations/thinkpad.nix with hardware-specific bits swapped for Surface.
#
# Deploys happen over tailscale from thinkpad/ryzen:
#   nixos-rebuild switch --flake .#surface --target-host vpittamp@surface
#
{ config, lib, pkgs, inputs, ... }:

let
  # Firefox 146+ overlay for native Wayland fractional scaling support
  pkgs-unstable = import inputs.nixpkgs-bleeding {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  # Latest lazygit/lazydocker without bumping the main channel (see flake.nix)
  pkgs-lazygit = import inputs.nixpkgs-lazygit {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  imports = [
    # Base configuration
    ./base.nix

    # Hardware
    ../hardware/surface.nix

    # nixos-hardware modules for Intel laptops
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd

    # linux-surface kernel (IPTS touchscreen/pen, Surface-specific power
    # management). Built locally — there is no public binary cache for it.
    inputs.nixos-hardware.nixosModules.microsoft-surface-common

    # Desktop environment (Sway - Wayland compositor)
    ../modules/desktop/sway.nix

    # Kernel-level key remapper (F23→Compose; no-op on keyboards without a
    # Copilot key, safe to keep for config parity with thinkpad)
    ../modules/services/keyd.nix

    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    # Feature 117: System service removed - now runs as home-manager user service

    # Bare metal optimizations (Podman, printing; no KVM/fingerprint on Surface)
    ../modules/services/bare-metal.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix

    # Chrome policy for Claude-in-Chrome extension (force-install in all Chrome profiles)
    ../modules/desktop/chrome-claude.nix

    # Chrome policy for Kimi WebBridge extension (force-install in all Chrome profiles)
    ../modules/desktop/chrome-kimi-webbridge.nix

    # Chrome managed bookmarks (one entry per PWA, generated from pwa-sites.nix)
    ../modules/desktop/chrome-bookmarks.nix

    # Chrome sign-in + sync policy (allow user to sign in, sync bookmarks etc.)
    ../modules/desktop/chrome-sync.nix

    # Chrome policy for native Gemini and Generative AI features
    ../modules/desktop/chrome-gemini.nix

    # Cachix Deploy for automated deployments
    ../modules/services/cachix-deploy.nix

    # NOT imported (thinkpad-only):
    # - ../modules/desktop/sunshine.nix (game streaming host — this laptop is weak
    #   hardware and acts as a client at most)
    # - ./thinkpad-lid-policy.nix (thinkpad-specific logind fragment)
  ];

  # linux-surface support: current nixos-hardware microsoft-surface-common only
  # ships the patched kernel (the old microsoft-surface.ipts/surface-control
  # options were removed upstream). IPTS userspace comes from nixpkgs.
  services.iptsd.enable = true;  # touchscreen + pen (Intel Precise Touch)

  # Firefox 146+ overlay for native Wayland fractional scaling support
  nixpkgs.overlays = [
    (final: prev: {
      firefox = pkgs-unstable.firefox;
      firefox-unwrapped = pkgs-unstable.firefox-unwrapped;

      # Latest lazygit / lazydocker without bumping the main channel.
      # Wrapped so `infocmp` (ncurses) is always on their PATH. See
      # packages/with-terminfo.nix and configurations/thinkpad.nix.
      lazygit = (import ../packages/with-terminfo.nix { pkgs = prev; }) pkgs-lazygit.lazygit "lazygit";
      lazydocker = (import ../packages/with-terminfo.nix { pkgs = prev; }) pkgs-lazygit.lazydocker "lazydocker";
      k9s = (import ../packages/with-terminfo.nix { pkgs = prev; }) prev.k9s "k9s";
      gh-dash = prev.callPackage ../packages/gh-dash.nix { };
      gh-enhance = prev.callPackage ../packages/gh-enhance.nix { };
      diffnav = prev.callPackage ../packages/diffnav.nix { };

      # NOTE: google-chrome stable comes straight from nixpkgs (149+). Do NOT pin
      # an older version here: Chrome's fallback Cast CRL expires 20 weeks after
      # the browser build date (cast_crl.cc "CRL - Not time-valid"), after which
      # cast device auth fails and the picker shows "No devices found".
      # (A stale 145 pin caused exactly that on 2026-07-29.)

      # Chrome beta/dev channel (for testing features behind newer flags)
      google-chrome-beta = prev.callPackage ../packages/google-chrome-beta.nix { };
      google-chrome-unstable = prev.callPackage ../packages/google-chrome-unstable.nix { };
    })
  ];

  # System identification
  networking.hostName = "surface";

  # Enable Sway Wayland compositor
  services.sway.enable = true;

  # ========== BARE METAL FEATURES ==========
  services.bare-metal = {
    enable = true;

    # No KVM/libvirt on this i5 — unused, and libvirtd only idle-flaps.
    enableVirtualization = false;

    # Podman rootless containers (complement to Docker)
    enablePodman = true;

    # Printing support with CUPS
    enablePrinting = true;

    # Surface Laptop 2 has no fingerprint reader
    enableFingerprint = false;

    # No gaming on this laptop
    enableGaming = false;
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

  # Memory management tweaks
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_ratio" = 10;
    "vm.laptop_mode" = 5;
  };

  # Boot configuration for standard x86_64 UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel parameters for Intel Kaby Lake R
  boot.kernelParams = [
    "i915.enable_psr=0"           # Disable Panel Self Refresh (flickers on KBL panels)
    "i915.enable_fbc=1"           # Enable framebuffer compression
    "intel_pstate=active"         # Use Intel P-state driver
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

  # NetworkManager for WiFi (wpa_supplicant backend — the thinkpad uses iwd,
  # but switching backends here would need the profile re-provisioned).
  networking.networkmanager.enable = true;

  # Declarative Wi-Fi profile for the home network. The PSK is NOT in this
  # repo: it is substituted at runtime from /etc/NetworkManager/secrets.env on
  # the surface (root:root 0600, provisioned out-of-band during bring-up).
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ "/etc/NetworkManager/secrets.env" ];
    profiles."Linksys 416" = {
      connection = {
        id = "Linksys 416";
        uuid = "c520f3e2-03e0-4e0e-9ea3-58ba99f8dd59";
        type = "wifi";
        interface-name = "wlp2s0";
      };
      wifi = {
        mode = "infrastructure";
        ssid = "Linksys 416";
      };
      wifi-security = {
        auth-alg = "open";
        key-mgmt = "wpa-psk";
        psk = "$LINKSYS416_PSK";
      };
      ipv4.method = "auto";
      ipv6 = {
        addr-gen-mode = "default";
        method = "auto";
      };
    };
  };

  # Fonts - Nerd Fonts for desktop shell glyph icons
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

  # Display configuration - UHD 620 via modesetting
  # Panel is 2256x1504 (~201 PPI); scaling is handled by Sway (scale 1.5,
  # see home-modules/desktop/sway.nix) rather than X DPI since the session
  # is Wayland-native.
  services.xserver = {
    videoDrivers = [ "modesetting" ];
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
    # Intel UHD 620 (Kaby Lake R) uses the iHD VA-API driver
    LIBVA_DRIVER_NAME = "iHD";

    # Enable Wayland for Electron apps
    NIXOS_OZONE_WL = "1";
  };

  # Touchpad configuration with natural scrolling (Surface precision touchpad)
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

  # Enable fwupd for firmware updates (LVFS publishes Surface Laptop 2 firmware)
  services.fwupd.enable = true;

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # 1Password configuration (same vault references as thinkpad)
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
  };

  # Cachix Deploy Agent - Auto-deploy on git push
  # Token stored in 1Password ("Cachix Deploy Agent Surface" item in CLI vault),
  # bootstrapped during surface bring-up
  services.cachix-deploy = {
    enable = true;
    onePassword = {
      enable = true;
      tokenReference = "op://CLI/Cachix Deploy Agent Surface/token";
    };
  };

  # Fallback password for initial setup (change with passwd)
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";

  # TPM 2.0: udev rules + tss group resource manager access
  security.tpm2.enable = true;

  # surface-control udev rules (SAM sysfs permissions)
  services.udev.packages = [ pkgs.surface-control ];

  # MSHW0092 touchpad (045E:0933): hid-generic claims it at boot, presenting
  # it as a plain "Mouse" (no ID_INPUT_TOUCHPAD) so libinput/Sway ignore it.
  # Force it onto hid-multitouch the moment the device appears. Broken on
  # every boot since ~2026-08-17; a manual rebind on 2026-08-30 restored it.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="hid", KERNEL=="0018:045E:0933.*", \
      RUN+="/bin/sh -c 'echo %k > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null; echo %k > /sys/bus/hid/drivers/hid-multitouch/bind'"
  '';

  # Add user to required groups
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" "video" "seat" "input" "onepassword" "tss" ];

  # Bluetooth support (Marvell 88W8897 AVASTAR WiFi/BT composite, USB-attached BT)
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };

  # Bluetooth manager GUI
  services.blueman.enable = true;

  # UPower for battery monitoring
  services.upower.enable = true;

  # TLP is deliberately NOT used: linux-surface documentation warns that TLP
  # causes problems on Surface devices unless carefully configured. Power
  # management is handled by surface-control (performance modes) + thermald.
  # mkForce: common-pc-laptop and microsoft-surface-common both mkDefault
  # conflicting values (true vs false) — settle it here.
  # See https://github.com/linux-surface/linux-surface/blob/master/README.md
  services.tlp.enable = lib.mkForce false;
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

    # Hardware video acceleration (Intel)
    intel-gpu-tools   # Intel GPU debugging (intel_gpu_top)
    libva-utils       # VA-API verification (vainfo)

    # Disk encryption and security
    cryptsetup

    # Hardware monitoring
    s-tui             # Stress test + monitoring TUI
    stress-ng         # CPU stress testing

    # Laptop-specific power tools
    acpid             # ACPI daemon
    upower            # Power device info

    # USB device management
    udiskie           # Automount USB drives

    # Webcam (Surface Laptop 2 has a 720p front camera)
    v4l-utils         # Video4Linux utilities
    cameractrls       # Webcam controls
    libcamera         # IPU3 camera pipeline tools (cam/qcam) — both the front
                      # 720p and the IR (Windows Hello) sensors hang off the
                      # Intel IPU3, so apps only see a camera once libcamera
                      # claims /dev/media*; PipeWire's libcamera SPA plugin
                      # (already in the closure) then exposes it to browsers.

    # Surface ACPI (SAM) control: performance/cooling modes, battery info and
    # (if the SL2 firmware exposes it) the battery charge limiter
    surface-control

    # TPM 2.0 tooling (/dev/tpm0 present on the SL2)
    tpm2-tools

    # Screen recording / screenshots (Wayland)
    wf-recorder       # Wayland screen recorder with VAAPI support
    grim              # Screenshot utility for Wayland
    slurp             # Region selection for screenshots/recording
  ];

  # Firefox configuration with PWA support
  programs.firefox = {
    enable = lib.mkDefault true;
  };

  # Tailscale VPN (same posture as thinkpad: plain SSH reachable over tailnet)
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    # --accept-routes is set centrally via extraSetFlags in
    # modules/services/networking.nix (extraUpFlags never applied: no authKeyFile).
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];  # SSH
    allowedUDPPorts = [ 5353 ];  # mDNS for Chrome Chromecast / TV discovery on LAN
    checkReversePath = "loose";  # For Tailscale
  };

  # ========== ADVANCED AUDIO (BARE METAL) ==========
  # Full PipeWire with low-latency and Bluetooth codecs
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

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

      # Jabra Evolve2 85 over BLUETOOTH - prioritize its output/input so that,
      # when the headset exposes a mic (HFP mode), it becomes the default source
      # for dictation without any script forcing a profile switch.
      "55-jabra-bluetooth" = {
        "monitor.bluez.rules" = [
          {
            matches = [
              { "device.name" = "~bluez_card.*Jabra.*"; }
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
              { "node.name" = "~bluez_output.*Jabra.*"; }
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
              { "node.name" = "~bluez_input.*Jabra.*"; }
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

  # ========== USB AUTOMOUNT ==========
  # Automatic mounting of USB drives
  services.udisks2.enable = true;

  # Polkit rules for 1Password integration
  security.polkit.extraConfig = lib.mkAfter ''
    // Allow 1Password CLI to use biometric unlock via polkit
    polkit.addRule(function(action, subject) {
      if (action.id == "com.1password.1Password.unlock" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.AUTH_SELF;
      }
    });
  '';

  # Installed from the 25.11 installer; keep in sync with the channel the
  # system was born on.
  system.stateVersion = "25.11";
}
