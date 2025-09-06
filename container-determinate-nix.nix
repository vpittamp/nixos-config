# Container configuration with Determinate Nix Installer
# This provides a better Nix experience in containers with improved caching and diagnostics
{ config, lib, pkgs, ... }:

let
  # Determinate Nix Installer binary
  # Using the static binary for container compatibility
  determinateNixInstaller = pkgs.fetchurl {
    url = "https://install.determinate.systems/nix/nix-installer-x86_64-linux";
    sha256 = "sha256-PLACEHOLDER"; # Will be updated with actual hash
    executable = true;
  };

  # Script to install Determinate Nix in container
  installDeterminateNix = pkgs.writeScriptBin "install-determinate-nix" ''
    #!${pkgs.bashInteractive}/bin/bash
    set -e
    
    echo "Installing Determinate Nix..."
    
    # Check if Nix is already installed
    if [ -d /nix/store ]; then
      echo "Nix store already exists, skipping installation"
      exit 0
    fi
    
    # Download and run the installer
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
      sh -s -- install linux \
        --no-confirm \
        --init none \
        --extra-conf "sandbox = false" \
        --extra-conf "experimental-features = nix-command flakes" \
        --extra-conf "trusted-users = root @wheel" \
        --extra-conf "max-jobs = auto" \
        --extra-conf "cores = 0"
    
    echo "Determinate Nix installation complete"
  '';

  # Enhanced entrypoint that uses Determinate Nix
  determinateEntrypoint = pkgs.writeScriptBin "container-entrypoint-determinate" ''
    #!${pkgs.bashInteractive}/bin/bash
    set -e
    
    echo "[entrypoint] Container starting with Determinate Nix support..."
    
    # Check if Nix is installed
    if [ ! -d /nix ]; then
      echo "[entrypoint] Nix not found, installing Determinate Nix..."
      ${installDeterminateNix}/bin/install-determinate-nix
    fi
    
    # Source Nix environment
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    elif [ -f /etc/profile.d/nix.sh ]; then
      . /etc/profile.d/nix.sh
    fi
    
    # Configure FlakeHub cache if token is provided
    if [ -n "$FLAKEHUB_TOKEN" ]; then
      echo "[entrypoint] Configuring FlakeHub cache..."
      export NIX_CONFIG="extra-substituters = https://cache.flakehub.com
extra-trusted-public-keys = cache.flakehub.com-1:wT3492wStJhBYwL8JaztnVDVdgNXRRdCpnCKRRRRvLc="
    fi
    
    # Continue with regular entrypoint
    exec /etc/container-entrypoint.sh "$@"
  '';
in
{
  # Include this in your container build
  environment.systemPackages = with pkgs; [
    # Core utilities
    bashInteractive
    coreutils
    curl
    wget
    git
    
    # Determinate Nix installer script
    installDeterminateNix
    determinateEntrypoint
    
    # Keep regular Nix as fallback
    nix
  ];
  
  # Environment variables for Determinate Nix
  environment.variables = {
    # Enable better error messages
    NIX_DAEMON_SOCKETFILE = "/nix/var/nix/daemon-socket/socket";
    
    # FlakeHub configuration (set FLAKEHUB_TOKEN in container runtime)
    FLAKEHUB_CACHE_ENABLED = "1";
  };
  
  # Nix configuration optimized for containers
  nix = {
    package = pkgs.nixFlakes;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "@wheel" ];
      
      # Use binary caches including FlakeHub
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.flakehub.com" # FlakeHub cache
      ];
      
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.flakehub.com-1:wT3492wStJhBYwL8JaztnVDVdgNXRRdCpnCKRRRRvLc="
      ];
      
      # Container optimizations
      sandbox = false; # Sandboxing doesn't work in containers
      auto-optimise-store = true;
      max-jobs = "auto";
      cores = 0;
      
      # Better diagnostics
      show-trace = true;
      narinfo-cache-negative-ttl = 0; # Don't cache missing paths
    };
  };
}