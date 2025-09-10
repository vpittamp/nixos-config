# NixOS configuration for M1 MacBook Pro with KDE Plasma 6
# 
# IMPORTANT: Apple Silicon Module Notes
# =====================================
# The apple-silicon-support module is REQUIRED for:
# - Correct disk device mappings (/dev/nvme0n1p* -> /dev/disk/by-*)
# - WiFi and Bluetooth hardware support
# - Display and GPU acceleration
# - Audio hardware support
#
# KNOWN ISSUE: Kernel build may fail with "rust/core.o Error 1"
# This is due to Rust version incompatibilities in the Asahi kernel.
#
# WORKAROUNDS:
# 1. Try building with cachix cache (usually has pre-built kernels)
# 2. If build fails, use configuration-m1-fallback.nix temporarily
# 3. After successful boot, re-enable the module
#
{ config, lib, pkgs, ... }:

{
  imports = [
    # Hardware configuration (generated during installation)
    ./hardware-m1.nix
    
    # Apple Silicon support - CRITICAL for hardware functionality
    # Comment out ONLY if kernel build fails, then use fallback config
    ./apple-silicon-support/apple-silicon-support
  ];

  # System identification
  system.stateVersion = "25.11";
  

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "vpittamp" ];
      auto-optimise-store = true;
      # Cachix for pre-built Apple Silicon kernels
      substituters = [
        "https://cache.nixos.org"
        "https://nixos-apple-silicon.cachix.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nixos-apple-silicon.cachix.org-1:HN6Zb4XV5bjFLGKZva1CGpJLuDqLux/erYbBbYneNRQ="
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

  # Boot configuration
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = false;
      # Longer timeout for troubleshooting
      timeout = 10;
      # Keep more generations for recovery
      systemd-boot.configurationLimit = 20;
    };
    
    # Disable Plymouth to avoid boot issues
    plymouth.enable = false;
    
    # Apple keyboard fixes
    extraModprobeConfig = ''
      options hid_apple iso_layout=0
      options hid_apple fnmode=2
    '';
    kernelModules = [ "hid-apple" ];
    
    # Clean /tmp on boot
    tmp.cleanOnBoot = true;
  };

  # Timezone and locale
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # Networking
  networking = {
    hostName = "nixos-m1";
    networkmanager.enable = true;
    
    # Use iwd for better WiFi support
    wireless.iwd = {
      enable = true;
      settings.General.EnableNetworkConfiguration = true;
    };
    
    # DNS
    nameservers = [ "8.8.8.8" "8.8.4.4" ];
    
    # Firewall
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };


  # Enable KDE Plasma 6 Desktop Environment
  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  
  # Enable SDDM Display Manager (KDE's native)
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  
  # Enable KDE Connect for phone integration
  programs.kdeconnect.enable = true;
  
  # Enable XWayland for compatibility
  programs.xwayland.enable = true;

  # Graphics configuration
  hardware.graphics = {
    enable = true;
  };

  # Sound configuration with PipeWire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable touchpad support
  services.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      naturalScrolling = true;
      scrollMethod = "twofinger";
      disableWhileTyping = true;
    };
  };

  # Services
  services = {
    openssh.enable = true;
    tailscale.enable = true;
    gvfs.enable = true;
    dbus.enable = true;
  };

  # User account
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" ];
    initialPassword = "changeme";
  };

  # Enable sudo
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };

  # System packages
  environment.systemPackages = with pkgs; [
    # Development tools with proper configuration
    vscode
    # Core utilities
    vim neovim git wget curl htop tree tmux
    
    # Terminal emulators
    alacritty foot kitty kdePackages.konsole
    
    # Development tools
    gcc gnumake python3 nodejs go
    
    # GUI applications
    firefox-wayland chromium vscodium
    
    # Media
    mpv pavucontrol
    
    # Utilities
    ripgrep fd bat eza fzf jq
    
    # Wayland tools
    wl-clipboard
    
    # File managers
    kdePackages.dolphin
    
    # KDE utilities (using kdePackages prefix for Qt6 compatibility)
    kdePackages.kate
    kdePackages.ark
    kdePackages.spectacle
    kdePackages.okular
    kdePackages.gwenview
    kdePackages.kcalc
    
    # System recovery tools
    gparted
    testdisk
    
    # Nix helper for easier rebuilds
    nh
  ];

  # Environment variables
  environment.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    # Remove desktop specification - KDE will set this
  };

  # Fonts
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      liberation_ttf
      fira-code
      jetbrains-mono
      font-awesome
      # Additional fonts for better rendering
      inter
      roboto
      ubuntu_font_family
    ];
    fontconfig = {
      defaultFonts = {
        serif = [ "Noto Serif" ];
        sansSerif = [ "Inter" "Noto Sans" ];
        monospace = [ "JetBrains Mono" "Fira Code" ];
      };
    };
  };

  # XDG portal for Wayland
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  
  # Fix for KDE not sourcing home-manager session variables
  # This ensures terminals in KDE work automatically with home-manager
  environment.loginShellInit = ''
    # Source user profile which contains home-manager session vars
    if [ -e "$HOME/.profile" ]; then
      . "$HOME/.profile"
    fi
  '';

  # Ensure bash is configured properly system-wide for KDE terminals
  programs.bash = {
    enable = true;
    enableCompletion = true;
    # This will source for all interactive bash shells (what Konsole starts)
    interactiveShellInit = ''
      # Source home-manager session vars if available
      if [ -e "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
        . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
      fi
    '';
  };

  # Additional shell aliases for recovery
  environment.shellAliases = {
    # Quick rebuilds
    rebuild = "sudo nixos-rebuild switch";
    rebuild-test = "sudo nixos-rebuild test";
    rebuild-boot = "sudo nixos-rebuild boot";
    # Using fallback config if needed
    rebuild-fallback = "sudo nixos-rebuild switch -I nixos-config=/etc/nixos/configuration-m1-fallback.nix";
    # System info
    nixos-version = "nixos-version --json | jq";
    # Disk utilities
    show-disks = "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,UUID";
    show-uuids = "blkid";
  };
  
  # Documentation for fresh install
  # ================================
  # After installing NixOS:
  # 1. Boot into the system
  # 2. Run: sudo blkid
  # 3. Update hardware-configuration.nix with correct UUIDs
  # 4. Run: sudo nixos-rebuild switch
  # 
  # If kernel build fails:
  # 1. Use: sudo nixos-rebuild switch -I nixos-config=/etc/nixos/configuration-m1-fallback.nix
  # 2. After successful boot, try re-enabling apple-silicon-support
}
