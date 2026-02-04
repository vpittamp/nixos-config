# i3 Project Event Listener Daemon - User Service Module
# Feature 117: Converted from system service to user service
#
# This module provides a home-manager user service that:
# - Maintains persistent IPC connection to Sway/i3 window manager
# - Processes window/workspace events in real-time
# - Automatically marks windows with project context
# - Exposes IPC socket for CLI tool queries
# - Dynamically discovers SWAYSOCK at startup (robust to Sway restarts)
#
# Benefits over system service (Feature 037):
# - PartOf=sway-session.target ensures proper lifecycle with Sway
# - Socket at $XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock
# - Lifecycle aligned with Sway session (not generic graphical session)
# - SWAYSOCK discovery ensures connectivity even after Sway restarts
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
    name = "i3-project-event-daemon-v135.2";  # Return structured not-found response
    version = "1.35.2";  # Feature 135: Return {window_id: null} instead of null
    src = daemonSrc;

    installPhase = ''
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon
      cp -r $src/* $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon/

      # Feature 085: Copy i3_project_manager module for monitoring panel publisher
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_manager
      cp -r ${../tools/i3_project_manager}/* $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_manager/
    '';
  };

  # Wrapper script that discovers SWAYSOCK dynamically before starting daemon
  # This ensures the daemon can reconnect to Sway even after Sway restarts
  daemonWrapper = pkgs.writeShellScriptBin "i3-project-daemon-wrapper" ''
    # Find user runtime directory
    USER_ID=$(${pkgs.coreutils}/bin/id -u)
    USER_RUNTIME_DIR="/run/user/$USER_ID"

    # Dynamically discover Sway IPC socket (matches pattern: sway-ipc.*.sock)
    # Use newest socket by modification time to handle Sway restarts
    # Note: sort -r sorts alphabetically which is wrong (992301 > 1762696)
    # Use ls -t to sort by modification time (newest first)
    SWAY_SOCK=$(${pkgs.coreutils}/bin/ls -t "$USER_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)

    if [ -n "$SWAY_SOCK" ]; then
      export SWAYSOCK="$SWAY_SOCK"
      export I3SOCK="$SWAY_SOCK"  # i3ipc library checks both
      echo "Found Sway IPC socket: $SWAY_SOCK" >&2
    else
      echo "ERROR: No Sway IPC socket found in $USER_RUNTIME_DIR" >&2
      exit 1
    fi

    # Set WAYLAND_DISPLAY if not already set
    if [ -z "$WAYLAND_DISPLAY" ]; then
      WAYLAND_SOCK=$(${pkgs.findutils}/bin/find "$USER_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -type s 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)
      if [ -n "$WAYLAND_SOCK" ]; then
        export WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$WAYLAND_SOCK")
        export XDG_RUNTIME_DIR="$USER_RUNTIME_DIR"
      fi
    fi

    # Execute the Python daemon
    exec ${pythonEnv}/bin/python3 -m i3_project_daemon "$@"
  '';

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
        # Feature 121: Start after Sway session is ready (not generic graphical session)
        # This ensures SWAYSOCK is available and prevents startup race conditions
        After = [ "sway-session.target" ];
        # Stop when Sway session stops (proper lifecycle binding)
        PartOf = [ "sway-session.target" ];
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

        # Feature 137: Prevent stale state accumulation
        # Automatically restart daemon every 12 hours to clear accumulated
        # failed launches, expired notifications, and other transient state
        # that can cause PWA workspace assignment failures over time
        RuntimeMaxSec = "12h";

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

        # Create runtime directories before starting
        # %t expands to $XDG_RUNTIME_DIR in user services
        # Feature 117: Also create badge directory for file-based badge storage
        ExecStartPre = [
          "${pkgs.coreutils}/bin/mkdir -p %t/i3-project-daemon"
          "${pkgs.coreutils}/bin/mkdir -p %t/i3pm-badges"
        ];

        # Use wrapper script that dynamically discovers SWAYSOCK
        # This ensures the daemon works even after Sway restarts
        ExecStart = "${daemonWrapper}/bin/i3-project-daemon-wrapper";

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
        # Feature 121: Auto-start with Sway session (ensures Sway IPC available)
        WantedBy = [ "sway-session.target" ];
      };
    };

    # Ensure data directories exist (via home.activation instead of tmpfiles)
    home.activation.createI3pmDataDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p $HOME/.local/share/i3pm/layouts
    '';
  };
}
