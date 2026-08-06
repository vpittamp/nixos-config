# Hardware configuration for Microsoft Surface Laptop 2 (Model 1769)
# Intel Core i5-8250U (Kaby Lake R) with UHD 620 integrated graphics
# 8GB RAM, 256GB SK hynix BC501 NVMe (soldered, not replaceable)
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration for Intel Kaby Lake R
  boot.initrd.availableKernelModules = [
    "xhci_pci"      # USB 3.0 host controller
    "nvme"          # NVMe SSD support
    "usbhid"        # USB HID (Surface keyboard connects internally via USB)
    "usb_storage"   # USB storage
    "sd_mod"        # SATA/SCSI disk support
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # NOTE: the soldered BC501 NVMe is flaky on this unit — it once failed to
  # enumerate at boot ("not ready after FLR", CSTS stuck) and later threw write
  # timeouts under a heavy discard burst (it recovered both times). A 30-second
  # power-button hold (EC reset) brings it back. If boot-time enumeration
  # failures recur, try adding to boot.kernelParams:
  #   "pcie_aspm=off" "nvme_core.default_ps_max_latency_us=0"

  # File systems (UUIDs from the 2026-08-06 install)
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/88e2eb9e-2c2b-4518-806c-ead996d2edea";
    fsType = "ext4";
    options = [ "noatime" "nodiratime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2770-E790";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Swap partition (8 GiB; matches RAM size, enough for light hibernation use)
  swapDevices = [
    { device = "/dev/disk/by-uuid/da6c5499-df10-4892-bc48-4e7fef8fce26"; }
  ];

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU configuration for Intel Kaby Lake R
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  # Intel CPU microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Hardware acceleration - Intel UHD 620 (Kaby Lake R integrated)
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver    # VAAPI iHD driver (Broadwell+, covers UHD 620)
      libva-vdpau-driver    # VDPAU-over-VAAPI fallback
    ];
  };

  # Firmware - Surface devices need redistributable firmware for Wi-Fi/BT
  hardware.enableRedistributableFirmware = true;

  # Console font for the 2256x1504 HiDPI panel
  console.earlySetup = true;
  console.font = "Lat2-Terminus16";
}
