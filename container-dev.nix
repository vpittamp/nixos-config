# Development container configuration
# This profile extends the base container with development-specific features
# It enables native Nix package management and development shells

{ config, pkgs, lib, ... }:

{
  imports = [
    ./container-profile.nix  # Base container configuration
  ];
  
  # Additional packages for development containers
  environment.systemPackages = with pkgs; [
    # Nix development tools
    nix-prefetch-git
    nixpkgs-fmt
    nil  # Nix LSP
    nix-tree
    nix-diff
    
    # Certificate management
    cacert
    ca-certificates
    
    # Shell environment tools
    direnv
    nix-direnv
    
    # Container debugging tools
    strace
    ltrace
    procps
    psmisc
    lsof
    
    # Network debugging
    netcat
    nmap
    tcpdump
    
    # Development essentials
    gdb
    valgrind
    perf-tools
    
    # Build tools
    gnumake
    cmake
    pkg-config
    autoconf
    automake
    libtool
  ];
  
  # Environment variables for development
  environment.variables = {
    # SSL Certificates
    NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
    
    # Nix configuration
    NIX_BUILD_SHELL = "${pkgs.bashInteractive}/bin/bash";
    
    # Development mode indicators
    CONTAINER_DEV_MODE = "true";
    
    # Allow direnv
    DIRENV_LOG_FORMAT = "";  # Quiet direnv output
  };
  
  # Nix configuration for development
  nix = {
    settings = {
      # Enable experimental features
      experimental-features = [ "nix-command" "flakes" ];
      
      # Trust users to install packages
      trusted-users = [ "root" "code" "@wheel" ];
      
      # Allow import from derivation (needed for some dev shells)
      allow-import-from-derivation = true;
      
      # Optimize for container environment
      auto-optimise-store = false;
      sandbox = false;
      
      # Enable substituters for faster downloads
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    
    # Configure garbage collection
    gc = {
      automatic = false;  # Manual GC in containers
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };
  
  # Create development shell activation script
  system.activationScripts.devShellSetup = ''
    # Create profile directories for non-root users
    mkdir -p /nix/var/nix/profiles/per-user/code
    chown -R 1000:100 /nix/var/nix/profiles/per-user/code 2>/dev/null || true
    
    # Create gcroots directory for development shells
    mkdir -p /nix/var/nix/gcroots/per-user/code
    chown -R 1000:100 /nix/var/nix/gcroots/per-user/code 2>/dev/null || true
    
    # Ensure SSL certificates are available
    if [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then
      echo "Setting up SSL certificates..."
      ${pkgs.cacert}/bin/ca-bundle > /etc/ssl/certs/ca-certificates.crt 2>/dev/null || true
    fi
  '';
  
  # Programs configuration
  programs = {
    # Enable direnv for automatic environment loading
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    
    # Enable command-not-found for package discovery
    command-not-found.enable = true;
  };
  
  # Services for development
  services = {
    # Ensure /tmp is writable and cleaned periodically
    systemd.tmpfiles.rules = [
      "d /tmp 1777 root root 10d"
      "d /var/tmp 1777 root root 10d"
    ];
  };
}