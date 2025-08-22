# Base configuration shared between WSL and containers
{ config, lib, pkgs, ... }:

let
  # Detect if we're building for a container
  isContainer = builtins.getEnv "NIXOS_CONTAINER" != "";
  
  # Get package profile from environment (used by overlay system)
  packageProfile = builtins.getEnv "NIXOS_PACKAGES";
in
{
  # Container mode configuration
  boot.isContainer = lib.mkIf isContainer true;

  # 1Password configuration
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "vpittamp" ];
  };
  
  # Alternative: Use programs.nix-ld for better compatibility
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      curl
      icu
      libuuid
      libsecret
    ];
  };

  # Create user
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    shell = pkgs.bash;
    createHome = true;
    home = "/home/vpittamp";
  };

  # Sudo configuration
  security.sudo = {
    wheelNeedsPassword = true;
    extraRules = [{
      users = [ "vpittamp" ];
      commands = [{
        command = "ALL";
        options = [ "NOPASSWD" ];
      }];
    }];
  };

  nixpkgs.config.allowUnfree = true;

  # Basic system packages
  environment.systemPackages = with pkgs; [
    neovim
    vim
    git
    wget
    curl
    nodejs_20
    claude-code
    docker-compose
  ];

  # Enable Docker (native NixOS docker package)
  virtualisation.docker = {
    enable = false;
    enableOnBoot = false;
    autoPrune.enable = false;
  };

  # Networking configuration
  networking = {
    hostName = if isContainer then "nixos-container" else "nixos-wsl";
  };

  # Enable nix flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.05";
}