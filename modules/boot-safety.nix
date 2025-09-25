# Boot Safety Module - Ensures critical modules are always available
# This module prevents boot failures due to missing filesystem drivers
{ config, lib, pkgs, ... }:

{
  # CRITICAL: Always include filesystem modules needed for boot
  # This prevents emergency mode due to missing filesystem drivers
  boot.initrd.kernelModules = [
    # FAT filesystem support (required for EFI boot partition)
    "vfat"
    "fat"
    "nls_cp437"      # Character set for FAT
    "nls_iso8859-1"  # Character set for FAT

    # Additional filesystem support
    "ext4"           # Root filesystem
  ];

  # Ensure these filesystems are always supported
  boot.supportedFilesystems = [
    "vfat"
    "ext4"
    "btrfs"  # In case of future migration
    "xfs"    # Alternative filesystem
  ];

  # Keep more generations to allow rollback
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;

  # Enable emergency boot options
  boot.kernelParams = lib.mkDefault [
    "boot.shell_on_fail"  # Drop to shell on boot failure
  ];

  # Ensure critical tools are in initrd
  boot.initrd.extraUtilsCommands = ''
    # Copy filesystem check tools
    copy_bin_and_libs ${pkgs.e2fsprogs}/bin/fsck.ext4
    copy_bin_and_libs ${pkgs.dosfstools}/bin/fsck.vfat
  '';

  # Add boot debug information
  boot.initrd.verbose = lib.mkDefault false;  # Set to true for debugging

  # Failsafe: Ensure modprobe is available
  boot.initrd.systemd.enable = lib.mkDefault true;
}