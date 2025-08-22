{ config, pkgs, lib, ... }:

{
  # SSH configuration with 1Password integration
  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host *
        IdentityAgent ~/.1password/agent.sock
    '';
  };
}