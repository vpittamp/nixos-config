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
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.i3ProjectEventListener;

  # Import i3pm package for shared models
  i3pmPackage = config.programs.i3pm.package or null;

  # Python dependencies for the daemon (T033)
  pythonEnv = if i3pmPackage != null then
    pkgs.python3.withPackages (ps: with ps; [
      i3ipc        # i3 IPC library
      systemd      # systemd-python for sd_notify/watchdog/journald
      i3pmPackage  # i3pm for shared Project models
    ])
  else
    pkgs.python3.withPackages (ps: with ps; [
      i3ipc
      systemd
    ]);

  # Daemon package (T033)
  daemonSrc = ./i3-project-event-daemon;

  daemonPackage = pkgs.stdenv.mkDerivation {
    name = "i3-project-event-daemon";
    src = daemonSrc;

    installPhase = ''
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon
      cp -r $src/* $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3_project_daemon/
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

    # Create runtime directory for IPC socket
    systemd.user.tmpfiles.rules = [
      "d %t/i3-project-daemon 0700 - - -"
    ];

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
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [
          "%t/i3-project-daemon"
          "%h/.config/i3"
        ];
        NoNewPrivileges = true;
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

    # Install CLI tools (T010, T011, T029-T032)
    home.packages = with pkgs; [
      pythonEnv  # Python environment for daemon

      # CLI tools as wrapper scripts
      (writeShellScriptBin "i3-project-switch" (builtins.readFile ../../scripts/i3-project-switch))
      (writeShellScriptBin "i3-project-current" (builtins.readFile ../../scripts/i3-project-current))
      (writeShellScriptBin "i3-project-list" (builtins.readFile ../../scripts/i3-project-list))
      (writeShellScriptBin "i3-project-create" (builtins.readFile ../../scripts/i3-project-create))
      (writeShellScriptBin "i3-project-daemon-status" (builtins.readFile ../../scripts/i3-project-daemon-status))
      (writeShellScriptBin "i3-project-daemon-events" (builtins.readFile ../../scripts/i3-project-daemon-events))
    ];

    # Shell aliases (T034)
    # Use mkForce to override existing pclear alias from bash.nix (Feature 012)
    programs.bash.shellAliases = mkIf cfg.enable {
      pswitch = lib.mkForce "i3-project-switch";
      pcurrent = lib.mkForce "i3-project-current";
      plist = lib.mkForce "i3-project-list";
      pclear = lib.mkForce "i3-project-switch --clear";  # Override old Feature 012 alias
    };
  };
}
