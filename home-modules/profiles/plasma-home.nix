{ config, pkgs, lib, inputs, osConfig, ... }:
{
  imports = [
    ../terminal/konsole.nix
    ../desktop/touchpad-gestures.nix
    ../desktop/plasma-config.nix
    ../desktop/plasma-sync.nix
    ../desktop/plasma-snapshot-analysis.nix
    ../desktop/project-activities
    ../desktop/activity-aware-apps-native.nix
    ../desktop/monitoring-desktop-widgets.nix
    ../desktop/speech-to-text-shortcuts.nix
    ../tools/kwallet-config.nix
    ../tools/firefox-pwas-declarative.nix
    inputs.plasma-manager.homeModules.plasma-manager
  ];

  programs.plasma = {
    enable = true;
    overrideConfig = false;  # Keep false to allow manual customization
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
