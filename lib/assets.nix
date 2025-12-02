# Assets Package: Copy static assets to Nix store for portable builds
# Feature 106: Make NixOS Config Portable
#
# This module creates a derivation that copies the assets directory to the Nix store.
# Assets are then referenced using store paths, ensuring builds work from any directory.
#
# Usage in other modules:
#   { assetsPackage, ... }:
#   {
#     icon = "${assetsPackage}/icons/my-icon.svg";
#   }
{ pkgs }:

pkgs.runCommand "nixos-config-assets" {} ''
  mkdir -p $out/icons
  cp -r ${../assets/icons}/* $out/icons/
''
