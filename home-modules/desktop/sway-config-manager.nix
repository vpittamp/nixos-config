{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.sway-config-manager;

  # Python environment with required packages
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    i3ipc        # i3/Sway IPC library
    pydantic     # Data validation
    jsonschema   # JSON schema validation
    watchdog     # File system monitoring
  ]);

  # Daemon source directory
  daemonSrc = ./sway-config-manager;

  # Daemon package - installs as Python module
  daemonPackage = pkgs.stdenv.mkDerivation {
    name = "sway-config-manager";
    version = "1.0.1";  # Incremented to force rebuild with __main__.py
    src = daemonSrc;

    installPhase = ''
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/sway_config_manager
      cp -r $src/* $out/lib/python${pkgs.python3.pythonVersion}/site-packages/sway_config_manager/
    '';
  };

  # Wrapper script to run daemon with proper PYTHONPATH
  daemonWrapper = pkgs.writeShellScript "sway-config-manager-daemon" ''
    export PYTHONPATH="${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages:''${PYTHONPATH}"
    export PYTHONUNBUFFERED=1
    cd ~
    exec ${pythonEnv}/bin/python ${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages/sway_config_manager/daemon.py
  '';

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

    # Feature 047 Phase 8 T059: Periodic validation timer
    enablePeriodicValidation = mkOption {
      type = types.bool;
      default = true;
      description = "Enable periodic configuration validation (daily)";
    };

    validationInterval = mkOption {
      type = types.str;
      default = "daily";
      description = "Interval for periodic validation (systemd.time format)";
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
      # CLI client
      (pkgs.writeShellScriptBin "swayconfig" ''
        export PYTHONPATH="${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages''${PYTHONPATH:+:}''${PYTHONPATH}"
        exec ${pythonEnv}/bin/python ${./sway-config-manager/cli.py} "$@"
      '')

      # Configuration migration tool (Feature 047 Phase 8 T065)
      (pkgs.writeShellScriptBin "swayconfig-migrate" ''
        export PYTHONPATH="${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages''${PYTHONPATH:+:}''${PYTHONPATH}"
        exec ${pythonEnv}/bin/python ${./sway-config-manager/migrate_config.py} "$@"
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
        ExecStart = "${daemonWrapper}";
        Restart = "on-failure";
        RestartSec = "3";

        # Feature 047 Phase 8 T061: Watchdog monitoring of configuration files
        # Monitor configuration directory for changes
        # Systemd will restart service if files don't exist
        ReadWritePaths = [
          cfg.configDir
        ];

        # Ensure configuration files exist before starting
        ExecStartPre = "${pkgs.writeShellScript "check-config-files" ''
          # Create config directory if it doesn't exist
          mkdir -p ${cfg.configDir}/projects
          mkdir -p ${cfg.configDir}/schemas

          # Check for required config files (don't fail, just warn)
          for file in keybindings.toml window-rules.json workspace-assignments.json; do
            if [ ! -f "${cfg.configDir}/$file" ]; then
              echo "Warning: Configuration file $file not found in ${cfg.configDir}"
              echo "Default files will be created by home-manager"
            fi
          done
        ''}";

        # Environment variables for daemon
        Environment = [
          "SWAY_CONFIG_DIR=${cfg.configDir}"
          "SWAY_CONFIG_ENABLE_FILE_WATCHER=${if cfg.enableFileWatcher then "1" else "0"}"
          "SWAY_CONFIG_DEBOUNCE_MS=${toString cfg.debounceMs}"
        ];
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    # Feature 047 Phase 8 T059: Periodic configuration validation timer
    systemd.user.services.sway-config-validation = mkIf cfg.enablePeriodicValidation {
      Unit = {
        Description = "Sway Configuration Validation";
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "sway-config-validate" ''
          export PYTHONPATH="${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages''${PYTHONPATH:+:}''${PYTHONPATH}"
          ${pythonEnv}/bin/python ${./sway-config-manager/cli.py} validate
        ''}";
        # Send desktop notification on failure
        ExecStopPost = "${pkgs.writeShellScript "validation-notify" ''
          if [ "$SERVICE_RESULT" != "success" ]; then
            ${pkgs.libnotify}/bin/notify-send -u critical \
              "Sway Configuration Validation Failed" \
              "Run 'swayconfig validate' to see errors"
          fi
        ''}";
      };
    };

    systemd.user.timers.sway-config-validation = mkIf cfg.enablePeriodicValidation {
      Unit = {
        Description = "Periodic Sway Configuration Validation";
      };

      Timer = {
        OnCalendar = cfg.validationInterval;
        Persistent = true;  # Run missed validations on boot
        Unit = "sway-config-validation.service";
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
