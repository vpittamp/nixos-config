# Hardware configuration for Acer Swift Go 16
# Intel Core Ultra CPU with Intel Arc integrated graphics
#
# UUIDs from actual installation - DO NOT CHANGE without verifying with blkid
#
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration
  boot.initrd.availableKernelModules = [
    "xhci_pci"      # USB 3.0
    "thunderbolt"   # Thunderbolt/USB4 support
    "vmd"           # Intel Volume Management Device
    "nvme"          # NVMe SSD support
    "usbhid"        # USB HID devices
    "usb_storage"   # USB storage
    "sd_mod"        # SATA/SCSI disk support
    "rtsx_usb_sdmmc" # Realtek USB SD card reader
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # File systems - Actual UUIDs from this Acer installation
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/61f896c5-e762-4f7a-a460-90e1d98ea931";
    fsType = "ext4";
    options = [ "noatime" "nodiratime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/DB0B-6CD4";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Swap - using swap file as configured in configurations/acer.nix
  swapDevices = [ ];

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU configuration for Intel Core Ultra
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";  # Battery-friendly default

  # Intel CPU microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Hardware acceleration - Intel Arc graphics
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # For 32-bit application compatibility (Steam, Wine, etc.)

    extraPackages = with pkgs; [
      intel-media-driver    # VAAPI driver for Intel Gen 8+ (including Arc)
      intel-compute-runtime # OpenCL support for Intel Arc
      vpl-gpu-rt            # Intel Video Processing Library (QSV)
    ];

    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver
    ];
  };

  # Firmware updates
  hardware.enableRedistributableFirmware = true;

  # Console font for high-DPI display
  console.earlySetup = true;
  console.font = "Lat2-Terminus16";
}
