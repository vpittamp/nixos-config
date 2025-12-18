{ config, pkgs, lib, inputs, ... }:

let
  # Use nixai from the dedicated flake
  nixaiPackage = inputs.nix-ai-help.packages.${pkgs.system}.default or null;
in
lib.mkIf (nixaiPackage != null) {
  # Install nixai - AI-powered NixOS assistant
  home.packages = [
    nixaiPackage
  ];
}
