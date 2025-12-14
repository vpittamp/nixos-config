# i3 Project Event Listener Daemon - User Service Module
# Feature 117: Converted from system service to user service
#
# This module provides a home-manager user service that:
# - Maintains persistent IPC connection to Sway/i3 window manager
# - Processes window/workspace events in real-time
# - Automatically marks windows with project context
# - Exposes IPC socket for CLI tool queries
# - Uses session environment (SWAYSOCK, WAYLAND_DISPLAY) directly
#
# Benefits over system service (Feature 037):
# - No socket discovery wrapper needed (inherits session environment)
# - PartOf=graphical-session.target works correctly
# - Socket at $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock
# - Lifecycle aligned with graphical session
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.i3-project-daemon;

  # Python dependencies for the daemon (same as system service)
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    i3ipc        # i3 IPC library
    systemd-python      # systemd-python for sd_notify/watchdog/journald
    watchdog     # File system monitoring
    pydantic     # Data validation for layout models and monitor config
    pytest       # Testing framework
    pytest-asyncio  # Async test support
    pytest-cov   # Coverage reporting
    rich         # Terminal UI for diagnostic commands
    jsonschema   # JSON schema validation (for compatibility with other modules)
    psutil       # Process utilities for scratchpad terminal validation (Feature 062)
  ]);

  # Daemon package (Feature 061: Unified mark format)
  daemonSrc = ../desktop/i3-project-event-daemon;

  daemonPackage = pkgs.stdenv.mkDerivation {
    name = "i3-project-event-daemon-v122";  # Bumped for Feature 117
    version = "1.22.0";  # Feature 117: User service conversion
    src = daemonSrc;

    installPhase = ''
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon
      cp -r $src/* $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon/

      # Feature 085: Copy i3_project_manager module for monitoring panel publisher
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_manager
      cp -r ${../tools/i3_project_manager}/* $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_manager/
    '';
  };

in
{
  options.programs.i3-project-daemon = {
    enable = mkEnableOption "i3 project event listener daemon (user service)";

    logLevel = mkOption {
      type = types.enum [ "DEBUG" "INFO" "WARNING" "ERROR" ];
      default = "DEBUG";
      description = "Logging level for the daemon";
    };
  };

  config = mkIf cfg.enable {
    # User service for the daemon
    # Feature 117: Direct Python invocation without wrapper script
    systemd.user.services.i3-project-daemon = {
      Unit = {
        Description = "i3 Project Event Listener Daemon";
        Documentation = "file:///etc/nixos/specs/117-convert-project-daemon/quickstart.md";
        # Start after graphical session is ready
        After = [ "graphical-session.target" ];
        # Stop when graphical session stops (lifecycle binding)
        PartOf = [ "graphical-session.target" ];
        # Limit restart frequency to prevent loops
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        Type = "notify";

        # CRITICAL FIX: Improved timeout configuration for stability
        # Watchdog: 20s (daemon pings every ~6.7s = 3x safety margin)
        WatchdogSec = 20;

        # Startup timeout: 30s is sufficient for initialization
        TimeoutStartSec = 30;

        # Shutdown timeout: 15s (daemon has 10s timeout internally + 5s buffer)
        TimeoutStopSec = 15;

        # Quick restart on failure
        Restart = "always";
        RestartSec = 2;

        # Resource limits (same as system service)
        MemoryMax = "100M";
        MemoryHigh = "80M";
        CPUQuota = "50%";
        TasksMax = 50;

        # Security hardening (minimal since we need /proc access)
        NoNewPrivileges = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        # Create socket directory before starting
        # %t expands to $XDG_RUNTIME_DIR in user services
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/i3-project-daemon";

        # Direct Python invocation (no wrapper script needed)
        # Session environment (SWAYSOCK, WAYLAND_DISPLAY, XDG_RUNTIME_DIR) inherited automatically
        ExecStart = "${pythonEnv}/bin/python3 -m i3_project_daemon";

        # Working directory for project config
        WorkingDirectory = "%h/.config/i3";

        # Environment variables
        Environment = [
          "LOG_LEVEL=${cfg.logLevel}"
          "PYTHONUNBUFFERED=1"
          "PYTHONPATH=${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages"
          "PYTHONWARNINGS=ignore::DeprecationWarning"
          # PATH includes user profile bin for app-launcher-wrapper
          "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:${pkgs.xorg.xprop}/bin:${pkgs.alacritty}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin"
        ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "i3-project-daemon";
      };

      Install = {
        # Auto-start with graphical session
        WantedBy = [ "graphical-session.target" ];
      };
    };

    # Ensure data directories exist (via home.activation instead of tmpfiles)
    home.activation.createI3pmDataDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p $HOME/.local/share/i3pm/layouts
    '';
  };
}
