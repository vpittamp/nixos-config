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
  # Use firmware from boot partition (requires --impure flag)
  hardware.asahi.peripheralFirmwareDirectory = /boot/asahi;
  networking.networkmanager.enable = true;
  
  # Display configuration for Retina display
  # Note: GPU acceleration is enabled by default with mesa 25.1 in nixos-apple-silicon
  services.xserver.dpi = 192;  # 2x scaling for Retina display (96 * 2)
  
  # Environment variables for better Wayland support
  environment.sessionVariables = {
    # Use Wayland for Qt applications
    QT_QPA_PLATFORM = "wayland";
    # Firefox Wayland support
    MOZ_ENABLE_WAYLAND = "1";
    # Scaling for GTK applications
    GDK_SCALE = "2";
    GDK_DPI_SCALE = "0.5";  # Compensate for GDK_SCALE
  };
  
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