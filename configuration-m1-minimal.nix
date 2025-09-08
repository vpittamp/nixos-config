# Minimal NixOS configuration for M1 MacBook Pro
# Use this for initial installation to avoid kernel panics
# After successful boot, you can add more features
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.plymouth.enable = false;
  boot.loader.timeout = 10;

  # System
  system.stateVersion = "25.11";
  nixpkgs.config.allowUnfree = true;

  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Networking
  networking.hostName = "nixos-m1";
  networking.networkmanager.enable = true;

  # Time
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # User
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "changeme";
  };

  # Enable sudo
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };

  # Minimal packages
  environment.systemPackages = with pkgs; [
    vim
    nano
    git
    wget
    curl
    htop
    tmux
    networkmanager
    tailscale
    nh  # Nix helper for easier rebuilds
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };
  
  # Enable Tailscale
  services.tailscale.enable = true;

  # Basic shell aliases
  environment.shellAliases = {
    rebuild = "sudo nixos-rebuild switch";
    ll = "ls -la";
  };
}