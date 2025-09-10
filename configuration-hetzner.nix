# Minimal NixOS configuration for Hetzner Cloud CCX33
# Phase 1: Bootstrap configuration
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config-hetzner.nix
  ];

  # Boot configuration for Hetzner
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    devices = [ "/dev/sda" ];
  };
  
  boot.initrd.availableKernelModules = [ "ata_piix" "virtio_pci" "virtio_scsi" "xhci_pci" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Networking configuration
  networking = {
    hostName = "nixos-hetzner";
    useDHCP = false;
    
    # Configure the main network interface - try both ens3 and enp1s0
    interfaces.ens3 = {
      useDHCP = true;  # For IPv4
      ipv6.addresses = [{
        address = "2a01:4ff:f0:cd16::1";
        prefixLength = 64;
      }];
    };
    
    interfaces.enp1s0 = {
      useDHCP = true;  # Alternative interface name
    };
    
    # IPv6 gateway
    defaultGateway6 = {
      address = "fe80::1";
      interface = "ens3";
    };
    
    # Firewall - minimal for now
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 41641 ];  # SSH and Tailscale
      allowedUDPPorts = [ 41641 ];  # Tailscale
      checkReversePath = "loose";  # For Tailscale
    };
  };
  
  # Enable Tailscale for reliable connectivity
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };


  # Your user account
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
    ];
  };

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Minimal system packages for bootstrap
  environment.systemPackages = with pkgs; [
    vim
    git
    tmux
    htop
    wget
    curl
    tree
    ripgrep
    fd
    ncdu
    rsync
  ];

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "vpittamp" ];
      auto-optimise-store = true;
      # Use cachix for faster builds
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  # Set your time zone
  time.timeZone = "UTC";

  # Select internationalisation properties
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # System state version
  system.stateVersion = "24.11";
}