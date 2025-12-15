# tmux-ai-monitor: Universal AI Assistant Progress Detection Service
# Feature 117: Improve Notification Progress Indicators
#
# This module provides a home-manager user service that:
# - Polls tmux panes to detect AI assistant processes (claude, codex)
# - Creates badge files for EWW monitoring panel display
# - Sends desktop notifications when assistants complete
# - Replaces application-specific hooks with universal detection
#
# The service writes badges to $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json
# which are consumed by the EWW monitoring panel via inotify.
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.tmux-ai-monitor;

  # Script paths
  scriptDir = ../../scripts/tmux-ai-monitor;

  # Default AI processes to detect
  defaultProcesses = [
    { name = "claude"; title = "Claude Code Ready"; source = "claude-code"; }
    { name = "codex"; title = "Codex Ready"; source = "codex"; }
  ];

in
{
  options.services.tmux-ai-monitor = {
    enable = mkEnableOption "tmux AI assistant monitor service";

    pollInterval = mkOption {
      type = types.int;
      default = 300;
      description = "Polling interval in milliseconds for tmux process detection";
    };

    processes = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Process name to detect (e.g., 'claude', 'codex')";
          };
          title = mkOption {
            type = types.str;
            description = "Notification title when process completes";
          };
          source = mkOption {
            type = types.str;
            description = "Source identifier for badge files";
          };
        };
      });
      default = defaultProcesses;
      description = "List of AI assistant processes to detect";
    };
  };

  config = mkIf cfg.enable {
    # User service for the tmux monitor
    systemd.user.services.tmux-ai-monitor = {
      Unit = {
        Description = "tmux AI Assistant Progress Monitor";
        Documentation = "file:///etc/nixos/specs/117-improve-notification-progress-indicators/quickstart.md";
        # Start after graphical session is ready
        After = [ "graphical-session.target" ];
        # Stop when graphical session stops
        PartOf = [ "graphical-session.target" ];
        # Don't start if tmux isn't configured (home-manager uses ~/.config/tmux/)
        ConditionPathExists = "%h/.config/tmux/tmux.conf";
      };

      Service = {
        Type = "simple";

        # Create badge directory before starting
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/i3pm-badges";

        # Main monitor script
        ExecStart = "${pkgs.bash}/bin/bash ${scriptDir}/monitor.sh";

        # Quick restart on failure
        Restart = "on-failure";
        RestartSec = 2;

        # Resource limits (lightweight process)
        MemoryMax = "50M";
        CPUQuota = "10%";

        # Environment variables
        Environment = [
          "POLL_INTERVAL_MS=${toString cfg.pollInterval}"
          "PATH=${pkgs.tmux}/bin:${pkgs.jq}/bin:${pkgs.sway}/bin:${pkgs.procps}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.libnotify}/bin:${pkgs.bc}/bin"
        ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "tmux-ai-monitor";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
