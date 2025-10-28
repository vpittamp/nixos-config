# Sway Wayland Compositor Configuration Module
# Parallel to i3wm.nix - adapted for Wayland on M1 MacBook Pro
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sway;
in {
  options.services.sway = {
    enable = mkEnableOption "Sway wayland compositor";

    package = mkOption {
      type = types.package;
      default = pkgs.sway;
      description = "Sway package to use";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [
        swaylock
        swayidle
        wl-clipboard  # Wayland clipboard utilities
        grim          # Screenshot utility for Wayland
        slurp         # Screen area selection tool
        mako          # Notification daemon for Wayland
      ];
      description = "Additional packages to install with Sway";
    };

    wrapperFeatures = mkOption {
      type = types.attrsOf types.bool;
      default = {
        base = true;
        gtk = true;
      };
      description = "Sway wrapper features to enable";
    };
  };

  config = mkIf cfg.enable {
    # Enable Wayland and Sway
    programs.sway = {
      enable = true;
      package = cfg.package;
      wrapperFeatures = cfg.wrapperFeatures;
      extraPackages = cfg.extraPackages;
    };

    # Wayland-specific environment variables (FR-004)
    environment.sessionVariables = {
      # Enable Wayland support for applications
      MOZ_ENABLE_WAYLAND = "1";           # Firefox
      NIXOS_OZONE_WL = "1";               # Chromium/Electron apps
      QT_QPA_PLATFORM = "wayland";        # Qt applications
      SDL_VIDEODRIVER = "wayland";        # SDL applications
      _JAVA_AWT_WM_NONREPARENTING = "1";  # Java AWT applications

      # XDG specifications for Wayland
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "sway";
    };

    # Set Sway as default session (parallel to i3 configuration)
    services.displayManager.defaultSession = mkDefault "sway";

    # Install Sway and essential tools
    environment.systemPackages = with pkgs; [
      cfg.package
      alacritty      # Terminal (Wayland-native)
      ghostty        # Alternative terminal (Wayland-native)
      foot           # Minimal Wayland terminal
    ] ++ cfg.extraPackages;

    # Enable XWayland for X11 app compatibility
    programs.xwayland.enable = mkDefault true;

    # Security: Enable polkit for privilege elevation
    security.polkit.enable = true;

    # D-Bus: Required for Wayland session management
    services.dbus.enable = true;

    # PipeWire for audio/video (better Wayland support than PulseAudio)
    services.pipewire = {
      enable = mkDefault true;
      alsa.enable = mkDefault true;
      pulse.enable = mkDefault true;
    };

    # Seat management for Wayland session access to DRM devices
    services.seatd.enable = true;

    # Add users to video group for DRM access
    users.groups.video = {};
  };
}
