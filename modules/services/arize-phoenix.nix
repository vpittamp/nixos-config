# Arize Phoenix - Generative AI Observability
# Feature: 129 Enhancement - GenAI Tracing
#
# This module provides Arize Phoenix for GenAI tracing and observability.
# It runs as a Docker container and receives OTLP traces from Grafana Alloy.
#
# UI: http://localhost:6006
# OTLP HTTP: http://localhost:4343/v1/traces
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.arize-phoenix;
in
{
  options.services.arize-phoenix = {
    enable = mkEnableOption "Arize Phoenix GenAI observability";

    port = mkOption {
      type = types.port;
      default = 6006;
      description = "Web UI and OTLP HTTP port";
    };

    grpcPort = mkOption {
      type = types.port;
      default = 4317;
      description = "OTLP gRPC port on host";
    };

    image = mkOption {
      type = types.str;
      default = "arizephoenix/phoenix:latest";
      description = "Phoenix container image";
    };
  };

  config = mkIf cfg.enable {
    # Phoenix runs in Docker
    virtualisation.docker.enable = true;

    # Create Phoenix container as a systemd service
    systemd.services.arize-phoenix = {
      description = "Arize Phoenix - GenAI Observability";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        # Run as root to manage Docker
        User = "root";
        Group = "root";

        # Pull and run Phoenix container
        ExecStartPre = "${pkgs.docker}/bin/docker pull ${cfg.image}";

        ExecStart = ''
          ${pkgs.docker}/bin/docker run \
            --rm \
            --name arize-phoenix \
            -p ${toString cfg.port}:6006 \
            -p ${toString cfg.grpcPort}:4317 \
            -v /var/lib/arize-phoenix:/data \
            -e PHOENIX_PORT=6006 \
            -e PHOENIX_HOST=0.0.0.0 \
            ${cfg.image}
        '';

        ExecStop = "${pkgs.docker}/bin/docker stop arize-phoenix";
        ExecStopPost = "${pkgs.docker}/bin/docker rm -f arize-phoenix || true";
      };
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d /var/lib/arize-phoenix 0755 root root -"
    ];

    # Firewall rules for local access
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port
        cfg.grpcPort
      ];
    };

    # Helper scripts
    environment.systemPackages = with pkgs;
      [ (writeShellScriptBin "phoenix-logs" ''
        #!/usr/bin/env bash
        docker logs -f arize-phoenix 2>&1
      '') ];
  };
}
