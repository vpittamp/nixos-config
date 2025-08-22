{ config, pkgs, lib, ... }:

{
  # Direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}