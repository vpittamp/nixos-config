# Container-specific overrides for the main configuration
# This module adapts the WSL configuration for container use
{ config, lib, pkgs, ... }:

{
  # Import modules for containers
  imports = [ 
    ./container-ssh.nix 
    # Use the simplified VS Code module with nix-community's vscode-server
    ./container-vscode-simple.nix
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
      # Add nix-ld for VS Code compatibility
      pkgs.nix-ld
      # Add CA certificates for SSL/TLS operations
      pkgs.cacert
      # Add neovim explicitly since home-manager packages don't get included
      pkgs.neovim
      # Add starship for prompt theming
      pkgs.starship
      # Add tmux for terminal multiplexing
      pkgs.tmux
      # Add locale support
      pkgs.glibcLocales
    ]
  );
  
  # Users for SSH access in containers
  users.users = {
    # Root user with development key for container access
    root = {
      openssh.authorizedKeys.keys = [
        # Development key for container access
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEyZ6emQaxS4xcdQf4y6fLUpmh11ufOi7jGLbOsvDY+7 dev@backstage"
      ];
    };
    # Code user for development containers
    code = {
      isNormalUser = true;
      uid = 1000;
      group = "users";
      extraGroups = [ "wheel" ];
      home = "/home/code";
      shell = pkgs.bash;
      createHome = true;
      # Allow passwordless sudo for development
      openssh.authorizedKeys.keys = [
        # Development key for container access
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEyZ6emQaxS4xcdQf4y6fLUpmh11ufOi7jGLbOsvDY+7 dev@backstage"
      ];
    };
  };
  
  # Ensure user management is properly initialized in containers
  users.mutableUsers = false;  # Users are defined declaratively
  
  # Create essential system groups
  users.groups = {
    users = { gid = 100; };
    wheel = { gid = 1; };
  };
  
  # Ensure wheel group has sudo access (override main config for containers)
  security.sudo.wheelNeedsPassword = lib.mkForce false;
  
  # Enable nix-ld for VS Code compatibility
  # This provides the dynamic loader at /lib64/ld-linux-x86-64.so.2
  # allowing VS Code's node binary to run
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Add libraries that VS Code and extensions might need
      stdenv.cc.cc
      stdenv.cc.cc.lib
      glibc
      zlib
      openssl
      curl
      icu
      xz
      # Additional libraries for node/VS Code
      libgcc
      libstdcxx5
      gcc-unwrapped.lib
      nodePackages.node-gyp-build
    ];
  };
  
  # Configure locale settings for containers
  i18n = {
    defaultLocale = "en_US.UTF-8";
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
    ];
  };
  
  
  # Environment variables for locale
  environment.variables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_COLLATE = "en_US.UTF-8";
    LOCALE_ARCHIVE = lib.mkForce "${pkgs.glibcLocales}/lib/locale/locale-archive";
  };
}