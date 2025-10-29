{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.sway-config-manager;

  # Default keybindings file (external TOML file for easier maintenance)
  defaultKeybindingsPath = ./sway-default-keybindings.toml;

  defaultWindowRules = ''
    {
      "version": "1.0",
      "rules": [
      ]
    }
  '';

  defaultWorkspaceAssignments = ''
    {
      "version": "1.0",
      "assignments": [
      ]
    }
  '';

in {
  options.programs.sway-config-manager = {
    enable = mkEnableOption "Sway dynamic configuration management";

    configDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.config/sway";
      description = "Directory for Sway configuration files";
    };

    enableFileWatcher = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic configuration reload on file changes";
    };

    debounceMs = mkOption {
      type = types.int;
      default = 500;
      description = "Debounce delay in milliseconds for file watcher";
    };
  };

  config = mkIf cfg.enable {
    # Create configuration directory structure
    home.file = {
      # Keybindings configuration
      ".config/sway/keybindings.toml" = {
        source = defaultKeybindingsPath;
        # Only create if doesn't exist (don't overwrite user changes)
        force = false;
      };

      # Window rules configuration
      ".config/sway/window-rules.json" = {
        text = defaultWindowRules;
        force = false;
      };

      # Workspace assignments configuration
      ".config/sway/workspace-assignments.json" = {
        text = defaultWorkspaceAssignments;
        force = false;
      };

      # Create projects directory
      ".config/sway/projects/.keep" = {
        text = "";
      };

      # Create schemas directory for JSON schemas
      ".config/sway/schemas/.keep" = {
        text = "";
      };
    };

    # Python environment with dependencies
    home.packages = with pkgs; [
      (python3.withPackages (ps: with ps; [
        i3ipc
        pydantic
        jsonschema
        watchdog
      ]))

      # CLI client
      (pkgs.writeShellScriptBin "swayconfig" ''
        exec ${pkgs.python3.withPackages (ps: with ps; [
          i3ipc pydantic jsonschema watchdog
        ])}/bin/python ${./sway-config-manager/cli.py} "$@"
      '')
    ];

    # Systemd user service for daemon
    systemd.user.services.sway-config-manager = mkIf cfg.enable {
      Unit = {
        Description = "Sway Configuration Manager Daemon";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.python3.withPackages (ps: with ps; [
          i3ipc pydantic jsonschema watchdog
        ])}/bin/python ${./sway-config-manager/daemon.py}";
        Restart = "on-failure";
        RestartSec = "3";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
