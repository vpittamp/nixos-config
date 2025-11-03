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
    # Use system Python - managed downloads won't work on NixOS due to dynamic linking
    UV_PYTHON_PREFERENCE = "only-system";
    # Tell UV where to find the system Python
    UV_PYTHON = "${pkgs.python3}/bin/python3";
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
    ../terminal/alacritty.nix  # Alacritty terminal with sesh integration (default)
    # ../terminal/ghostty.nix    # Ghostty terminal (backup option at WS12) - DISABLED: Using Alacritty as default, uncomment to re-enable
    ../terminal/xresources.nix # XTerm styling (for fzf-launcher)

    # Desktop configurations
    ../desktop/dunst.nix       # Notification daemon for i3
    ../desktop/i3-window-rules.nix  # Auto-generate i3 window rules from app-registry (Feature 035)
    ../desktop/i3-project-daemon.nix  # Event-driven daemon for project-scoped window management
    ../tools/i3-project-monitor.nix  # Terminal monitoring tool for i3 project system (Feature 017)
    ../tools/i3-project-test.nix     # Test framework for i3 project system (Feature 018)
    ../tools/window-env.nix          # Helper to query window PIDs and environment variables

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
    ../tools/htop.nix
    ../tools/btop.nix
    ../tools/chromium.nix # Enabled for Playwright MCP support
    ../tools/firefox.nix
    ../tools/docker.nix # Docker with 1Password authentication
    ../tools/pwa-helpers.nix  # PWA validation and helper commands (manual installation via Firefox GUI)
    ../tools/pwa-launcher.nix  # Dynamic PWA launcher with cross-machine compatibility
    # ../tools/web-apps-declarative.nix  # Chromium-based web app launcher - DISABLED (using Firefox PWAs instead)
    ../tools/clipcat.nix  # Clipboard history manager with X11 support (Feature 007)
    ../tools/screenshot-ocr.nix  # Screenshot (Spectacle) and OCR (gImageReader) tools
    ../tools/lazygit.nix  # Terminal UI for Git and Docker
    ../tools/k9s.nix
    ../tools/yazi.nix
    ../tools/nix.nix
    ../tools/vscode.nix
    ../tools/gitkraken.nix
    ../tools/kubernetes-apps.nix
    ../tools/konsole-profiles.nix
    ../tools/walker-commands.nix  # Dynamic command management for Walker (Feature 050)

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

  # VSCode profile configuration
  # All VSCode instances (including activity-aware launchers) use this profile
  # Use "nixos" to continue using your existing profile with all customizations
  modules.tools.vscode.defaultProfile = "nixos";

  programs.home-manager.enable = true;

  # Enable automatic restart of systemd user services on home-manager activation
  # This is now the default in newer home-manager, but we set it explicitly
  systemd.user.startServices = "sd-switch";

  # Enable XDG base directories and desktop entries
  xdg.enable = true;
  # MIME associations are fully managed in firefox.nix when Firefox is enabled
  # No need for duplicate configuration here

  home.sessionVariables = sessionConfig;

  # Add ~/.local/bin to PATH for user scripts and CLI tools
  # Include /run/wrappers/bin explicitly to ensure setuid wrappers (sudo, etc.) are found
  home.sessionPath = [
    "/run/wrappers/bin"  # CRITICAL: Must come first for setuid wrappers (sudo, doas, etc.)
    "$HOME/.local/bin"
  ];

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
