# Hardware configuration for M1 MacBook Pro with Asahi Linux
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration for Apple Silicon
  boot = {
    # Use the systemd-boot EFI boot loader
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

  # Disko configuration for disk partitioning
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";  # M1 MacBook internal SSD
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "defaults" ];
              };
            };
            root = {
              priority = 2;
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [ "defaults" "noatime" ];
              };
            };
          };
        };
      };
    };
  };

  # File systems configuration (will be overridden by disko during installation)
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
    # Enable firmware for Apple Silicon
    asahi = {
      enable = true;
      withRust = true;
      useExperimentalGPUDriver = true;
      experimentalGPUInstallMode = "replace";
    };
    
    # Graphics support
    opengl = {
      enable = true;
      driSupport = true;
    };
    
    # Audio support
    pulseaudio.enable = false;
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