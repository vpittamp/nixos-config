{ pkgs, lib, ... }:

let
  # Use an older nixpkgs version that has Python 3.11 and working Azure CLI
  pkgs-stable = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz";
    sha256 = "0zydsqiaz8qi4zd63zsb2gij2p614cgkcaisnk11wjy3nmiq0x1s";
  }) {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
  pkgs-stable.azure-cli