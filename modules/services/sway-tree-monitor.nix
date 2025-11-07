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

  # Daemon wrapper with proper PYTHONPATH and Sway IPC socket discovery
  daemonWrapper = pkgs.writeShellScript "sway-tree-monitor-daemon" ''
    # Find user runtime directory
    USER_ID=$(${pkgs.coreutils}/bin/id -u)
    USER_RUNTIME_DIR="/run/user/$USER_ID"

    # Find Sway IPC socket (matches pattern: sway-ipc.*.sock)
    SWAY_SOCK=$(${pkgs.findutils}/bin/find "$USER_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*.sock' -type s 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)

    if [ -n "$SWAY_SOCK" ]; then
      export SWAYSOCK="$SWAY_SOCK"
      export I3SOCK="$SWAY_SOCK"  # i3ipc library checks both
      echo "Found Sway IPC socket: $SWAY_SOCK" >&2
    else
      echo "ERROR: No Sway IPC socket found in $USER_RUNTIME_DIR" >&2
      exit 1
    fi

    # Set WAYLAND_DISPLAY
    WAYLAND_SOCK=$(${pkgs.findutils}/bin/find "$USER_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -type s 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)
    if [ -n "$WAYLAND_SOCK" ]; then
      WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$WAYLAND_SOCK")
      export WAYLAND_DISPLAY
      export XDG_RUNTIME_DIR="$USER_RUNTIME_DIR"
    fi

    # Set Python environment
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

        # Security hardening (relaxed for Sway IPC socket access)
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "sway-tree-monitor";
      };
    };
  };
}
