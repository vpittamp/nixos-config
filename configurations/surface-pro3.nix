# Microsoft Surface Pro 3 (2014) Configuration
# Intel Core i5-4300U (Haswell) with HD Graphics 4400, 3.7 GiB RAM
#
# A near-parity sibling of configurations/surface.nix. It diverges on hardware
# (Haswell, not Kaby Lake R — see hardware/surface-pro3.nix) and drops exactly
# three things: the linux-surface kernel, Podman, and CUPS printing.
#
# The first cut of this file trimmed far more on the assumption that a 3.7 GiB
# machine could not carry it. Measurement said otherwise: full parity is 40.1
# GiB against 35.0 GiB trimmed, a 5.1 GiB difference on a 108 GiB root, and
# every module dropped for "memory" except Podman and printing turned out to
# define no systemd units at all. Only those two run anything, so only those
# two are still off. See the "DELIBERATELY NOT IMPORTED" block below.
#
# Deploys happen over tailscale from ryzen (never build on the Pro 3 itself):
#   nixos-rebuild switch --flake .#surface-pro3 \
#     --target-host vpittamp@surface-pro --use-remote-sudo
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
    ../hardware/surface-pro3.nix

    # nixos-hardware modules for Intel laptops
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd

    # Desktop environment (Sway - Wayland compositor)
    ../modules/desktop/sway.nix

    # Services
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/development.nix

    # Home Assistant Core — see that file for the version rationale (pinned
    # nixpkgs carries 2026.6.1; upstream 2026.8.x needs a full channel bump).
    ../modules/services/home-assistant.nix

    # Bare metal essentials (no Podman/printing here — see below)
    ../modules/services/bare-metal.nix

    # Browser integrations. These were dropped in the first cut of this file on
    # the assumption they cost RAM; measurement showed otherwise. None of the
    # six defines a systemd unit — they install packages and policy files, so
    # they are inert until an application is launched. Restoring them costs
    # ~5.0 GiB of a 108 GiB root and nothing resident.
    ../modules/desktop/firefox-1password.nix
    ../modules/desktop/chrome-claude.nix
    ../modules/desktop/chrome-kimi-webbridge.nix
    ../modules/desktop/chrome-bookmarks.nix
    ../modules/desktop/chrome-sync.nix
    ../modules/desktop/chrome-gemini.nix

    # ========== DELIBERATELY NOT IMPORTED (vs configurations/surface.nix) ==========
    #
    # inputs.nixos-hardware.nixosModules.microsoft-surface-common
    #   Builds the linux-surface patched kernel, which has no binary cache. On
    #   this CPU that is hours of compilation, and the Pro 3 gains nothing from
    #   it: its digitizer is an N-trig HID device (NTRG0001 1B96:1B05) that
    #   mainline already drives. Confirmed enumerating on the stock 6.12 kernel
    #   during install. services.iptsd is omitted for the same reason — IPTS is
    #   Surface Pro 4 and newer, so on this machine it has nothing to talk to.
    #
    # Podman and CUPS printing (see services.bare-metal below)
    #   The only two dropped pieces that run always-on daemons. Kept off because
    #   this machine has 3.7 GiB of RAM, not because of their ~115 MiB on disk.
    #
    # ../modules/services/cachix-deploy.nix
    #   Needs its own agent token provisioned in 1Password + registered at
    #   app.cachix.org. Add once this host is worth auto-deploying to.
  ];

  # Kept byte-identical to configurations/surface.nix on purpose: these overlays
  # decide store paths, and CI already builds and pushes the `surface` closure to
  # pittampalli.cachix.org (see .github/workflows/deploy.yml). Matching them
  # means this host downloads those derivations instead of building them.
  # diffnav and gh-enhance are not in nixpkgs at all — home-modules/profiles/
  # base-home.nix imports tools that reference them, so these are load-bearing.
  nixpkgs.overlays = [
    (final: prev: {
      firefox = pkgs-unstable.firefox;
      firefox-unwrapped = pkgs-unstable.firefox-unwrapped;

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
  networking.hostName = "surface-pro3";

  # Enable Sway Wayland compositor
  services.sway.enable = true;

  # ========== BARE METAL FEATURES ==========
  # The only two pieces still dropped vs surface.nix. Both add always-running
  # daemons (podman socket + aardvark-dns; cupsd + cups-browsed + avahi), which
  # is the whole reason they stay off — their disk cost is only ~115 MiB.
  services.bare-metal = {
    enable = true;
    enableVirtualization = false;  # 2 cores / 3.7 GiB — nothing to spare
    enablePodman = false;          # resident daemon; off for RAM headroom
    enablePrinting = false;        # resident daemon; no printer on this host
    enableFingerprint = false;     # Surface Pro 3 has no fingerprint reader
    enableGaming = false;

    # This host is administered entirely over tailscale — it has no local user
    # session most of the time, so a lid-triggered suspend takes it off the
    # network with no way to bring it back short of physically pressing power.
    # It dropped off the tailnet exactly that way during bring-up. The default
    # externalPower/docked values already keep it awake; "lock" on battery is
    # the deliberate divergence, trading standby time for reachability. (Type
    # Cover closed == lid closed on a Surface, which makes this easy to trip.)
    lidPolicy.battery = "lock";
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

  # Memory management. Diverges from surface.nix (swappiness 10): with 3.7 GiB
  # of RAM and 8 GiB of swap this machine is expected to swap, and suppressing
  # it just pushes the box into reclaim stalls instead. 60 is the kernel default.
  boot.kernel.sysctl = {
    "vm.swappiness" = 60;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_ratio" = 10;
    "vm.laptop_mode" = 5;
  };

  # Boot configuration for standard x86_64 UEFI.
  # Secure Boot was already disabled in the Surface UEFI during bring-up.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel parameters for Haswell. Note these differ from surface.nix: the
  # Kaby Lake PSR workaround there (i915.enable_psr=0) is not needed on
  # Haswell, and this generation defaults to intel_pstate anyway.
  boot.kernelParams = [
    "i915.enable_fbc=1"           # Framebuffer compression (power saving)
  ];

  systemd.services.home-manager-vpittamp = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "2s";
      StartLimitBurst = 3;
      StartLimitIntervalSec = 30;
    };
  };

  # NetworkManager for WiFi. The connection profile is NOT declared here: it was
  # seeded into /etc/NetworkManager/system-connections during install and is
  # stateful, which keeps the PSK out of this repo.
  networking.networkmanager.enable = true;

  # Firewall: base networking.nix enables it with SSH/Tailscale only; also allow
  # mDNS so Chrome Chromecast / TV discovery works on the LAN.
  networking.firewall.allowedUDPPorts = [ 5353 ];

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

  # Display - HD Graphics 4400 via modesetting. Panel is 2160x1440 (~216 PPI);
  # scaling is handled by Sway (scale 1.5, see home-modules/desktop/sway.nix).
  services.xserver = {
    videoDrivers = [ "modesetting" ];
  };

  environment.sessionVariables = {
    XCURSOR_SIZE = "24";
    _JAVA_OPTIONS = "-Dsun.java2d.uiScale=1.0";
    ELECTRON_FORCE_IS_PACKAGED = "true";

    # Haswell uses the legacy i965 VA-API driver, NOT iHD. surface.nix sets
    # LIBVA_DRIVER_NAME = "iHD" because Kaby Lake R supports it; that value
    # here would silently disable hardware video decode entirely.
    LIBVA_DRIVER_NAME = "i965";

    NIXOS_OZONE_WL = "1";
  };

  # Type Cover touchpad
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

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
  services.fwupd.enable = true;

  # Garbage collection is inherited from base.nix (weekly, --delete-older-than
  # 7d). Not overridden here: base.nix defines nix.gc.options without mkDefault,
  # so any value set here is a module conflict rather than an override.

  # 1Password. gui.enable adds the package plus polkit config and no systemd
  # unit, so it costs 513.6 MiB on disk and nothing resident until launched —
  # and the Walker `*` provider needs the GUI running to unlock the CLI.
  services.onepassword = {
    enable = true;
    user = "vpittamp";
    gui.enable = true;
    automation.enable = false;
    passwordManagement.enable = false;
    ssh.enable = true;
  };

  # Fallback password for initial setup (change with passwd)
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";

  # TPM 2.0 is present on the Pro 3 and exposed as /dev/tpm0
  security.tpm2.enable = true;

  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" "video" "seat" "input" "onepassword" "tss" ];

  # Bluetooth (Marvell 88W8897 AVASTAR WiFi/BT composite — same chip as the
  # Laptop 2, USB-attached BT side)
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true;
  };
  services.blueman.enable = true;

  services.upower.enable = true;

  # TLP off for the same reason as surface.nix (Surface power management is
  # better left to the kernel + thermald than to TLP's defaults).
  services.tlp.enable = lib.mkForce false;
  services.power-profiles-daemon.enable = false;
  services.thermald.enable = true;

  environment.systemPackages = with pkgs; [
    ghostty
    brightnessctl

    # Icon rasterisation for the PWA install path (pwa-helpers)
    imagemagick
    librsvg

    # Remote access
    tailscale

    # Power management utilities
    powertop
    acpi

    # Hardware info
    pciutils
    usbutils
    lshw

    # VA-API verification (expect i965, not iHD, on this machine)
    libva-utils

    # TPM 2.0 tooling
    tpm2-tools

    # Screenshots / recording (Wayland)
    grim
    slurp
  ];
}
