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
    ../modules/services/onepassword.nix
  ];

  # System identification
  networking.hostName = "nixos-m1";
  
  # Swap configuration - 8GB swap file for memory pressure relief
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8192; # 8GB swap
    }
  ];
  
  # Memory management tweaks for better performance
  boot.kernel.sysctl = {
    "vm.swappiness" = 10; # Reduce swap usage unless necessary
    "vm.vfs_cache_pressure" = 50; # Balance between caching and reclaiming memory
    "vm.dirty_background_ratio" = 5; # Start writing dirty pages earlier
    "vm.dirty_ratio" = 10; # Force synchronous I/O earlier
  };
  
  # Boot configuration for Apple Silicon
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;  # Keep only 5 generations to prevent EFI space issues
  boot.loader.efi.canTouchEfiVariables = false;  # Different on Apple Silicon
  
  # Apple Silicon specific settings
  boot.initrd.availableKernelModules = [
    "brcmfmac"
    "xhci_pci"      # USB 3.0
    "usbhid"        # USB HID devices
    "usb_storage"   # USB storage
    "nvme"          # NVMe SSD support
  ];
  
  # Fix keyboard layout for US keyboards on Apple Silicon
  boot.extraModprobeConfig = ''
    options hid_apple iso_layout=0
  '';
  # Use firmware from boot partition (requires --impure flag)
  hardware.asahi.peripheralFirmwareDirectory = /boot/asahi;
  
  # Use NetworkManager with wpa_supplicant for WiFi (more stable on Apple Silicon)
  networking.networkmanager = {
    enable = true;
    wifi.backend = "wpa_supplicant";  # Use wpa_supplicant for better stability
  };
  
  # Disable IWD - conflicts with NetworkManager on Apple Silicon
  networking.wireless.iwd.enable = false;
  
  # Display configuration for Retina display
  # Following NixOS HiDPI recommendations: use integer scaling with higher DPI
  services.xserver = {
    dpi = 180;  # Recommended DPI for Retina displays
    
    # Force proper DPI in X11 server
    serverFlagsSection = ''
      Option "DPI" "180 x 180"
    '';
    
    # X11-specific scaling configuration
    displayManager.sessionCommands = ''
      # GTK applications - integer scaling only (GDK_SCALE must be integer)
      export GDK_SCALE=2
      export GDK_DPI_SCALE=0.5  # Inverse of GDK_SCALE for fine-tuning
      
      # Qt applications - auto-detect HiDPI
      export QT_AUTO_SCREEN_SCALE_FACTOR=1
      unset QT_SCALE_FACTOR  # Let Qt auto-detect
      
      # Java applications
      export _JAVA_OPTIONS="-Dsun.java2d.uiScale=2"
      
      # Cursor size for HiDPI
      export XCURSOR_SIZE=48
      
      # Firefox-specific scaling
      export MOZ_ENABLE_WAYLAND=0  # Force X11 for Firefox
      export MOZ_USE_XINPUT2=1
      
      # Let KDE handle its own scaling based on DPI
      kwriteconfig5 --file kcmfonts --group General --key forceFontDPI 180 || true
    '';
  };
  
  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  
  # CPU configuration for Apple M1
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  
  # Hardware acceleration support
  hardware.graphics.enable = true;
  
  # Firmware updates
  hardware.enableRedistributableFirmware = true;
  
  
  
  # Automatic garbage collection to prevent space issues
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
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