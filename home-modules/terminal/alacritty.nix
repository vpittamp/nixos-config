# Alacritty Terminal Emulator Configuration
# Implements FR-024 through FR-027
{ config, lib, pkgs, ... }:

{
  imports = [ ./terminal-defaults.nix ];

  programs.alacritty = {
    enable = true;

    settings = {
      # Terminal environment (FR-025)
      env.TERM = "xterm-256color";

      # Font configuration (FR-058) - using centralized terminal defaults
      font = {
        normal = {
          family = config.terminal.defaults.font.family;
          style = "Regular";
        };
        bold = {
          family = config.terminal.defaults.font.family;
          style = "Bold";
        };
        italic = {
          family = config.terminal.defaults.font.family;
          style = "Italic";
        };
        size = config.terminal.defaults.font.size;
      };

      # Window configuration (FR-062) - using centralized defaults
      window = {
        padding = {
          x = config.terminal.defaults.padding.x;
          y = config.terminal.defaults.padding.y;
        };
        decorations = "full";
        dynamic_title = true;
        opacity = 1.0;
      };

      # Clipboard integration (FR-060, FR-028)
      selection = {
        save_to_clipboard = true;
      };

      # Scrollback configuration (FR-061)
      scrolling = {
        history = 10000;
        multiplier = 3;
      };

      # Catppuccin Mocha color scheme (FR-059) - using centralized defaults
      colors = {
        primary = {
          background = "#${config.terminal.defaults.colors.background}";
          foreground = "#${config.terminal.defaults.colors.foreground}";
        };

        cursor = {
          text = "#${config.terminal.defaults.colors.background}";
          cursor = "#f5e0dc";
        };

        normal = {
          black = "#45475a";
          red = "#f38ba8";
          green = "#a6e3a1";
          yellow = "#f9e2af";
          blue = "#89b4fa";
          magenta = "#f5c2e7";
          cyan = "#94e2d5";
          white = "#bac2de";
        };

        bright = {
          black = "#585b70";
          red = "#f38ba8";
          green = "#a6e3a1";
          yellow = "#f9e2af";
          blue = "#89b4fa";
          magenta = "#f5c2e7";
          cyan = "#94e2d5";
          white = "#a6adc8";
        };
      };

      # Mouse configuration
      mouse = {
        hide_when_typing = true;
      };

      # Keyboard bindings - preserve compatibility with tmux (FR-025, FR-026)
      keyboard.bindings = [
        # Clipboard shortcuts
        { key = "V"; mods = "Control|Shift"; action = "Paste"; }
        { key = "C"; mods = "Control|Shift"; action = "Copy"; }

        # Clear screen (compatible with bash)
        { key = "L"; mods = "Control"; chars = "\\f"; }

        # Disable Alacritty's default Quit binding to allow i3 to handle window closing
        # This ensures Super+Shift+Q passes through to i3 for proper window management
        { key = "Q"; mods = "Super|Shift"; action = "None"; }
      ];
    };
  };

  # Note: Alacritty is now the default terminal application
  # Configured in app-registry-data.nix for project-scoped terminal sessions
}
