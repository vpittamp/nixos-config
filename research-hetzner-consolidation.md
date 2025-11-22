# Hetzner-Sway Variant Consolidation Research

## Executive Summary

This research explores strategies for consolidating 4 hetzner-sway configuration variants (production, image, minimal, ultra-minimal) into a single parameterized configuration. The analysis compares **NixOS Module Options** vs **Builder Function** patterns, examines common configuration extraction, and provides concrete implementation recommendations.

**Recommended Approach:** Module Options Pattern with Profile Imports (Strategy #3)
**Complexity Trade-off:** Medium complexity, high maintainability
**Code Reduction:** ~40-50% (from ~700 LOC to ~350-400 LOC)

---

## Current State Analysis

### Configuration Variants

| Variant | LOC | Purpose | Key Differences |
|---------|-----|---------|-----------------|
| `hetzner-sway.nix` | 282 | Production deployment | Full features + disko + assertions |
| `hetzner-sway-image.nix` | 261 | VM image distribution | No disko/assertions + VM settings |
| `hetzner-sway-minimal.nix` | 118 | Development/testing | Minimal imports + WayVNC only |
| `hetzner-sway-ultra-minimal.nix` | 41 | Minimal boot test | No imports except base |

### Code Duplication

**Shared Configuration (~40-50% overlap):**
- Base imports: `base.nix`, QEMU guest profile
- Boot loader: GRUB configuration (device paths vary)
- Kernel modules: virtio, kvm-intel, sd_mod, sr_mod
- Networking: DHCP, firewall (ports vary)
- Headless Wayland: WLR environment variables
- Greetd auto-login: Sway startup script
- User configuration: vpittamp user/groups

**Variant-Specific Configuration:**
- **Production**: disko, hetzner-check, all services (1Password, i3pm, audio, keyd)
- **Image**: virtualisation.diskSize, virtualisation.memorySize
- **Minimal**: Minimal packages, simplified WayVNC service
- **Ultra-minimal**: No imports, no services

---

## Pattern 1: NixOS Module Options

### Overview

Create a reusable NixOS module with configurable options, similar to nixpkgs service modules.

### Implementation Strategy

**Step 1: Create Module** (`modules/hetzner-sway-base.nix`)

```nix
{ config, lib, pkgs, modulesPath, ... }:

with lib;

let
  cfg = config.profiles.hetzner-sway;
in
{
  options.profiles.hetzner-sway = {
    enable = mkEnableOption "Hetzner Sway base configuration";

    profile = mkOption {
      type = types.enum [ "production" "image" "minimal" "ultra-minimal" ];
      default = "production";
      description = "Configuration profile variant";
    };

    # Feature flags for conditional enabling
    features = {
      enableDisko = mkOption {
        type = types.bool;
        default = true;
        description = "Enable disko disk configuration";
      };

      enableAssertions = mkOption {
        type = types.bool;
        default = true;
        description = "Enable hetzner environment checks";
      };

      enableServices = mkOption {
        type = types.bool;
        default = true;
        description = "Enable full service suite (1Password, i3pm, keyd, etc)";
      };

      enableDesktop = mkOption {
        type = types.bool;
        default = true;
        description = "Enable desktop modules (Sway, WayVNC, Firefox)";
      };

      enableAudio = mkOption {
        type = types.bool;
        default = true;
        description = "Enable audio services (PipeWire, Tailscale audio)";
      };
    };

    # Boot configuration
    boot = {
      device = mkOption {
        type = types.str;
        default = "/dev/sda";
        description = "Boot device path";
      };

      efiSupport = mkOption {
        type = types.bool;
        default = true;
        description = "Enable EFI boot support";
      };
    };

    # Virtualization settings (for image builds)
    virtualisation = {
      diskSize = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Disk size in MB (for VM images)";
      };

      memorySize = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Memory size in MB (for build VMs)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Common imports (always included)
    imports = [
      ./base.nix
      (modulesPath + "/profiles/qemu-guest.nix")
    ]
    # Conditional imports based on feature flags
    ++ optionals cfg.features.enableDisko [ ../disk-config.nix ]
    ++ optionals cfg.features.enableAssertions [ ../modules/assertions/hetzner-check.nix ]
    ++ optionals cfg.features.enableServices [
      ../modules/services/development.nix
      ../modules/services/networking.nix
      ../modules/services/onepassword.nix
      ../modules/services/i3-project-daemon.nix
      ../modules/services/keyd.nix
      ../modules/services/sway-tree-monitor.nix
    ]
    ++ optionals cfg.features.enableDesktop [
      ../modules/desktop/sway.nix
      ../modules/desktop/wayvnc.nix
      ../modules/desktop/firefox-1password.nix
      ../modules/desktop/firefox-pwa-1password.nix
    ]
    ++ optionals cfg.features.enableAudio [
      ../modules/services/onepassword-automation.nix
      ../modules/services/onepassword-password-management.nix
      ../modules/services/speech-to-text-safe.nix
      ../modules/services/tailscale-audio.nix
    ];

    # System identification
    networking.hostName = "nixos-hetzner-sway";

    # Boot configuration (use module options)
    boot.loader.grub = {
      enable = true;
      device = cfg.boot.device;
      efiSupport = cfg.boot.efiSupport;
      efiInstallAsRemovable = cfg.boot.efiSupport;
    };

    # Kernel configuration (common)
    boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
    boot.kernelModules = [ "kvm-intel" ];
    boot.kernelParams = [ "net.ifnames=0" ];

    # Networking (common)
    networking.useDHCP = true;

    # Virtualization settings (conditional)
    virtualisation = mkIf (cfg.virtualisation.diskSize != null) {
      diskSize = cfg.virtualisation.diskSize;
      memorySize = mkIf (cfg.virtualisation.memorySize != null) cfg.virtualisation.memorySize;
    };

    # Headless Wayland configuration (common)
    programs.sway.enable = mkIf cfg.features.enableDesktop true;
    services.wayvnc.enable = mkIf cfg.features.enableDesktop true;

    services.udev.extraRules = mkIf cfg.features.enableDesktop ''
      KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess"
    '';

    # Greetd auto-login (common)
    services.greetd = mkIf cfg.features.enableDesktop {
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

    # Environment variables (common)
    environment.sessionVariables = mkIf cfg.features.enableDesktop {
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

    # XDG portals (conditional)
    xdg.portal = mkIf cfg.features.enableDesktop {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-wlr
        xdg-desktop-portal-gtk
      ];
      config.common.default = [ "wlr" "gtk" ];
    };

    # User lingering (common)
    systemd.tmpfiles.rules = [
      "f /var/lib/systemd/linger/vpittamp 0644 root root - -"
    ];

    # Firewall (profile-dependent)
    networking.firewall = {
      allowedTCPPorts = [ 22 ]  # SSH always allowed
        ++ optionals (cfg.profile == "production" || cfg.profile == "image") [ 5900 8080 ];

      interfaces."tailscale0".allowedTCPPorts = optionals (cfg.profile == "production" || cfg.profile == "image") [
        5900 5901 5902
      ];

      checkReversePath = "loose";
    };

    # Packages (profile-dependent)
    environment.systemPackages = with pkgs;
      # Minimal packages (all profiles)
      [ vim htop neofetch ]
      # Standard packages (production, image, minimal)
      ++ optionals (cfg.profile != "ultra-minimal") [
        sway wayvnc wl-clipboard wlr-randr dotool ghostty
        btop iotop nethogs tailscale
      ];

    # Performance tuning (conditional)
    powerManagement.cpuFreqGovernor = mkIf (cfg.profile != "ultra-minimal") (lib.mkForce "performance");

    # Disable SDDM (conditional)
    services.displayManager.sddm.enable = mkIf cfg.features.enableDesktop (lib.mkForce false);

    # System state version
    system.stateVersion = "24.11";
  };
}
```

**Step 2: Update Configuration Files**

`configurations/hetzner-sway.nix` (Production):
```nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ../modules/hetzner-sway-base.nix
  ];

  profiles.hetzner-sway = {
    enable = true;
    profile = "production";

    # All features enabled (defaults)
    features = {
      enableDisko = true;
      enableAssertions = true;
      enableServices = true;
      enableDesktop = true;
      enableAudio = true;
    };

    boot = {
      device = "/dev/sda";
      efiSupport = true;
    };
  };

  # Production-specific overrides
  services.i3ProjectDaemon.logLevel = "DEBUG";
  services.onepassword-password-management = {
    enable = true;
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
    users.vpittamp = {
      enable = true;
      passwordReference = "op://CLI/NixOS User Password/password";
    };
    updateInterval = "hourly";
  };
}
```

`configurations/hetzner-sway-image.nix` (VM Image):
```nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ../modules/hetzner-sway-base.nix
  ];

  profiles.hetzner-sway = {
    enable = true;
    profile = "image";

    # Disable disko/assertions for nixos-generators
    features = {
      enableDisko = false;
      enableAssertions = false;
      enableServices = true;
      enableDesktop = true;
      enableAudio = true;
    };

    boot = {
      device = "/dev/sda";
      efiSupport = true;
    };

    # VM-specific settings
    virtualisation = {
      diskSize = 50 * 1024;  # 50GB
      memorySize = 4096;     # 4GB
    };
  };
}
```

`configurations/hetzner-sway-minimal.nix` (Minimal):
```nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ../modules/hetzner-sway-base.nix
  ];

  profiles.hetzner-sway = {
    enable = true;
    profile = "minimal";

    # Minimal feature set
    features = {
      enableDisko = false;
      enableAssertions = false;
      enableServices = false;
      enableDesktop = true;  # Keep Sway + WayVNC
      enableAudio = false;
    };

    boot = {
      device = "/dev/vda";
      efiSupport = false;  # BIOS boot for simplicity
    };

    virtualisation.diskSize = 50 * 1024;
  };

  # Minimal-specific: Simplified WayVNC service
  systemd.user.services.wayvnc = {
    description = "WayVNC server for Wayland";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc 0.0.0.0 5900";
      Restart = "on-failure";
      RestartSec = "5s";
    };

    environment.XDG_RUNTIME_DIR = "/run/user/1000";
  };
}
```

`configurations/hetzner-sway-ultra-minimal.nix` (Ultra-minimal):
```nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ../modules/hetzner-sway-base.nix
  ];

  profiles.hetzner-sway = {
    enable = true;
    profile = "ultra-minimal";

    # All features disabled
    features = {
      enableDisko = false;
      enableAssertions = false;
      enableServices = false;
      enableDesktop = false;
      enableAudio = false;
    };

    boot.device = "/dev/vda";
    virtualisation.diskSize = 50 * 1024;
  };

  # Ultra-minimal overrides (no base.nix, no services)
  imports = lib.mkForce [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
}
```

### Pros

- **Type Safety**: `mkOption` provides type checking and validation
- **Documentation**: Auto-generates NixOS manual pages with `description` fields
- **Error Messages**: Clear error messages with proper source location
- **Ecosystem Alignment**: Standard NixOS pattern used throughout nixpkgs
- **Discoverability**: `nix repl` can introspect options via `config.profiles.hetzner-sway`
- **Third-party Integration**: Other modules can conditionally check/override options
- **Lazy Evaluation**: NixOS module system optimizes evaluation

### Cons

- **Boilerplate**: Requires `options` and `config` sections
- **Initial Complexity**: More upfront design work
- **Learning Curve**: Requires understanding module system (mkIf, mkDefault, etc)
- **Indirection**: Two files to edit (module + configuration)

---

## Pattern 2: Builder Function

### Overview

Create a function that accepts parameters and returns a complete configuration, similar to nixpkgs derivation builders.

### Implementation Strategy

**Step 1: Create Builder** (`lib/hetzner-sway-builder.nix`)

```nix
{ inputs, lib, pkgs, modulesPath, ... }:

# Builder function that returns a complete NixOS configuration
{ profile ? "production"
, enableDisko ? true
, enableAssertions ? true
, enableServices ? true
, enableDesktop ? true
, enableAudio ? true
, bootDevice ? "/dev/sda"
, efiSupport ? true
, diskSize ? null
, memorySize ? null
}:

{
  imports = [
    ./base.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ]
  ++ lib.optionals enableDisko [ ../disk-config.nix ]
  ++ lib.optionals enableAssertions [ ../modules/assertions/hetzner-check.nix ]
  ++ lib.optionals enableServices [
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/i3-project-daemon.nix
    ../modules/services/keyd.nix
    ../modules/services/sway-tree-monitor.nix
  ]
  ++ lib.optionals enableDesktop [
    ../modules/desktop/sway.nix
    ../modules/desktop/wayvnc.nix
    ../modules/desktop/firefox-1password.nix
    ../modules/desktop/firefox-pwa-1password.nix
  ]
  ++ lib.optionals enableAudio [
    ../modules/services/onepassword-automation.nix
    ../modules/services/onepassword-password-management.nix
    ../modules/services/speech-to-text-safe.nix
    ../modules/services/tailscale-audio.nix
  ];

  # System identification
  networking.hostName = "nixos-hetzner-sway";

  # Boot configuration
  boot.loader.grub = {
    enable = true;
    device = bootDevice;
    efiSupport = efiSupport;
    efiInstallAsRemovable = efiSupport;
  };

  # Kernel modules (common)
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelParams = [ "net.ifnames=0" ];

  # Networking
  networking.useDHCP = true;

  # Virtualization (conditional)
  virtualisation = lib.optionalAttrs (diskSize != null) {
    diskSize = diskSize;
    memorySize = if memorySize != null then memorySize else 2048;
  };

  # Rest of configuration...
  # (Similar to module options config section)
}
```

**Step 2: Use Builder in Configurations**

`configurations/hetzner-sway.nix`:
```nix
{ inputs, ... }:

let
  builder = import ../lib/hetzner-sway-builder.nix { inherit inputs lib pkgs modulesPath; };
in
builder {
  profile = "production";
  # All defaults (enableDisko = true, enableServices = true, etc)
}
```

`configurations/hetzner-sway-image.nix`:
```nix
{ inputs, ... }:

let
  builder = import ../lib/hetzner-sway-builder.nix { inherit inputs lib pkgs modulesPath; };
in
builder {
  profile = "image";
  enableDisko = false;
  enableAssertions = false;
  diskSize = 50 * 1024;
  memorySize = 4096;
}
```

### Pros

- **Simplicity**: Single function, straightforward parameters
- **Flexibility**: Can pass arbitrary parameters (not just predefined options)
- **No Boilerplate**: Direct function call, no module system overhead
- **Testability**: Easy to test with different parameter combinations
- **Performance**: Potentially faster evaluation (no module system overhead)

### Cons

- **No Type Safety**: No automatic type checking (can pass wrong types)
- **No Documentation**: No auto-generated manual pages
- **Poor Error Messages**: Cryptic errors without source location
- **Non-standard**: Doesn't integrate with NixOS module system
- **No Discoverability**: Can't introspect available options via `nix repl`
- **Limited Merging**: Can't easily override from other modules
- **Infinite Recursion Risk**: "Working around the module system will cause issues" (NixOS wiki)

---

## Pattern 3: Profile Imports (Hybrid Approach)

### Overview

Create profile-specific modules that import a common base, similar to nixpkgs' `profiles/minimal.nix` and `profiles/installation-device.nix`.

### Implementation Strategy

**Step 1: Create Common Base** (`modules/hetzner-sway-common.nix`)

```nix
# Common configuration shared by all Hetzner Sway variants
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./base.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # System identification
  networking.hostName = lib.mkDefault "nixos-hetzner-sway";

  # Boot configuration (use mkDefault for override)
  boot.loader.grub = {
    enable = lib.mkDefault true;
    device = lib.mkDefault "/dev/sda";
    efiSupport = lib.mkDefault true;
    efiInstallAsRemovable = lib.mkDefault true;
  };

  # Kernel modules (common)
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelParams = [ "net.ifnames=0" ];

  # Networking (common)
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.checkReversePath = lib.mkDefault "loose";

  # Headless Wayland environment variables (common)
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

  # User lingering (common)
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/vpittamp 0644 root root - -"
  ];

  # System state version
  system.stateVersion = lib.mkDefault "24.11";
}
```

**Step 2: Create Profile Modules**

`modules/profiles/hetzner-sway-production.nix`:
```nix
# Production profile with full features
{ config, lib, pkgs, ... }:

{
  imports = [
    ../hetzner-sway-common.nix
    ../../disk-config.nix
    ../assertions/hetzner-check.nix

    # Services
    ../services/development.nix
    ../services/networking.nix
    ../services/onepassword.nix
    ../services/i3-project-daemon.nix
    ../services/keyd.nix
    ../services/sway-tree-monitor.nix

    # Desktop
    ../desktop/sway.nix
    ../desktop/wayvnc.nix
    ../desktop/firefox-1password.nix
    ../desktop/firefox-pwa-1password.nix

    # Audio
    ../services/onepassword-automation.nix
    ../services/onepassword-password-management.nix
    ../services/speech-to-text-safe.nix
    ../services/tailscale-audio.nix
  ];

  # Profile identifier
  system.nixos.variant_id = "production";

  # Greetd auto-login (production)
  services.greetd = {
    enable = true;
    settings.default_session = {
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

  # Firewall (production)
  networking.firewall = {
    allowedTCPPorts = [ 22 5900 8080 ];
    interfaces."tailscale0".allowedTCPPorts = [ 5900 5901 5902 ];
  };

  # Packages (production)
  environment.systemPackages = with pkgs; [
    wl-clipboard wlr-randr wayvnc dotool
    ghostty htop btop iotop nethogs neofetch tailscale
  ];

  # Performance tuning
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Disable SDDM
  services.displayManager.sddm.enable = lib.mkForce false;
}
```

`modules/profiles/hetzner-sway-image.nix`:
```nix
# VM image profile (no disko, with virtualisation settings)
{ config, lib, pkgs, ... }:

{
  imports = [
    ../hetzner-sway-common.nix
    # Skip disk-config.nix and hetzner-check.nix

    # Same services as production
    ../services/development.nix
    ../services/networking.nix
    ../services/onepassword.nix
    ../services/i3-project-daemon.nix
    ../services/keyd.nix
    ../services/sway-tree-monitor.nix
    ../desktop/sway.nix
    ../desktop/wayvnc.nix
    ../desktop/firefox-1password.nix
    ../desktop/firefox-pwa-1password.nix
    ../services/onepassword-automation.nix
    ../services/onepassword-password-management.nix
    ../services/speech-to-text-safe.nix
    ../services/tailscale-audio.nix
  ];

  # Profile identifier
  system.nixos.variant_id = "image";

  # VM settings
  virtualisation.diskSize = 50 * 1024;
  virtualisation.memorySize = 4096;

  # Same as production (reuse)
  services.greetd = {
    enable = true;
    settings.default_session = {
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

  networking.firewall = {
    allowedTCPPorts = [ 22 5900 8080 ];
    interfaces."tailscale0".allowedTCPPorts = [ 5900 5901 5902 ];
  };

  environment.systemPackages = with pkgs; [
    wl-clipboard wlr-randr wayvnc dotool
    ghostty htop btop iotop nethogs neofetch tailscale
  ];

  powerManagement.cpuFreqGovernor = lib.mkForce "performance";
  services.displayManager.sddm.enable = lib.mkForce false;
}
```

`modules/profiles/hetzner-sway-minimal.nix`:
```nix
# Minimal profile (Sway + WayVNC only)
{ config, lib, pkgs, ... }:

{
  imports = [
    ../hetzner-sway-common.nix
    # Minimal imports only
  ];

  # Profile identifier
  system.nixos.variant_id = "minimal";

  # Override boot for BIOS
  boot.loader.grub = {
    device = lib.mkForce "/dev/vda";
    efiSupport = lib.mkForce false;
  };

  # VM settings
  virtualisation.diskSize = 50 * 1024;

  # Firewall (minimal)
  networking.firewall.allowedTCPPorts = [ 22 5900 ];

  # Enable Sway
  programs.sway.enable = true;

  # Minimal packages
  environment.systemPackages = with pkgs; [
    sway wayvnc wl-clipboard htop neofetch
  ];

  # Tailscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # WayVNC PAM
  security.pam.services.wayvnc.text = ''
    auth    required pam_unix.so
    account required pam_unix.so
  '';

  # Greetd (minimal)
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd sway";
        user = "vpittamp";
      };
      initial_session = {
        command = "sway";
        user = "vpittamp";
      };
    };
  };

  # WayVNC user service
  systemd.user.services.wayvnc = {
    description = "WayVNC server for Wayland";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc 0.0.0.0 5900";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    environment.XDG_RUNTIME_DIR = "/run/user/1000";
  };

  # User groups (minimal)
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" ];
}
```

`modules/profiles/hetzner-sway-ultra-minimal.nix`:
```nix
# Ultra-minimal profile (boot test only)
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    # Skip base.nix and all other modules
  ];

  # Profile identifier
  system.nixos.variant_id = "ultra-minimal";

  # System identification
  networking.hostName = "nixos-hetzner-sway";

  # Networking
  networking.useDHCP = true;

  # VM settings
  virtualisation.diskSize = 50 * 1024;

  # Minimal packages
  environment.systemPackages = with pkgs; [ vim htop ];

  # SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # User
  users.users.vpittamp = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos123";
  };

  # Sudo
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11";
}
```

**Step 3: Update Configuration Files (Thin Wrappers)**

`configurations/hetzner-sway.nix`:
```nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ../modules/profiles/hetzner-sway-production.nix
  ];

  # Production-specific overrides (if any)
  services.i3ProjectDaemon.logLevel = "DEBUG";

  services.onepassword-password-management = {
    enable = true;
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
    users.vpittamp = {
      enable = true;
      passwordReference = "op://CLI/NixOS User Password/password";
    };
    updateInterval = "hourly";
  };
}
```

`configurations/hetzner-sway-image.nix`:
```nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ../modules/profiles/hetzner-sway-image.nix
  ];

  # Image-specific overrides (if any)
}
```

`configurations/hetzner-sway-minimal.nix`:
```nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ../modules/profiles/hetzner-sway-minimal.nix
  ];
}
```

`configurations/hetzner-sway-ultra-minimal.nix`:
```nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ../modules/profiles/hetzner-sway-ultra-minimal.nix
  ];
}
```

### Pros

- **Simple**: No new abstraction layer, just modularization
- **NixOS-Native**: Uses standard import/override pattern
- **Clear Separation**: Each profile is self-contained
- **Easy to Understand**: Clear file structure
- **Flexible**: Easy to add profile-specific overrides
- **Ecosystem Alignment**: Matches nixpkgs profiles pattern

### Cons

- **Code Duplication**: Some duplication between profiles (greetd, firewall, packages)
- **No Type Safety**: No option type checking (relies on module system only)
- **Manual Synchronization**: Changes to common config require updating all profiles
- **No Validation**: No centralized validation of profile combinations

---

## Common Configuration Extraction

### Identified Common Elements

| Configuration Section | Commonality | Variance |
|----------------------|-------------|----------|
| Base imports | 100% | None |
| QEMU guest profile | 100% | None |
| Kernel modules | 100% | None |
| Kernel params | 100% | None |
| Networking (DHCP) | 100% | None |
| Wayland env vars | 100% | None (when desktop enabled) |
| User lingering | 100% | None |
| System state version | 100% | None |
| Boot loader (GRUB) | 80% | Device path, EFI support |
| Firewall | 60% | Ports vary by profile |
| Packages | 40% | Varies significantly |
| Service imports | 25% | Production/image vs minimal |

### Extraction Strategy

**High-Value Extraction (>80% common):**
- Kernel configuration (modules, params)
- Wayland environment variables
- User lingering
- System state version
- Networking base config

**Medium-Value Extraction (40-80% common):**
- Boot loader (parameterize device/EFI)
- Greetd auto-login (common when desktop enabled)

**Low-Value Extraction (<40% common):**
- Service imports (use conditional imports)
- Packages (use conditional lists)
- Firewall (use profile-specific overrides)

---

## Conditional Packages & Services

### Using lib.optionals

```nix
# Conditional imports
imports = [
  ./base.nix
]
++ lib.optionals enableDisko [ ../disk-config.nix ]
++ lib.optionals enableServices [
  ../modules/services/i3-project-daemon.nix
  ../modules/services/keyd.nix
];

# Conditional packages
environment.systemPackages = with pkgs;
  [ vim htop ]  # Always included
  ++ lib.optionals (profile != "ultra-minimal") [
    sway wayvnc wl-clipboard
  ]
  ++ lib.optionals (profile == "production") [
    ghostty btop iotop nethogs tailscale
  ];
```

### Using lib.mkIf

```nix
# Conditional services
services.greetd = lib.mkIf enableDesktop {
  enable = true;
  settings.default_session = {
    command = "...";
    user = "vpittamp";
  };
};

# Conditional firewall ports
networking.firewall.allowedTCPPorts = [ 22 ]
  ++ lib.optionals (profile == "production" || profile == "image") [ 5900 8080 ];
```

### Best Practices

1. **Use lib.optionals for lists**: Cleaner than if-then-else for import/package lists
2. **Use lib.mkIf for attrsets**: Better for service/module configuration blocks
3. **Avoid nested conditionals**: Extract to separate variables/functions
4. **Use lib.mkDefault for overridable defaults**: Allows profile-specific overrides
5. **Group related conditionals**: Keep feature flags together

---

## Flake Integration

### Pattern 1: Module Options Integration

```nix
# nixos/default.nix
{
  hetzner-sway = helpers.mkSystem {
    hostname = "nixos-hetzner-sway";
    system = "x86_64-linux";
    modules = [
      disko.nixosModules.disko
      ../modules/hetzner-sway-base.nix

      # Configuration
      {
        profiles.hetzner-sway = {
          enable = true;
          profile = "production";
          features = {
            enableDisko = true;
            enableServices = true;
            enableDesktop = true;
            enableAudio = true;
          };
        };
      }

      # Home Manager
      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/hetzner-sway.nix ];
      })
    ];
  };

  hetzner-sway-image = helpers.mkSystem {
    hostname = "nixos-hetzner-sway";
    system = "x86_64-linux";
    modules = [
      # No disko
      ../modules/hetzner-sway-base.nix

      {
        profiles.hetzner-sway = {
          enable = true;
          profile = "image";
          features.enableDisko = false;
          features.enableAssertions = false;
          virtualisation = {
            diskSize = 50 * 1024;
            memorySize = 4096;
          };
        };
      }

      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/hetzner-sway.nix ];
      })
    ];
  };

  # Similar for minimal and ultra-minimal...
}
```

### Pattern 2: Builder Function Integration

```nix
# nixos/default.nix
let
  hetznerSwayBuilder = import ../lib/hetzner-sway-builder.nix;
in
{
  hetzner-sway = helpers.mkSystem {
    hostname = "nixos-hetzner-sway";
    system = "x86_64-linux";
    modules = [
      disko.nixosModules.disko
      (hetznerSwayBuilder {
        profile = "production";
        # Use all defaults
      })

      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/hetzner-sway.nix ];
      })
    ];
  };

  hetzner-sway-image = helpers.mkSystem {
    hostname = "nixos-hetzner-sway";
    system = "x86_64-linux";
    modules = [
      (hetznerSwayBuilder {
        profile = "image";
        enableDisko = false;
        enableAssertions = false;
        diskSize = 50 * 1024;
        memorySize = 4096;
      })

      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/hetzner-sway.nix ];
      })
    ];
  };
}
```

### Pattern 3: Profile Imports Integration

```nix
# nixos/default.nix
{
  hetzner-sway = helpers.mkSystem {
    hostname = "nixos-hetzner-sway";
    system = "x86_64-linux";
    modules = [
      disko.nixosModules.disko
      ../configurations/hetzner-sway.nix  # Imports production profile

      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/hetzner-sway.nix ];
      })
    ];
  };

  hetzner-sway-image = helpers.mkSystem {
    hostname = "nixos-hetzner-sway";
    system = "x86_64-linux";
    modules = [
      ../configurations/hetzner-sway-image.nix  # Imports image profile

      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/hetzner-sway.nix ];
      })
    ];
  };

  # etc...
}
```

### Backwards Compatibility

All three patterns maintain backwards compatibility:

```bash
# Production deployment
sudo nixos-rebuild switch --flake .#hetzner-sway

# VM image build
nix build .#hetzner-sway-qcow2

# Minimal test
nix build .#hetzner-sway-minimal-qcow2
```

Configuration names remain unchanged in `nixosConfigurations` and `packages`.

---

## Recommended Approach

### Strategy: Profile Imports (Pattern 3)

**Rationale:**
1. **Simplicity**: No new abstraction, just modularization
2. **Ecosystem Alignment**: Matches nixpkgs pattern (profiles/minimal.nix, profiles/installation-device.nix)
3. **Clear Separation**: Each profile is self-contained and easy to understand
4. **Low Risk**: No breaking changes, incremental adoption possible
5. **Maintainability**: Easy to add/remove/modify profiles

### Implementation Plan

**Phase 1: Extract Common Base (1-2 hours)**
- Create `modules/hetzner-sway-common.nix` with shared configuration
- Extract kernel modules, networking, Wayland env vars, user lingering
- Use `lib.mkDefault` for overridable defaults

**Phase 2: Create Profile Modules (2-3 hours)**
- Create `modules/profiles/hetzner-sway-production.nix`
- Create `modules/profiles/hetzner-sway-image.nix`
- Create `modules/profiles/hetzner-sway-minimal.nix`
- Create `modules/profiles/hetzner-sway-ultra-minimal.nix`
- Each profile imports common base + profile-specific modules

**Phase 3: Update Configuration Files (1 hour)**
- Update `configurations/hetzner-sway.nix` to import production profile
- Update other configuration files to import respective profiles
- Add profile-specific overrides as needed

**Phase 4: Testing & Validation (2-3 hours)**
- Test each configuration with `nixos-rebuild dry-build`
- Verify QCOW2 image builds with `nix build .#hetzner-sway-qcow2`
- Compare generated configurations with `nix-diff`
- Validate no regressions in functionality

**Total Estimated Time: 6-9 hours**

### Expected Results

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Total LOC | ~700 | ~400 | -43% |
| Duplication | ~300 LOC | ~50 LOC | -83% |
| Files | 4 | 9 | +5 |
| Complexity | Low | Medium | +1 |
| Maintainability | Medium | High | +2 |

### File Structure

```
configurations/
├── hetzner-sway.nix              (10 LOC - thin wrapper)
├── hetzner-sway-image.nix        (5 LOC - thin wrapper)
├── hetzner-sway-minimal.nix      (5 LOC - thin wrapper)
└── hetzner-sway-ultra-minimal.nix (5 LOC - thin wrapper)

modules/
├── hetzner-sway-common.nix       (100 LOC - common base)
└── profiles/
    ├── hetzner-sway-production.nix     (80 LOC)
    ├── hetzner-sway-image.nix          (75 LOC)
    ├── hetzner-sway-minimal.nix        (60 LOC)
    └── hetzner-sway-ultra-minimal.nix  (40 LOC)
```

---

## Alternative Recommendation (If More Flexibility Needed)

### Strategy: Module Options (Pattern 1)

**Use Cases:**
- Need type safety and validation
- Want auto-generated documentation
- Plan to expose options to third-party modules
- Prefer NixOS-native pattern over custom modularization

**Trade-offs:**
- Higher initial complexity (+2-3 hours development time)
- Better long-term maintainability
- More flexible for future extensions
- Steeper learning curve for contributors

---

## Maintenance Tradeoffs

### Benefits of Consolidation

| Benefit | Impact | Example |
|---------|--------|---------|
| **DRY Principle** | High | Single source for Wayland env vars |
| **Consistency** | High | All variants use same kernel modules |
| **Easier Updates** | High | Update service imports once, affects all |
| **Reduced Testing** | Medium | Fewer files to validate |
| **Clearer Intent** | Medium | Profile names explicitly state purpose |

### Potential Drawbacks

| Drawback | Risk | Mitigation |
|----------|------|------------|
| **Increased Indirection** | Low | Use clear naming, comments |
| **Harder to Understand** | Low | Document profile structure |
| **Merge Conflicts** | Low | Profiles rarely edited simultaneously |
| **Testing Complexity** | Medium | Test each profile independently |
| **Debugging Difficulty** | Low | Use `--show-trace` for import chain |

### When to Use Separate Files

**Use separate files when:**
- Variants have <20% code overlap
- Profiles serve fundamentally different purposes
- Configuration changes independently
- Team members work on different variants simultaneously

**Use consolidation when:**
- Variants have >40% code overlap (✓ Current case)
- Profiles differ only in feature flags
- Changes should propagate across variants
- Maintenance burden is high

---

## Code Examples

### Example 1: Conditional Service Import

```nix
# modules/hetzner-sway-common.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.profiles.hetzner-sway;

  # Helper to conditionally import services
  importServices = profile: {
    production = [
      ../services/i3-project-daemon.nix
      ../services/keyd.nix
      ../services/sway-tree-monitor.nix
      ../services/onepassword.nix
      ../services/onepassword-automation.nix
      ../services/speech-to-text-safe.nix
      ../services/tailscale-audio.nix
    ];
    image = [
      ../services/i3-project-daemon.nix
      ../services/keyd.nix
      ../services/sway-tree-monitor.nix
      ../services/onepassword.nix
    ];
    minimal = [];
    ultra-minimal = [];
  }.${profile};
in
{
  imports = [
    ./base.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ]
  ++ (importServices cfg.profile);

  # Rest of configuration...
}
```

### Example 2: Profile-Specific Package Lists

```nix
# Using lib.optionals with helper function
let
  packagesByProfile = profile: with pkgs;
    # Minimal packages (all profiles)
    [ vim htop ]

    # Standard packages (production, image, minimal)
    ++ lib.optionals (profile != "ultra-minimal") [
      sway wayvnc wl-clipboard wlr-randr
    ]

    # Development packages (production, image)
    ++ lib.optionals (profile == "production" || profile == "image") [
      ghostty btop iotop nethogs neofetch tailscale dotool
    ];
in
{
  environment.systemPackages = packagesByProfile config.profiles.hetzner-sway.profile;
}
```

### Example 3: Firewall Configuration

```nix
# Profile-specific firewall configuration
networking.firewall = {
  # Common: SSH always allowed
  allowedTCPPorts = [ 22 ]
    # Production/Image: VNC + Web
    ++ lib.optionals (cfg.profile == "production" || cfg.profile == "image")
       [ 5900 8080 ]
    # Minimal: VNC only
    ++ lib.optionals (cfg.profile == "minimal")
       [ 5900 ];

  # Tailscale interface (production/image only)
  interfaces."tailscale0".allowedTCPPorts =
    lib.optionals (cfg.profile == "production" || cfg.profile == "image")
    [ 5900 5901 5902 ];

  checkReversePath = "loose";
};
```

---

## Validation & Testing

### Pre-Consolidation Validation

```bash
# 1. Build all variants to ensure they work
sudo nixos-rebuild dry-build --flake .#hetzner-sway
nix build .#hetzner-sway-qcow2
nix build .#hetzner-sway-minimal

# 2. Generate configuration dumps for comparison
nix eval --json .#nixosConfigurations.hetzner-sway.config \
  > /tmp/before-production.json

nix eval --json .#nixosConfigurations.hetzner-sway-image.config \
  > /tmp/before-image.json
```

### Post-Consolidation Validation

```bash
# 1. Build all variants (should succeed)
sudo nixos-rebuild dry-build --flake .#hetzner-sway
nix build .#hetzner-sway-qcow2
nix build .#hetzner-sway-minimal

# 2. Generate new configuration dumps
nix eval --json .#nixosConfigurations.hetzner-sway.config \
  > /tmp/after-production.json

# 3. Compare configurations (should be identical)
diff <(jq -S . /tmp/before-production.json) \
     <(jq -S . /tmp/after-production.json)

# Or use nix-diff for detailed comparison
nix-diff \
  /tmp/before-production.json \
  /tmp/after-production.json
```

### Regression Testing Checklist

- [ ] All variants build successfully (`nixos-rebuild dry-build`)
- [ ] QCOW2 images build without errors (`nix build .#hetzner-sway-qcow2`)
- [ ] Generated configurations are identical (use `nix-diff`)
- [ ] Service imports are correct (check with `nix eval`)
- [ ] Boot loader configuration is correct
- [ ] Firewall ports match expected values
- [ ] Package lists match expected values
- [ ] No new errors in build logs

---

## Conclusion

### Summary of Recommendations

1. **Use Profile Imports (Pattern 3)** for this use case
   - Clear, simple, ecosystem-aligned
   - Low risk, incremental adoption
   - Matches nixpkgs patterns

2. **Extract ~60% of common configuration** to `hetzner-sway-common.nix`
   - Kernel modules, networking, Wayland env vars
   - Use `lib.mkDefault` for overridable defaults

3. **Create 4 profile modules** in `modules/profiles/`
   - Production, image, minimal, ultra-minimal
   - Each imports common base + profile-specific modules

4. **Update configuration files** to be thin wrappers
   - Import respective profile module
   - Add profile-specific overrides

5. **Validate with nix-diff** before/after consolidation
   - Ensure no regressions
   - Verify configuration equivalence

### Expected Outcomes

- **43% code reduction** (700 LOC → 400 LOC)
- **83% duplication reduction** (300 LOC → 50 LOC)
- **Higher maintainability** (single source of truth)
- **Clearer intent** (profile names explicit)
- **No breaking changes** (backward compatible)

### Next Steps

1. Review this research document
2. Approve recommended approach (Profile Imports)
3. Implement Phase 1 (Extract common base)
4. Test and validate
5. Implement Phase 2-4 (Create profiles, update configs)
6. Final testing and documentation update

---

## References

- [NixOS Module System Documentation](https://nixos.org/manual/nixos/stable/index.html#sec-writing-modules)
- [NixOS Profiles (nixpkgs)](https://github.com/NixOS/nixpkgs/tree/master/nixos/modules/profiles)
- [NixOS Module Types](https://nlewo.github.io/nixos-manual-sphinx/development/option-types.xml.html)
- [NixOS Flakes Book - Module System](https://nixos-and-flakes.thiscute.world/other-usage-of-flakes/module-system)
- [Conditional NixOS Config](https://librephoenix.com/2023-12-26-nixos-conditional-config-and-custom-options)

---

**Document Version:** 1.0
**Date:** 2025-11-22
**Author:** Claude Code (Research Assistant)
**Purpose:** Hetzner-Sway Configuration Consolidation Research
