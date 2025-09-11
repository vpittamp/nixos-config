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
  
  boot.initrd.kernelModules = [ ];
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

  swapDevices = [ ];
  
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