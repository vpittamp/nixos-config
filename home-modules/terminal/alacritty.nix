{ config, pkgs, lib, ... }:

{
  programs.alacritty = {
    enable = true;

    settings = {
      # Font configuration
      font = {
        size = 11.0;
      };

      # Color scheme - VS Code Dark+ inspired for maximum visibility
      colors = {
        primary = {
          background = "#1e1e1e";
          foreground = "#d4d4d4";
        };

        normal = {
          black   = "#000000";
          red     = "#cd3131";
          green   = "#0dbc79";
          yellow  = "#e5e510";
          blue    = "#2472c8";
          magenta = "#bc3fbc";
          cyan    = "#11a8cd";
          white   = "#e5e5e5";
        };

        bright = {
          black   = "#666666";
          red     = "#f14c4c";
          green   = "#23d18b";
          yellow  = "#f5f543";
          blue    = "#3b8eea";
          magenta = "#d670d6";
          cyan    = "#29b8db";
          white   = "#ffffff";
        };
      };

      # Window settings
      window = {
        opacity = 1.0;  # No transparency
        decorations = "full";
      };

      # Scrolling
      scrolling = {
        history = 10000;
        multiplier = 3;
      };

      # Cursor
      cursor = {
        style = {
          shape = "Block";
          blinking = "Off";
        };
      };
    };
  };
}
