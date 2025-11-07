{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sway-tree-monitor;

  # Python environment with all required dependencies
  pythonEnv = pkgs.python311.withPackages (ps: with ps; [
    i3ipc
    xxhash
    orjson
    textual
    pydantic
    rich
  ]);

  # Daemon package
  daemonSrc = ../../home-modules/tools/sway-tree-monitor;

  daemonPackage = pkgs.stdenv.mkDerivation {
    name = "sway-tree-monitor";
    version = "1.0.0";
    src = daemonSrc;

    installPhase = ''
      mkdir -p $out/lib/python${pkgs.python311.pythonVersion}/site-packages/sway_tree_monitor
      cp -r $src/* $out/lib/python${pkgs.python311.pythonVersion}/site-packages/sway_tree_monitor/
    '';
  };

  # Daemon wrapper with proper PYTHONPATH
  daemonWrapper = pkgs.writeShellScript "sway-tree-monitor-daemon" ''
    export PYTHONPATH="${daemonPackage}/lib/python${pkgs.python311.pythonVersion}/site-packages:$PYTHONPATH"
    export PYTHONUNBUFFERED=1
    export LOG_LEVEL="${cfg.logLevel}"
    ${optionalString (cfg.socketPath != null) ''export SOCKET_PATH="${cfg.socketPath}"''}
    ${optionalString (cfg.persistenceDir != null) ''export PERSISTENCE_DIR="${cfg.persistenceDir}"''}
    export BUFFER_SIZE="${toString cfg.bufferSize}"

    exec ${pythonEnv}/bin/python -m sway_tree_monitor.daemon
  '';
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
      description = "Sway Tree Diff Monitor - Real-time window state monitoring";
      documentation = [ "file:///etc/nixos/specs/064-sway-tree-diff-monitor/quickstart.md" ];
      after = [ "graphical-session.target" "sway-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "sway-session.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${daemonWrapper}";
        Restart = "on-failure";
        RestartSec = "5s";

        # Performance limits (from spec: <25MB memory, <2% CPU)
        MemoryMax = "50M";  # 2x target for safety margin
        MemoryHigh = "40M";
        CPUQuota = "5%";  # 2.5x target for bursts

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
    };
  };
}
