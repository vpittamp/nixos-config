# Alacritty Terminal Emulator Configuration
# Implements FR-024 through FR-027
{ config, lib, pkgs, ... }:

{
  programs.alacritty = {
    enable = true;

    settings = {
      # Terminal environment (FR-025)
      env.TERM = "xterm-256color";

      # Font configuration (FR-058)
      font = {
        normal = {
          family = "FiraCode Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "FiraCode Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "FiraCode Nerd Font";
          style = "Italic";
        };
        size = 9.0;
      };

      # Window configuration (FR-062)
      window = {
        padding = {
          x = 2;
          y = 2;
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

      # Catppuccin Mocha color scheme (FR-059)
      colors = {
        primary = {
          background = "#1e1e2e";
          foreground = "#cdd6f4";
        };

        cursor = {
          text = "#1e1e2e";
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
      ];
    };
  };

  # Set as default terminal (FR-024)
  home.sessionVariables = {
    TERMINAL = "alacritty";
  };
}
