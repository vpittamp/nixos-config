{ config, pkgs, lib, inputs, osConfig, ... }:
{
  imports = [
    ../terminal/konsole.nix
    ../desktop/touchpad-gestures.nix
    ../desktop/plasma-config.nix
    ../desktop/project-activities
    ../apps/headlamp.nix
    ../apps/headlamp-config.nix
    ../tools/kwallet-config.nix
    inputs.plasma-manager.homeModules.plasma-manager
  ];

  programs.plasma = {
    enable = true;
    overrideConfig = true;
    resetFilesExclude = lib.mkBefore [ "plasma-org.kde.plasma.desktop-appletsrc" ];
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
