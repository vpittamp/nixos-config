{ config, lib, pkgs, sharedPythonEnv, ... }:

with lib;

let
  cfg = config.programs.sway-config-manager;

  # Note: Python environment is provided by python-environment.nix (shared environment)
  # sharedPythonEnv = sharedPythonEnv;  # No longer needed - use sharedPythonEnv directly

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
    exec ${sharedPythonEnv}/bin/python ${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages/sway_config_manager/daemon.py
  '';

  # Default keybindings file (external TOML file for easier maintenance)
  defaultKeybindingsPath = ./sway-default-keybindings.toml;

  defaultAppearancePath = ./sway-default-appearance.json;

  # Legacy workspace mode handler removed (Feature 042)
  # Workspace mode now uses daemon IPC via i3pm CLI commands
  # See modesConfContents below for new implementation

  modesConfContents = ''
    # Sway Modes Configuration
    # Feature 042: Event-Driven Workspace Mode Navigation
    # Digit accumulation and workspace switching via daemon IPC

    # Goto workspace mode - Type digits to switch workspace
    # Feature 042 - T035: Pango markup for native mode indicator
    mode "→ WS" {
        # Digit input (calls daemon via i3pm CLI)
        bindsym 0 exec i3pm-workspace-mode digit 0
        bindsym 1 exec i3pm-workspace-mode digit 1
        bindsym 2 exec i3pm-workspace-mode digit 2
        bindsym 3 exec i3pm-workspace-mode digit 3
        bindsym 4 exec i3pm-workspace-mode digit 4
        bindsym 5 exec i3pm-workspace-mode digit 5
        bindsym 6 exec i3pm-workspace-mode digit 6
        bindsym 7 exec i3pm-workspace-mode digit 7
        bindsym 8 exec i3pm-workspace-mode digit 8
        bindsym 9 exec i3pm-workspace-mode digit 9

        # Execute switch (daemon handles workspace switch + output focus + mode exit)
        bindsym Return exec i3pm-workspace-mode execute
        bindsym KP_Enter exec i3pm-workspace-mode execute

        # Cancel/exit mode
        bindsym Escape exec i3pm-workspace-mode cancel
    }

    # Move window to workspace mode - Type digits to move window
    # Feature 042 - T035: Pango markup for native mode indicator
    mode "⇒ WS" {
        # Digit input (shared accumulation state with goto mode)
        bindsym 0 exec i3pm-workspace-mode digit 0
        bindsym 1 exec i3pm-workspace-mode digit 1
        bindsym 2 exec i3pm-workspace-mode digit 2
        bindsym 3 exec i3pm-workspace-mode digit 3
        bindsym 4 exec i3pm-workspace-mode digit 4
        bindsym 5 exec i3pm-workspace-mode digit 5
        bindsym 6 exec i3pm-workspace-mode digit 6
        bindsym 7 exec i3pm-workspace-mode digit 7
        bindsym 8 exec i3pm-workspace-mode digit 8
        bindsym 9 exec i3pm-workspace-mode digit 9

        # Execute move (daemon handles move + follow + output focus + mode exit)
        bindsym Return exec i3pm-workspace-mode execute
        bindsym KP_Enter exec i3pm-workspace-mode execute

        # Cancel/exit mode
        bindsym Escape exec i3pm-workspace-mode cancel
    }
  '';

  scratchpadToggleScript = pkgs.writeShellScript "scratchpad-terminal-toggle.sh" ''
    set -euo pipefail

    JQ=${pkgs.jq}/bin/jq
    SWAYMSG=${pkgs.sway}/bin/swaymsg
    ALACRITTY=${pkgs.alacritty}/bin/alacritty

    PROJECT_INFO='{}'
    if command -v i3pm >/dev/null 2>&1; then
      if PROJECT_JSON=''$(i3pm project current --json 2>/dev/null); then
        PROJECT_INFO=''$PROJECT_JSON
      fi
    fi

    PROJECT_NAME=''$(echo "''$PROJECT_INFO" | "''$JQ" -r '.name // empty' 2>/dev/null || echo "")
    PROJECT_DIR=''$(echo "''$PROJECT_INFO" | "''$JQ" -r '.directory // empty' 2>/dev/null || echo "")
    DISPLAY_NAME=''$(echo "''$PROJECT_INFO" | "''$JQ" -r '.display_name // empty' 2>/dev/null || echo "")

    if [[ -z "''$PROJECT_NAME" ]]; then
      SCOPE="global"
      SLUG="global"
      FRIENDLY="Global"
    else
      SCOPE="project"
      SLUG=''$(printf '%s' "''$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/--+/-/g')
      if [[ -z "''$SLUG" ]]; then
        SLUG="project"
      fi
      if [[ -n "''$DISPLAY_NAME" ]]; then
        FRIENDLY="''$DISPLAY_NAME"
      else
        FRIENDLY="''$PROJECT_NAME"
      fi
    fi

    APP_ID="scratchpad-terminal-''${SLUG}"
    TITLE="Scratchpad (''${FRIENDLY})"

    get_tree() {
      "''$SWAYMSG" -r -t get_tree
    }

    TREE=''$(get_tree)

    if printf '%s\n' "''$TREE" | "''$JQ" -e --arg id "''$APP_ID" 'recurse(.nodes[]?, .floating_nodes[]?) | select(.app_id == ''$id)' >/dev/null; then
      if printf '%s\n' "''$TREE" | "''$JQ" -e --arg id "''$APP_ID" 'recurse(.nodes[]?, .floating_nodes[]?) | select(.app_id == ''$id) | (.scratchpad_state != "none")' >/dev/null; then
        "''$SWAYMSG" "[app_id=\"^''${APP_ID}$\"] scratchpad show" >/dev/null
      else
        "''$SWAYMSG" "[app_id=\"^''${APP_ID}$\"] move scratchpad" >/dev/null
      fi
      exit 0
    fi

    SESSION_DIR="''$PROJECT_DIR"
    if [[ -z "''$SESSION_DIR" ]]; then
      SESSION_DIR="''$HOME"
    fi

    if command -v sesh >/dev/null 2>&1; then
      TERMINAL_CMD=(sesh connect "''$SESSION_DIR")
    else
      TERMINAL_CMD=(bash -lc "cd \"''$SESSION_DIR\" && exec ''${SHELL:-bash}")
    fi

    (
      export I3PM_APP_ID="''$APP_ID"
      export I3PM_APP_NAME="scratchpad-terminal"
      export I3PM_PROJECT_NAME="''$PROJECT_NAME"
      export I3PM_PROJECT_DIR="''$SESSION_DIR"
      export I3PM_PROJECT_DISPLAY_NAME="''$DISPLAY_NAME"
      export I3PM_SCOPE="''$SCOPE"
      export I3PM_ACTIVE=''$([[ "''$SCOPE" == "project" ]] && echo "true" || echo "false")
      export I3PM_LAUNCH_TIME="''$(date +%s)"
      export I3PM_LAUNCHER_PID="''$$"
      if command -v sesh >/dev/null 2>&1; then
        "''${ALACRITTY}" --class "''$APP_ID" --title "''$TITLE" -e sesh connect "''$SESSION_DIR" >/dev/null 2>&1 &
      else
        "''${ALACRITTY}" --class "''$APP_ID" --title "''$TITLE" -e bash -lc "cd \"''$SESSION_DIR\" && exec ''${SHELL:-bash}" >/dev/null 2>&1 &
      fi
    )

    for _ in ''$(seq 1 50); do
      sleep 0.05
      if get_tree | "''$JQ" -e --arg id "''$APP_ID" 'recurse(.nodes[]?, .floating_nodes[]?) | select(.app_id == ''$id)' >/dev/null; then
        "''$SWAYMSG" "[app_id=\"^''${APP_ID}$\"] scratchpad show" >/dev/null
        exit 0
      fi
    done

    echo "scratchpad-terminal-toggle: Timed out waiting for terminal window" >&2
    exit 1
  '';

  defaultWindowRules = ''
    {
      "version": "1.0",
      "rules": [
        {
          "id": "scratchpad-terminal",
          "source": "nix",
          "scope": "global",
          "priority": 50,
          "criteria": {
            "app_id": "^scratchpad-terminal(-[a-z0-9-]+)?$"
          },
          "actions": [
            "floating enable",
            "resize set width 1400 px height 850 px",
            "move position center",
            "move scratchpad"
          ]
        }
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
    # Following home-manager best practices for mutable user-editable files:
    # - Don't manage editable config files with home-manager (creates read-only symlinks)
    # - Store immutable templates that daemon copies on first run
    # - Let users edit actual config files without nixos-rebuild
    # Reference: https://www.foodogsquared.one/posts/2023-03-24-managing-mutable-files-in-nixos/
    home.file = {
      # Create projects directory
      ".config/sway/projects/.keep" = {
        text = "";
      };

      # Create schemas directory for JSON schemas
      ".config/sway/schemas/.keep" = {
        text = "";
      };

      # Ensure scripts directory exists (symlink-friendly)
      ".config/sway/scripts/.keep" = {
        text = "";
      };

      # Store default templates (immutable, in Nix store)
      # Daemon will copy these to ~/.config/sway/ on first run if files don't exist
      ".local/share/sway-config-manager/templates/keybindings.toml" = {
        source = defaultKeybindingsPath;
      };

      ".local/share/sway-config-manager/templates/window-rules.json" = {
        text = defaultWindowRules;
      };

      ".local/share/sway-config-manager/templates/workspace-assignments.json" = {
        text = defaultWorkspaceAssignments;
      };

      ".local/share/sway-config-manager/templates/appearance.json" = {
        source = defaultAppearancePath;
      };

      # Project-aware scratchpad toggle script
      ".config/sway/scripts/scratchpad-terminal-toggle.sh" = {
        source = scratchpadToggleScript;
        executable = true;
      };

      # Legacy workspace mode handler removed (Feature 042)
      # Workspace mode now uses daemon IPC via i3pm CLI commands

      # Workspace modes configuration
      ".config/sway/modes.conf" = {
        text = modesConfContents;
      };

      ".local/share/sway-config-manager/templates/.gitignore" = {
        text = ''
          # Exclude backup directories from git tracking
          .backups/
          .config-version

          # Exclude generated Sway configuration files
          *-generated.conf

          # Exclude temporary files
          *.tmp
          *.swp
          *~
        '';
      };
    };

    # Python environment with dependencies
    home.packages = with pkgs; [
      # CLI client
      (pkgs.writeShellScriptBin "swayconfig" ''
        export PYTHONPATH="${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages''${PYTHONPATH:+:}''${PYTHONPATH}"
        exec ${sharedPythonEnv}/bin/python ${./sway-config-manager/cli.py} "$@"
      '')

      # Configuration migration tool (Feature 047 Phase 8 T065)
      (pkgs.writeShellScriptBin "swayconfig-migrate" ''
        export PYTHONPATH="${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages''${PYTHONPATH:+:}''${PYTHONPATH}"
        exec ${sharedPythonEnv}/bin/python ${./sway-config-manager/migrate_config.py} "$@"
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
        # Following home-manager best practices: Copy templates to writable location on first run
        ExecStartPre = "${pkgs.writeShellScript "check-config-files" ''
          # Create config directory if it doesn't exist
          mkdir -p ${cfg.configDir}/projects
          mkdir -p ${cfg.configDir}/schemas

          # Template directory (immutable, in Nix store)
          TEMPLATE_DIR="$HOME/.local/share/sway-config-manager/templates"

          # Copy template files to config directory if they don't exist
          # This allows users to edit files without nixos-rebuild
          for file in keybindings.toml window-rules.json workspace-assignments.json appearance.json .gitignore; do
            if [ ! -f "${cfg.configDir}/$file" ]; then
              if [ -f "$TEMPLATE_DIR/$file" ]; then
                echo "Creating initial config file: ${cfg.configDir}/$file (from template)"
                cp "$TEMPLATE_DIR/$file" "${cfg.configDir}/$file"
                chmod 644 "${cfg.configDir}/$file"
              else
                echo "Warning: Template file $file not found in $TEMPLATE_DIR"
              fi
            fi
          done

          mkdir -p ${cfg.configDir}/scripts

          # Ensure generated config placeholders exist to avoid include errors on first launch
          for generated in keybindings-generated.conf appearance-generated.conf; do
            if [ ! -f "${cfg.configDir}/$generated" ]; then
              echo "Creating placeholder: ${cfg.configDir}/$generated"
              printf "# Managed by sway-config-manager\n" > "${cfg.configDir}/$generated"
              chmod 644 "${cfg.configDir}/$generated"
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
          ${sharedPythonEnv}/bin/python ${./sway-config-manager/cli.py} validate
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
