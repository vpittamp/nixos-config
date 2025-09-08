# NixOS FALLBACK configuration for M1 MacBook Pro with KDE Plasma 6
# 
# USE THIS CONFIG WHEN:
# - Apple Silicon module fails to build due to Rust kernel errors
# - You need to boot the system for recovery/troubleshooting
# - As a temporary workaround while waiting for upstream fixes
#
# LIMITATIONS WITHOUT APPLE SILICON MODULE:
# - WiFi and Bluetooth may not work properly
# - GPU acceleration will be limited
# - Audio devices may not be detected
# - Power management will be basic
# - Some disk mappings may need manual configuration
#
# TO USE THIS CONFIG:
# sudo nixos-rebuild switch -I nixos-config=/etc/nixos/configuration-m1-fallback.nix
#
{ config, lib, pkgs, ... }:

{
  imports = [
    # Hardware configuration (generated during installation)
    # Make sure this file uses device paths like /dev/nvme0n1p7 
    # instead of UUIDs if apple-silicon module is disabled
    ./hardware-configuration.nix
    
    # APPLE SILICON MODULE DISABLED FOR FALLBACK
    # Uncomment below to re-enable when build issues are resolved
    # ./apple-silicon-support
  ];

  # System identification
  system.stateVersion = "25.11";
  
  # FALLBACK MODE INDICATOR
  environment.etc."nixos-fallback-mode".text = ''
    This system is running in FALLBACK MODE without Apple Silicon support.
    Some hardware features may not work correctly.
    To restore full functionality, fix the kernel build issue and re-enable
    the apple-silicon-support module in configuration-m1.nix
  '';

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "vpittamp" ];
      auto-optimise-store = true;
      # Cachix for pre-built packages
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Boot configuration - FALLBACK SPECIFIC
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = false;
      # Extra long timeout for troubleshooting
      timeout = 15;
      # Keep many generations for recovery
      systemd-boot.configurationLimit = 30;
    };
    
    # Disable Plymouth to avoid boot issues
    plymouth.enable = false;
    
    # Use standard kernel instead of Asahi custom kernel
    # This avoids Rust build issues but loses Apple Silicon optimizations
    kernelPackages = pkgs.linuxPackages_latest;
    
    # Basic Apple keyboard support (may work without module)
    extraModprobeConfig = ''
      options hid_apple iso_layout=0
      options hid_apple fnmode=2
    '';
    kernelModules = [ "hid-apple" ];
    
    # Verbose boot for debugging
    kernelParams = [ "verbose" "nosplash" ];
    
    # Clean /tmp on boot
    tmp.cleanOnBoot = true;
  };

  # Timezone and locale
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # Networking - BASIC FALLBACK CONFIG
  networking = {
    hostName = "nixos-m1-fallback";
    # Use NetworkManager for basic connectivity
    # WiFi may not work without Apple Silicon drivers
    networkmanager.enable = true;
    
    # Fallback DNS servers
    nameservers = [ "8.8.8.8" "8.8.4.4" "1.1.1.1" ];
    
    # Firewall with recovery ports
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ]; # SSH only for recovery
    };
  };

  # Enable KDE Plasma 6 Desktop Environment
  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  
  # Enable SDDM Display Manager
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  
  # Enable XWayland for compatibility
  programs.xwayland.enable = true;

  # Basic graphics support (may be limited without Apple Silicon drivers)
  hardware.opengl = {
    enable = true;
  };

  # Sound configuration with PipeWire (may not detect all devices)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable touchpad support (basic functionality)
  services.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      naturalScrolling = true;
      scrollMethod = "twofinger";
      disableWhileTyping = true;
    };
  };

  # Essential services for recovery
  services = {
    # SSH for remote recovery
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes"; # Allow root for emergency recovery
        PasswordAuthentication = true;
      };
    };
    
    # Basic file system support
    gvfs.enable = true;
    dbus.enable = true;
  };

  # User account
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" ];
    # Set a known password for recovery access
    initialPassword = "nixos-recovery";
  };

  # Enable sudo for recovery operations
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    # Allow passwordless sudo for emergency recovery
    extraRules = [{
      users = [ "vpittamp" ];
      commands = [
        { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/blkid"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/mount"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/umount"; options = [ "NOPASSWD" ]; }
      ];
    }];
  };

  # Minimal system packages for recovery and basic functionality
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim
    nano
    git
    wget
    curl
    htop
    tree
    
    # Terminal emulators
    konsole
    foot
    
    # Essential dev tools for fixing issues
    gcc
    gnumake
    
    # Network tools for troubleshooting
    networkmanager
    dig
    netcat
    
    # File manager
    dolphin
    
    # Basic KDE utilities
    kdePackages.kate
    kdePackages.ark
    
    # System recovery tools
    gparted
    testdisk
    e2fsprogs
    dosfstools
    
    # Utilities
    ripgrep
    fd
    bat
    fzf
    jq
    
    # Nix tools
    nix-prefetch-git
    nixpkgs-fmt
    nh # Nix helper
    
    # Hardware info tools
    pciutils
    usbutils
    lshw
  ];

  # Environment variables
  environment.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    # Indicate fallback mode
    NIXOS_FALLBACK_MODE = "1";
  };

  # Minimal fonts for basic UI
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      liberation_ttf
      jetbrains-mono
    ];
  };

  # XDG portal for Wayland
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  
  # Recovery shell aliases
  environment.shellAliases = {
    # Quick rebuilds
    rebuild = "sudo nixos-rebuild switch";
    rebuild-main = "sudo nixos-rebuild switch -I nixos-config=/etc/nixos/configuration-m1.nix";
    rebuild-test = "sudo nixos-rebuild test";
    rebuild-boot = "sudo nixos-rebuild boot";
    # System info for troubleshooting
    show-disks = "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,UUID";
    show-uuids = "sudo blkid";
    show-hardware = "sudo lshw -short";
    show-kernel = "uname -a";
    # Recovery helpers
    fix-network = "sudo systemctl restart NetworkManager";
    check-boot = "systemctl status systemd-boot";
    list-generations = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";
  };
  
  # RECOVERY INSTRUCTIONS
  # =====================
  # 1. If this fallback config boots successfully:
  #    - Run: show-disks
  #    - Note the correct device paths and UUIDs
  #    - Update hardware-configuration.nix if needed
  #
  # 2. To restore full Apple Silicon support:
  #    - Wait for upstream Rust/kernel fixes
  #    - Try: rebuild-main
  #    - If it fails, check nixos-apple-silicon GitHub for updates
  #
  # 3. Emergency recovery if system won't boot:
  #    - Boot from NixOS installer USB
  #    - Mount partitions and chroot
  #    - Use this fallback config to get a working system
  #
  # 4. Network recovery (if WiFi doesn't work):
  #    - Use Ethernet adapter if available
  #    - Or boot into macOS and download updates
  #    - Transfer via USB to NixOS partition
}