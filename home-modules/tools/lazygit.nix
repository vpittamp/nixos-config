# Lazygit - Terminal UI for Git
# Provides .desktop entries to launch in terminal from rofi
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    lazygit
    lazydocker
  ];

  # Desktop entries now managed by app-registry.nix (Feature 034)
  # xdg.dataFile."applications/lazygit.desktop".text = ''
  #   [Desktop Entry]
  #   Type=Application
  #   Name=Lazygit
  #   Comment=Simple terminal UI for git commands
  #   Exec=ghostty -e lazygit
  #   Icon=git
  #   Terminal=false
  #   Categories=Development;RevisionControl;
  #   Keywords=git;vcs;version control;
  # '';

  xdg.dataFile."applications/lazydocker.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Lazydocker
    Comment=Simple terminal UI for docker and docker-compose
    Exec=ghostty -e lazydocker
    Icon=docker
    Terminal=false
    Categories=Development;System;
    Keywords=docker;container;compose;
  '';

  # Optional: Configure lazygit if config file exists
  # programs.lazygit = {
  #   enable = true;
  #   settings = {
  #     # Add custom lazygit settings here if needed
  #   };
  # };
}
