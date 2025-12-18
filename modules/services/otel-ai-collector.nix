# Feature 123: OpenTelemetry Collector for AI Assistant Monitoring
#
# This module provides the OTEL collector configuration that:
# - Receives OTLP telemetry from Claude Code and Codex CLI on port 4318
# - Forwards to otel-ai-monitor user service on port 4320 for session aggregation
# - Optionally exports to file for debugging
# - Exports to Kubernetes OTel stack via Tailscale for persistence (ClickHouse/Grafana)
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

    enableK8sExporter = mkOption {
      type = types.bool;
      default = true;
      description = "Enable exporting to the Kubernetes OTel stack";
    };

    k8sExporterEndpoint = mkOption {
      type = types.str;
      default = "http://otel-collector.tail286401.ts.net:4318";
      description = "Endpoint for the Kubernetes OTel Collector (via Tailscale)";
    };

    enableZPages = mkOption {
      type = types.bool;
      default = true;
      description = "Enable zpages extension for live debugging at http://localhost:55679";
    };

    zpagesPort = mkOption {
      type = types.port;
      default = 55679;
      description = "Port for zpages HTTP server";
    };
  };

  config = mkIf cfg.enable {
    services.opentelemetry-collector = {
      enable = true;
      package = pkgs.opentelemetry-collector-contrib;  # Has file exporter

      settings = {
        # Extensions for debugging and health checks
        extensions = lib.optionalAttrs cfg.enableZPages {
          zpages = {
            endpoint = "0.0.0.0:${toString cfg.zpagesPort}";
          };
        };

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
          # Kubernetes OTel Stack Exporter (optional)
          // (lib.optionalAttrs cfg.enableK8sExporter {
            "otlphttp/k8s" = {
              endpoint = cfg.k8sExporterEndpoint;
              encoding = "json";
              tls = {
                insecure = true; # Tailscale provides security
              };
            };
          })
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
          # Enable extensions
          extensions = lib.optional cfg.enableZPages "zpages";

          pipelines = {
            traces = {
              receivers = [ "otlp" ];
              exporters = filter (e: e != null) [
                (if cfg.enableDebugExporter then "debug" else null)
                (if cfg.enableFileExporter then "file" else null)
                (if cfg.enableK8sExporter then "otlphttp/k8s" else null)
                "otlphttp"
              ];
            };
            logs = {
              receivers = [ "otlp" ];
              exporters = filter (e: e != null) [
                (if cfg.enableDebugExporter then "debug" else null)
                (if cfg.enableFileExporter then "file" else null)
                (if cfg.enableK8sExporter then "otlphttp/k8s" else null)
                "otlphttp"
              ];
            };
            metrics = {
              receivers = [ "otlp" ];
              exporters = filter (e: e != null) [
                (if cfg.enableDebugExporter then "debug" else null)
                (if cfg.enableFileExporter then "file" else null)
                (if cfg.enableK8sExporter then "otlphttp/k8s" else null)
                "otlphttp"
              ];
            };
          };
        };
      };
    };
  };
}
