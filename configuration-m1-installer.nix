# NixOS configuration for M1 MacBook Pro - Installer version
# Based on official nixos-apple-silicon instructions
# This follows the exact setup from the documentation
{ config, lib, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Include the necessary packages and configuration for Apple Silicon support.
    ./apple-silicon-support
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # System version
  system.stateVersion = "25.11";

  # Basic networking with iwd for WiFi (as recommended in docs)
  networking.hostName = "nixos-m1";
  networking.wireless.iwd = {
    enable = true;
    settings.General.EnableNetworkConfiguration = true;
  };

  # Time zone and locale
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # User account
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "changeme";
  };

  # Allow unfree packages (needed for firmware)
  nixpkgs.config.allowUnfree = true;

  # Enable sudo
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };

  # Minimal packages for initial boot
  environment.systemPackages = with pkgs; [
    vim
    nano
    wget
    curl
    git
  ];

  # Enable OpenSSH for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
  };

  # Enable Tailscale for easier remote access
  services.tailscale.enable = true;

  # Apple keyboard layout fix (for US keyboards)
  boot.extraModprobeConfig = ''
    options hid_apple iso_layout=0
  '';
}