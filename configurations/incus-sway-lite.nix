# Incus Sway Lite VM Configuration
# Lightweight, headless NixOS image for Incus VM testing with full Sway/i3pm workflow.
#
# Build target: .#incus-sway-lite (nixosConfiguration)
# Image target: .#incus-sway-lite-qcow2 (package)
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # QEMU guest defaults (drivers, agent integration, virtual hardware tuning).
    (modulesPath + "/profiles/qemu-guest.nix")
    ./base.nix
    ../modules/desktop/sway.nix
  ];

  networking.hostName = "incus-sway-lite";
  system.stateVersion = "25.11";

  # Keep base image lean; this VM does not need cluster CA sync by default.
  services.clusterCerts.enable = lib.mkForce false;

  # Explicit image defaults for Incus VM disk images.
  # We intentionally do not import virtualisation/kubevirt.nix here:
  # that module enables cloud-init metadata crawling which delays boot in Incus
  # and can interfere with deterministic DHCP behavior.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  boot.growPartition = true;
  boot.loader.grub = {
    enable = true;
    # keep BIOS boot support for compatibility with existing instances
    device = "/dev/vda";
    # also install an EFI target so fresh Incus VMs boot without forcing CSM
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.loader.timeout = 0;
  boot.loader.efi.canTouchEfiVariables = false;

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "virtio_balloon"
    "xhci_pci"
    "ahci"
    "sd_mod"
  ];
  boot.kernelParams = [
    "net.ifnames=0"
    "console=ttyS0"
  ];

  services.qemuGuest.enable = true;
  systemd.services."serial-getty@ttyS0".enable = true;
  services.cloud-init.enable = lib.mkForce false;

  # Use deterministic DHCP in Incus VMs via networkd.
  networking.useDHCP = lib.mkForce false;
  networking.useNetworkd = true;
  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks."10-incus-eth" = {
      matchConfig.Name = "e*";
      networkConfig.DHCP = "yes";
    };
  };

  # Incus VM + Sway headless stack
  services.sway.enable = true;

  # Headless Sway login session for remote desktop workflows.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "${pkgs.writeShellScript "sway-headless-session" ''
          export WLR_BACKENDS=headless
          export WLR_HEADLESS_OUTPUTS=3
          export WLR_LIBINPUT_NO_DEVICES=1
          export WLR_RENDERER=pixman
          export XDG_SESSION_TYPE=wayland
          export XDG_CURRENT_DESKTOP=sway
          export QT_QPA_PLATFORM=wayland
          export GDK_BACKEND=wayland
          export GSK_RENDERER=cairo
          export WLR_NO_HARDWARE_CURSORS=1
          exec ${pkgs.sway}/bin/sway
        ''}";
        user = "vpittamp";
      };
      default_session = {
        command = "${pkgs.writeShellScript "sway-headless-session-default" ''
          export WLR_BACKENDS=headless
          export WLR_HEADLESS_OUTPUTS=3
          export WLR_LIBINPUT_NO_DEVICES=1
          export WLR_RENDERER=pixman
          export XDG_SESSION_TYPE=wayland
          export XDG_CURRENT_DESKTOP=sway
          export QT_QPA_PLATFORM=wayland
          export GDK_BACKEND=wayland
          export GSK_RENDERER=cairo
          export WLR_NO_HARDWARE_CURSORS=1
          exec ${pkgs.sway}/bin/sway
        ''}";
        user = "vpittamp";
      };
    };
  };

  environment.sessionVariables = {
    WLR_BACKENDS = "headless";
    WLR_HEADLESS_OUTPUTS = "3";
    WLR_LIBINPUT_NO_DEVICES = "1";
    WLR_RENDERER = "pixman";
    WLR_NO_HARDWARE_CURSORS = "1";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "sway";
    QT_QPA_PLATFORM = "wayland";
    GDK_BACKEND = "wayland";
    GSK_RENDERER = "cairo";
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
    config.common.default = [ "wlr" "gtk" ];
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    openFirewall = true;
    extraUpFlags = [ "--ssh" ];
  };

  networking.firewall = {
    enable = true;
    checkReversePath = "loose";
    allowedTCPPorts = [ 22 5900 5901 5902 ];
  };

  # Keep runtime dependencies for headless desktop debugging available,
  # while keeping system package footprint small.
  environment.systemPackages = lib.mkForce (with pkgs; [
    # Keep /run/current-system/sw/bin/bash available for passwd shells.
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    iproute2
    iputils
    procps
    systemd
    util-linux
    vim
    git
    curl
    jq
    tmux
    wayvnc
    wl-clipboard
  ]);

  # Reduce closure size compared to desktop/bare-metal targets.
  documentation = {
    enable = false;
    doc.enable = false;
    info.enable = false;
    man.enable = false;
    nixos.enable = false;
  };

  # Keep only fonts used by bars/prompt/icons.
  fonts.packages = lib.mkForce (with pkgs; [
    font-awesome
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ]);

  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    # Avoid /run/current-system shell indirection issues in image boots.
    shell = lib.getExe pkgs.bashInteractive;
    initialPassword = lib.mkDefault "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0gmlXX6rWgC+4XW6FYBuN8gSOp7H/U+s8UeALbTnmG vpittamp@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7 1Password Git Signing Key"
    ];
  };

  users.users.root.shell = lib.getExe pkgs.bashInteractive;

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/var/lib/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
      {
        path = "/var/lib/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
      X11Forwarding = false;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/ssh 0700 root root -"
  ];
}
