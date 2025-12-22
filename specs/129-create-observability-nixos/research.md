# Research: NixOS Full Observability Stack

**Feature**: 129-create-observability-nixos
**Date**: 2025-12-19

## R1. Grafana Alloy NixOS Packaging

**Decision**: Use official `pkgs.grafana-alloy` package from nixpkgs (v1.11.3+).

**Rationale**:
- Official package available and maintained in nixpkgs
- Described as "Open source OpenTelemetry Collector distribution with built-in Prometheus pipelines and support for metrics, logs, traces, and profiles"
- No custom derivation needed

**Alternatives Considered**:
- Custom derivation from binary: Unnecessary since official package exists
- Building from source: Unnecessary overhead

**Implementation**:
```nix
environment.systemPackages = [ pkgs.grafana-alloy ];
```

---

## R2. Grafana Beyla NixOS Packaging

**Decision**: Create custom Nix derivation for Beyla binary.

**Rationale**:
- Beyla not available in nixpkgs (as of 2025-12)
- eBPF tools have complex kernel dependencies
- Binary download approach is cleanest for now

**Alternatives Considered**:
- Docker/Podman container: Adds complexity, less NixOS-native
- Wait for official package: Delays implementation

**Implementation**: Custom derivation fetching binary from GitHub releases, with systemd service for capabilities.

---

## R3. Alloy Configuration for OTLP Forwarding

**Decision**: Use `otelcol.receiver.otlp` → `otelcol.processor.batch` → multiple `otelcol.exporter.otlp` components.

**Rationale**:
- Component architecture allows forwarding to multiple endpoints
- Batch processing improves compression and reduces network requests
- Memory buffer provides resilience during downstream unavailability

**Configuration**:
```alloy
// Receive OTLP on HTTP 4318
otelcol.receiver.otlp "default" {
  http {
    endpoint = "0.0.0.0:4318"
  }

  output {
    metrics = [otelcol.processor.batch.default.input]
    logs    = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}

// Batch processing with memory buffer
otelcol.processor.batch "default" {
  send_batch_size = 1000
  timeout = "10s"
  send_batch_max_size = 2000

  output {
    metrics = [
      otelcol.exporter.otlphttp.local.input,
      otelcol.exporter.otlphttp.k8s.input
    ]
    logs = [
      otelcol.exporter.otlphttp.local.input,
      otelcol.exporter.otlphttp.k8s.input
    ]
    traces = [
      otelcol.exporter.otlphttp.local.input,
      otelcol.exporter.otlphttp.k8s.input
    ]
  }
}

// Local otel-ai-monitor on 4320
otelcol.exporter.otlphttp "local" {
  client {
    endpoint = "http://localhost:4320"
    tls {
      insecure = true
    }
  }
}

// Remote K8s endpoint
otelcol.exporter.otlphttp "k8s" {
  client {
    endpoint = "https://otel-collector-<cluster>.tail286401.ts.net"
  }
}
```

**Alternatives Considered**:
- Single exporter: Can't support both local and remote
- No batching: Higher network overhead, less resilient

---

## R4. Beyla Process Discovery

**Decision**: Use port-based discovery with `BEYLA_OPEN_PORT` environment variable.

**Rationale**:
- Python processes show as "python3" making executable matching unreliable
- Port-based discovery is most reliable method
- Works regardless of process name

**Configuration**:
```nix
systemd.services.beyla = {
  environment = {
    BEYLA_OPEN_PORT = "4320,8080";  # otel-ai-monitor and i3pm ports
    BEYLA_SERVICE_NAME = "workstation-services";
  };
  serviceConfig = {
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
  };
};

# Kernel sysctl for eBPF access
boot.kernel.sysctl."kernel.perf_event_paranoid" = 1;
```

**Alternatives Considered**:
- Process name matching: Unreliable for Python
- CAP_SYS_ADMIN only: Overly broad permissions

---

## R5. Pyroscope Python Integration

**Decision**: Use `pkgs.pyroscope` server with SDK instrumentation in Python apps.

**Rationale**:
- `pkgs.pyroscope` (v1.13.4) available in nixpkgs
- SDK approach provides integration with existing OTLP pipeline
- py-spy available as fallback for ad-hoc profiling

