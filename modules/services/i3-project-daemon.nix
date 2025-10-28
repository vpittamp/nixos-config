# i3 Project Event Listener Daemon
# NixOS System Module for event-driven i3 project management
#
# This module provides a systemd system service (running as user) that:
# - Maintains persistent IPC connection to i3 window manager
# - Processes window/workspace events in real-time
# - Automatically marks windows with project context
# - Exposes IPC socket for CLI tool queries
# - Uses socket activation for reliable startup
#
# Feature 037: Converted from user service to system service to avoid
# namespace isolation issues that prevent reading /proc/{pid}/environ
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.i3ProjectDaemon;

  # Python dependencies for the daemon
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    i3ipc        # i3 IPC library
    systemd      # systemd-python for sd_notify/watchdog/journald
    watchdog     # File system monitoring
    pydantic     # Data validation for layout models and monitor config
    pytest       # Testing framework
    pytest-asyncio  # Async test support
    pytest-cov   # Coverage reporting
  ]);

  # Daemon package
  daemonSrc = ../../home-modules/desktop/i3-project-event-daemon;

  daemonPackage = pkgs.stdenv.mkDerivation {
    name = "i3-project-event-daemon";
    version = "1.3.0";  # Feature 038: Window state preservation (tiling/floating, workspace, geometry)
    src = daemonSrc;

    installPhase = ''
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon
      cp -r $src/* $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon/
    '';
  };

  # Wrapper script to find Sway IPC socket (Feature 046)
  # System services don't have access to user session environment (SWAYSOCK, WAYLAND_DISPLAY)
  # This wrapper scans /run/user/{uid} for sway-ipc socket and exports SWAYSOCK
  daemonWrapper = pkgs.writeShellScript "i3-project-daemon-wrapper" ''
    # Get user ID
    USER_ID=$(${pkgs.coreutils}/bin/id -u)
    USER_RUNTIME_DIR="/run/user/$USER_ID"

    # Find Sway IPC socket (matches pattern: sway-ipc.*.sock)
    SWAY_SOCK=$(${pkgs.findutils}/bin/find "$USER_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*.sock' -type s 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)

    if [ -n "$SWAY_SOCK" ]; then
      export SWAYSOCK="$SWAY_SOCK"
      export I3SOCK="$SWAY_SOCK"  # i3ipc library checks both
      echo "Found Sway IPC socket: $SWAY_SOCK" >&2
    else
      # Fallback: Check for i3 IPC socket (i3-ipc.*.sock)
      I3_SOCK=$(${pkgs.findutils}/bin/find "$USER_RUNTIME_DIR" -maxdepth 1 -name 'i3-ipc.*.sock' -type s 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)
      if [ -n "$I3_SOCK" ]; then
        export I3SOCK="$I3_SOCK"
        echo "Found i3 IPC socket: $I3_SOCK" >&2
      else
        echo "ERROR: No Sway or i3 IPC socket found in $USER_RUNTIME_DIR" >&2
      fi
    fi

    # Set WAYLAND_DISPLAY for Wayland compositors
    WAYLAND_SOCK=$(${pkgs.findutils}/bin/find "$USER_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -type s 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)
    if [ -n "$WAYLAND_SOCK" ]; then
      WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$WAYLAND_SOCK")
      export WAYLAND_DISPLAY
      echo "Found Wayland display: $WAYLAND_DISPLAY" >&2
    fi

    # Log final environment for debugging
    echo "i3pm daemon environment: SWAYSOCK=$SWAYSOCK I3SOCK=$I3SOCK WAYLAND_DISPLAY=$WAYLAND_DISPLAY" >&2

    # Run daemon
    exec ${pythonEnv}/bin/python3 -m i3_project_daemon
  '';

in
{
  options.services.i3ProjectDaemon = {
    enable = mkEnableOption "i3 project event listener daemon";

    user = mkOption {
      type = types.str;
      default = "vpittamp";
      description = "User to run the daemon as";
    };

    logLevel = mkOption {
      type = types.enum [ "DEBUG" "INFO" "WARNING" "ERROR" ];
      default = "INFO";
      description = "Logging level for the daemon";
    };
  };

  config = mkIf cfg.enable {
    # Create runtime and data directories via systemd tmpfiles
    systemd.tmpfiles.rules = [
      "d /run/i3-project-daemon 0700 ${cfg.user} users -"
      "d /home/${cfg.user}/.local/share/i3pm 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.local/share/i3pm/layouts 0755 ${cfg.user} users -"
    ];

    # Socket unit for socket activation
    systemd.sockets.i3-project-daemon = {
      description = "i3 Project Event Listener IPC Socket";
      wantedBy = [ "sockets.target" ];
      partOf = [ "i3-project-daemon.service" ];

      socketConfig = {
        # IMPORTANT: This path is also referenced in home-modules/tools/app-launcher.nix
        # If you change this, update daemonSocketPath in that module
        ListenStream = "/run/i3-project-daemon/ipc.sock";
        SocketMode = "0600";
        SocketUser = cfg.user;
        SocketGroup = "users";
        Accept = false;
      };
    };

    # Service unit for the daemon
    systemd.services.i3-project-daemon = {
      description = "i3 Project Event Listener Daemon";
      documentation = [ "file:///etc/nixos/specs/015-create-a-new/quickstart.md" ];

      # Start after graphical session for the user
      after = [ "graphical.target" ];
      requires = [ "i3-project-daemon.socket" ];

      # NOTE: partOf/PartOf not working in NixOS system services (Feature 046)
      # Attempted: partOf = [ "graphical.target" ]; and unitConfig.PartOf
      # Neither generated PartOf directive in systemd unit file
      # Workaround: Manual restart after greetd/Sway restart:
      #   sudo systemctl restart i3-project-daemon
      # Future: Consider socket reconnection detection in daemon code

      serviceConfig = {
        Type = "notify";
        User = cfg.user;
        Group = "users";

        # Watchdog configuration
        WatchdogSec = 30;
        Restart = "always";
        RestartSec = 5;

        # Resource limits
        MemoryMax = "100M";
        MemoryHigh = "80M";
        CPUQuota = "50%";
        TasksMax = 50;

        # Security: Minimal hardening since we need /proc access
        NoNewPrivileges = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        # Execution (using wrapper to import user environment - Feature 046)
        ExecStart = "${daemonWrapper}";
        WorkingDirectory = "/home/${cfg.user}/.config/i3";

        # Environment variables
        Environment = [
          "LOG_LEVEL=${cfg.logLevel}"
          "PYTHONUNBUFFERED=1"
          "PYTHONPATH=${daemonPackage}/lib/python${pkgs.python3.pythonVersion}/site-packages"
          "PYTHONWARNINGS=ignore::DeprecationWarning"
          "PATH=/run/wrappers/bin:${pkgs.xorg.xprop}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin"
          "DISPLAY=:10.0"
          "XAUTHORITY=/home/${cfg.user}/.Xauthority"
        ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "i3-project-daemon";
      };
    };
  };
}
