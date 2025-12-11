# Hardware configuration for Acer Swift Go 16
# Intel Core Ultra CPU with Intel Arc integrated graphics
#
# IMPORTANT: This is a TEMPLATE file for fresh NixOS installation
# After first boot, verify disk UUIDs with: sudo blkid
# and update if needed
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
    "nvme"          # NVMe SSD support
    "usbhid"        # USB HID devices
    "usb_storage"   # USB storage
    "sd_mod"        # SATA/SCSI disk support
    "rtsx_pci_sdmmc" # Realtek SD card reader (common on Acer laptops)
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # File systems - TEMPLATE VALUES
  # These will be replaced during installation or after first boot
  #
  # Using labels (set during partitioning with mkfs commands)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    options = [ "noatime" "nodiratime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Swap configuration
  # Option 1: Swap file (recommended for SSDs)
  # swapDevices = [
  #   { device = "/var/lib/swapfile"; size = 16384; }  # 16GB swap
  # ];

  # Option 2: Swap partition (if created during install)
  # swapDevices = [
  #   { device = "/dev/disk/by-label/swap"; }
  # ];

  # No swap by default - configure after install based on RAM
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

  # TROUBLESHOOTING DISK ISSUES
  # ============================
  # If system fails to boot with "waiting for device" error:
  #
  # 1. Boot from installer USB
  # 2. Mount your root partition:
  #    mkdir /mnt
  #    mount /dev/nvme0n1p2 /mnt  # Adjust partition number
  #    mount /dev/nvme0n1p1 /mnt/boot  # Adjust partition number
  #
  # 3. Find correct UUIDs:
  #    blkid
  #
  # 4. Edit this file and switch to UUID-based mounting if labels fail
  #
  # 5. Rebuild from chroot:
  #    nixos-enter
  #    nixos-rebuild boot
  #
  # 6. Reboot and select new generation
}