**Configuration**:
```python
# In Python application
import pyroscope

pyroscope.configure(
    application_name = "otel-ai-monitor",
    server_address = "http://pyroscope.tail286401.ts.net:4040",
    tags = {
        "service": "otel-ai-monitor",
        "host": os.environ.get("HOSTNAME", "unknown")
    }
)
```

**NixOS service** (optional local server for development):
```nix
systemd.services.pyroscope = {
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.pyroscope}/bin/pyroscope server";
    DynamicUser = true;
    StateDirectory = "pyroscope";
  };
};
```

**Alternatives Considered**:
- py-spy only: No continuous storage or trends
- Alloy Pyroscope integration: Adds complexity

---

## R6. Alloy Journald Log Collection

**Decision**: Use `loki.source.journal` component with systemd unit filtering.

**Rationale**:
- Native Alloy component for journald
- Supports filtering by units and priorities
- Relabeling adds context for Loki queries

**Configuration**:
```alloy
// Collect from otel-ai-monitor
loki.source.journal "otel_monitor" {
  path = "/var/log/journal"
  matches = "_SYSTEMD_UNIT=otel-ai-monitor.service"

  labels = {
    job = "systemd-journal"
    service = "otel-ai-monitor"
  }

  forward_to = [loki.write.k8s.receiver]
}

// Collect from i3pm daemon
loki.source.journal "i3pm" {
  matches = "_SYSTEMD_UNIT=i3pm-daemon.service"

  labels = {
    job = "systemd-journal"
    service = "i3pm-daemon"
  }

  forward_to = [loki.write.k8s.receiver]
}

// Add hostname metadata
loki.relabel "add_host" {
  forward_to = [loki.write.k8s.receiver]

  rule {
    source_labels = ["__journal__hostname"]
    target_label  = "host"
  }
}

loki.write "k8s" {
  endpoint {
    url = "https://loki-<cluster>.tail286401.ts.net/loki/api/v1/push"
  }
}
```

**Recommended labels**:
- `service`: Service name from `_SYSTEMD_UNIT`
- `level`: Log level from `PRIORITY_KEYWORD`
- `host`: Hostname
- `job`: Always "systemd-journal"

**Alternatives Considered**:
- Promtail: Deprecated in favor of Alloy
- Manual log file parsing: Less reliable than journald

---

## R7. Systemd Service Ordering

**Decision**: Use `after` and `wants` directives; Alloy starts first.

**Rationale**:
- `after` ensures proper startup order
- `wants` creates soft dependency (system boots if Alloy fails)
- Prevents telemetry loss during boot

**Configuration**:
```nix
systemd.services.grafana-alloy = {
  wantedBy = [ "multi-user.target" ];
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];

  serviceConfig = {
    Type = "simple";
    ExecStart = "${pkgs.grafana-alloy}/bin/alloy run /etc/alloy/config.alloy";
    Restart = "always";
    RestartSec = "5s";
  };
};

# otel-ai-monitor depends on Alloy
systemd.services.otel-ai-monitor = {
  after = [ "grafana-alloy.service" ];
  wants = [ "grafana-alloy.service" ];
};

# Beyla depends on Alloy
systemd.services.beyla = {
  after = [ "grafana-alloy.service" ];
  wants = [ "grafana-alloy.service" ];
};
```

**Alternatives Considered**:
- `requires` instead of `wants`: Too strict; system shouldn't fail if Alloy has issues
- No ordering: Telemetry lost during boot

---

## Summary

| Component | Package Source | Status |
|-----------|----------------|--------|
| Grafana Alloy | nixpkgs (`pkgs.grafana-alloy`) | ✅ Available |
| Grafana Beyla | Custom derivation | ⚠️ Needs creation |
| Pyroscope | nixpkgs (`pkgs.pyroscope`) | ✅ Available |
| py-spy | nixpkgs (`pkgs.py-spy`) | ✅ Available (fallback) |

**Key Implementation Notes**:
1. Alloy is the unified collector, replacing otel-ai-collector
2. Beyla requires custom derivation + CAP_BPF capabilities
3. Service ordering: Alloy → Beyla/otel-ai-monitor/i3pm-daemon
4. Journald logs filtered by systemd unit with service labels
5. Pyroscope SDK integrated into Python apps for continuous profiling
