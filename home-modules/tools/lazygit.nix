# Lazygit - Terminal UI for Git
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    lazygit
  ];

  # Desktop entries managed by app-registry.nix (Feature 034)
}
