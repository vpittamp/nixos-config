# Container-specific overrides for the main configuration
# This module adapts the WSL configuration for container use
{ config, lib, pkgs, ... }:

{
  # Import modules for containers
  imports = [ 
    ./container-ssh.nix 
    # Use the simplified VS Code module with nix-community's vscode-server
    ./container-vscode-simple.nix
    # Proper flake support with git repository
    ./container-flake-proper.nix
  ];
  
  # Explicitly disable WSL features in containers
  disabledModules = [ ];
  
  # Container-specific settings
  boot.isContainer = true;
  
  # Optimize Nix for container builds and ad-hoc package management
  nix = {
    settings = {
      # Use binary caches for faster downloads
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
        "https://nix-community.cachix.org"
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
      
      # Trust the build user and code user for nix-env
      trusted-users = [ "root" "code" "@wheel" ];
      allowed-users = [ "root" "code" "@wheel" ];
      
      # Enable flakes and other experimental features for modern Nix usage
      experimental-features = [ "nix-command" "flakes" ];
      
      # Auto-optimize store to save space
      auto-optimise-store = true;
      
      # Disable sandbox for container compatibility
      # Containers already provide isolation, and sandbox causes issues
      sandbox = false;
    };
    
    # Garbage collection settings for containers
    gc = {
      automatic = false; # Manual GC in containers
      options = "--max-freed 1G";
    };
  };
  
  # Disable WSL module in containers
  wsl.enable = lib.mkForce false;
  
  # Disable 1password in containers (saves ~611MB)
  programs._1password.enable = lib.mkForce false;
  programs._1password-gui.enable = lib.mkForce false;
  
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
  # The overlays/packages.nix already handles NIXOS_PACKAGES environment variable
  # and returns the appropriate package set via allPackages
  environment.systemPackages = lib.mkForce (with pkgs; let
    overlayPackages = import ./overlays/packages.nix { inherit pkgs lib; };
  in
    # Use the pre-filtered allPackages from overlays/packages.nix
    # which respects the NIXOS_PACKAGES environment variable
    overlayPackages.allPackages ++ [
      # Always include SSH-related packages for containers
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
      # Locale support is handled by i18n.supportedLocales
      # Don't include full glibcLocales package (saves ~200MB)
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
  # Use minimal C.UTF-8 locale to save space and avoid locale warnings
  i18n = {
    defaultLocale = "C.UTF-8";
    supportedLocales = [
      "C.UTF-8/UTF-8"  # Minimal UTF-8 locale, no need for full language packs
    ];
  };
  
  
  # Environment variables for locale
  environment.variables = {
    LANG = "C.UTF-8";
    LC_ALL = "C.UTF-8";
    # C.UTF-8 is built into glibc, no need for locale-archive
    # This saves space and avoids locale warnings
    
    # Add nixpkgs channel path for easier package discovery
    NIX_PATH = lib.mkForce "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs";
  };
  
  # Add helpful aliases for ad-hoc package management
  environment.shellAliases = {
    # Quick package management
    "nix-search" = "nix search nixpkgs";
    "nix-install" = "nix-env -iA nixpkgs";
    "nix-shell-with" = "nix-shell -p";  # e.g., nix-shell-with python3 nodejs
    "nix-run" = "nix run nixpkgs#";     # e.g., nix-run cowsay hello
    "nix-list" = "nix-env -q";
    "nix-remove" = "nix-env -e";
    "nix-gc" = "nix-collect-garbage -d";
    
    # Helpful shortcuts
    "nsp" = "nix-shell -p";  # Short for nix-shell-with
    "nr" = "nix run nixpkgs#"; # Short for nix-run
  };
  
  # Add documentation for container users
  environment.etc."motd".text = ''
    ╔══════════════════════════════════════════════════════════════╗
    ║  NixOS Development Container                                  ║
    ║  Ad-hoc package management with Nix:                          ║
    ║                                                                ║
    ║  • nix-shell -p <pkg>     # Temporary shell with package      ║
    ║  • nix run nixpkgs#<pkg>  # Run package without installing    ║
    ║  • nix-install <pkg>      # Install package permanently       ║
    ║  • nix search nixpkgs <q> # Search for packages               ║
    ║                                                                ║
    ║  Examples:                                                     ║
    ║    nix-shell -p python3 nodejs  # Shell with Python & Node    ║
    ║    nix run nixpkgs#htop         # Run htop without install    ║
    ║    nix-install go               # Install Go permanently      ║
    ║                                                                ║
    ║  Type 'cat /etc/motd' to see this message again.              ║
    ╚══════════════════════════════════════════════════════════════╝
  '';
}