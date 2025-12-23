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

    # Goto workspace mode - Type digits to switch workspace OR letters for project
    # Feature 042 - T035: Pango markup for native mode indicator
    # Option A: Unified Smart Detection - digits=workspace, letters=project
    mode "→ WS" {
        # Digit input (calls daemon via i3pm CLI) - Workspace navigation
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

        # Letter input (Option A: Smart Detection) - Project navigation
        bindsym a exec i3pm-workspace-mode char a
        bindsym b exec i3pm-workspace-mode char b
        bindsym c exec i3pm-workspace-mode char c
        bindsym d exec i3pm-workspace-mode char d
        bindsym e exec i3pm-workspace-mode char e
        bindsym f exec i3pm-workspace-mode char f
        bindsym g exec i3pm-workspace-mode char g
        bindsym h exec i3pm-workspace-mode char h
        bindsym i exec i3pm-workspace-mode char i
        bindsym j exec i3pm-workspace-mode char j
        bindsym k exec i3pm-workspace-mode char k
        bindsym l exec i3pm-workspace-mode char l
        bindsym m exec i3pm-workspace-mode char m
        bindsym n exec i3pm-workspace-mode char n
        bindsym o exec i3pm-workspace-mode char o
        bindsym p exec i3pm-workspace-mode char p
        bindsym q exec i3pm-workspace-mode char q
        bindsym r exec i3pm-workspace-mode char r
        bindsym s exec i3pm-workspace-mode char s
        bindsym t exec i3pm-workspace-mode char t
        bindsym u exec i3pm-workspace-mode char u
        bindsym v exec i3pm-workspace-mode char v
        bindsym w exec i3pm-workspace-mode char w
        bindsym x exec i3pm-workspace-mode char x
        bindsym y exec i3pm-workspace-mode char y
        bindsym z exec i3pm-workspace-mode char z

        # Execute switch (daemon handles workspace/project switch + mode exit)
        bindsym Return exec i3pm-workspace-mode execute
        bindsym KP_Enter exec i3pm-workspace-mode execute

        # Cancel/exit mode
        bindsym Escape exec i3pm-workspace-mode cancel
    }

    # Move window to workspace mode - Type digits to move window OR letters for project
    # Feature 042 - T035: Pango markup for native mode indicator
    # Option A: Unified Smart Detection (move mode also supports project switching)
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

        # Letter input (Option A: Smart Detection) - Project navigation
        bindsym a exec i3pm-workspace-mode char a
        bindsym b exec i3pm-workspace-mode char b
        bindsym c exec i3pm-workspace-mode char c
        bindsym d exec i3pm-workspace-mode char d
        bindsym e exec i3pm-workspace-mode char e
        bindsym f exec i3pm-workspace-mode char f
        bindsym g exec i3pm-workspace-mode char g
        bindsym h exec i3pm-workspace-mode char h
        bindsym i exec i3pm-workspace-mode char i
        bindsym j exec i3pm-workspace-mode char j
        bindsym k exec i3pm-workspace-mode char k
        bindsym l exec i3pm-workspace-mode char l
        bindsym m exec i3pm-workspace-mode char m
        bindsym n exec i3pm-workspace-mode char n
        bindsym o exec i3pm-workspace-mode char o
        bindsym p exec i3pm-workspace-mode char p
        bindsym q exec i3pm-workspace-mode char q
        bindsym r exec i3pm-workspace-mode char r
        bindsym s exec i3pm-workspace-mode char s
        bindsym t exec i3pm-workspace-mode char t
        bindsym u exec i3pm-workspace-mode char u
        bindsym v exec i3pm-workspace-mode char v
        bindsym w exec i3pm-workspace-mode char w
        bindsym x exec i3pm-workspace-mode char x
        bindsym y exec i3pm-workspace-mode char y
        bindsym z exec i3pm-workspace-mode char z

        # Execute move (daemon handles move + follow + output focus + mode exit)
        bindsym Return exec i3pm-workspace-mode execute
        bindsym KP_Enter exec i3pm-workspace-mode execute

        # Cancel/exit mode
        bindsym Escape exec i3pm-workspace-mode cancel
    }
  '';

  # Legacy scratchpad script removed - now using i3pm scratchpad toggle
  # See Feature 062: Project-Scoped Scratchpad Terminal

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
            "resize set width 1200 px height 600 px",
            "move position center",
            "move scratchpad"
          ]
        },
        {
          "id": "monitoring-panel",
          "source": "nix",
          "scope": "global",
          "priority": 60,
          "criteria": {
            "app_id": "^eww-monitoring-panel$"
          },
          "actions": [
            "floating enable",
            "resize set width 800 px height 600 px",
            "move position center",
            "sticky enable"
          ]
        },
        {
          "id": "1password-main",
          "source": "nix",
          "scope": "global",
          "priority": 70,
          "criteria": {
            "app_id": "^1[Pp]assword$",
            "title": "^1Password$"
          },
          "actions": [
            "floating enable",
            "resize set width 900 px height 600 px",
            "move position center"
          ]
        },
        {
          "id": "1password-quick-access",
          "source": "nix",
          "scope": "global",
          "priority": 71,
          "criteria": {
            "app_id": "^1[Pp]assword$",
            "title": "^Quick Access"
          },
          "actions": [
            "floating enable",
            "sticky enable",
            "move position center"
          ]
        },
        {
          "id": "1password-unlock",
          "source": "nix",
          "scope": "global",
          "priority": 72,
          "criteria": {
            "app_id": "^1[Pp]assword$",
            "title": "^Unlock"
          },
          "actions": [
            "floating enable",
            "sticky enable",
            "move position center",
            "focus"
          ]
        },
        {
          "id": "polkit-agent",
          "source": "nix",
          "scope": "global",
          "priority": 80,
          "criteria": {
            "app_id": "^lxqt-policykit-agent$"
          },
          "actions": [
            "floating enable",
            "sticky enable",
            "move position center",
            "focus"
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
      # NOTE: Keybindings are now managed statically in sway-keybindings.nix
      # ".local/share/sway-config-manager/templates/keybindings.toml" = {
      #   source = defaultKeybindingsPath;
      # };

      ".local/share/sway-config-manager/templates/window-rules.json" = {
        text = defaultWindowRules;
      };

      ".local/share/sway-config-manager/templates/workspace-assignments.json" = {
        text = defaultWorkspaceAssignments;
      };

      ".local/share/sway-config-manager/templates/appearance.json" = {
        source = defaultAppearancePath;
      };

      # Legacy scratchpad toggle script removed (Feature 062)
      # Now using: i3pm scratchpad toggle (daemon-based implementation)

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
        # Feature 121: Use sway-session.target for proper Sway lifecycle binding
        After = [ "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
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
          # NOTE: keybindings.toml removed - keybindings now managed statically in sway-keybindings.nix
          for file in window-rules.json workspace-assignments.json appearance.json .gitignore; do
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
          # NOTE: keybindings-generated.conf removed - keybindings now managed statically
          for generated in appearance-generated.conf; do
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
        # Feature 121: Auto-start with Sway session (directly uses swaymsg)
        WantedBy = [ "sway-session.target" ];
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
