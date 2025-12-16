# otel-ai-monitor: OpenTelemetry AI Assistant Monitoring Service
# Feature 123: OpenTelemetry AI Assistant Monitoring
#
# This module provides a home-manager user service that:
# - Receives OTLP telemetry from Claude Code and Codex CLI
# - Tracks AI assistant session states (idle, working, completed)
# - Outputs JSON streams for EWW deflisten consumption
# - Sends desktop notifications on task completion
#
# Replaces the legacy tmux-ai-monitor polling-based approach with
# native OpenTelemetry event-driven monitoring.
#
{ config, lib, pkgs, self, ... }:

with lib;

let
  cfg = config.services.otel-ai-monitor;

  # Python environment with required dependencies
  pythonEnv = pkgs.python311.withPackages (ps: with ps; [
    aiohttp
    pydantic
    # opentelemetry-proto for protobuf parsing
    # Note: May need to add this if not in nixpkgs
  ]);

  # Package the monitor scripts
  monitorPackage = pkgs.stdenv.mkDerivation {
    pname = "otel-ai-monitor";
    version = "0.1.0";
    src = lib.cleanSource (self + "/scripts/otel-ai-monitor");

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      # Python modules must use underscores, not hyphens
      mkdir -p $out/lib/otel_ai_monitor
      cp -r . $out/lib/otel_ai_monitor/

      mkdir -p $out/bin
      makeWrapper ${pythonEnv}/bin/python $out/bin/otel-ai-monitor \
        --add-flags "-m otel_ai_monitor" \
        --set PYTHONPATH "$out/lib"
    '';
  };

in
{
  options.services.otel-ai-monitor = {
    enable = mkEnableOption "OpenTelemetry AI assistant monitor service";

    port = mkOption {
      type = types.port;
      default = 4318;
      description = "OTLP HTTP receiver port (default: 4318, standard OTLP HTTP port)";
    };

    completionQuietPeriodSec = mkOption {
      type = types.number;
      default = 3;
      description = "Seconds of quiet before marking session as completed";
    };

    sessionTimeoutSec = mkOption {
      type = types.number;
      default = 300;
      description = "Seconds before expiring inactive sessions (default: 5 minutes)";
    };

    completedTimeoutSec = mkOption {
      type = types.number;
      default = 30;
      description = "Seconds before auto-transitioning completed sessions to idle";
    };

    enableNotifications = mkOption {
      type = types.bool;
      default = true;
      description = "Enable desktop notifications on session completion";
    };

    broadcastIntervalSec = mkOption {
      type = types.number;
      default = 5;
      description = "Seconds between full session list broadcasts";
    };

    usePipe = mkOption {
      type = types.bool;
      default = true;
      description = "Write JSON to named pipe instead of stdout";
    };

    pipePath = mkOption {
      type = types.str;
      default = "\${XDG_RUNTIME_DIR}/otel-ai-monitor.pipe";
      description = "Path to named pipe for JSON output";
    };

    verbose = mkOption {
      type = types.bool;
      default = false;
      description = "Enable verbose logging";
    };
  };

  config = mkIf cfg.enable {
    # User service for the OTLP monitor
    systemd.user.services.otel-ai-monitor = {
      Unit = {
        Description = "OpenTelemetry AI Assistant Monitor";
        Documentation = "file:///etc/nixos/specs/123-otel-tracing/quickstart.md";
        # Start after graphical session is ready
        After = [ "graphical-session.target" ];
        # Stop when graphical session stops
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";

        # Build command with all options
        ExecStart = let
          args = [
            "--port" (toString cfg.port)
            "--quiet-period" (toString cfg.completionQuietPeriodSec)
            "--session-timeout" (toString cfg.sessionTimeoutSec)
            "--completed-timeout" (toString cfg.completedTimeoutSec)
            "--broadcast-interval" (toString cfg.broadcastIntervalSec)
          ]
          ++ lib.optionals cfg.usePipe [ "--pipe" cfg.pipePath ]
          ++ lib.optionals (!cfg.enableNotifications) [ "--no-notifications" ]
          ++ lib.optionals cfg.verbose [ "--verbose" ];
        in "${monitorPackage}/bin/otel-ai-monitor ${lib.concatStringsSep " " args}";

        # Quick restart on failure
        Restart = "on-failure";
        RestartSec = 2;

        # Resource limits (lightweight async Python service)
        MemoryMax = "30M";
        CPUQuota = "10%";

        # Environment for notifications
        Environment = [
          "PATH=${pkgs.libnotify}/bin:${pkgs.sway}/bin:${pkgs.coreutils}/bin"
        ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "otel-ai-monitor";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
