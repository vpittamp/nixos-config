# M1 MacBook Pro Configuration
# Apple Silicon variant with desktop environment
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Base configuration
    ./base.nix
    
    # Hardware
    ../hardware/m1.nix
    
    # Apple Silicon support - CRITICAL for hardware functionality
    inputs.nixos-apple-silicon.nixosModules.default
    
    # Desktop environment
    ../modules/desktop/kde-plasma.nix
    
    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
  ];

  # System identification
  networking.hostName = "nixos-m1";
  
  # Boot configuration for Apple Silicon
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;  # Different on Apple Silicon
  
  # Apple Silicon specific settings
  boot.initrd.availableKernelModules = [
    "brcmfmac"
    "xhci_pci"      # USB 3.0
    "usbhid"        # USB HID devices
    "usb_storage"   # USB storage
    "nvme"          # NVMe SSD support
  ];
  hardware.asahi.peripheralFirmwareDirectory = ./firmware;
  networking.networkmanager.enable = true;
  
  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  
  # CPU configuration for Apple M1
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  
  # Hardware acceleration support
  hardware.graphics.enable = true;
  
  # Firmware updates
  hardware.enableRedistributableFirmware = true;
  
  
  
  # Additional Apple Silicon caches
  nix.settings = {
    substituters = lib.mkAfter [
      "https://nixos-apple-silicon.cachix.org"
    ];
    trusted-public-keys = lib.mkAfter [
      "nixos-apple-silicon.cachix.org-1:HN6Zb4XV5bjFLGKZva1CGpJLuDqLux/erYbBbYneNRQ="
    ];
  };
  
  # Set initial password for user (change after first login!)
  users.users.vpittamp.initialPassword = "nixos";
  
  # Disable services that don't work well on Apple Silicon
  services.xrdp.enable = lib.mkForce false;  # RDP doesn't work well on M1
  
  # Additional packages for Apple Silicon
  environment.systemPackages = with pkgs; [
    # Tools that work well on ARM
    neovim
    alacritty
  ];
  
  # System state version
  system.stateVersion = "25.11";
}