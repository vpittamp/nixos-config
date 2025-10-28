# Hetzner Environment Check
# Ensures Hetzner configuration is only deployed to Hetzner Cloud servers
{ config, lib, pkgs, ... }:

let
  isWSL = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;

  # Check for QEMU/KVM (used by Hetzner)
  isVirtualMachine =
    (builtins.pathExists /sys/devices/virtual/dmi/id/sys_vendor &&
     builtins.elem (builtins.readFile /sys/devices/virtual/dmi/id/sys_vendor) ["QEMU\n" "KVM\n"]) ||
    (builtins.pathExists /sys/devices/virtual/dmi/id/product_name &&
     (let product = builtins.readFile /sys/devices/virtual/dmi/id/product_name;
      in builtins.elem product [
        "Standard PC (Q35 + ICH9, 2009)\n"
        "Standard PC (i440FX + PIIX, 1996)\n"
      ]));

  # We check configuration hostname, not runtime hostname
  # (runtime hostname may not be accessible during build)
  # Support both hetzner (i3) and hetzner-sway configurations (Feature 046)
  isCorrectHost = builtins.elem config.networking.hostName ["nixos-hetzner" "nixos-hetzner-sway"];
in
{
  assertions = [
    {
      assertion = !isWSL;
      message = ''
        ═══════════════════════════════════════════════════════════════
        ERROR: Cannot deploy Hetzner configuration to WSL!

        You are trying to deploy the Hetzner configuration but this
        appears to be a WSL environment.

        Please use: sudo nixos-rebuild switch --flake .#wsl
        ═══════════════════════════════════════════════════════════════
      '';
    }
    {
      assertion = isCorrectHost;
      message = ''
        ═══════════════════════════════════════════════════════════════
        ERROR: Hostname mismatch!

        Expected hostname: nixos-hetzner or nixos-hetzner-sway
        Current config hostname: ${config.networking.hostName}

        This configuration is intended for the Hetzner server.
        ═══════════════════════════════════════════════════════════════
      '';
    }
  ];

  warnings = [
    "Building Hetzner configuration - environment checks enabled"
    (lib.optionalString (!isVirtualMachine) "Warning: Not detected as virtual machine - might not be Hetzner Cloud")
  ];
}