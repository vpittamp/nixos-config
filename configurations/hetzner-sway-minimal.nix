# Minimal Hetzner Sway QCOW2 image configuration (Feature 007-number-7-short)
# Minimal configuration to fit in limited build VM memory
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Base configuration
    ./base.nix

    # QEMU guest optimizations
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # System identification
  networking.hostName = "nixos-hetzner-sway";

  # Boot configuration - Use lib.mkDefault to allow format override
  boot.loader.grub = {
    enable = lib.mkDefault true;
    device = lib.mkDefault "nodev";  # For EFI boot
    efiSupport = lib.mkDefault true;
    efiInstallAsRemovable = lib.mkDefault true;
  };

  # Kernel modules
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelParams = [ "net.ifnames=0" ];

  # Networking
  networking.useDHCP = true;
  networking.firewall.checkReversePath = "loose";

  # Disk size
  virtualisation.diskSize = 50 * 1024;  # 50GB

  # Filesystem definitions (required by make-disk-image.nix)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  # Enable Sway
  programs.sway.enable = true;

  # Minimal packages
  environment.systemPackages = with pkgs; [
    sway
    wl-clipboard
    htop
    neofetch
  ];

  # SSH access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # User groups
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" ];

  system.stateVersion = "24.11";
}
