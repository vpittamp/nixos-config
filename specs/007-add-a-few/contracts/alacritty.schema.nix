# Contract Schema: Alacritty Terminal Emulator Configuration
# Module: home-modules/terminal/alacritty.nix
# Purpose: Define the configuration contract for Alacritty terminal emulator

{ lib, ... }:

{
  # Alacritty terminal emulator configuration
  programs.alacritty = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Alacritty terminal emulator (FR-024)";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.alacritty;
      description = "Alacritty package to use";
    };

    settings = {
      # Environment variables
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { TERM = "xterm-256color"; };
        description = ''
          Environment variables to set for terminal sessions.
          TERM should be xterm-256color to work with tmux terminal overrides.
        '';
      };

      # Font configuration
      font = {
        normal = {
          family = lib.mkOption {
            type = lib.types.str;
            default = "FiraCode Nerd Font";
            description = "Font family for normal text";
          };

          style = lib.mkOption {
            type = lib.types.str;
            default = "Regular";
            description = "Font style for normal text";
          };
        };

        size = lib.mkOption {
          type = lib.types.numbers.positive;
          default = 9.0;
          description = "Font size in points";
        };
      };

      # Window configuration
      window = {
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

        decorations = lib.mkOption {
          type = lib.types.enum [ "full" "none" "transparent" "buttonless" ];
          default = "full";
          description = "Window decoration mode (use 'full' for i3wm window management)";
        };

        dynamic_title = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Allow terminal to set window title";
        };
      };

      # Clipboard integration
      selection = {
        save_to_clipboard = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Automatically save text selection to clipboard.
            Essential for clipboard history integration (FR-028, FR-029).
          '';
        };
      };

      # Scrollback configuration
      scrolling = {
        history = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10000;
          description = "Number of lines in scrollback buffer";
        };

        multiplier = lib.mkOption {
          type = lib.types.int;
          default = 3;
          description = "Lines to scroll per scroll wheel step";
        };
      };

      # Color scheme (Catppuccin Mocha)
      colors = {
        primary = {
          background = lib.mkOption {
            type = lib.types.str;
            default = "#1e1e2e";
            description = "Primary background color";
          };

          foreground = lib.mkOption {
            type = lib.types.str;
            default = "#cdd6f4";
            description = "Primary foreground color";
          };
        };

        cursor = {
          text = lib.mkOption {
            type = lib.types.str;
            default = "#1e1e2e";
            description = "Cursor text color";
          };

          cursor = lib.mkOption {
            type = lib.types.str;
            default = "#f5e0dc";
            description = "Cursor background color";
          };
        };

        normal = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {
            black = "#45475a";
            red = "#f38ba8";
            green = "#a6e3a1";
            yellow = "#f9e2af";
            blue = "#89b4fa";
            magenta = "#f5c2e7";
            cyan = "#94e2d5";
            white = "#bac2de";
          };
          description = "Normal terminal colors";
        };

        bright = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {
            black = "#585b70";
            red = "#f38ba8";
            green = "#a6e3a1";
            yellow = "#f9e2af";
            blue = "#89b4fa";
            magenta = "#f5c2e7";
            cyan = "#94e2d5";
            white = "#a6adc8";
          };
          description = "Bright terminal colors";
        };
      };

      # Mouse bindings
      mouse = {
        hide_when_typing = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Hide mouse cursor when typing";
        };
      };

      # Keyboard bindings (optional overrides)
      keyboard = {
        bindings = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [];
          description = ''
            Custom keyboard bindings for Alacritty.
            Leave empty to use defaults compatible with tmux keybindings.
          '';
          example = [
            { key = "V"; mods = "Control|Shift"; action = "Paste"; }
            { key = "C"; mods = "Control|Shift"; action = "Copy"; }
          ];
        };
      };
    };
  };

  # Integration with i3wm
  programs.i3 = {
    defaultTerminal = lib.mkOption {
      type = lib.types.str;
      default = "alacritty";
      description = "Default terminal emulator for i3wm (FR-024)";
    };

    keybindings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "i3wm keybindings for terminal";
      example = {
        "$mod+Return" = "exec alacritty";                                    # Launch terminal (FR-024)
        "$mod+Shift+Return" = "exec alacritty --class floating_terminal";   # Floating terminal
      };
    };
  };

  # Environment variables for i3-sensible-terminal
  home.sessionVariables = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { TERMINAL = "alacritty"; };
    description = "Set TERMINAL environment variable for i3-sensible-terminal";
  };

  # Validation assertions
  config = lib.mkIf config.programs.alacritty.enable {
    assertions = [
      {
        assertion = config.programs.alacritty.settings.env.TERM == "xterm-256color";
        message = "Alacritty TERM should be 'xterm-256color' for tmux compatibility (FR-025)";
      }
      {
        assertion = config.programs.alacritty.settings.selection.save_to_clipboard == true;
        message = "Alacritty selection.save_to_clipboard should be true for clipboard integration (FR-028)";
      }
      {
        assertion =
          let
            fontExists = pkgs.lib.any
              (pkg: pkg.pname or "" == "fira-code" || pkg.name or "" == "fira-code")
              config.fonts.packages or [];
          in
          fontExists || config.programs.alacritty.settings.font.normal.family != "FiraCode Nerd Font";
        message = "Font family must be available in system fonts";
      }
    ];

    # Ensure compatibility with existing terminal tools
    programs.tmux.enable = lib.mkDefault true;  # FR-025: preserve tmux
    programs.bash.enable = lib.mkDefault true;  # FR-025: preserve bash
    # Note: sesh and Starship are assumed to be configured separately and remain unchanged
  };
}
