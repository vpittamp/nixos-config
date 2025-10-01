# Hardware configuration for Hetzner Cloud servers
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Boot configuration
  boot.initrd.availableKernelModules = [ 
    "ahci" 
    "xhci_pci" 
    "virtio_pci" 
    "virtio_scsi" 
    "sd_mod" 
    "sr_mod" 
  ];
  
  # CRITICAL: Include filesystem modules for boot partition
  # Without these, the system will fail to mount /boot and drop to emergency mode
  boot.initrd.kernelModules = [
    "vfat"           # Required for EFI /boot partition
    "nls_cp437"      # Character encoding for FAT
    "nls_iso8859-1"  # ISO character encoding for FAT
  ];
  boot.kernelModules = [ "kvm-amd" ];  # Hetzner uses AMD EPYC CPUs
  boot.extraModulePackages = [ ];

  # File systems - Hetzner server specific
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/9209b382-481e-4eaf-bf22-7dfb7373f798";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/C197-021E";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Swap configuration - 8GB swap file
  # NixOS will auto-create this file when 'size' is specified
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8192; # 8GB in MiB (megabytes)
      # priority = 10; # Optional: lower values = higher priority
    }
  ];
  
  # Networking
  networking.usePredictableInterfaceNames = false;
  
  # Hardware settings
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  
  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  
  # Graphics - using new API (hardware.graphics instead of hardware.opengl)
  hardware.graphics.enable = true;
  
  # Power management - can be overridden
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  
  # Enable QEMU guest agent
  services.qemuGuest.enable = true;
  
  # System packages for virtualization
  environment.systemPackages = with pkgs; [
    qemu-utils
  ];
}