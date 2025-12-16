# Sway Socket Cleanup Timer
# Feature 121: Automatic cleanup of stale Sway IPC socket files
#
# This module creates a systemd timer that runs every 5 minutes to remove
# orphaned sway-ipc.*.sock files. A socket is considered orphaned if:
# - The PID extracted from the socket filename doesn't exist
# - The process with that PID is not actually sway
#
# This prevents accumulation of stale sockets that can interfere with
# socket discovery and cause connection failures.
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.sway-socket-cleanup;

  # Cleanup script that removes stale sway sockets
  cleanupScript = pkgs.writeShellScript "sway-socket-cleanup" ''
    # Feature 121: Cleanup stale sway-ipc sockets
    USER_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
    CLEANED=0
    CHECKED=0

    # Iterate over all sway-ipc socket files
    for sock in "$USER_RUNTIME_DIR"/sway-ipc.*.sock; do
      # Skip if no matches (glob didn't expand)
      [ -e "$sock" ] || continue

      CHECKED=$((CHECKED + 1))

      # Extract PID from filename (sway-ipc.$UID.$PID.sock)
      pid=$(${pkgs.coreutils}/bin/basename "$sock" | ${pkgs.coreutils}/bin/cut -d. -f3)

      # Validate PID is numeric
      if ! echo "$pid" | ${pkgs.gnugrep}/bin/grep -qE '^[0-9]+$'; then
        echo "Warning: Invalid PID format in socket filename: $sock"
        continue
      fi

      # Check if process exists
      if ! ${pkgs.coreutils}/bin/kill -0 "$pid" 2>/dev/null; then
        echo "Removing stale socket: $sock (PID $pid not running)"
        ${pkgs.coreutils}/bin/rm -f "$sock"
        CLEANED=$((CLEANED + 1))
        continue
      fi

      # Check if process is actually sway
      PROC_COMM="/proc/$pid/comm"
      if [ -f "$PROC_COMM" ]; then
        PROC_NAME=$(${pkgs.coreutils}/bin/cat "$PROC_COMM" 2>/dev/null || echo "unknown")
        if [ "$PROC_NAME" != "sway" ]; then
          echo "Removing stale socket: $sock (PID $pid is $PROC_NAME, not sway)"
          ${pkgs.coreutils}/bin/rm -f "$sock"
          CLEANED=$((CLEANED + 1))
        fi
      fi
    done

    echo "Socket cleanup complete: checked $CHECKED, removed $CLEANED stale socket(s)"
  '';

in
{
  options.programs.sway-socket-cleanup = {
    enable = mkEnableOption "Automatic cleanup of stale Sway IPC sockets";

    interval = mkOption {
      type = types.str;
      default = "5min";
      description = "How often to run the cleanup (systemd OnUnitActiveSec format)";
    };

    initialDelay = mkOption {
      type = types.str;
      default = "5min";
      description = "Delay before first cleanup run after boot (systemd OnBootSec format)";
    };
  };

  config = mkIf cfg.enable {
    # Systemd user service for one-shot cleanup
    systemd.user.services.sway-socket-cleanup = {
      Unit = {
        Description = "Cleanup stale Sway IPC sockets";
        Documentation = "file:///etc/nixos/specs/121-improve-socket-discovery/quickstart.md";
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${cleanupScript}";

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "sway-socket-cleanup";
      };
    };

    # Systemd user timer that triggers the cleanup service periodically
    systemd.user.timers.sway-socket-cleanup = {
      Unit = {
        Description = "Periodic cleanup of stale Sway IPC sockets";
        Documentation = "file:///etc/nixos/specs/121-improve-socket-discovery/quickstart.md";
      };

      Timer = {
        # First run after boot
        OnBootSec = cfg.initialDelay;
        # Repeat interval
        OnUnitActiveSec = cfg.interval;
        # Don't run if we missed a scheduled time (sockets are transient)
        Persistent = false;
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
