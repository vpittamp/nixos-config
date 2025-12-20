# Feature Specification: NixOS Full Observability Stack

**Feature Branch**: `129-create-observability-nixos`
**Created**: 2025-12-19
**Status**: Draft
**Input**: User description: "Create comprehensive observability architecture using Grafana LGTM stack with local AI monitoring and remote Kubernetes storage/visualization"

## Clarifications

### Session 2025-12-19

- Q: Telemetry buffering strategy when Kubernetes backend unreachable? → A: Memory buffer with size limit (100MB) - drop oldest when full
- Q: Telemetry data retention period in Kubernetes? → A: 30 days for all signals (metrics, logs, traces, profiles)

## Background

The system currently has OpenTelemetry-based AI assistant monitoring (Feature 123) that tracks Claude Code, Codex CLI, and Gemini CLI sessions locally. This feature extends observability to capture comprehensive system telemetry including:

- System metrics (CPU, memory, disk, network)
- Application traces and spans
- Continuous profiling data
- Auto-instrumented HTTP/gRPC services
- Centralized log aggregation

The architecture maintains **local AI session monitoring** for real-time EWW widget updates while sending all telemetry to a **Kubernetes-hosted Grafana stack** for storage, analysis, and visualization.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        NixOS Workstation (Local)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Claude Code │  │ Codex CLI   │  │ Gemini CLI  │  │ Python/Go Services  │ │
│  │ (OTLP SDK)  │  │ (OTLP SDK)  │  │ (OTLP SDK)  │  │ (Auto-instrumented) │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                │                    │            │
│         └────────────────┴────────────────┴────────────────────┘            │
│                                    │                                        │
│                                    ▼                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        GRAFANA ALLOY                                 │   │
│  │                   (Unified Telemetry Collector)                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │   │
│  │  │ OTLP Receiver│  │ Beyla eBPF   │  │ Node Exporter│               │   │
│  │  │  (port 4318) │  │ (auto-instr) │  │ (unix stats) │               │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │   │
│  └──────────────────────────────┬───────────────────────────────────────┘   │
│                                 │                                           │
│         ┌───────────────────────┼───────────────────────┐                   │
│         │                       │                       │                   │
│         ▼                       ▼                       ▼                   │
│  ┌─────────────────┐    ┌─────────────────┐    ┌───────────────────┐       │
│  │ otel-ai-monitor │    │    Pyroscope    │    │ Kubernetes LGTM   │       │
│  │ (Local Sessions)│    │ (Local Profiler)│    │  (via Tailscale)  │       │
│  │       │         │    │       │         │    │                   │       │
│  │       ▼         │    └───────┼─────────┘    └─────────┬─────────┘       │
│  │  EWW Widgets    │            │                        │                 │
│  │  Notifications  │            │                        │                 │
│  └─────────────────┘            │                        │                 │
│                                 │                        │                 │
└─────────────────────────────────┼────────────────────────┼─────────────────┘
                                  │                        │
                                  │    Tailscale VPN       │
                                  │                        │
