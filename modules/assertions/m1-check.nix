# M1/Apple Silicon Environment Check
# Ensures M1 configuration is only deployed to Apple Silicon systems
{ config, lib, pkgs, ... }:

let
  isWSL = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;

  # Check for Apple Silicon markers
  isAppleSilicon =
    config.nixpkgs.hostPlatform.system == "aarch64-linux" &&
    ((builtins.pathExists /sys/firmware/devicetree/base/compatible &&
      builtins.match ".*apple.*" (builtins.readFile /sys/firmware/devicetree/base/compatible) != null) ||
     (builtins.pathExists /sys/firmware/devicetree/base/model &&
      builtins.match ".*Apple.*" (builtins.readFile /sys/firmware/devicetree/base/model) != null));

  isCorrectHost = config.networking.hostName == "nixos-m1";
in
{
  assertions = [
    {
      assertion = !isWSL;
      message = ''
        ═══════════════════════════════════════════════════════════════
        ERROR: Cannot deploy M1 configuration to WSL!

        You are trying to deploy the M1 configuration but this
        appears to be a WSL environment.

        Please use: sudo nixos-rebuild switch --flake .#wsl
        ═══════════════════════════════════════════════════════════════
      '';
    }
    {
      assertion = config.nixpkgs.hostPlatform.system == "aarch64-linux";
      message = ''
        ═══════════════════════════════════════════════════════════════
        ERROR: Wrong architecture!

        M1 configuration requires aarch64-linux but system is:
        ${config.nixpkgs.hostPlatform.system}

        This configuration is only for Apple Silicon Macs.
        ═══════════════════════════════════════════════════════════════
      '';
    }
    {
      assertion = isCorrectHost;
      message = ''
        ═══════════════════════════════════════════════════════════════
        ERROR: Hostname mismatch!

        Expected hostname: nixos-m1
        Current hostname: ${config.networking.hostName}

        This might not be the correct system for this configuration.
        ═══════════════════════════════════════════════════════════════
      '';
    }
  ];

  warnings = [
    "Building M1 configuration - environment checks enabled"
    (lib.optionalString (!isAppleSilicon) "Warning: Apple Silicon markers not detected")
  ];
}