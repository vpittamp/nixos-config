# Minimal Hetzner Sway QCOW2 image configuration (Feature 007-number-7-short)
# Minimal configuration to fit in limited build VM memory
# NOW WITH WAYVNC SUPPORT
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
    device = lib.mkForce "/dev/vda";  # For BIOS boot on QCOW2
    efiSupport = lib.mkDefault false;  # Disable EFI for simplicity
  };

  # Kernel modules
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelParams = [ "net.ifnames=0" ];

  # Networking
  networking.useDHCP = true;
  networking.firewall.checkReversePath = "loose";
  networking.firewall.allowedTCPPorts = [ 5900 ];  # WayVNC port

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

  # Minimal packages (including WayVNC)
  environment.systemPackages = with pkgs; [
    sway
    wayvnc
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

  # WayVNC PAM authentication
  security.pam.services.wayvnc = {
    text = ''
      auth    required pam_unix.so
      account required pam_unix.so
    '';
  };

  # Greetd auto-login for vpittamp user with Sway
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd sway";
        user = "vpittamp";
      };
      initial_session = {
        command = "sway";
        user = "vpittamp";
      };
    };
  };

  # WayVNC systemd user service (auto-start with Sway)
  systemd.user.services.wayvnc = {
    description = "WayVNC server for Wayland";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc 0.0.0.0 5900";
      Restart = "on-failure";
      RestartSec = "5s";
    };

    environment = {
      XDG_RUNTIME_DIR = "/run/user/1000";
    };
  };

  # User groups
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" ];

  system.stateVersion = "24.11";
}
