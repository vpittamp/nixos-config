# Hardware configuration for Lenovo ThinkPad
# Intel Core Ultra 7 155U (Meteor Lake) with Intel Arc integrated graphics
# 32GB RAM
#
# Note: UUIDs need to be set after actual NixOS installation
# Use 'blkid' to get the correct UUIDs from your installed system
#
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration for Intel Core Ultra (Meteor Lake)
  boot.initrd.availableKernelModules = [
    "xhci_pci"      # USB 3.0/4.0 host controller
    "thunderbolt"   # Thunderbolt/USB4 support
    "nvme"          # NVMe SSD support
    "usbhid"        # USB HID devices
    "usb_storage"   # USB storage
    "sd_mod"        # SATA/SCSI disk support
    "rtsx_pci_sdmmc" # Realtek PCI SD card reader (common in ThinkPads)
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # File systems - PLACEHOLDER UUIDs (must be updated after installation)
  # Run 'sudo blkid' after installation to get actual UUIDs
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER-ROOT-UUID";
    fsType = "ext4";
    options = [ "noatime" "nodiratime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER-BOOT-UUID";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Swap - using swap file as configured in configurations/thinkpad.nix
  swapDevices = [ ];

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU configuration for Intel Core Ultra (Meteor Lake)
  # Uses powersave by default for battery efficiency
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  # Intel CPU microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Hardware acceleration - Intel Arc graphics (Meteor Lake integrated)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # For 32-bit application compatibility (Steam, Wine, etc.)

    extraPackages = with pkgs; [
      intel-media-driver    # VAAPI driver for Intel Gen 8+ (including Arc/Meteor Lake)
      intel-compute-runtime # OpenCL support for Intel Arc
      vpl-gpu-rt            # Intel Video Processing Library (QSV)
      intel-ocl             # Additional OpenCL support
    ];

    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver
    ];
  };

  # Firmware updates - essential for Meteor Lake support
  hardware.enableRedistributableFirmware = true;

  # Console font for high-DPI display
  console.earlySetup = true;
  console.font = "Lat2-Terminus16";
}
