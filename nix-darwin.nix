{ config, pkgs, lib, ... }:
{
  # Disable nix-darwin's Nix management due to Determinate Nix Installer
  nix.enable = false;
  
  # System state version
  system.stateVersion = 6;

  # Use zsh (default shell on macOS)
  programs.zsh.enable = true;

  # Define the primary user so Home Manager can infer a home path
  users.users.vinodpittampalli = {
    name = "vinodpittampalli";
    home = "/Users/vinodpittampalli";
  };

  # Allow TouchID for sudo if available (updated option name)
  security.pam.services.sudo_local.touchIdAuth = true;

  # Install some basic system packages; user packages are defined in home-manager.
  environment.systemPackages = with pkgs; [
    git
    curl
    jq
    gnupg
    ripgrep
    fd
    bat
  ];

  # You can add macOS defaults here by uncommenting and customizing:
  # system.defaults.NSGlobalDomain.AppleShowAllExtensions = true;
  # system.defaults.dock.autohide = true;
  # system.defaults.finder.AppleShowAllFiles = true;
}