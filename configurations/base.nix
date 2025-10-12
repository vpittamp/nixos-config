# Base NixOS configuration shared across all systems
# This provides the foundation that all target configurations build upon
{ config, lib, pkgs, ... }:

{
  # No imports needed - environment check will be in each specific config

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
      ];
    };
    
    vpittamp = {
      isNormalUser = true;
      description = "Vinod Pittampalli";
      extraGroups = [ "wheel" "networkmanager" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
      ];
      # Password will be set per-system if needed
    };
  };

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Core Nix configuration
  nix = {
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

    # Nix tools
    nix-prefetch-git
    nixpkgs-fmt
    nh

    # Custom scripts
    (pkgs.writeScriptBin "nixos-metadata" (builtins.readFile ../scripts/nixos-metadata))
    (pkgs.writeScriptBin "test-ai-agents-permissions" (builtins.readFile ../scripts/test-ai-agents-permissions))
  ];
}