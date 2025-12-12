# Hardware configuration for AMD Ryzen Desktop
# AMD Ryzen 5 7600X3D (Zen 4 with 3D V-Cache) - 6 cores, 4.1GHz base, 96MB L3 cache
# 32GB RAM
#
# Note: UUIDs need to be set after actual NixOS installation
# Use 'blkid' to get the correct UUIDs from your installed system
#
# GPU Configuration:
# - If using AMD GPU: This config includes AMD GPU support
# - If using NVIDIA: Comment out AMD GPU section and enable NVIDIA in configuration file
#
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration for AMD Ryzen (Zen 4)
  boot.initrd.availableKernelModules = [
    "xhci_pci"      # USB 3.0 host controller
    "ahci"          # SATA AHCI controller
    "nvme"          # NVMe SSD support
    "usbhid"        # USB HID devices
    "usb_storage"   # USB storage
    "sd_mod"        # SATA/SCSI disk support
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];  # Early load for AMD GPU
  boot.kernelModules = [ "kvm-amd" ];
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

  # Swap - using swap file as configured in configurations/ryzen.nix
  swapDevices = [ ];

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU configuration for AMD Ryzen 7600X3D
  # Use performance governor for desktop (always plugged in)
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";

  # AMD CPU microcode updates
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Hardware acceleration - AMD GPU (RDNA/RDNA2/RDNA3)
  # If using NVIDIA, comment out this section and configure NVIDIA in the main config
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # For 32-bit application compatibility (Steam, Wine, etc.)

    extraPackages = with pkgs; [
      amdvlk                # AMD Vulkan driver
      rocmPackages.clr.icd  # OpenCL support for AMD (ROCm)
    ];

    extraPackages32 = with pkgs.pkgsi686Linux; [
      amdvlk
    ];
  };

  # AMD GPU specific - use RADV (Mesa Vulkan) by default, can override to AMDVLK
  environment.variables = {
    # Use RADV by default (better performance in most cases)
    # Set to "amdvlk" to use AMDVLK instead
    AMD_VULKAN_ICD = "RADV";
  };

  # Firmware updates - essential for modern AMD hardware
  hardware.enableRedistributableFirmware = true;

  # Console font
  console.earlySetup = true;
  console.font = "Lat2-Terminus16";
}
