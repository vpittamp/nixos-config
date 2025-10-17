# i3wsr - Dynamic Workspace Renaming for i3wm
# Automatically renames i3 workspaces to reflect running applications
{ config, lib, pkgs, ... }:

with lib;

{
  # Install i3wsr package
  home.packages = [ pkgs.i3wsr ];

  # Configure i3wsr
  xdg.configFile."i3wsr/config.toml".text = ''
    [general]
    separator = " | "
    default_icon = ""

    [options]
    remove_duplicates = true
    no_names = false

    [icons]
    # Standard applications
    firefox = ""
    code = ""
    "Code" = ""
    alacritty = ""
    "Alacritty" = ""

    # Firefox PWAs (generic detection)
    # All Firefox PWAs have WM_CLASS pattern: FFPWA-{ID}
    # This matches any FFPWA window and shows a web app icon

    [aliases.class]
    # Generic Firefox PWA detection
    # Matches all PWA windows: FFPWA-01K665SPD8EPMP3JTW02JM1M0Z, etc.
    "^FFPWA-.*" = "PWA"

    # Standard application aliases
    "^Code$" = "VSCode"
  '';

  # Start i3wsr automatically with i3
  # Note: This adds to the manual i3 config at ~/.config/i3/config
  # We use a separate autostart script to avoid modifying the manual config
  home.file.".config/i3/scripts/i3wsr-start.sh" = {
    text = ''
      #!/usr/bin/env bash
      # Start i3wsr daemon
      ${pkgs.i3wsr}/bin/i3wsr
    '';
    executable = true;
  };

  # Create systemd user service for i3wsr
  systemd.user.services.i3wsr = {
    Unit = {
      Description = "i3 workspace renamer";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.i3wsr}/bin/i3wsr";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
