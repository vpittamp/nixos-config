# Container-specific overrides for the main configuration
# This module adapts the WSL configuration for container use
{ config, lib, pkgs, ... }:

{
  # Explicitly disable WSL features in containers
  disabledModules = [ ];
  
  # Container-specific settings
  boot.isContainer = true;
  
  # Disable WSL module in containers
  wsl.enable = lib.mkForce false;
  
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
  
  # Override environment packages for containers
  # Use NIXOS_PACKAGES environment variable to control what gets installed
  # Default: essential packages only (from overlays/packages.nix)
  environment.systemPackages = lib.mkForce (with pkgs; let
    overlayPackages = import ./overlays/packages.nix { inherit pkgs lib; };
  in
    # For containers: use essential packages by default
    # Can be overridden with NIXOS_PACKAGES env var at build time
    overlayPackages.essential ++ overlayPackages.extras
  );
}