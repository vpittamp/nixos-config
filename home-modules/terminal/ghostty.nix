# Ghostty Terminal Emulator Configuration
# Modern GPU-accelerated terminal with native tabs and splits
{ config, lib, pkgs, ... }:

{
  imports = [ ./terminal-defaults.nix ];

  programs.ghostty = {
    enable = true;

    settings = {
      # Font configuration - using centralized terminal defaults
      font-family = config.terminal.defaults.font.family;
      font-size = config.terminal.defaults.font.size;

      # Theme - Catppuccin Mocha colors (using centralized defaults)
      background = config.terminal.defaults.colors.background;
      foreground = config.terminal.defaults.colors.foreground;

      # Window configuration - using centralized defaults
      window-padding-x = config.terminal.defaults.padding.x;
      window-padding-y = config.terminal.defaults.padding.y;

      # Clipboard
      clipboard-read = "allow";
      clipboard-write = "allow";

      # Mouse
      mouse-hide-while-typing = true;

      # Scroll sensitivity - reduce for more precise scrolling
      # Default multiplier is 1.0, reduce to 0.3 for finer control
      mouse-scroll-multiplier = 0.3;

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