┌─────────────────────────────────┼────────────────────────┼─────────────────┐
│                                 ▼                        ▼                 │
│                      Kubernetes Cluster (Ryzen)                            │
├────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         OTEL Collector                               │  │
│  │                    (Receives from workstations)                      │  │
│  └──────────────────────────────┬───────────────────────────────────────┘  │
│                                 │                                          │
│         ┌───────────────────────┼───────────────────────┐                  │
│         ▼                       ▼                       ▼                  │
│  ┌─────────────┐         ┌─────────────┐         ┌─────────────┐          │
│  │    MIMIR    │         │    LOKI     │         │    TEMPO    │          │
│  │  (Metrics)  │         │   (Logs)    │         │  (Traces)   │          │
│  └──────┬──────┘         └──────┬──────┘         └──────┬──────┘          │
│         │                       │                       │                  │
│         └───────────────────────┼───────────────────────┘                  │
│                                 ▼                                          │
│                          ┌─────────────┐                                   │
│                          │   GRAFANA   │                                   │
│                          │ (Dashboard) │                                   │
│                          └─────────────┘                                   │
│                                 │                                          │
│                          ┌──────┴──────┐                                   │
│                          │  PYROSCOPE  │                                   │
│                          │ (Profiles)  │                                   │
│                          └─────────────┘                                   │
└────────────────────────────────────────────────────────────────────────────┘
```

**Key Design Decisions:**
1. **Local AI monitoring preserved** - otel-ai-monitor continues providing real-time session state to EWW widgets
2. **Grafana Alloy replaces otel-ai-collector** - Single unified collector with built-in exporters
3. **Beyla for auto-instrumentation** - eBPF-based HTTP/gRPC tracing without code changes
4. **Remote storage** - All telemetry persisted in Kubernetes LGTM stack via Tailscale
5. **Pyroscope dual-mode** - Local profiler agent sends to remote Pyroscope server

## User Scenarios & Testing *(mandatory)*

### User Story 1 - System Health Dashboard (Priority: P1)

As a system administrator, I want to view real-time system metrics in Grafana, so I can monitor workstation health and resource usage.

**Why this priority**: Core functionality - system observability is the primary goal of this feature.

**Independent Test**: Open Grafana dashboard, verify CPU, memory, disk, and network metrics appear from workstation within 30 seconds of enabling the service.

**Acceptance Scenarios**:

1. **Given** Alloy is running with node exporter, **When** I open Grafana system dashboard, **Then** I see current CPU, memory, disk, and network metrics
2. **Given** workstation has high CPU usage, **When** I view the dashboard, **Then** CPU graphs reflect actual usage within 15 seconds
3. **Given** multiple workstations are configured, **When** I view Grafana, **Then** I can filter/select between different hosts

---

### User Story 2 - Application Tracing (Priority: P1)

As a developer, I want to see distributed traces for my applications, so I can debug performance issues and understand request flow.

**Why this priority**: Equal to system metrics - tracing provides essential debugging capability.

**Independent Test**: Make an HTTP request to a Python service, verify trace appears in Grafana Tempo within 5 seconds.

**Acceptance Scenarios**:

1. **Given** Beyla is watching my Python daemon, **When** it handles an HTTP request, **Then** a trace span appears in Tempo
2. **Given** a trace exists, **When** I click on it in Grafana, **Then** I see the full span hierarchy with timing
3. **Given** otel-ai-monitor receives OTLP data, **When** I search traces, **Then** I can find Claude Code API request spans

---

### User Story 3 - Local AI Session Awareness (Priority: P1)

As a developer using AI assistants, I want to continue seeing real-time session status in my desktop widgets, so my existing workflow is preserved.

**Why this priority**: Critical - must not regress existing AI monitoring functionality.

**Independent Test**: Submit prompt to Claude Code, verify EWW top bar shows working state within 1 second (same as current behavior).

**Acceptance Scenarios**:

1. **Given** the new observability stack is enabled, **When** I use Claude Code, **Then** EWW widgets show session state identically to before
2. **Given** AI session completes, **When** completion occurs, **Then** desktop notification appears within 1 second
3. **Given** Kubernetes backend is unreachable, **When** I use AI assistants, **Then** local monitoring continues working

---

### User Story 4 - Centralized Log Search (Priority: P2)

As a system administrator, I want to search logs from all my workstations in one place, so I can troubleshoot issues across machines.

**Why this priority**: Important but secondary to metrics and tracing.

**Independent Test**: Generate a log message on workstation, search for it in Grafana Loki within 30 seconds.

**Acceptance Scenarios**:

1. **Given** Alloy is collecting journald logs, **When** a service logs an error, **Then** the log appears in Loki
2. **Given** logs from multiple hosts, **When** I search by hostname, **Then** I can filter to specific machine
3. **Given** a trace ID, **When** I click "logs for this trace", **Then** correlated logs appear

---

### User Story 5 - Performance Profiling (Priority: P3)

As a developer debugging performance, I want to see CPU and memory profiles for my Python daemons, so I can identify bottlenecks.

**Why this priority**: Advanced debugging feature, nice-to-have after core observability works.

**Independent Test**: Trigger load on otel-ai-monitor, view flame graph in Grafana showing hot functions.

**Acceptance Scenarios**:

1. **Given** Pyroscope agent is attached to a Python process, **When** I view Grafana profiles, **Then** I see CPU flame graph
2. **Given** continuous profiling is running, **When** I select a time range, **Then** I can compare before/after profiles
3. **Given** high memory usage, **When** I view allocation profile, **Then** I can identify memory-heavy functions

---

### Edge Cases

- What happens when Kubernetes backend is unreachable? Local AI monitoring continues; telemetry buffered in memory (100MB limit), oldest dropped when full
- What happens when Alloy crashes? Systemd restarts it; brief gap in telemetry collection
- What happens when Beyla can't attach to a process? Logs warning; process runs normally without instrumentation
- What happens when memory buffer fills? Oldest telemetry data dropped to maintain 100MB limit
- What happens when Pyroscope overhead is too high? Profiler can be disabled per-host via configuration

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy Grafana Alloy as the unified telemetry collector
- **FR-002**: System MUST collect system metrics (CPU, memory, disk, network, filesystem) via built-in node exporter
- **FR-003**: System MUST receive OTLP telemetry on port 4318 (standard) and forward to both local and remote destinations
- **FR-004**: System MUST forward AI session telemetry to otel-ai-monitor for local EWW consumption
- **FR-005**: System MUST export all telemetry to Kubernetes OTEL collector via Tailscale
- **FR-006**: System MUST deploy Grafana Beyla for eBPF-based auto-instrumentation of HTTP/gRPC services
- **FR-007**: System MUST configure Beyla to watch Python daemons (otel-ai-monitor, i3pm)
- **FR-008**: System MUST integrate Pyroscope profiling agent for continuous profiling
- **FR-009**: System MUST collect journald logs and forward to remote Loki
- **FR-010**: System MUST provide NixOS module options to enable/disable each component
- **FR-011**: System MUST preserve existing otel-ai-monitor functionality unchanged
- **FR-012**: System MUST support multiple workstations sending to same Kubernetes backend

### Key Entities

- **Grafana Alloy**: Unified OpenTelemetry collector replacing otel-ai-collector, with built-in receivers and exporters
- **Beyla**: eBPF auto-instrumentation daemon that generates traces for HTTP/gRPC without code changes
- **Pyroscope Agent**: Continuous profiling agent that captures CPU/memory profiles and sends to remote server
- **LGTM Stack**: Loki (logs), Grafana (visualization), Tempo (traces), Mimir (metrics) - hosted in Kubernetes
- **otel-ai-monitor**: Existing local service for AI session state tracking (preserved unchanged)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: System metrics appear in Grafana within 30 seconds of workstation boot
- **SC-002**: HTTP request traces appear in Tempo within 5 seconds of request completion
- **SC-003**: Existing AI session monitoring latency unchanged (state changes in EWW within 1 second)
- **SC-004**: Alloy memory usage stays below 200MB under normal operation
- **SC-005**: Beyla adds less than 5% overhead to instrumented services
- **SC-006**: Log entries searchable in Loki within 30 seconds of generation
- **SC-007**: All workstations identifiable by hostname in Grafana dashboards
- **SC-008**: Local monitoring continues functioning when Kubernetes backend unreachable

## Assumptions

1. Kubernetes cluster (Ryzen) is running and accessible via Tailscale
2. LGTM stack (Mimir, Loki, Tempo, Grafana, Pyroscope) is deployed in Kubernetes
3. Tailscale provides secure network connectivity between workstations and cluster
4. NixOS workstations have systemd for service management
5. Beyla requires Linux kernel 5.8+ with BTF support
6. Pyroscope Python integration available via pip/nix package
7. LGTM stack configured with 30-day retention for all telemetry signals

## Out of Scope

- Deploying LGTM stack in Kubernetes (assumed pre-existing)
- Alerting rules and notification channels
- Custom Grafana dashboards (use community dashboards initially)
- Windows or macOS workstation support
- Cost monitoring or usage quotas
- Multi-cluster Kubernetes support
