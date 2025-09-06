# Base container configuration - minimal system with Nix
# This creates a lightweight base image that can be extended at runtime
{ config, lib, pkgs, ... }:

{
  # Mark as container
  boot.isContainer = true;
  
  # Disable WSL features
  wsl.enable = lib.mkForce false;
  
  # Core system packages only - no development tools
  environment.systemPackages = with pkgs; [
    # Core utilities
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    which
    file
    
    # Nix essentials
    nix
    nix-prefetch-git
    cachix
    
    # Network tools
    curl
    wget
    openssh
    
    # Required for container operation
    procps
    shadow
    util-linux
    
    # Git for flake operations
    git
    
    # Home-manager for runtime configuration
    home-manager
  ];
  
  # Nix configuration for runtime package management
  nix = {
    package = pkgs.nixFlakes;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "@wheel" ];
      
      # Use binary caches
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://claude-code.cachix.org"  # Pre-built claude-code binaries
      ];
      
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="  # Claude Code cache
      ];
      
      # Optimize for container
      auto-optimise-store = true;
      max-jobs = "auto";
      cores = 0;
    };
  };
  
  # Basic user setup
  users.users = {
    root = {
      isNormalUser = false;
      home = "/root";
      shell = pkgs.bashInteractive;
    };
    
    code = {
      isNormalUser = true;
      home = "/home/code";
      shell = pkgs.bashInteractive;
      uid = 1000;
      group = "users";
      extraGroups = [ "wheel" ];
    };
    
    vpittamp = {
      isNormalUser = true;
      home = "/home/vpittamp";
      shell = pkgs.bashInteractive;
      uid = 1001;
      group = "users";
      extraGroups = [ "wheel" ];
    };
  };
  
  # Enable wheel group for sudo
  security.sudo.wheelNeedsPassword = false;
  
  # Disable unnecessary services
  services.nscd.enable = false;
  systemd.services = {
    systemd-udevd.enable = false;
    systemd-udev-settle.enable = false;
  };
  
  # Basic networking
  networking.hostName = "nixos-base";
  
  # System state version
  system.stateVersion = "24.05";
}