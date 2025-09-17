# Container Configuration
# Minimal NixOS for Docker/Kubernetes containers
{ config, lib, pkgs, inputs ? null, containerProfile ? null, ... }:

let
  resolvedProfile =
    if containerProfile != null then containerProfile else builtins.getEnv "NIXOS_PACKAGES";
  packageEnv = if resolvedProfile == "" then "minimal" else resolvedProfile;
in
{
  imports = [
    # Base configuration (minimal)
    ./base.nix
    
    # Container services
    ../modules/services/container.nix
  ];

  # Container-specific settings
  boot.isContainer = true;
  
  # Disable unnecessary services in containers
  services.openssh.enable = lib.mkDefault false;  # Enable via env var if needed
  
  # System identification
  networking.hostName = lib.mkDefault "nixos-container";
  
  # Minimal firewall (containers rely on Docker/K8s networking)
  networking.firewall.enable = false;
  
  # Container-optimized Nix settings
  nix = {
    settings = {
      # Additional caches for containers
      substituters = lib.mkAfter [
        "https://devenv.cachix.org"
      ];
      
      trusted-public-keys = lib.mkAfter [
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
      
      # Optimize for container environment
      max-jobs = "auto";
      cores = 0; # Use all available cores
      max-substitution-jobs = 16; # Parallel downloads
      
      # Reduce memory usage during builds
      min-free = 128 * 1024 * 1024; # 128MB
      max-free = 1024 * 1024 * 1024; # 1GB
      
      # Trust the build user and code user for nix-env
      trusted-users = [ "root" "code" "vpittamp" "@wheel" ];
    };
  };
  
  # Container user (in addition to vpittamp from base)
  users.users.code = {
    isNormalUser = true;
    uid = 1000;
    group = "users";
    extraGroups = [ "wheel" ];
    home = "/home/code";
    shell = pkgs.bash;
    # No password for container user
  };
  
  # Minimal package set for containers (override base)
  environment.systemPackages = lib.mkForce (with pkgs; [
    # Absolute essentials only
    vim
    git
    curl
    jq
    bash
    coreutils
  ] ++ lib.optionals (packageEnv == "development") [
    # Development tools if requested
    nodejs_20
    python3
    go
    docker-client
    kubectl
  ]);
  
  # Container-specific environment variables
  environment.variables = {
    NIXOS_CONTAINER = "1";
    CONTAINER_PROFILE = packageEnv;
  };
  
  # Disable documentation in containers
  documentation = {
    enable = false;
    doc.enable = false;
    info.enable = false;
    man.enable = false;
    nixos.enable = false;
  };
  
  # System state version
  system.stateVersion = "24.11";
}
