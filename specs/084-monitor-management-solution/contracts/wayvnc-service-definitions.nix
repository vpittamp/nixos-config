# WayVNC Service Definitions for M1 Hybrid Mode
# Feature: 084-monitor-management-solution
# Date: 2025-11-19

{ config, lib, pkgs, ... }:

let
  # Helper to create WayVNC wrapper script with transient seat detection
  mkWayvncWrapper = output: port: socket:
    pkgs.writeShellScript "wayvnc-${output}" ''
      # Detect ext_transient_seat_v1 protocol support
      TRANSIENT_SEAT_SUPPORTED=0
      PROTO_OUTPUT=$(swaymsg -t get_version 2>/dev/null || true)
      if echo "$PROTO_OUTPUT" | grep -q "ext_transient_seat_v1"; then
        TRANSIENT_SEAT_SUPPORTED=1
      fi

      # Build WayVNC command with appropriate options
      WAYVNC_CMD="${pkgs.wayvnc}/bin/wayvnc"
      WAYVNC_ARGS="-o ${output} -p ${toString port}"

      if [ "$TRANSIENT_SEAT_SUPPORTED" = "1" ]; then
        # Use transient seat for dedicated input seat per VNC client
        WAYVNC_ARGS="$WAYVNC_ARGS --transient-seat"
      fi

      # Add control socket for management
      WAYVNC_ARGS="$WAYVNC_ARGS -S ${socket}"

      exec $WAYVNC_CMD $WAYVNC_ARGS
    '';
in
{
  # WayVNC service for first virtual display (V1)
  systemd.user.services."wayvnc@HEADLESS-1" = {
    Unit = {
      Description = "WayVNC VNC server for virtual display V1";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = mkWayvncWrapper "HEADLESS-1" 5900 "/run/user/1000/wayvnc-v1.sock";
      Restart = "on-failure";
      RestartSec = "1";
      # Environment for proper Wayland socket discovery
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/1000"
      ];
    };

    # Do NOT auto-start - managed by profile switching
    Install = { };
  };

  # WayVNC service for second virtual display (V2)
  systemd.user.services."wayvnc@HEADLESS-2" = {
    Unit = {
      Description = "WayVNC VNC server for virtual display V2";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = mkWayvncWrapper "HEADLESS-2" 5901 "/run/user/1000/wayvnc-v2.sock";
      Restart = "on-failure";
      RestartSec = "1";
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/1000"
      ];
    };

    # Do NOT auto-start - managed by profile switching
    Install = { };
  };
}

# Usage Notes:
#
# These services are NOT auto-started (no WantedBy).
# Profile switching scripts manage lifecycle:
#
# Activate VNC:
#   systemctl --user start wayvnc@HEADLESS-1.service
#
# Deactivate VNC:
#   systemctl --user stop wayvnc@HEADLESS-1.service
#
# Check status:
#   systemctl --user status wayvnc@HEADLESS-1.service
#
# Port assignments:
#   - V1 (HEADLESS-1): Port 5900
#   - V2 (HEADLESS-2): Port 5901
#
# Control socket allows:
#   - wayvncctl --socket /run/user/1000/wayvnc-v1.sock disconnect-client
#   - wayvncctl --socket /run/user/1000/wayvnc-v1.sock output-cycle
