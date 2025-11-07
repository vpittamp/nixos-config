{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sway-tree-monitor;
in
{
  options.services.sway-tree-monitor = {
    enable = mkEnableOption "Sway Tree Diff Monitor daemon";

    bufferSize = mkOption {
      type = types.int;
      default = 500;
      description = "Maximum number of events in circular buffer";
    };

    socketPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to Unix socket (default: $XDG_RUNTIME_DIR/sway-tree-monitor.sock)";
    };

    persistenceDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Directory for event persistence (default: $XDG_DATA_HOME/sway-tree-monitor)";
    };

    logLevel = mkOption {
      type = types.enum [ "DEBUG" "INFO" "WARNING" "ERROR" ];
      default = "INFO";
      description = "Python logging level";
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services.sway-tree-monitor = {
      Unit = {
        Description = "Sway Tree Diff Monitor - Real-time window state monitoring";
        Documentation = [ "file:///etc/nixos/specs/064-sway-tree-diff-monitor/quickstart.md" ];
        After = [ "graphical-session.target" "sway-session.target" ];
        PartOf = [ "graphical-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.python311}/bin/python -m sway_tree_monitor.daemon";
        Restart = "on-failure";
        RestartSec = "5s";

        # Performance limits (from spec: <25MB memory, <2% CPU)
        MemoryMax = "50M";  # 2x target for safety margin
        MemoryHigh = "40M";
        CPUQuota = "5%";  # 2.5x target for bursts

        # Environment
        Environment = [
          "PYTHONUNBUFFERED=1"
          "LOG_LEVEL=${cfg.logLevel}"
        ] ++ (optionals (cfg.socketPath != null) [
          "SOCKET_PATH=${cfg.socketPath}"
        ]) ++ (optionals (cfg.persistenceDir != null) [
          "PERSISTENCE_DIR=${cfg.persistenceDir}"
        ]) ++ [
          "BUFFER_SIZE=${toString cfg.bufferSize}"
        ];

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          "%t"  # XDG_RUNTIME_DIR for socket
          "%h/.local/share/sway-tree-monitor"  # Persistence directory
        ];
        NoNewPrivileges = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        PrivateDevices = true;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "sway-tree-monitor";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };

    # Add Python environment with required packages
    home.packages = with pkgs; [
      (python311.withPackages (ps: with ps; [
        i3ipc
        xxhash
        orjson
        textual
        pydantic
        rich
      ]))
    ];
  };
}
