{ config, pkgs, lib, inputs, osConfig, ... }:
{
  imports = [
    ../terminal/konsole.nix
    ../desktop/touchpad-gestures.nix
    ../desktop/plasma-config.nix
    ../desktop/plasma-sync.nix  # Analysis tool for comparing plasma configs
    # ../desktop/plasma-pwa-taskbar.nix  # Disabled - conflicts with plasma-manager
    ../desktop/project-activities
    ../desktop/activity-aware-apps-native.nix  # Native KDE activity management
    ../desktop/monitoring-desktop-widgets.nix  # Monitoring activity widgets
    #     ../apps/headlamp.nix
    #     ../apps/headlamp-config.nix
    ../tools/kwallet-config.nix
    ../tools/firefox-pwas-declarative.nix  # Declaratively install and manage PWAs
    # ../tools/pwa-taskbar-pins.nix  # Disabled - using panels.nix instead
    inputs.plasma-manager.homeModules.plasma-manager
  ];

  programs.plasma = {
    enable = true;
    overrideConfig = false;  # Keep false to allow manual customization
  };

  # Disabled - using panels.nix for permanent pins instead
  # programs.pwa-taskbar-pins = {
  #   enable = true;
  #   autoPin = true;  # Automatically pin PWAs after installation
  # };

  # Disable PWA taskbar module - causes conflicts
  # programs.plasma-pwa-taskbar = {
  #   enable = false;
  # };

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
