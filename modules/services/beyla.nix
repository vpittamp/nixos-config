{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.beyla;
in
{
  options.services.beyla = {
    enable = mkEnableOption "Beyla eBPF auto-instrumentation";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../pkgs/beyla.nix {};
      description = "Beyla package to use";
    };

    config = mkOption {
      type = types.attrs;
      default = {};
      description = "Beyla configuration (YAML-style as Nix attributes)";
    };

    monitorAiAssistants = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to automatically configure Beyla to monitor AI assistants (Claude, Gemini, Codex)";
    };

    otlpEndpoint = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "OTLP OTLP/HTTP endpoint to export telemetry to";
    };

    envFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Environment file containing sensitive configuration (e.g. OTLP auth)";
    };
  };

  config = mkIf cfg.enable {
    # Beyla requires eBPF privileges
    systemd.services.beyla = {
      description = "Beyla eBPF auto-instrumentation";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = let
          discoveryServices = if cfg.monitorAiAssistants then [
            {
              name = "ai-assistants";
              exe_path = ".*(claude|gemini|codex).*";
            }
          ] else [];
          
          otlpExport = if cfg.otlpEndpoint != null then {
            endpoint = cfg.otlpEndpoint;
            tls = {
              ca_file = "/etc/otel/certs/ca.crt";
              cert_file = "/etc/otel/certs/client.crt";
              key_file = "/etc/otel/certs/client.key";
            };
          } else {};

          finalConfig = recursiveUpdate {
            # Default Beyla config
            attributes = {
              kubernetes = {
                enable = false; # Running on local machine, not in K8s
              };
            };
            discovery = {
              services = discoveryServices;
            };
            otel_traces_export = otlpExport;
          } cfg.config;
        in "${cfg.package}/bin/beyla --config=${pkgs.writeText "beyla.yaml" (builtins.toJSON finalConfig)}";
        Restart = "always";
        # CAP_SYS_ADMIN, CAP_NET_RAW, CAP_BPF are usually required for eBPF
        # Some systems might need more or less depending on kernel version
        CapabilityBoundingSet = [ "CAP_SYS_ADMIN" "CAP_NET_RAW" "CAP_BPF" "CAP_DAC_READ_SEARCH" "CAP_SYS_PTRACE" ];
        AmbientCapabilities = [ "CAP_SYS_ADMIN" "CAP_NET_RAW" "CAP_BPF" "CAP_DAC_READ_SEARCH" "CAP_SYS_PTRACE" ];
        EnvironmentFile = mkIf (cfg.envFile != null) cfg.envFile;
        
        # Security hardening
        ProtectSystem = "full";
        ProtectHome = "read-only";
        PrivateTmp = true;
      };
    };
  };
}
