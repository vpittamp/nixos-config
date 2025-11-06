# Terminal Default Configuration
# Centralized font and styling settings shared across terminal emulators
{ lib, ... }:

{
  options.terminal.defaults = {
    font = {
      family = lib.mkOption {
        type = lib.types.str;
        default = "FiraCode Nerd Font";
        description = "Default font family for all terminal emulators";
      };

      size = lib.mkOption {
        type = lib.types.number;
        default = 9;
        description = "Default font size for all terminal emulators";
      };
    };

    padding = {
      x = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Horizontal padding in pixels";
      };

      y = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Vertical padding in pixels";
      };
    };

    colors = {
      # Catppuccin Mocha color scheme
      background = lib.mkOption {
        type = lib.types.str;
        default = "1e1e2e";
        description = "Terminal background color (hex without #)";
      };

      foreground = lib.mkOption {
        type = lib.types.str;
        default = "cdd6f4";
        description = "Terminal foreground/text color (hex without #)";
      };
    };
  };
}
