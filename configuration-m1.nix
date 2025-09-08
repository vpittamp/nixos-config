# NixOS configuration for M1 MacBook Pro with GUI support
{ config, lib, pkgs, ... }:

{
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix
    
    # Apple Silicon support
    ./apple-silicon-support
  ];

  # System identification
  system.stateVersion = "25.11";
  

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "vpittamp" ];
      auto-optimise-store = true;
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
      timeout = 3;
    };
    
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
  hardware.opengl = {
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
    vscode
    # Core utilities
    vim neovim git wget curl htop tree tmux
    
    # Terminal emulators
    alacritty foot kitty konsole
    
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
    dolphin
    
    # KDE utilities
    kate ark spectacle
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
    ];
  };

  # XDG portal for Wayland
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
