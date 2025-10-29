# WayVNC Systemd Service Definitions
# Feature 048: Multi-Monitor Headless Sway/Wayland Setup
#
# This file documents the systemd service configuration for three WayVNC instances.
# To be integrated into home-modules/desktop/sway.nix

{
  # Service for HEADLESS-1 (primary display, workspaces 1-2, port 5900)
  systemd.user.services."wayvnc@HEADLESS-1" = {
    Unit = {
      Description = "wayvnc VNC server for HEADLESS-1";
      Documentation = "https://github.com/any1/wayvnc";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      # Capture HEADLESS-1 output on port 5900
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o HEADLESS-1 -p 5900";
      Restart = "on-failure";
      RestartSec = "1";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # Service for HEADLESS-2 (secondary display, workspaces 3-5, port 5901)
  systemd.user.services."wayvnc@HEADLESS-2" = {
    Unit = {
      Description = "wayvnc VNC server for HEADLESS-2";
      Documentation = "https://github.com/any1/wayvnc";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      # Capture HEADLESS-2 output on port 5901
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o HEADLESS-2 -p 5901";
      Restart = "on-failure";
      RestartSec = "1";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # Service for HEADLESS-3 (tertiary display, workspaces 6-9, port 5902)
  systemd.user.services."wayvnc@HEADLESS-3" = {
    Unit = {
      Description = "wayvnc VNC server for HEADLESS-3";
      Documentation = "https://github.com/any1/wayvnc";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      # Capture HEADLESS-3 output on port 5902
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o HEADLESS-3 -p 5902";
      Restart = "on-failure";
      RestartSec = "1";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}

# Service Dependency Contract:
# =============================
#
# PRECONDITIONS:
# - Sway compositor MUST be running with IPC socket available
# - sway-session.target MUST be active
# - HEADLESS-1, HEADLESS-2, HEADLESS-3 outputs MUST exist (created by WLR_HEADLESS_OUTPUTS=3)
#
# POSTCONDITIONS:
# - Three WayVNC processes running, each capturing one output
# - VNC ports 5900, 5901, 5902 listening on all interfaces (0.0.0.0)
# - Ports only accessible via Tailscale interface (enforced by firewall rules)
#
# FAILURE BEHAVIOR:
# - Restart=on-failure ensures automatic recovery if VNC server crashes
# - RestartSec=1 prevents rapid restart loops
# - PartOf=sway-session.target ensures services stop when Sway exits
#
# LOGGING:
# - Service logs available via: journalctl --user -u wayvnc@HEADLESS-1 -f
# - Log rotation handled by systemd journald
#
# VALIDATION:
# - Check service status: systemctl --user status wayvnc@HEADLESS-1
# - List all instances: systemctl --user list-units 'wayvnc@*'
# - Test VNC connectivity: vncviewer <tailscale-ip>:5900
