# Feature 129: Grafana Beyla - eBPF Auto-Instrumentation
#
# This module provides Grafana Beyla for automatic application instrumentation:
# - Uses eBPF to instrument HTTP/gRPC services without code changes
# - Requires Linux kernel 5.8+ with BTF support
# - Generates traces for Python daemons (otel-ai-monitor, i3pm)
# - Sends traces to local Grafana Alloy on port 4318
#
# NOTE: Beyla is not in nixpkgs (as of 2025-12), requires custom derivation
#       See research.md R2 for details
#
# Required capabilities (from research.md R4):
# - CAP_BPF: Load and verify eBPF programs
# - CAP_SYS_PTRACE: Attach to running processes
# - CAP_NET_RAW: Raw network socket access for HTTP tracing
# - CAP_CHECKPOINT_RESTORE: Process snapshot for analysis
# - CAP_DAC_READ_SEARCH: Read process memory maps
# - CAP_PERFMON: Access perf events
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.grafana-beyla;

  # Custom Beyla package - fetch binary from GitHub releases
  # Beyla is not in nixpkgs as of 2025-12
  beylaPackage = pkgs.stdenv.mkDerivation rec {
    pname = "grafana-beyla";
    version = "1.8.4";

    src = pkgs.fetchurl {
      url = "https://github.com/grafana/beyla/releases/download/v${version}/beyla-linux-amd64-v${version}.tar.gz";
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # FIXME: Update with real hash
    };

    sourceRoot = ".";

    installPhase = ''
      mkdir -p $out/bin
      cp beyla $out/bin/
      chmod +x $out/bin/beyla
    '';

    meta = with lib; {
      description = "eBPF-based auto-instrumentation for HTTP/gRPC applications";
      homepage = "https://github.com/grafana/beyla";
      license = licenses.asl20;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  options.services.grafana-beyla = {
    enable = mkEnableOption "Grafana Beyla eBPF auto-instrumentation";

    package = mkOption {
      type = types.package;
      default = beylaPackage;
      description = "Beyla package to use (custom derivation by default)";
    };

    openPorts = mkOption {
      type = types.str;
      default = "4320,8080";
      description = "Comma-separated ports to instrument (port-based discovery)";
    };

    serviceName = mkOption {
      type = types.str;
      default = "workstation-services";
      description = "Service name for generated traces";
    };

    alloyEndpoint = mkOption {
      type = types.str;
      default = "http://localhost:4318";
      description = "OTLP endpoint for traces (usually local Alloy)";
    };
  };

  config = mkIf cfg.enable {
    # Kernel sysctl for eBPF access (from research.md R4)
    boot.kernel.sysctl."kernel.perf_event_paranoid" = mkDefault 1;

    # Systemd service for Beyla
    systemd.services.grafana-beyla = {
      description = "Grafana Beyla - eBPF Auto-Instrumentation";
      documentation = [ "https://grafana.com/docs/beyla/" ];

      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "grafana-alloy.service" ];
      wants = [ "network-online.target" "grafana-alloy.service" ];

      environment = {
        BEYLA_OPEN_PORT = cfg.openPorts;
        BEYLA_SERVICE_NAME = cfg.serviceName;
        OTEL_EXPORTER_OTLP_ENDPOINT = cfg.alloyEndpoint;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/beyla";
        Restart = "always";
        RestartSec = "10s";

        # Required eBPF capabilities (from research.md R4)
        AmbientCapabilities = [
          "CAP_BPF"
          "CAP_SYS_PTRACE"
          "CAP_NET_RAW"
          "CAP_CHECKPOINT_RESTORE"
          "CAP_DAC_READ_SEARCH"
          "CAP_PERFMON"
        ];
        CapabilityBoundingSet = [
          "CAP_BPF"
          "CAP_SYS_PTRACE"
          "CAP_NET_RAW"
          "CAP_CHECKPOINT_RESTORE"
          "CAP_DAC_READ_SEARCH"
          "CAP_PERFMON"
        ];

        # Security hardening (what we can apply with eBPF requirements)
        NoNewPrivileges = false;  # Needs to acquire capabilities
        PrivateTmp = true;

        # Working directory
        StateDirectory = "grafana-beyla";
        WorkingDirectory = "/var/lib/grafana-beyla";
      };
    };

    # Assertions to check kernel requirements
    assertions = [
      {
        assertion = versionAtLeast config.boot.kernelPackages.kernel.version "5.8";
        message = "Grafana Beyla requires Linux kernel 5.8+ for eBPF support";
      }
    ];
  };
}
