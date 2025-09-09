{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./apple-silicon-support/apple-silicon-support
  ];

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # Swap configuration
  swapDevices = [ {
    device = "/swapfile";
    size = 4096;
  } ];

  # Networking
  networking.hostName = "nixos-m1";
  networking.networkmanager.enable = true;
  
  # Time zone
  time.timeZone = "America/New_York";

  # User account
  users.users.vpittamp = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "audio" ];
    shell = pkgs.bash;
  };

  # Enable SSH
  services.openssh.enable = true;

  # Enable Tailscale
  services.tailscale.enable = true;

  # KDE Plasma 6
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Audio
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  
  # Bluetooth support
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # Enable Avahi for mDNS (required for AirPlay)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      userServices = true;
    };
  };

  # Enable KDE Connect
  programs.kdeconnect.enable = true;

  # Enable screen sharing in Wayland
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-kde ];
    config.common.default = "kde";
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Essential packages
  environment.systemPackages = with pkgs; [
    # Terminal & Shell
    vim
    neovim
    git
    wget
    curl
    tmux
    htop
    btop
    
    # Development
    gcc
    gnumake
    nodejs_22
    python3
    go
    rustc
    cargo
    
    # Desktop apps
    firefox
    vscode
    alacritty
    
    # System tools
    tailscale
    docker-compose
    kubectl
    k9s
    usbutils
    
    # Bluetooth tools
    bluez
    bluez-tools
    
    # File management
    yazi
    ripgrep
    fd
    bat
    eza
    fzf
  ];

  # Enable Docker
  virtualisation.docker.enable = true;

  # Enable sudo
  security.sudo.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    liberation_ttf
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
  ];

  system.stateVersion = "24.05";
}
