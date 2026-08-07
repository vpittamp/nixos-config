# Hardware configuration for Microsoft Surface Pro 3 (2014)
# Intel Core i5-4300U (Haswell) with HD Graphics 4400
# 4GB RAM (3.7 GiB usable), 128GB Samsung MZMTE128 SATA SSD
#
# Deliberately does NOT use the linux-surface kernel. The Pro 3 predates IPTS:
# its digitizer is an N-trig unit (NTRG0001 1B96:1B05) that mainline drives as
# a plain HID device, confirmed enumerating on the stock 6.12 installer kernel.
# nixos-hardware's microsoft-surface-common would build a patched kernel with
# no binary cache, which on a 2-core Haswell with 4GB RAM is hours of build
# time for no functional gain. See configurations/surface-pro3.nix.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration. The SSD is SATA (ahci), not NVMe — this is the main
  # divergence from hardware/surface.nix, which is an NVMe machine.
  boot.initrd.availableKernelModules = [
    "xhci_pci"      # USB 3.0 host controller
    "ahci"          # SATA AHCI (Samsung MZMTE128)
    "usb_storage"   # USB storage
    "sd_mod"        # SATA/SCSI disk support
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # File systems (UUIDs from the 2026-08-07 install: 1G ESP / 8G swap / rest ext4)
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/2236ab2e-f8b4-4f17-b01f-273d22831379";
    fsType = "ext4";
    options = [ "noatime" "nodiratime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/FB51-C8ED";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # 8 GiB swap — more than double the 3.7 GiB of RAM. This machine will swap
  # under the Sway + Quickshell session, so the headroom is deliberate.
  swapDevices = [
    { device = "/dev/disk/by-uuid/7db4a9a9-ea90-421e-8850-6d841bbddd50"; }
  ];

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU configuration for Haswell-ULT
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  # Intel CPU microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Hardware acceleration — HD Graphics 4400 (Haswell).
  # Haswell predates the iHD driver, which requires Broadwell or newer, so this
  # uses the legacy i965 driver. hardware/surface.nix uses intel-media-driver
  # (iHD) because Kaby Lake R supports it; copying that here would silently
  # give no VA-API at all.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-vaapi-driver    # i965 VAAPI driver (Haswell-era iGPUs)
      libva-vdpau-driver    # VDPAU-over-VAAPI fallback
    ];
  };

  # Firmware — the Marvell 88W8897 (mwifiex) Wi-Fi/BT needs redistributable
  # firmware blobs to associate at all.
  hardware.enableRedistributableFirmware = true;

  # Console font for the 2160x1440 HiDPI panel
  console.earlySetup = true;
  console.font = "Lat2-Terminus16";
}
