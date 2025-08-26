# Container-specific overrides for the main configuration
# This module adapts the WSL configuration for container use
{ config, lib, pkgs, ... }:

{
  # Import modules for containers
  imports = [ 
    ./container-ssh.nix 
    # Use the simplified VS Code module with nix-community's vscode-server
    ./container-vscode-simple.nix
    # ./container-vscode.nix  # Old manual approach (kept for reference)
    ./container-entrypoint.nix  # Entrypoint script for proper initialization
  ];
  
  # Explicitly disable WSL features in containers
  disabledModules = [ ];
  
  # Container-specific settings
  boot.isContainer = true;
  
  # Optimize Nix for container builds
  nix = {
    settings = {
      # Use binary caches for faster downloads
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
      ];
      
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
      
      # Optimize for container environment
      max-jobs = "auto";
      cores = 0; # Use all available cores
      max-substitution-jobs = 16; # Parallel downloads
      connect-timeout = 10;
      download-attempts = 3;
      
      # Reduce memory usage during builds
      min-free = 128 * 1024 * 1024; # 128MB
      max-free = 1024 * 1024 * 1024; # 1GB
      
      # Trust the build user
      trusted-users = [ "root" "@wheel" ];
      
      # Enable flakes
      experimental-features = [ "nix-command" "flakes" ];
    };
    
    # Garbage collection settings for containers
    gc = {
      automatic = false; # Manual GC in containers
      options = "--max-freed 1G";
    };
  };
  
  # Disable WSL module in containers
  wsl.enable = lib.mkForce false;
  
  # Disable systemd services that don't work in containers
  systemd.services = {
    systemd-udevd.enable = false;
    systemd-udev-settle.enable = false;
    systemd-modules-load.enable = false;
    systemd-tmpfiles-setup-dev.enable = false;
    # Disable WSL-specific services if they exist
    docker-desktop-proxy.enable = lib.mkForce false;
  };
  
  # Disable WSL-specific activation scripts
  system.activationScripts = {
    dockerDesktopIntegration = lib.mkForce "";
    wslClipboard = lib.mkForce "";
  };
  
  # Override networking for containers
  networking.hostName = lib.mkForce "nixos-container";
  
  # Disable user systemd services that are WSL-specific
  systemd.user = lib.mkForce {};
  
  # Override environment packages for containers
  # Use NIXOS_PACKAGES environment variable to control what gets installed
  # Default: essential packages only (from overlays/packages.nix)
  environment.systemPackages = lib.mkForce (with pkgs; let
    overlayPackages = import ./overlays/packages.nix { inherit pkgs lib; };
  in
    # For containers: use essential packages by default
    # Can be overridden with NIXOS_PACKAGES env var at build time
    overlayPackages.essential ++ overlayPackages.extras ++ [
      # Add SSH-related packages for containers
      pkgs.openssh
      # Add neovim since home-manager won't be applied for code user
      pkgs.neovim
      # Add other development tools that would normally come from home-manager
      pkgs.ripgrep
      pkgs.fd
      pkgs.nodejs_20
    ]
  );
  
  # Users for SSH access in containers
  users.users = {
    # Code user for development containers
    code = {
      isNormalUser = true;
      uid = 1000;
      group = "users";
      extraGroups = [ "wheel" ];
      home = "/home/code";
      shell = pkgs.bash;
      # Allow passwordless sudo for development
      openssh.authorizedKeys.keys = [
        # These will be overridden by mounted secrets
        # Add default keys here if needed
      ];
    };
    # Also create vpittamp user for home-manager compatibility
    vpittamp = {
      isNormalUser = true;
      uid = 1001;
      group = "users";
      extraGroups = [ "wheel" ];
      home = "/home/vpittamp";
      shell = pkgs.bash;
      createHome = true;
    };
  };
  
  # Ensure wheel group has sudo access
  security.sudo.wheelNeedsPassword = false;
}