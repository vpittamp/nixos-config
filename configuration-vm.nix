# NixOS configuration for UTM/QEMU virtual machine on Apple Silicon
{ config, lib, pkgs, ... }:

{
  imports = [
    # Hardware configuration will be generated during install
    ./hardware-configuration.nix
  ];

  # Boot configuration for VM
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Optimize for VM environment
  boot.kernelParams = [ "console=tty0" "console=ttyS0,115200" ];
  
  # Enable QEMU guest agent for better integration
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;  # For clipboard sharing
  
  # Networking - use default NAT or bridged
  networking = {
    hostName = "nixos-vm";
    networkmanager.enable = true;
    # Enable SSH for remote access from macOS
    firewall.allowedTCPPorts = [ 22 ];
  };
  
  # Enable SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;  # Change to false after setting up keys
    };
  };
  
  # Create your user
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    shell = pkgs.bash;
    # Set initial password (change after first login)
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here for passwordless login
      # "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
    ];
  };
  
  # Enable Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };
  
  # X11/Wayland for GUI (optional)
  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    desktopManager.xfce.enable = true;  # Lightweight for VM
    # Or use Gnome/KDE if you prefer
    videoDrivers = [ "qxl" "modesetting" ];  # VM-optimized drivers
  };
  
  # Audio support in VM
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  
  # System packages - minimal for VM
  environment.systemPackages = with pkgs; [
    vim
    git
    tmux
    htop
    curl
    wget
    firefox  # If using GUI
  ];
  
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  
  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  
  system.stateVersion = "25.05";
}