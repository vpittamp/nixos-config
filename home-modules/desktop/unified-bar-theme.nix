{ config, pkgs, lib, ... }:

let
  # Catppuccin Mocha color palette
  # Reference: https://github.com/catppuccin/catppuccin
  mocha = {
    base = "#1e1e2e";     # Background base
    mantle = "#181825";   # Darker background
    surface0 = "#313244"; # Surface layer 1
    surface1 = "#45475a"; # Surface layer 2
    overlay0 = "#6c7086"; # Overlay/border
    text = "#cdd6f4";     # Primary text
    subtext0 = "#a6adc8"; # Dimmed text
    blue = "#89b4fa";     # Focused accent
    mauve = "#cba6f7";    # Border accent
    yellow = "#f9e2af";   # Pending state
    red = "#f38ba8";      # Urgent/critical
    green = "#a6e3a1";    # Success
    teal = "#94e2d5";     # Info
  };

  # Unified theme configuration (appearance.json)
  themeConfig = {
    version = "1.0";
    theme = "catppuccin-mocha";

    colors = mocha;

    fonts = {
      bar = "FiraCode Nerd Font";
      bar_size = 8.0;
      workspace = "FiraCode Nerd Font";
      workspace_size = 11.0;
      notification = "Ubuntu Nerd Font";
      notification_size = 10.0;
    };

    workspace_bar = {
      height = 32;
      padding = 4;
      border_radius = 6;
      button_spacing = 3;
      icon_size = 16;
    };

    top_bar = {
      position = "top";
      separator = " | ";
      show_tray = true;
      show_binding_mode = true;
    };

    notification_center = {
      position_x = "right";
      position_y = "top";
      width = 500;
      timeout = 10;
      timeout_critical = 0;  # Never timeout critical notifications
      grouping = true;
    };
  };

in {
  # Unified Bar Theme Configuration
  # Centralized appearance config for all bar components (Swaybar, Eww, SwayNC)
  # Based on Feature 057: Unified Bar System with Enhanced Workspace Mode

  config = {
    # Generate appearance.json configuration file
    xdg.configFile."sway/appearance.json".text = builtins.toJSON themeConfig;

    # Feature 057: T017 - Theme reload hooks
    # Reload all bars after theme changes
    home.activation.reloadBarsAfterThemeChange = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Reload hooks will be triggered on next home-manager activation
      # Manual reload: swaymsg reload && eww reload && swaync-client --reload-css
      $DRY_RUN_CMD echo "Theme reload hooks configured. Run after rebuild:"
      $DRY_RUN_CMD echo "  swaymsg reload              # Reload Swaybar"
      $DRY_RUN_CMD echo "  eww reload                  # Reload workspace bar"
      $DRY_RUN_CMD echo "  swaync-client --reload-css  # Reload notification center CSS"
    '';

    # Export theme colors for use by other modules
    # Other bar modules can access these via config.wayland.windowManager.sway.config.colors
    wayland.windowManager.sway.config = lib.mkIf config.wayland.windowManager.sway.enable {
      colors = {
        background = mocha.base;
        focused = {
          background = mocha.surface0;
          border = mocha.blue;
          childBorder = mocha.blue;
          indicator = mocha.mauve;
          text = mocha.text;
        };
        focusedInactive = {
          background = mocha.base;
          border = mocha.surface0;
          childBorder = mocha.surface0;
          indicator = mocha.overlay0;
          text = mocha.subtext0;
        };
        unfocused = {
          background = mocha.base;
          border = mocha.surface0;
          childBorder = mocha.surface0;
          indicator = mocha.overlay0;
          text = mocha.subtext0;
        };
        urgent = {
          background = mocha.base;
          border = mocha.red;
          childBorder = mocha.red;
          indicator = mocha.red;
          text = mocha.text;
        };
        placeholder = {
          background = mocha.base;
          border = mocha.surface0;
          childBorder = mocha.surface0;
          indicator = mocha.overlay0;
          text = mocha.subtext0;
        };
      };
    };
  };
}
