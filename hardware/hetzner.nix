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
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # File systems - these should be defined by generated hardware-configuration.nix
  # or overridden in the specific system configuration
  
  # Networking
  networking.usePredictableInterfaceNames = false;
  
  # Hardware settings
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  
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