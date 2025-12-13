# Hardware configuration for AMD Ryzen Desktop
# AMD Ryzen 5 7600X3D (Zen 4 with 3D V-Cache) - 6 cores, 4.1GHz base, 96MB L3 cache
# NVIDIA GeForce RTX 5070 (GB205, Blackwell architecture)
# 32GB RAM
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
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];  # Early load for NVIDIA GPU
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # File systems
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/9b21906c-50e4-4fe1-9973-2663eec204cb";
    fsType = "ext4";
    options = [ "noatime" "nodiratime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/98CD-6F3E";
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

  # Hardware acceleration - NVIDIA GPU (RTX 5070 Blackwell)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # For 32-bit application compatibility (Wine, etc.)
  };

  # NVIDIA kernel parameters for Wayland
  boot.kernelParams = [
    "nvidia-drm.modeset=1"                              # DRM KMS support (required for Wayland)
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"     # Preserve VRAM on sleep
  ];

  # Firmware updates - essential for modern AMD hardware
  hardware.enableRedistributableFirmware = true;

  # Console font
  console.earlySetup = true;
  console.font = "Lat2-Terminus16";
}
