# Contract Schema: Clipcat Clipboard Manager Configuration
# Module: home-modules/tools/clipcat.nix
# Purpose: Define the configuration contract for Clipcat clipboard history

{ lib, ... }:

{
  # Clipcat clipboard manager configuration
  services.clipcat = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Clipcat clipboard manager with history";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.clipcat;
      description = "Clipcat package to use";
    };

    daemonSettings = {
      daemonize = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run clipcat daemon in background";
      };

      max_history = lib.mkOption {
        type = lib.types.ints.between 10 1000;
        default = 100;
        description = "Maximum number of clipboard entries to store (FR-017: min 50)";
      };

      history_file_path = lib.mkOption {
        type = lib.types.str;
        default = "$HOME/.cache/clipcat/clipcatd-history";
        description = "Path to persistent clipboard history file";
      };

      watcher = {
        enable_clipboard = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Monitor X11 CLIPBOARD selection (Ctrl+C/V) - FR-034";
        };

        enable_primary = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Monitor X11 PRIMARY selection (mouse select/middle-click) - FR-034";
        };

        primary_threshold_ms = lib.mkOption {
          type = lib.types.int;
          default = 5000;
          description = "Minimum time (ms) before updating PRIMARY selection history";
        };

        denied_text_regex_patterns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            # Password patterns (16-128 chars with complexity)
            "^[A-Za-z0-9!@#$%^&*()_+\\-=\\[\\]{}|;:,.<>?]{16,128}$"
            # Credit card numbers
            "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b"
            # SSH private keys
            "-----BEGIN.*PRIVATE KEY-----"
            # API tokens/secrets
            "(?i)(api[_-]?key|api[_-]?secret|token|bearer)[\\s:=]+[A-Za-z0-9_\\-]+"
            # JWT tokens
            "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"
            # AWS keys
            "AKIA[0-9A-Z]{16}"
            # GitHub tokens
            "gh[ps]_[A-Za-z0-9]{36,}"
          ];
          description = ''
            Regex patterns for sensitive content to exclude from clipboard history (FR-034b).
            Clipboard entries matching these patterns will be rejected.
          '';
        };

        filter_text_min_length = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Minimum text length to capture";
        };

        filter_text_max_length = lib.mkOption {
          type = lib.types.int;
          default = 20000000;  # 20MB
          description = "Maximum text length to capture (FR-034a)";
        };

        filter_image_max_size = lib.mkOption {
          type = lib.types.int;
          default = 5242880;  # 5MB
          description = "Maximum image size in bytes to capture";
        };

        sensitive_mime_types = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "MIME types to exclude from clipboard history";
          example = [ "image/svg+xml" "application/x-509-ca-cert" ];
        };
      };

      capture_image = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Capture image content in clipboard history";
      };
    };

    menuSettings = {
      finder = lib.mkOption {
        type = lib.types.enum [ "rofi" "dmenu" "custom" ];
        default = "rofi";
        description = "Application launcher to use for clipboard menu";
      };

      rofi_config_path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to custom rofi configuration";
        example = "$HOME/.config/rofi/config.rasi";
      };

      finder_args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional arguments for the finder command";
        example = [ "-dmenu" "-p" "Clipboard" "-theme" "clipboard" ];
      };
    };
  };

  # Integration with i3wm
  programs.i3 = {
    keybindings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "i3wm keybindings for clipboard operations";
      example = {
        "$mod+v" = "exec clipcat-menu";              # Open clipboard menu (FR-031)
        "$mod+Shift+v" = "exec clipctl clear";       # Clear clipboard history (FR-034c)
      };
    };
  };

  # Validation assertions
  config = lib.mkIf config.services.clipcat.enable {
    assertions = [
      {
        assertion = config.services.clipcat.daemonSettings.max_history >= 50;
        message = "clipcat max_history must be at least 50 (SC-017)";
      }
      {
        assertion =
          config.services.clipcat.daemonSettings.watcher.enable_clipboard ||
          config.services.clipcat.daemonSettings.watcher.enable_primary;
        message = "At least one of enable_clipboard or enable_primary must be true (FR-034)";
      }
      {
        assertion =
          config.services.xserver.enable or false;
        message = "Clipcat requires X11 display server (services.xserver.enable)";
      }
    ];
  };
}
