# Minimal NixOS VM configuration for KubeVirt
# This configuration builds upon base.nix and adds VM-specific features
{ config, pkgs, modulesPath, lib, ... }:

{
  imports = [
    # Reuse existing base configuration (SSH keys, users, core packages)
    ./base.nix

    # QEMU guest optimizations (virtio drivers, agent)
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # VM-specific configuration
  networking.hostName = "nixos-kubevirt-vm";

  # Cloud-init support for KubeVirt (REQUIRED)
  # This allows dynamic configuration via cloud-init from VirtualMachine spec
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # QEMU guest agent for better VM integration (RECOMMENDED)
  # Provides VM metadata and improves host-guest communication
  # Note: qemu-guest-agent is automatically enabled by qemu-guest.nix profile import

  # Enable root login for emergency access
  users.users.root.initialHashedPassword = "";  # Empty password for root
  services.openssh.settings.PermitRootLogin = "yes";

  # Boot configuration for VM
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";  # virtio disk device
  };

  # Desktop environment: XFCE (lightweight and fast)
  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
    displayManager.lightdm.enable = true;
  };

  # xrdp: Remote Desktop Protocol server for RDP access
  services.xrdp = {
    enable = true;
    defaultWindowManager = "xfce4-session";
    openFirewall = true;  # Opens port 3389 in firewall
  };

  # Minimal additional packages for VM workloads
  # (base.nix already provides: vim, git, curl, jq, tmux, htop, etc.)
  environment.systemPackages = with pkgs; [
    # Desktop environment tools
    firefox
    xfce.thunar  # File manager
    xfce.xfce4-terminal  # Terminal emulator

    # VM-specific tools (add as needed):
    # kubectl
    # docker
  ];

  # System state version (matches base.nix)
  system.stateVersion = lib.mkDefault "24.11";

  # Note: base.nix already provides:
  # - SSH with authorized keys for vpittamp user
  # - Nix flakes enabled
  # - Essential CLI tools (vim, git, ripgrep, fd, tmux)
  # - Auto garbage collection
  # - Sudo without password for wheel group
  # - Time zone: America/New_York
  # - Locale: en_US.UTF-8
}
