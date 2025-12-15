{ config, pkgs, lib, ... }:

{
  # Direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # Devenv integration (enables `use devenv` in project .envrc files)
    stdlib = ''
      eval "$(${lib.getExe pkgs.devenv} direnvrc)"
    '';
  };
}
