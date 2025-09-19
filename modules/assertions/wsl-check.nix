# WSL Environment Check
# Ensures WSL configuration is only deployed to WSL environments
{ config, lib, pkgs, ... }:

let
  isWSL = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;
  isCorrectHost = config.networking.hostName == "nixos-wsl";
in
{
  assertions = [
    {
      assertion = isWSL && isCorrectHost;
      message = ''
        ═══════════════════════════════════════════════════════════════
        ERROR: Wrong configuration for this system!

        You are trying to deploy the WSL configuration but:
        - WSL detected: ${if isWSL then "Yes" else "No"}
        - Hostname match: ${if isCorrectHost then "Yes" else "No (current: ${config.networking.hostName})"}

        This configuration should only be used in WSL environments.

        If you're on Hetzner, use: sudo nixos-rebuild switch --flake .#hetzner
        If you're on M1 Mac, use: sudo nixos-rebuild switch --flake .#m1
        ═══════════════════════════════════════════════════════════════
      '';
    }
  ];

  warnings = [ "Building WSL configuration - environment checks enabled" ];
}