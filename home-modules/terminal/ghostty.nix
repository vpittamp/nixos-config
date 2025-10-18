# Ghostty Terminal Emulator Configuration
# Modern GPU-accelerated terminal with native tabs and splits
{ config, lib, pkgs, ... }:

{
  programs.ghostty = {
    enable = true;

    settings = {
      # Font configuration - matching Alacritty setup
      font-family = "FiraCode Nerd Font";
      font-size = 12;

      # Theme - Catppuccin Mocha colors (manual)
      background = "1e1e2e";
      foreground = "cdd6f4";

      # Window configuration
      window-padding-x = 2;
      window-padding-y = 2;

      # Clipboard
      clipboard-read = "allow";
      clipboard-write = "allow";

      # Mouse
      mouse-hide-while-typing = true;

      # Shell integration (Ghostty's killer feature)
      shell-integration = "detect";

      # Cursor
      cursor-style = "block";

      # Terminal type
      term = "xterm-256color";

      # Auto-update (disable on NixOS)
      auto-update = "off";

      # Window close behavior - don't prompt when closing
      confirm-close-surface = false;

      # Allow multiple independent instances (required for i3-projects)
      # "never" = each instance is independent (needed for multiple workspaces)
      # "single-instance" = reuses existing process (default)
      # "always" = uses cgroups for isolation
      linux-cgroup = "never";
    };
  };

  # Make Ghostty the default terminal globally
  home.sessionVariables = {
    TERMINAL = "ghostty";
    TERM_PROGRAM = "ghostty";
  };

  # Set Ghostty as the default terminal emulator in XDG MIME types
  # This ensures all applications that need to launch a terminal use Ghostty
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/terminal" = "ghostty.desktop";
      "application/x-terminal-emulator" = "ghostty.desktop";
    };
  };
}
