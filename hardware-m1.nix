# Hardware configuration for M1 MacBook Pro with NixOS Apple Silicon
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration for Apple Silicon
  boot = {
    # Use the systemd-boot EFI boot loader (managed by nixos-apple-silicon)
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = false;
      timeout = 3;
    };
    
    # Initial ramdisk modules
    initrd.availableKernelModules = [ 
      "usb_storage"
      "sdhci_pci"
    ];
    
    kernelModules = [ ];
    extraModulePackages = [ ];
    
    # Support for NVMe and other storage
    supportedFilesystems = [ "ext4" "btrfs" "xfs" "ntfs" ];
  };

  # Filesystem configuration for M1 MacBook
  # These need to match your actual partition setup
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  
  swapDevices = [ ];

  # Apple Silicon specific hardware configuration
  hardware = {
    # Asahi configuration
    asahi = {
      # Disable peripheral firmware extraction for now
      # This will be enabled when firmware is available
      extractPeripheralFirmware = false;
    };
    
    # Graphics support
    graphics = {
      enable = true;
    };
    
  };

  # Enable sound with PipeWire (better for Apple Silicon)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Networking
  networking = {
    useDHCP = lib.mkDefault true;
    # NetworkManager for easier WiFi management
    networkmanager.enable = true;
  };

  # CPU configuration
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  
  # Power management for laptops
  powerManagement = {
    enable = true;
    cpuFreqGovernor = lib.mkDefault "ondemand";
  };

  # Enable touchpad support
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      tapping = true;
      clickMethod = "clickfinger";
    };
  };
}