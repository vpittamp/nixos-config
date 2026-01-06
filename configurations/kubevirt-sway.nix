# KubeVirt Sway Desktop Configuration
# Full Sway desktop environment optimized for KubeVirt VMs
#
# Build: nix build .#kubevirt-sway-qcow2
# Size target: ~2-3GB (full desktop, no hardware-specific bloat)
#
# Includes:
# - Sway Wayland compositor with full window management
# - Project management (i3pm, eww bars, workspace management)
# - 1Password CLI + GUI
# - Terminal tools (ghostty, alacritty, tmux)
# - Development tools (Docker, git, kubectl, etc.)
# - Tailscale for remote access
#
# Excluded (not needed in KubeVirt):
# - Hardware-specific (ThinkPad, fingerprint, TLP, thermald)
# - Bare-metal virtualization (libvirtd - nested KVM is problematic)
# - Bluetooth, WiFi (using virtio network)
# - Hardware video acceleration (Intel/AMD specific)
#
{ config, lib, pkgs, inputs, modulesPath, ... }:

{
  imports = [
    # KubeVirt module - enables QEMU guest agent, cloud-init, SSH, serial console
    # Also configures GRUB on /dev/vda with auto-resize root filesystem
    (modulesPath + "/virtualisation/kubevirt.nix")

    # Base configuration (users, SSH, nix settings, base packages)
    ./base.nix

    # Desktop environment (Sway - Wayland compositor)
    ../modules/desktop/sway.nix

    # Services
    ../modules/services/networking.nix     # Tailscale + firewall
    ../modules/services/onepassword.nix    # 1Password CLI + GUI

    # Home-manager for full desktop setup
    inputs.home-manager.nixosModules.home-manager
  ];

  # ========== IDENTIFICATION ==========
  networking.hostName = "nixos-kubevirt-sway";
  system.stateVersion = "24.11";

  # ========== BOOT OPTIMIZATIONS ==========
  # Add virtio kernel modules for KubeVirt performance
  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net" "virtio_balloon"
  ];
  boot.kernelParams = [ "net.ifnames=0" "console=ttyS0" ];

  # ========== NETWORKING ==========
  networking.useDHCP = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 5900 ];  # SSH + VNC
  };

  # ========== SWAY DESKTOP ==========
  services.sway.enable = true;

  # Display manager - greetd for Wayland/Sway login
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd sway";
        user = "greeter";
      };
    };
  };

  # ========== 1PASSWORD ==========
  services.onepassword = {
    enable = true;
    user = "vpittamp";
    gui.enable = true;  # 1Password GUI for desktop
    ssh.enable = true;  # SSH agent integration
  };

  # ========== HOME-MANAGER ==========
  # Full desktop setup with Sway config, eww bars, project management
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users.vpittamp = { ... }: {
      imports = [
        ../home-vpittamp.nix  # Full Sway desktop config
      ];
      # stateVersion inherited from base-home.nix
    };
  };

  # ========== USER CONFIGURATION ==========
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "video" "input" "docker" ];
    initialPassword = "nixos123";  # Change on first login or via cloud-init
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0gmlXX6rWgC+4XW6FYBuN8gSOp7H/U+s8UeALbTnmG vpittamp@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7 1password-git-signing"
    ];
  };

  # ========== DEVELOPMENT TOOLS ==========
  # Docker (no libvirtd - nested KVM in KubeVirt is problematic)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # ========== PACKAGES ==========
  environment.systemPackages = with pkgs; [
    # Terminals
    ghostty
    alacritty
    foot

    # Core tools
    vim
    git
    gh           # GitHub CLI
    curl
    wget
    htop
    tmux
    tree
    ripgrep
    fd
    jq
    yq

    # 1Password
    _1password-gui
    _1password-cli

    # Kubernetes tools (for managing the host cluster)
    kubectl
    kubernetes-helm
    k9s
    argocd

    # Development
    nodejs_20
    python3
    go

    # Network tools
    tailscale
    netcat
    dig

    # VNC for remote desktop
    wayvnc

    # Sway extras
    wl-clipboard
    grim
    slurp
    swaylock
    swayidle
    swaynotificationcenter
  ];

  # ========== NIX CONFIGURATION ==========
  # Fonts and Cachix cache config inherited from base.nix

  # ========== DISK SIZE ==========
  # 80GB for full desktop + development tools
  virtualisation.diskSize = 80 * 1024;  # MiB

  # ========== TIME & LOCALE ==========
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
}
