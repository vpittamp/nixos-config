{ config, pkgs, lib, inputs, osConfig, ... }:
{
  imports = [
    ../terminal/konsole.nix
    ../desktop/touchpad-gestures.nix
    ../desktop/plasma-config.nix
    ../desktop/plasma-sync.nix  # Analysis tool for comparing plasma configs
    ../desktop/plasma-pwa-taskbar.nix  # Fixed and re-enabled
    ../desktop/project-activities
    ../desktop/activity-aware-apps-native.nix  # Native KDE activity management
    ../desktop/monitoring-desktop-widgets.nix  # Monitoring activity widgets
    ../apps/headlamp.nix
    ../apps/headlamp-config.nix
    ../tools/kwallet-config.nix
    inputs.plasma-manager.homeModules.plasma-manager
  ];

  programs.plasma = {
    enable = true;
    overrideConfig = true;  # Let Nix fully manage KDE config files
    # resetFilesExclude = lib.mkBefore [ "plasma-org.kde.plasma.desktop-appletsrc" ];  # Not needed with overrideConfig = true
  };

  # Enable PWA taskbar integration
  programs.plasma-pwa-taskbar = {
    enable = true;
    # PWAs will be automatically pulled from system configuration
    primaryScreen = true;
    additionalScreens = [];  # Add screen numbers if multiple monitors
  };

  programs.konsole = {
    enable = true;
    defaultProfile = "Shell";
    profiles.Shell = {
      font.name = "FiraCode Nerd Font";
      font.size = 11;
      command = "/run/current-system/sw/bin/bash -l";
      colorScheme = "WhiteOnBlack";
    };
  };

  xsession.enable = true;
}
