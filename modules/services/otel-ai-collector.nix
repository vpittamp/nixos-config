# Feature 123: OpenTelemetry Collector for AI Assistant Monitoring
#
# This module provides the OTEL collector configuration that:
# - Receives OTLP telemetry from Claude Code and Codex CLI on port 4318
# - Forwards to otel-ai-monitor user service on port 4320 for session aggregation
# - Optionally exports to file for debugging
#
# The user service (otel-ai-monitor) handles session state and emits JSON
# for EWW widgets to consume.
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.otel-ai-collector;
in
{
  options.services.otel-ai-collector = {
    enable = mkEnableOption "OpenTelemetry collector for AI assistant monitoring";

    receiverPort = mkOption {
      type = types.port;
      default = 4318;
      description = "OTLP HTTP receiver port (standard: 4318)";
    };

    forwarderPort = mkOption {
      type = types.port;
      default = 4320;
      description = "Port to forward to otel-ai-monitor user service";
    };

    enableDebugExporter = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug exporter (verbose logging to journalctl)";
    };

    enableFileExporter = mkOption {
      type = types.bool;
      default = true;
      description = "Enable file exporter for raw telemetry analysis";
    };

    fileExporterPath = mkOption {
      type = types.str;
      default = "/var/lib/opentelemetry-collector/traces.json";
      description = "Path for file exporter output";
    };
  };

  config = mkIf cfg.enable {
    services.opentelemetry-collector = {
      enable = true;
      package = pkgs.opentelemetry-collector-contrib;  # Has file exporter

      settings = {
        receivers = {
          otlp = {
            protocols = {
              http = {
                endpoint = "0.0.0.0:${toString cfg.receiverPort}";
              };
            };
          };
        };

        exporters =
          # OTLP HTTP exporter to otel-ai-monitor (always enabled)
          {
            otlphttp = {
              endpoint = "http://127.0.0.1:${toString cfg.forwarderPort}";
              encoding = "json";  # Use JSON for easier parsing
              compression = "none";  # Disable compression for local forwarding
              tls = {
                insecure = true;  # Local connection, no TLS needed
              };
            };
          }
          # Debug exporter (optional)
          // (lib.optionalAttrs cfg.enableDebugExporter {
            debug = {
              verbosity = "detailed";
            };
          })
          # File exporter (optional)
          // (lib.optionalAttrs cfg.enableFileExporter {
            file = {
              path = cfg.fileExporterPath;
            };
          });

        service = {
          pipelines = {
            traces = {
              receivers = [ "otlp" ];
              exporters = filter (e: e != null) [
                (if cfg.enableDebugExporter then "debug" else null)
                (if cfg.enableFileExporter then "file" else null)
                "otlphttp"
              ];
            };
            logs = {
              receivers = [ "otlp" ];
              exporters = filter (e: e != null) [
                (if cfg.enableDebugExporter then "debug" else null)
                (if cfg.enableFileExporter then "file" else null)
                "otlphttp"
              ];
            };
          };
        };
      };
    };
  };
}
