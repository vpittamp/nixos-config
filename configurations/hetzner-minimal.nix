# Minimal Hetzner configuration for nixos-anywhere initial deployment
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Include the disko module for disk configuration
    ../disk-config.nix
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];

  # Basic networking
  networking.hostName = "nixos-hetzner";
  networking.useDHCP = lib.mkDefault true;

  # Enable SSH for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Create users with SSH access
  users.users.root = {
    # No password - SSH key only
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
    ];
  };
  
  users.users.vpittamp = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
    ];
  };

  # Allow sudo without password for wheel group (temporarily)
  security.sudo.wheelNeedsPassword = false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
  ];

  # This is required for nixos-anywhere
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  
  system.stateVersion = "24.11";
}