# i3 Project Manager - Dynamic Runtime Project Management
# Home Manager Module for i3-native project workspace management
#
# This module provides dynamic project management using i3's native features:
# - Runtime JSON configuration files (no rebuild required)
# - i3 marks for window-project association
# - i3 scratchpad for window visibility management
# - i3 tick events for real-time synchronization
# - i3 append_layout for workspace restoration
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.i3ProjectManager;

in
{
  options.programs.i3ProjectManager = {
    enable = mkEnableOption "i3 dynamic project workspace management";

    package = mkOption {
      type = types.package;
      default = pkgs.i3;
      description = "i3 package to use";
    };

    enableShellcheck = mkOption {
      type = types.bool;
      default = true;
      description = "Enable shellcheck validation for deployed scripts";
    };

    defaultAppClasses = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          scoped = mkOption {
            type = types.bool;
            description = "Whether this application is project-scoped";
          };
          workspace = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Default workspace assignment";
          };
          description = mkOption {
            type = types.str;
            default = "";
            description = "Human-readable description";
          };
        };
      });
      default = {
        Code = {
          scoped = true;
          workspace = 2;
          description = "VS Code editor";
        };
        Ghostty = {
          scoped = true;
          workspace = 1;
          description = "Ghostty terminal";
        };
        lazygit = {
          scoped = true;
          workspace = 7;
          description = "Lazygit git UI";
        };
        yazi = {
          scoped = true;
          workspace = 5;
          description = "Yazi file manager";
        };
        Firefox = {
          scoped = false;
          description = "Firefox browser (global)";
        };
        "^FFPWA-.*" = {
          scoped = false;
          description = "Firefox PWAs (global)";
        };
      };
      description = ''
        Default application class classifications.
        User can override by editing ~/.config/i3/app-classes.json
      '';
    };
  };

  config = mkIf cfg.enable {
    # T004: Shellcheck validation assertion
    assertions = [
      {
        assertion = cfg.enableShellcheck -> (pkgs.shellcheck != null);
        message = "Shellcheck validation enabled but shellcheck package not available";
      }
    ];

    # Ensure required packages are available
    home.packages = with pkgs; [
      jq          # JSON parsing
      xdotool     # Window ID retrieval
      rofi        # Project switcher UI
    ] ++ (if cfg.enableShellcheck then [ shellcheck ] else []);

    # Create directory structure
    home.file.".config/i3/projects/.keep".text = "# Project JSON files directory";
    home.file.".config/i3/launchers/.keep".text = "# Application launcher scripts";
    home.file.".config/i3/scripts/.keep".text = "# Project management scripts";

    # NOTE: active-project file is NOT managed by home-manager because it needs to be writable
    # It will be created on first use by the project management scripts

    # Generate default app-classes.json
    home.file.".config/i3/app-classes.json".text = builtins.toJSON {
      version = "1.0";
      classes = mapAttrsToList (class: config: {
        inherit class;
        scoped = config.scoped;
        workspace = config.workspace;
        description = config.description;
      }) cfg.defaultAppClasses;
    };

    # T002: Deploy common.sh shared library
    home.file.".config/i3/scripts/common.sh" = {
      executable = true;
      source = ./scripts/i3-project-common.sh;
    };

    # T009-T014: Deploy Phase 3 (US1) project management scripts
    home.file.".config/i3/scripts/project-create.sh" = {
      executable = true;
      source = ./scripts/project-create.sh;
    };

    home.file.".config/i3/scripts/project-delete.sh" = {
      executable = true;
      source = ./scripts/project-delete.sh;
    };

    home.file.".config/i3/scripts/project-list.sh" = {
      executable = true;
      source = ./scripts/project-list.sh;
    };

    home.file.".config/i3/scripts/project-switch.sh" = {
      executable = true;
      source = ./scripts/project-switch.sh;
    };

    home.file.".config/i3/scripts/project-clear.sh" = {
      executable = true;
      source = ./scripts/project-clear.sh;
    };

    home.file.".config/i3/scripts/project-current.sh" = {
      executable = true;
      source = ./scripts/project-current.sh;
    };

    # T017-T018: Deploy Phase 4 (US4) project management scripts
    home.file.".config/i3/scripts/project-validate.sh" = {
      executable = true;
      source = ./scripts/project-validate.sh;
    };

    home.file.".config/i3/scripts/project-edit.sh" = {
      executable = true;
      source = ./scripts/project-edit.sh;
    };

    # T024-T028: Deploy Phase 5 (US2) window management and launcher scripts
    home.file.".config/i3/scripts/project-mark-window.sh" = {
      executable = true;
      source = ./scripts/project-mark-window.sh;
    };

    home.file.".config/i3/scripts/launch-code.sh" = {
      executable = true;
      source = ./scripts/launch-code.sh;
    };

    home.file.".config/i3/scripts/launch-ghostty.sh" = {
      executable = true;
      source = ./scripts/launch-ghostty.sh;
    };

    home.file.".config/i3/scripts/launch-lazygit.sh" = {
      executable = true;
      source = ./scripts/launch-lazygit.sh;
    };

    home.file.".config/i3/scripts/launch-yazi.sh" = {
      executable = true;
      source = ./scripts/launch-yazi.sh;
    };

    # T037: Deploy Phase 6 (US3) polybar integration script
    home.file.".config/polybar/scripts/i3-project-indicator.py" = {
      executable = true;
      source = ./scripts/polybar-i3-project-indicator.py;
    };

    # T041: Deploy Phase 7 (US5) workspace output reassignment script
    home.file.".config/i3/scripts/reassign-workspaces.sh" = {
      executable = true;
      source = ./scripts/reassign-workspaces.sh;
    };

    # T048: Deploy Phase 9 rofi project switcher
    home.file.".config/i3/scripts/rofi-project-switcher.sh" = {
      executable = true;
      source = ./scripts/rofi-project-switcher.sh;
    };

    # T015: Create command-line symlinks in ~/.local/bin/
    home.file.".local/bin/i3-project-create".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-create.sh";
    home.file.".local/bin/i3-project-delete".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-delete.sh";
    home.file.".local/bin/i3-project-list".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-list.sh";
    home.file.".local/bin/i3-project-switch".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-switch.sh";
    home.file.".local/bin/i3-project-clear".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-clear.sh";
    home.file.".local/bin/i3-project-current".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-current.sh";

    # T022: Create symlinks for Phase 4 commands
    home.file.".local/bin/i3-project-validate".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-validate.sh";
    home.file.".local/bin/i3-project-edit".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-edit.sh";

    # T033: Create symlink for Phase 5 window marking
    home.file.".local/bin/i3-project-mark-window".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-mark-window.sh";
  };
}
