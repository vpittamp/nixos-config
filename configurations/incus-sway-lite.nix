# Incus Sway Lite VM Configuration
# Lightweight, headless NixOS image for Incus VM testing with full Sway/i3pm workflow.
#
# Build target: .#incus-sway-lite (nixosConfiguration)
# Image target: .#incus-sway-lite-qcow2 (package)
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Provides VM image defaults required for disk image generation:
    # root filesystem, GRUB-on-vda, cloud-init compatibility, qemu guest settings.
    (modulesPath + "/virtualisation/kubevirt.nix")

    (modulesPath + "/profiles/qemu-guest.nix")
    ./base.nix
    ../modules/desktop/sway.nix
  ];

  networking.hostName = "incus-sway-lite";
  system.stateVersion = "25.11";

  # Keep base image lean; this VM does not need cluster CA sync by default.
  services.clusterCerts.enable = lib.mkForce false;

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

  networking.useDHCP = true;

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
    initialPassword = lib.mkDefault "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0gmlXX6rWgC+4XW6FYBuN8gSOp7H/U+s8UeALbTnmG vpittamp@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7 1Password Git Signing Key"
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
      X11Forwarding = false;
    };
  };
}
