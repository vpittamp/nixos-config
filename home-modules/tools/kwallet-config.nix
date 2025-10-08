{ config, pkgs, lib, ... }:

{
  # KDE Wallet home-manager configuration
  # Note: KDE Wallet auto-unlock via PAM is configured in modules/desktop/kde-plasma.nix

  # Install wallet management tools
  # Note: kwallet and kwallet-pam are already provided by KDE Plasma system packages
  home.packages = with pkgs; [
    libsecret  # Secret Service API library for application integration
    kdePackages.kwalletmanager  # GUI wallet management tool
  ];

  # KDE Wallet will be created automatically on first use by KDE applications
  # PAM integration (configured at system level) handles auto-unlock with login password
  # No additional initialization or systemd services needed
}