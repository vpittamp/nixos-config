{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.sway-config-manager;

  # Default configuration files
  defaultKeybindings = ''
    # Sway Keybindings Configuration
    # Managed by sway-config-manager
    # Source: runtime
    # Edit this file and run 'i3pm config reload' to apply changes

    [keybindings]
    # Example keybindings (these will be merged with Nix base config)
    # "Mod+Return" = { command = "exec terminal", description = "Open terminal" }
    # "Control+1" = { command = "workspace number 1", description = "Switch to workspace 1" }
  '';

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
        text = defaultKeybindings;
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
      (python311.withPackages (ps: with ps; [
        i3ipc
        pydantic
        jsonschema
        watchdog
      ]))

      # CLI client
      (pkgs.writeShellScriptBin "swayconfig" ''
        exec ${pkgs.python311.withPackages (ps: with ps; [
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
        ExecStart = "${pkgs.python311.withPackages (ps: with ps; [
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
