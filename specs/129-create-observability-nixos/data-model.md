# Data Model: NixOS Full Observability Stack

**Feature**: 129-create-observability-nixos
**Date**: 2025-12-19

## Overview

This feature is infrastructure-as-code (NixOS modules) with no custom data persistence. Data flows through existing protocols (OTLP, Loki API, Pyroscope API) to remote Kubernetes storage.

## Entities

### NixOS Module Options

#### `services.grafana-alloy`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable Grafana Alloy telemetry collector |
| `configFile` | path | null | Path to Alloy configuration file |
| `package` | package | pkgs.grafana-alloy | Alloy package to use |
| `otlpPort` | port | 4318 | OTLP HTTP receiver port |
| `localForwardPort` | port | 4320 | Port for local otel-ai-monitor |
| `k8sEndpoint` | string | "" | Kubernetes OTEL collector endpoint |
| `lokiEndpoint` | string | "" | Loki push endpoint |
| `enableNodeExporter` | bool | true | Collect system metrics |
| `enableJournald` | bool | true | Collect journald logs |
| `journaldUnits` | list[string] | [] | Systemd units to collect logs from |

#### `services.grafana-beyla`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable Beyla eBPF auto-instrumentation |
| `package` | package | (custom) | Beyla package |
| `openPorts` | string | "" | Comma-separated ports to instrument |
| `serviceName` | string | "workstation" | Service name for traces |
| `alloyEndpoint` | string | "localhost:4318" | OTLP endpoint for traces |

#### `services.pyroscope-agent`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable Pyroscope profiling |
| `serverAddress` | string | "" | Remote Pyroscope server address |
| `applications` | list[attrs] | [] | Applications to profile |

### Telemetry Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Data Flow Diagram                         │
└─────────────────────────────────────────────────────────────────┘

Source                    Collector              Destination
──────                    ─────────              ───────────

Claude Code ─────┐
Codex CLI ───────┼──► OTLP HTTP ──► Alloy ──┬──► otel-ai-monitor (local)
Gemini CLI ──────┘     :4318                │
                                            └──► K8s OTEL Collector
                                                    │
Python daemons ──► Beyla eBPF ──► Alloy ────────────┤
                                                    │
Node Exporter ──► Prometheus ──► Alloy ─────────────┼──► Mimir (K8s)
  (system)        metrics                           │
                                                    │
Journald ──────► Loki source ──► Alloy ─────────────┼──► Loki (K8s)
  (logs)                                            │
                                                    │
Python apps ───► Pyroscope SDK ─────────────────────┴──► Pyroscope (K8s)
  (profiles)
```

### Signal Types

| Signal | Format | Source | Destination |
|--------|--------|--------|-------------|
| Traces | OTLP | AI CLIs, Beyla | Tempo (K8s) |
| Metrics | OTLP/Prometheus | Node exporter, apps | Mimir (K8s) |
| Logs | Loki API | Journald | Loki (K8s) |
| Profiles | Pyroscope API | Python SDK | Pyroscope (K8s) |

## State Transitions

### Service Lifecycle

```
                        ┌─────────────────┐
                        │    STOPPED      │
                        └────────┬────────┘
                                 │ systemctl start
                                 ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     FAILED      │◄────│   STARTING      │────►│    RUNNING      │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
        │                        ▲                       │
        │                        │ restart               │
        │                        │                       │
        └────────────────────────┴───────────────────────┘
                                 │
                                 │ K8s unreachable
                                 ▼
                        ┌─────────────────┐
                        │   DEGRADED      │
                        │ (local only)    │
                        └─────────────────┘
```

### Telemetry Buffering States

```
                    ┌─────────────────┐
                    │    FLOWING      │ (normal operation)
                    └────────┬────────┘
                             │ K8s unreachable
                             ▼
┌─────────────────┐ ┌─────────────────┐
│    DROPPING     │◄│   BUFFERING     │ (memory queue active)
│ (buffer full)   │ └────────┬────────┘
└─────────────────┘          │ K8s recovers
                             ▼
                    ┌─────────────────┐
                    │   FLUSHING      │ (draining buffer)
                    └────────┬────────┘
                             │ buffer empty
                             ▼
                    ┌─────────────────┐
                    │    FLOWING      │
                    └─────────────────┘
```

## Validation Rules

### Module Configuration

1. **K8s endpoint required**: If `services.grafana-alloy.k8sEndpoint` is empty, warn but allow (local-only mode)
2. **Port conflicts**: Verify `otlpPort` (4318) and `localForwardPort` (4320) are not in use
3. **Beyla kernel requirements**: Fail if kernel < 5.8 or BTF not available
4. **Journald units exist**: Warn if specified units don't exist on system

### Runtime Validation

1. **Alloy health check**: `/metrics` endpoint returns 200
2. **OTLP receiver**: Accepts POST to `/v1/traces`, `/v1/logs`, `/v1/metrics`
3. **Beyla attached**: Log "attached to process" for each discovered process
4. **K8s connectivity**: Test connection to k8sEndpoint on startup

## Relationships

```
┌────────────────────────────────────────────────────────────────────┐
│                     NixOS Module Relationships                      │
└────────────────────────────────────────────────────────────────────┘

┌─────────────────────┐
│ configurations/     │
│   hetzner-sway.nix  │
│   thinkpad.nix      │
└─────────┬───────────┘
          │ imports
          ▼
┌─────────────────────┐     ┌─────────────────────┐
│ modules/services/   │────►│ home-modules/       │
│   grafana-alloy.nix │     │ services/           │
│   grafana-beyla.nix │     │   otel-ai-monitor   │
│   pyroscope-agent   │     └─────────────────────┘
└─────────────────────┘               │
          │                           │ depends on (after)
          │                           ▼
          │                 ┌─────────────────────┐
          └────────────────►│ systemd ordering    │
                            │   alloy → beyla     │
                            │   alloy → otel-ai   │
                            └─────────────────────┘
```

## Data Retention

| Signal | Local Retention | Remote Retention (K8s) |
|--------|-----------------|------------------------|
| Traces | None (forwarded) | 30 days |
| Metrics | None (forwarded) | 30 days |
| Logs | Journald default | 30 days |
| Profiles | None (forwarded) | 30 days |

## Identity and Uniqueness

### Host Identification

All telemetry includes host identification via:
- `host.name`: Hostname from `/etc/hostname`
- `service.instance.id`: Unique per-workstation identifier
- `resource.attributes.host`: For Loki labels

### Session Identification

AI session tracking (preserved from Feature 123):
- `session.id`: UUID per conversation
- `tool`: claude-code, codex-cli, gemini-cli
- `project`: Extracted from window marks
