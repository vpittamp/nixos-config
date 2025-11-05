# i3 Project Event Listener Daemon
# Home Manager Module for event-driven i3 project management
#
# This module provides a systemd user service that:
# - Maintains persistent IPC connection to i3 window manager
# - Processes window/workspace events in real-time
# - Automatically marks windows with project context
# - Exposes IPC socket for CLI tool queries
# - Uses socket activation for reliable startup
#
{ config, lib, pkgs, sharedPythonEnv, ... }:

with lib;

let
  cfg = config.services.i3ProjectEventListener;

  # Use shared Python environment from python-environment.nix
  pythonEnv = sharedPythonEnv;

  # Daemon package (T033)
  daemonSrc = ./i3-project-event-daemon;

  daemonPackage = pkgs.stdenv.mkDerivation {
    name = "i3-project-event-daemon";
    version = "1.6.0";  # Feature 059: Include scratchpad windows in window tree by default
    src = daemonSrc;

    installPhase = ''
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon
      cp -r $src/* $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon/
      # Feature 033: Includes MonitorConfigManager and workspace distribution logic
    '';
  };

in
{
  options.services.i3ProjectEventListener = {
    enable = mkEnableOption "i3 project event listener daemon";

    logLevel = mkOption {
      type = types.enum [ "DEBUG" "INFO" "WARNING" "ERROR" ];
      default = "INFO";
      description = "Logging level for the daemon";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically start the daemon with the user session";
    };
  };

  config = mkIf cfg.enable {
    # Assertion: Warn if i3 config not found (but don't fail)
    # Note: System uses i3 via config file only, not xsession.windowManager.i3.enable
    # assertions = [
    #   {
    #     assertion = config.xsession.windowManager.i3.enable or false;
    #     message = ''
    #       i3ProjectEventListener requires i3 window manager to be enabled.
    #       Set xsession.windowManager.i3.enable = true or disable this service.
    #     '';
    #   }
    # ];

    # Create runtime and data directories
    systemd.user.tmpfiles.rules = [
      "d %t/i3-project-daemon 0700 - - -"
      "d %h/.local/share/i3pm 0755 - - -"  # Feature 030: Layout snapshot storage
      "d %h/.local/share/i3pm/layouts 0755 - - -"
    ];

    # Feature 033: Generate default workspace-to-monitor mapping configuration
    # Creates config file only if it doesn't already exist (force=false)
    xdg.configFile."i3/workspace-monitor-mapping.json" = {
      enable = true;
      force = false;  # Don't overwrite existing config
      text = builtins.toJSON {
        version = "1.0";
        distribution = {
          "1_monitor" = {
            primary = [ 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 ];
            secondary = [];
            tertiary = [];
          };
          "2_monitors" = {
            primary = [ 1 2 ];
            secondary = [ 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 ];
            tertiary = [];
          };
          "3_monitors" = {
            primary = [ 1 2 ];
            secondary = [ 3 4 5 ];
            tertiary = [ 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 ];
          };
        };
        workspace_preferences = {};
        output_preferences = {};
        debounce_ms = 1000;
        enable_auto_reassign = true;
      };
    };

    # Socket unit for socket activation (T028)
    systemd.user.sockets.i3-project-event-listener = {
      Unit = {
        Description = "i3 Project Event Listener IPC Socket";
        PartOf = [ "i3-project-event-listener.service" ];
      };

      Socket = {
        ListenStream = "%t/i3-project-daemon/ipc.sock";
        SocketMode = "0600";  # Owner-only access
        Accept = false;       # Single service handles all connections
      };

      Install = {
        WantedBy = if cfg.autoStart then [ "sockets.target" ] else [];
      };
    };

    # Service unit for the daemon (T028)
    systemd.user.services.i3-project-event-listener = {
      Unit = {
        Description = "i3 Project Event Listener Daemon";
        Documentation = [ "file:///etc/nixos/specs/015-create-a-new/quickstart.md" ];
        After = [ "graphical-session.target" ];
        Requires = [ "i3-project-event-listener.socket" ];
      };

      Service = {
        Type = "notify";           # Wait for READY=1 via sd_notify
        WatchdogSec = 30;          # Expect watchdog ping every 30s
        Restart = "always";        # Always restart on failure
        RestartSec = 5;            # Wait 5s before restart

        # Security hardening (T028)
        # Note: ProtectSystem, ProtectHome, and PrivateTmp disabled to allow reading
        # /proc/{pid}/environ for cross-service process inspection (Feature 037 window filtering)
        # CAP_SYS_PTRACE required to read /proc/{pid}/environ across user namespaces
        AmbientCapabilities = "CAP_SYS_PTRACE";
        ReadWritePaths = [
          "%t/i3-project-daemon"
          "%h/.config/i3"
          "%h/.local/share/i3pm"  # Feature 030: Layout snapshot storage
        ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        # Resource limits (T028)
        MemoryMax = "100M";
        MemoryHigh = "80M";
        CPUQuota = "50%";
        TasksMax = 50;

        # Execution (T027, T033)
        ExecStart = "${pythonEnv}/bin/python3 -m i3_project_daemon";
        WorkingDirectory = "%h/.config/i3";

        # Set PYTHONPATH to include daemon package
        Environment = [
          "LOG_LEVEL=${cfg.logLevel}"
          "PYTHONUNBUFFERED=1"
          "PYTHONPATH=${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages"
          "PYTHONWARNINGS=ignore::DeprecationWarning"
          # Feature 037: Put /run/wrappers/bin first for setuid sudo access
          "PATH=/run/wrappers/bin:${pkgs.xorg.xprop}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin"
        ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "i3-project-daemon";

        # NOTE: systemd-python emits "no running event loop" warnings to stderr from C code
        # These warnings occur during sd_notify() calls and are cosmetic (sd_notify doesn't
        # need an event loop). We've attempted multiple suppression methods (FD redirection,
        # LogFilterPatterns, context managers) but the warnings originate from C-level fprintf
        # calls that bypass Python's stderr. The warnings are harmless and don't affect
        # functionality - they can be safely ignored when reviewing logs.
      };

      Install = {
        WantedBy = if cfg.autoStart then [ "graphical-session.target" ] else [];
      };
    };

    # Install CLI tools
    # NOTE: All daemon diagnostic tools are now provided by i3pm CLI (Feature 022)
    # Use 'i3pm daemon status' and 'i3pm daemon events' instead
    # Python environment provided by shared python-environment.nix
    # (removed from here to avoid buildEnv conflicts)
    home.packages = with pkgs; [];

    # Shell aliases (T034) - Feature 022: Migrated to use i3pm CLI
    # NOTE: These aliases are now redundant since i3pm module provides identical aliases
    # Kept for backward compatibility during transition
    programs.bash.shellAliases = mkIf cfg.enable {
      # Deprecated: Use i3pm directly instead
      # pswitch, pcurrent, plist, pclear are provided by i3pm module
    };
  };
}
