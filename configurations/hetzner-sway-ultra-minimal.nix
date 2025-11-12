# Ultra-minimal Hetzner Sway image - No imports to avoid conflicts with nixos-generators
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # System identification
  networking.hostName = "nixos-hetzner-sway";

  # Networking
  networking.useDHCP = true;

  # Disk size
  virtualisation.diskSize = 50 * 1024;

  # Minimal packages
  environment.systemPackages = with pkgs; [
    vim
    htop
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Create vpittamp user
  users.users.vpittamp = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos123";
  };

  # Allow sudo
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11";
}
