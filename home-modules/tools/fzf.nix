{ config, pkgs, lib, ... }:

{
  # FZF with embedded Catppuccin Mocha colors
  programs.fzf = {
    enable = true;
    # Full bash integration: Ctrl+R (history), Ctrl+P (files), Alt+C (dirs)
    enableBashIntegration = true;

    # Use fzf's built-in --walker for file searching
    # walker is fast, respects .gitignore, and is built into fzf
    # Note: Commands are set to empty to trigger fzf's built-in walker
    # Walker options are configured via FZF_*_OPTS in bash.nix
    defaultCommand = "";
    changeDirWidgetCommand = "";
    fileWidgetCommand = "";


    defaultOptions = [
      # Tmux integration - use centered popup like clipboard history
      # center = floating popup in middle of screen (like clipcat-fzf)
      # 90% width, 80% height for good visibility
      "--tmux=center,90%,80%"

      # When not in tmux, use these settings
      "--height=40%"
      "--layout=reverse"
      "--border=rounded"

      # Info display
      "--info=inline"

      # Better scoring for file paths
      "--scheme=path"

      # Catppuccin Mocha colors
      "--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8"
      "--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc"
      "--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
    ];

    # Tmux integration
    # enableShellIntegration required by sesh
    # --tmux flag in defaultOptions provides automatic popup behavior
    tmux = {
      enableShellIntegration = true;
    };
  };
}