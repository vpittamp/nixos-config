{ config, pkgs, lib, inputs, osConfig, ... }:

let
  hostName =
    if osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else null;
  sessionConfig = {
    # Qt settings for Wayland
    QT_AUTO_SCREEN_SCALE_FACTOR = "1"; # Let Qt detect from Wayland
    QT_ENABLE_HIGHDPI_SCALING = "1"; # Enable HiDPI support
    PLASMA_USE_QT_SCALING = "1"; # Let Plasma handle Qt scaling

    # Cursor theme + base size. The Bibata theme (vs the bare unscaled default) is
    # what fixes the previously-tiny/blurry cursor; sway then scales it by each
    # output's scale, so this 24px base is ~60px on the Samsung 4K TV (scale 2.5)
    # and ~30px on the 1.25x panels — proportional without being oversized. Keep in
    # sync with the `seat * xcursor_theme` line in sway.nix.
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";

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
    ../terminal/herdr.nix
    ../terminal/ghostty.nix    # Ghostty terminal (default)

    # Desktop configurations
    # Event-driven daemon now managed by system service (Feature 037) - see configurations/thinkpad.nix
    ../tools/window-env.nix          # Helper to query window PIDs and environment variables

    # Editor configurations
    ../editors/neovim.nix
    ../tools/copilot-auth.nix        # GitHub Copilot authentication (1Password + hosts.json)
    ../tools/gh-aw.nix               # Register gh-aw as a `gh` CLI extension (xdg link)
    ../tools/gh-dash.nix             # GitHub PR/issues dashboard and gh extension link
    ../tools/gh-enhance.nix          # Register gh-enhance as a `gh` CLI extension (xdg link)
    ../tools/diffnav.nix             # GitHub-style diff pager and gh extension link

    # Tool configurations
    ../tools/git.nix
    ../tools/git-gtr.nix
    ../tools/ssh.nix
    ../tools/onepassword.nix
    ../tools/onepassword-env.nix
    ../tools/onepassword-plugins.nix
    ../tools/onepassword-autostart.nix
    ../tools/bat.nix
    ../tools/direnv.nix
    ../tools/fzf.nix
    ../tools/fzf-file-search.nix  # Floating fzf file search with nvim integration
    ../tools/htop.nix
    ../tools/btop.nix
    ../tools/chromium.nix # Enabled for Playwright MCP support
    ../tools/firefox.nix
    ../tools/docker.nix # Docker with 1Password authentication
    ../tools/pwa-helpers.nix  # PWA validation and helper commands (manual installation via Firefox GUI)
    ../tools/pwa-launcher.nix  # Dynamic PWA launcher with cross-machine compatibility
    ../tools/pwa-url-router.nix  # Feature 113: Route external URLs to PWAs by domain
    ../tools/clipcat.nix  # Clipboard history manager with X11 support (Feature 007)
    ../tools/lazygit.nix  # Terminal UI for Git and Docker
    ../tools/lazyworktree.nix  # Terminal UI for git worktree management
    ../tools/lazydocker.nix  # Lazydocker config with Gitea push commands
    ../tools/k9s.nix
    ../tools/yazi.nix
    ../tools/nix.nix
    ../tools/nix-bloat-audit.nix
    ../tools/vscode.nix
    ../tools/gitkraken.nix
    ../tools/postman.nix
    ../tools/kubernetes-apps.nix
    ../tools/remote-kubeconfig.nix
    ../tools/fleet-kubeconfigs.nix  # token-free tailnet kubectl access to fleet clusters
    ../tools/walker-commands.nix  # Dynamic command management for Walker (Feature 050)
    ../tools/voxtype.nix  # Push-to-talk speech-to-text config (Sway handles keybinding)

    # AI Assistant configurations
    ../ai-assistants/workflow-builder-mcp.nix
    ../ai-assistants/claude-code.nix
    ../ai-assistants/claude-code-glm.nix
    ../ai-assistants/codex.nix
    ../ai-assistants/browser-mcp-lifecycle.nix
    ../ai-assistants/copilot-cli.nix
    ../ai-assistants/antigravity-cli.nix
    ../ai-assistants/kimi-code.nix
    ../ai-assistants/nix-ai-help.nix
    ../ai-assistants/openshell.nix

    # External modules
    inputs.onepassword-shell-plugins.hmModules.default
  ];

  home.stateVersion = "25.05";
  home.enableNixpkgsReleaseCheck = false;

  home.packages =
    let
      userPackages = import ../../user/packages.nix { inherit pkgs lib inputs; };
    in
    userPackages.all ++ [ pkgs.papirus-icon-theme ];

  modules.tools.yazi.enable = true;
  modules.tools.fzf-file-search.enable = true;  # Floating fzf file search
  modules.tools.docker.enable = true; # Docker with 1Password integration
  modules.tools.remoteKubeconfig.enable = true;
  modules.tools.fleetKubeconfigs.enable = true;  # `sync-fleet-kubeconfigs` → token-free fleet kubectl over Tailscale
  modules.aiAssistants.workflowBuilderMcp.enable = builtins.elem hostName [ "ryzen" "thinkpad" ];
  programs.pwa-url-router.enable = false;  # Feature 113: DISABLED - using Chrome as default browser

  # VSCode profile configuration
  # All VSCode instances (including activity-aware launchers) use this profile
  # Use "default" to avoid home-manager warnings about mutableExtensionsDir and update checks
  modules.tools.vscode.defaultProfile = "default";

  programs.home-manager.enable = true;

  # Enable automatic restart of systemd user services on home-manager activation
  # This is now the default in newer home-manager, but we set it explicitly
  systemd.user.startServices = "sd-switch";

  # Enable XDG base directories and desktop entries
  xdg.enable = true;
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];
  };
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
