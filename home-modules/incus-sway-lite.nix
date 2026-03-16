# Home-manager profile for Incus Sway Lite VMs
# Includes Sway + i3pm/worktree + terminal/tmux + local OTEL AI monitoring.
{ pkgs, lib, ... }:
{
  imports = [
    # Shell + terminal core
    ./shell/bash.nix
    ./shell/starship.nix
    ./shell/colors.nix
    ./terminal/tmux.nix
    ./terminal/sesh.nix
    ./terminal/ghostty.nix
    ./terminal/xresources.nix

    # Core editor/tools
    ./editors/neovim.nix
    ./tools/git.nix
    ./tools/ssh.nix
    ./tools/nix.nix
    ./tools/fzf.nix
    ./tools/bat.nix
    ./tools/direnv.nix
    ./tools/yazi.nix

    # Desktop + sway stack
    ./desktop/python-environment.nix
    ./desktop/sway.nix
    ./desktop/unified-bar-theme.nix
    ./desktop/quickshell-runtime-shell.nix
    ./desktop/quickshell-worktree-app.nix
    ./desktop/eww-top-bar.nix
    ./desktop/swaync.nix
    ./desktop/sway-config-manager.nix

    # Project/worktree management
    ./services/i3-project-daemon.nix
    ./tools/i3pm-deno.nix
    ./tools/i3pm-diagnostic.nix
    # Launcher + app registry
    ./desktop/walker.nix
    ./desktop/app-registry.nix
    ./tools/pwa-launcher.nix

    # Local AI monitoring stack (lightweight)
    ./services/otel-ai-monitor.nix
    # Keep heavy AI CLIs out of the base image; install on-demand when needed.
    # ./ai-assistants/claude-code.nix
    # ./ai-assistants/codex.nix
    # Keep Gemini/nix-ai-help out of the baked image; it is very large and
    # can stall disk-image cptofs. Install on-demand inside the VM instead.

    # Keep user home clean across rebuild cycles
    ./profiles/declarative-cleanup.nix
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";
  home.stateVersion = "25.05";
  home.enableNixpkgsReleaseCheck = false;

  programs.home-manager.enable = true;
  systemd.user.startServices = "sd-switch";
  xdg.enable = true;

  home.sessionPath = [
    "/run/wrappers/bin"
    "$HOME/.local/bin"
  ];

  home.packages = with pkgs; [
    ripgrep
    fd
    eza
    zoxide
    tree
    htop
    btop
    jq
    yq
    curl
    wget
    wl-clipboard
    grim
    slurp
    swaylock
    swayidle
  ];

  # i3-msg → swaymsg compatibility symlink
  home.file.".local/bin/i3-msg" = {
    source = "${pkgs.sway}/bin/swaymsg";
    executable = true;
  };

  # Explicitly force headless Sway mode for Incus VM image behavior.
  programs.sway-profile.mode = "headless";

  programs.i3-project-daemon = {
    enable = true;
    logLevel = "INFO";
  };

  # Lightweight AI monitoring: local-only service, no remote push/sink.
  services.otel-ai-monitor = {
    enable = true;
    port = 4318;
    enableNotifications = false;
    remoteSink.enable = false;
    remotePush.enable = false;
  };

  programs.sway-config-manager = {
    enable = true;
    enableFileWatcher = true;
    debounceMs = 500;
  };

  programs.quickshell-runtime-shell.enable = true;
  programs.quickshell-worktree-app.enable = true;
  programs.eww-top-bar.enable = true;
}
