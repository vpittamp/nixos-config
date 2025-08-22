# Container-specific overrides for the main configuration
# This module adapts the WSL configuration for container use
{ config, lib, pkgs, ... }:

{
  # Explicitly disable WSL features in containers
  disabledModules = [ ];
  
  # Container-specific settings
  boot.isContainer = true;
  
  # Disable systemd services that don't work in containers
  systemd.services = {
    systemd-udevd.enable = false;
    systemd-udev-settle.enable = false;
    systemd-modules-load.enable = false;
    systemd-tmpfiles-setup-dev.enable = false;
    # Disable WSL-specific services if they exist
    docker-desktop-proxy.enable = lib.mkForce false;
  };
  
  # Disable WSL-specific activation scripts
  system.activationScripts = {
    dockerDesktopIntegration = lib.mkForce "";
    wslClipboard = lib.mkForce "";
  };
  
  # Override networking for containers
  networking.hostName = lib.mkForce "nixos-container";
  
  # Disable user systemd services that are WSL-specific
  systemd.user = lib.mkForce {};
  
  # Override environment packages to remove WSL-specific ones
  environment.systemPackages = lib.mkForce (with pkgs; [
    neovim
    vim
    git
    wget
    curl
    nodejs_20
    claude-code
    docker-compose
    # No wslu or VSCode wrapper in containers
  ]);
}