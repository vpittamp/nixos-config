{ config, pkgs, lib, ... }:

{
  # FZF with embedded Catppuccin Mocha colors
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;

    # Use fd for faster file searching (replaces default find command)
    # fd is smarter - respects .gitignore and ignores .git directories
    defaultCommand = "${pkgs.fd}/bin/fd --type f --hidden --exclude .git";

    # Also use fd when triggered with ALT-C (directory search)
    changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type d --hidden --exclude .git";

    # Use fd for CTRL-P (file search) - remapped from CTRL-T in bash.nix
    fileWidgetCommand = "${pkgs.fd}/bin/fd --type f --hidden --exclude .git";

    defaultOptions = [
      # Tmux integration - automatically use popup when inside tmux
      "--tmux=center,80%,70%"

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