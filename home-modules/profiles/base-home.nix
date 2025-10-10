{ config, pkgs, lib, inputs, osConfig, ... }:

let
  hostName =
    if osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else null;
  isM1 = hostName == "nixos-m1";
  sessionConfig = {
    # Don't set GDK_SCALE - KDE Wayland already handles 200% scaling
    # Setting both causes double-scaling for Electron apps
    # GDK_DPI_SCALE = if isM1 then "0.5" else "1.0";  # Not needed with Wayland
    # GDK_SCALE = if isM1 then "2" else "1";  # Causes double-scaling

    # Qt settings for KDE
    QT_AUTO_SCREEN_SCALE_FACTOR = "1"; # Let Qt detect from Wayland
    QT_ENABLE_HIGHDPI_SCALING = "1"; # Enable HiDPI support
    PLASMA_USE_QT_SCALING = "1"; # Let Plasma handle Qt scaling

    # Cursor size
    XCURSOR_SIZE = if isM1 then "48" else "24"; # 48 for 200% scaling

    # UV (Python package manager) configuration for NixOS
    # Use system Python instead of downloading pre-built binaries
    UV_PYTHON_PREFERENCE = "only-system";
  };
in
{
  imports = [
    # Shell configurations
    ../shell/bash.nix
    ../shell/starship.nix
    ../shell/colors.nix

    # Terminal configurations
    ../terminal/tmux.nix
    ../terminal/sesh.nix

    # Editor configurations
    ../editors/neovim.nix

    # Tool configurations
    ../tools/git.nix
    ../tools/ssh.nix
    ../tools/onepassword.nix
    ../tools/onepassword-env.nix
    ../tools/onepassword-plugins.nix
    ../tools/onepassword-autostart.nix
    ../tools/bat.nix
    ../tools/direnv.nix
    ../tools/fzf.nix
    ../tools/chromium.nix # Enabled for Playwright MCP support
    ../tools/firefox.nix
    ../tools/docker.nix # Docker with 1Password authentication
    # ../tools/firefox-pwas-declarative.nix  # Disabled - causing boot hang
    ../tools/k9s.nix
    ../tools/yazi.nix
    ../tools/nix.nix
    ../tools/vscode.nix
    ../tools/gitkraken.nix
    ../tools/kubernetes-apps.nix
    ../tools/konsole-profiles.nix

    # AI Assistant configurations
    ../ai-assistants/claude-code.nix
    ../ai-assistants/codex.nix
    ../ai-assistants/gemini-cli.nix

    # External modules
    inputs.onepassword-shell-plugins.hmModules.default
  ];

  home.stateVersion = "25.05";
  home.enableNixpkgsReleaseCheck = false;

  home.packages =
    let
      userPackages = import ../../user/packages.nix { inherit pkgs lib; };
      packageConfig = import ../../shared/package-lists.nix { inherit pkgs lib; };
    in
    packageConfig.getProfile.user ++ [ pkgs.papirus-icon-theme ];

  modules.tools.yazi.enable = true;
  modules.tools.docker.enable = true; # Docker with 1Password integration
  modules.tools.docker.autoLogin = true; # Auto-login to Docker Hub on shell startup

  # VSCode profile configuration
  # All VSCode instances (including activity-aware launchers) use this profile
  # Use "nixos" to continue using your existing profile with all customizations
  modules.tools.vscode.defaultProfile = "nixos";

  programs.home-manager.enable = true;

  # Enable XDG base directories and desktop entries
  xdg.enable = true;
  # MIME associations are fully managed in firefox.nix when Firefox is enabled
  # No need for duplicate configuration here

  home.sessionVariables = sessionConfig;

  # Firefox PWAs configuration - DISABLED (causing boot hang)
  # programs.firefox-pwas = {
  #   enable = true;
  #   pwas = [
  #     # CNOE Developer Tools
  #     "argocd"
  #     "gitea"
  #     "backstage"
  #     "headlamp"
  #     "kargo"
  #     # Other PWAs
  #     "google"
  #     "youtube"
  #   ];
  #     pinToTaskbar = true;  # Pin them to KDE taskbar
  #   };
}
