# NixOS Module Options Contract

## services.grafana-alloy

```nix
{
  services.grafana-alloy = {
    enable = lib.mkEnableOption "Grafana Alloy telemetry collector";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.grafana-alloy;
      description = "Grafana Alloy package to use";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to custom Alloy configuration file";
    };

    otlpPort = lib.mkOption {
      type = lib.types.port;
      default = 4318;
      description = "OTLP HTTP receiver port";
    };

    localForwardPort = lib.mkOption {
      type = lib.types.port;
      default = 4320;
      description = "Port for local otel-ai-monitor forwarding";
    };

    k8sEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://otel-collector.tail286401.ts.net:4318";
      description = "Kubernetes OTEL collector endpoint";
    };

    lokiEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://loki.tail286401.ts.net:3100";
      description = "Loki push endpoint";
    };

    mimirEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://mimir.tail286401.ts.net";
      description = "Mimir remote write endpoint";
    };

    enableNodeExporter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable system metrics collection via node exporter";
    };

    enableJournald = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable journald log collection";
    };

    journaldUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "otel-ai-monitor.service"
        "i3pm-daemon.service"
        "grafana-alloy.service"
      ];
      description = "Systemd units to collect logs from";
    };
  };
}
```

## services.grafana-beyla

```nix
{
  services.grafana-beyla = {
    enable = lib.mkEnableOption "Grafana Beyla eBPF auto-instrumentation";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.grafana-beyla;  # Custom derivation
      description = "Beyla package to use";
    };

    openPorts = lib.mkOption {
      type = lib.types.str;
      default = "4320,8080";
      description = "Comma-separated ports to instrument";
    };

    serviceName = lib.mkOption {
      type = lib.types.str;
      default = "workstation-services";
      description = "Service name for generated traces";
    };

    alloyEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "localhost:4318";
      description = "OTLP endpoint for traces (usually local Alloy)";
    };
  };
}
```

## services.pyroscope-agent

```nix
{
  services.pyroscope-agent = {
    enable = lib.mkEnableOption "Pyroscope continuous profiling agent";

    serverAddress = lib.mkOption {
      type = lib.types.str;
      default = "http://pyroscope.tail286401.ts.net:4040";
      description = "Remote Pyroscope server address";
    };

    applications = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Application name";
          };
          pythonPath = lib.mkOption {
            type = lib.types.str;
            description = "Path to Python script or module";
          };
          tags = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Additional tags for profiles";
          };
        };
      });
      default = [];
      description = "List of applications to profile";
    };
  };
}
```

## Example Configuration

```nix
# configurations/thinkpad.nix
{ config, pkgs, ... }:

{
  imports = [
    ../modules/services/grafana-alloy.nix
    ../modules/services/grafana-beyla.nix
    ../modules/services/pyroscope-agent.nix
  ];

  services.grafana-alloy = {
    enable = true;
    k8sEndpoint = "http://otel-collector.tail286401.ts.net:4318";
    enableNodeExporter = true;
    enableJournald = true;
    journaldUnits = [
      "otel-ai-monitor.service"
      "i3pm-daemon.service"
    ];
  };

  services.grafana-beyla = {
    enable = true;
    openPorts = "4320,8080";
    serviceName = "thinkpad-services";
  };

  # Pyroscope is optional, enable for debugging
  services.pyroscope-agent.enable = false;
}
```
