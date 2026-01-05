# Base NixOS configuration shared across all systems
# This provides the foundation that all target configurations build upon
{ config, lib, pkgs, ... }:

{
  imports = [
    ../modules/services/cluster-certs.nix
  ];

  # System identification
  system.stateVersion = lib.mkDefault "24.11";
  
  # Boot configuration basics (can be overridden)
  boot = {
    tmp.cleanOnBoot = true;
    loader = {
      timeout = lib.mkDefault 3;
    };
  };

  # Core networking
  networking = {
    useDHCP = lib.mkDefault true;
    firewall = {
      enable = lib.mkDefault true;
      allowedTCPPorts = [ 22 ];  # SSH is always allowed
    };
  };

  # Time zone and locale
  time.timeZone = lib.mkDefault "America/New_York";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };

  # Enable SSH by default
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = lib.mkDefault true;
      X11Forwarding = lib.mkDefault true;
    };
  };

  # User accounts
  users.users = {
    root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0gmlXX6rWgC+4XW6FYBuN8gSOp7H/U+s8UeALbTnmG vpittamp@gmail.com"
      ];
    };

    vpittamp = {
      isNormalUser = true;
      description = "Vinod Pittampalli";
      extraGroups = [ "wheel" "networkmanager" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0gmlXX6rWgC+4XW6FYBuN8gSOp7H/U+s8UeALbTnmG vpittamp@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7 1Password Git Signing Key"
      ];
      # Password will be set per-system if needed
    };
  };

  # Allow sudo without password for wheel group
  security.sudo = {
    wheelNeedsPassword = false;

    # Feature 037: Allow i3pm daemon to read /proc/{pid}/environ for window filtering
    extraRules = [{
      users = [ "vpittamp" ];
      commands = [{
        command = "/run/current-system/sw/bin/cat /proc/*/environ";
        options = [ "NOPASSWD" ];
      }];
    }];
  };

  # Ensure per-user profile roots exist (needed for home-manager when run via system builds)
  systemd.tmpfiles.rules = [
    "d /nix/var/nix/profiles/per-user/vpittamp 0755 vpittamp users -"
  ];

  # Trust local Kubernetes cluster CA certificates
  # Required for Nix to fetch from Attic cache over HTTPS
  # CA is synced by: stacks/scripts/certificates/sync-cluster-certificates.sh
  services.clusterCerts.enable = true;

  # Core Nix configuration
  nix = {
    # Pin the daemon/client to the latest stable Nix to avoid 2.31.2 crash bug
    package = pkgs.nixVersions.latest;

    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "vpittamp" "@wheel" ];
      auto-optimise-store = true;
      
      # Use cachix for faster builds
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      # Attic cache for backstage builds (local k8s cluster)
      # Public key is persistent in Azure Key Vault (setup by setup-persistent-certs.sh)
      extra-substituters = [
        "https://attic.cnoe.localtest.me:8443/backstage"
      ];
      extra-trusted-public-keys = [
        "backstage:MSuDAPGlAmwOAiSTeDW5JrFuh5f7UVX3I3k2G+Yerk4="
      ];
    };
    
    # Garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Fonts configuration - enable Nerd Fonts for terminal icons
  fonts.packages = with pkgs; [
    nerd-fonts.hack
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.meslo-lg
    font-awesome  # For i3 workspace icons
  ];

  # Essential base packages
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim
    git
    wget
    curl
    htop
    tmux
    tree
    ripgrep
    fd
    ncdu
    rsync
    openssl
    jq
    socat  # Required by app-launcher-wrapper.sh for daemon IPC

    # X11 utilities
    xorg.xdpyinfo  # X display information utility
    xorg.xhost     # X server access control
    xorg.xwininfo  # Window information utility
    xorg.xeyes     # X11 test application
    xorg.xclock    # X11 test application

    # Nix tools
    nix-prefetch-git
    nixpkgs-fmt
    nh  # Modern Nix helper with nom integration
    nix-output-monitor  # Better build visualization (nom)

    # Custom scripts
    (pkgs.writeScriptBin "nixos-metadata" (builtins.readFile ../scripts/nixos-metadata))
    (pkgs.writeScriptBin "nixos-generation-info" (builtins.readFile ../scripts/nixos-generation-info))
    (pkgs.writeScriptBin "nixos-build-status" (builtins.readFile ../scripts/nixos-build-status))
    (pkgs.writeScriptBin "nixos-build-wrapper" (builtins.readFile ../scripts/nixos-build-wrapper))
    (pkgs.writeScriptBin "test-ai-agents-permissions" (builtins.readFile ../scripts/test-ai-agents-permissions))
  ];
}
