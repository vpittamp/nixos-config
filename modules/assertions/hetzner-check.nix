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
     let product = builtins.readFile /sys/devices/virtual/dmi/id/product_name;
     in builtins.elem product [
       "Standard PC (Q35 + ICH9, 2009)\n"
       "Standard PC (i440FX + PIIX, 1996)\n"
     ]);

  # Check hostname
  currentHostname =
    if builtins.pathExists /proc/sys/kernel/hostname
    then lib.removeSuffix "\n" (builtins.readFile /proc/sys/kernel/hostname)
    else "unknown";

  isCorrectHost = currentHostname == "nixos-hetzner" || currentHostname == config.networking.hostName;
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

        Expected hostname: nixos-hetzner
        Current hostname: ${currentHostname}

        This might not be the correct system for this configuration.
        ═══════════════════════════════════════════════════════════════
      '';
    }
  ];

  warnings = [
    "Building Hetzner configuration - environment checks enabled"
    (lib.optionalString (!isVirtualMachine) "Warning: Not detected as virtual machine - might not be Hetzner Cloud")
  ];
}