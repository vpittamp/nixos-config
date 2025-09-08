# Hardware configuration template for M1 MacBook Pro
# 
# IMPORTANT: This is a TEMPLATE file for fresh NixOS installation
# The actual hardware-configuration.nix will be generated during installation
#
# INSTALLATION INSTRUCTIONS:
# =========================
# 1. During NixOS installation, the installer will generate hardware-configuration.nix
# 2. After first boot, verify disk UUIDs with: sudo blkid
# 3. Update this file if UUIDs don't match
# 4. Common partition layout on M1 MacBook Pro:
#    - /dev/nvme0n1p5 or p6: EFI boot partition (FAT32, ~500MB)
#    - /dev/nvme0n1p7 or p8: Root partition (ext4, 80GB)
#    - /dev/nvme0n1p8 or p9: Swap partition (optional)
#
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration
  boot.initrd.availableKernelModules = [ 
    "xhci_pci"      # USB 3.0
    "usbhid"        # USB HID devices
    "usb_storage"   # USB storage
    "nvme"          # NVMe SSD support
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # File systems - TEMPLATE VALUES
  # These will be replaced during installation
  # 
  # Option 1: Using UUIDs (preferred after first boot)
  fileSystems."/" = {
    # Replace with actual UUID from: blkid /dev/nvme0n1p7
    device = "/dev/disk/by-uuid/REPLACE-WITH-ROOT-UUID";
    fsType = "ext4";
    options = [ "noatime" "nodiratime" ];
  };

  fileSystems."/boot" = {
    # Replace with actual UUID from: blkid /dev/nvme0n1p5
    device = "/dev/disk/by-uuid/REPLACE-WITH-BOOT-UUID";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Option 2: Using device paths (fallback if UUIDs fail)
  # Uncomment these if UUID mounting fails:
  #
  # fileSystems."/" = {
  #   device = "/dev/nvme0n1p7";  # Adjust partition number as needed
  #   fsType = "ext4";
  #   options = [ "noatime" "nodiratime" ];
  # };
  #
  # fileSystems."/boot" = {
  #   device = "/dev/nvme0n1p5";  # Adjust partition number as needed
  #   fsType = "vfat";
  #   options = [ "fmask=0022" "dmask=0022" ];
  # };

  # Option 3: Using labels (if you labeled partitions during install)
  # Uncomment if you used labels:
  #
  # fileSystems."/" = {
  #   device = "/dev/disk/by-label/nixos";
  #   fsType = "ext4";
  #   options = [ "noatime" "nodiratime" ];
  # };
  #
  # fileSystems."/boot" = {
  #   device = "/dev/disk/by-label/boot";
  #   fsType = "vfat";
  #   options = [ "fmask=0022" "dmask=0022" ];
  # };

  # Swap configuration (optional)
  # Uncomment and adjust if you created a swap partition:
  # swapDevices = [
  #   { device = "/dev/disk/by-uuid/REPLACE-WITH-SWAP-UUID"; }
  # ];
  
  # Or use a swap file instead:
  # swapDevices = [
  #   { device = "/swapfile"; size = 8192; }  # 8GB swap file
  # ];
  
  # No swap by default
  swapDevices = [ ];

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  
  # CPU configuration for Apple M1
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  
  # Hardware acceleration support
  hardware.opengl = {
    enable = true;
    driSupport = true;
  };

  # Firmware updates
  hardware.enableRedistributableFirmware = true;
  
  # High-DPI console for Retina display
  console.earlySetup = true;
  console.font = "ter-v32n";  # Larger font for HiDPI
  
  # TROUBLESHOOTING DISK ISSUES
  # ============================
  # If system fails to boot with "waiting for device" error:
  #
  # 1. Boot from installer USB
  # 2. Mount your root partition:
  #    mkdir /mnt
  #    mount /dev/nvme0n1p7 /mnt  # Adjust partition number
  #    mount /dev/nvme0n1p5 /mnt/boot  # Adjust partition number
  #
  # 3. Find correct UUIDs:
  #    blkid
  #
  # 4. Edit this file:
  #    nano /mnt/etc/nixos/hardware-configuration.nix
  #
  # 5. Update UUIDs or switch to device paths
  #
  # 6. Rebuild from chroot:
  #    nixos-enter
  #    nixos-rebuild boot
  #
  # 7. Reboot and select new generation
  
  # APPLE SILICON SPECIFIC NOTES
  # =============================
  # The Apple Silicon module may override some disk mappings.
  # If you see different device names after enabling the module,
  # this is expected behavior. The module provides:
  # - Proper NVMe controller initialization
  # - Correct device tree mappings
  # - Power management for M1 storage controller
}