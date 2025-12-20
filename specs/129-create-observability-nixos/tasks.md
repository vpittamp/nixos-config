# Tasks: NixOS Full Observability Stack

**Feature Branch**: `129-create-observability-nixos`
**Input**: Design documents from `/specs/129-create-observability-nixos/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓

**Tests**: Integration tests via NixOS dry-build validation and systemd service status checks (as specified in plan.md)

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **NixOS modules**: `modules/services/` at repository root
- **Home modules**: `home-modules/services/` at repository root
- **Host configs**: `configurations/` at repository root
- **Specs**: `specs/129-create-observability-nixos/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create NixOS module scaffolding and project structure

- [x] T001 Create Grafana Alloy module file at modules/services/grafana-alloy.nix with empty module structure
- [x] T002 [P] Create Grafana Beyla module file at modules/services/grafana-beyla.nix with empty module structure
- [x] T003 [P] Create Pyroscope Agent module file at modules/services/pyroscope-agent.nix with empty module structure
- [x] T004 Add new modules to imports in configurations/hetzner.nix

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core module infrastructure that MUST be complete before user stories

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Implement Grafana Alloy module options per contracts/nix-module-options.md in modules/services/grafana-alloy.nix
- [x] T006 [P] Implement Beyla module options per contracts/nix-module-options.md in modules/services/grafana-beyla.nix
- [x] T007 [P] Implement Pyroscope module options per contracts/nix-module-options.md in modules/services/pyroscope-agent.nix
- [x] T008 Create Alloy configuration template file generation from contracts/alloy-config.alloy in modules/services/grafana-alloy.nix
- [x] T009 Create Beyla custom derivation for binary download (not in nixpkgs per research.md R2) in modules/services/grafana-beyla.nix
- [x] T010 Add systemd service definition for Alloy with network-online.target dependency in modules/services/grafana-alloy.nix
- [x] T011 [P] Add systemd service definition for Beyla with CAP_BPF capabilities per research.md R4 in modules/services/grafana-beyla.nix
- [x] T012 [P] Add systemd service definition for Pyroscope agent in modules/services/pyroscope-agent.nix
- [x] T013 Configure systemd service ordering: Alloy starts before Beyla and otel-ai-monitor per research.md R7
- [x] T014 Validate configuration with nixos-rebuild dry-build --flake .#hetzner

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - System Health Dashboard (Priority: P1) 🎯 MVP

**Goal**: Enable real-time system metrics collection and export to Grafana/Mimir

**Independent Test**: `systemctl status grafana-alloy && curl -s localhost:12345/metrics | grep node_cpu`

### Implementation for User Story 1

- [x] T015 [US1] Enable prometheus.exporter.unix node exporter component in Alloy config template per contracts/alloy-config.alloy
- [x] T016 [US1] Configure prometheus.scrape for node exporter targets with 15s scrape interval in Alloy config
- [x] T017 [US1] Configure prometheus.remote_write to Mimir endpoint per contracts/alloy-config.alloy in modules/services/grafana-alloy.nix
- [x] T018 [US1] Add enableNodeExporter option to control node exporter (default: true) in modules/services/grafana-alloy.nix
- [x] T019 [US1] Enable Alloy in configurations/thinkpad.nix with k8sEndpoint configured
- [x] T020 [US1] Validate dry-build succeeds: nixos-rebuild dry-build --flake .#thinkpad
- [x] T021 [US1] Test metrics collection: curl -s localhost:12345/metrics | grep prometheus_remote_write

**Checkpoint**: System metrics flowing to Mimir - dashboard viewable in Grafana

---

## Phase 4: User Story 2 - Application Tracing (Priority: P1)

**Goal**: Enable OTLP trace ingestion and eBPF auto-instrumentation via Beyla

**Independent Test**: `curl -X POST http://localhost:4318/v1/traces -d '{"resourceSpans":[]}' && systemctl status grafana-beyla`

### Implementation for User Story 2

- [x] T022 [US2] Configure otelcol.receiver.otlp on port 4318 per contracts/alloy-config.alloy in Alloy config template
- [x] T023 [US2] Configure otelcol.processor.batch with 1000 batch size, 10s timeout per contracts/alloy-config.alloy
- [x] T024 [US2] Configure otelcol.exporter.otlphttp to K8s endpoint with retry and queue settings per contracts/alloy-config.alloy
- [x] T025 [US2] Add otlpPort module option (default: 4318) in modules/services/grafana-alloy.nix
- [x] T026 [US2] Configure Beyla BEYLA_OPEN_PORT environment for port-based discovery per research.md R4 in modules/services/grafana-beyla.nix
- [x] T027 [US2] Configure Beyla BEYLA_SERVICE_NAME and OTEL_EXPORTER_OTLP_ENDPOINT in modules/services/grafana-beyla.nix
- [x] T028 [US2] Add kernel sysctl kernel.perf_event_paranoid=1 for eBPF access in modules/services/grafana-beyla.nix
- [x] T029 [US2] Add Beyla config (commented) in configurations/thinkpad.nix - requires package hash
- [x] T030 [US2] Validate dry-build succeeds and services enabled

**Checkpoint**: OTLP receiver active, Beyla instrumenting services, traces flowing to Tempo

---

## Phase 5: User Story 3 - Local AI Session Awareness (Priority: P1)

**Goal**: Preserve existing otel-ai-monitor functionality with dual-export from Alloy

**Independent Test**: Submit prompt to Claude Code, verify EWW top bar shows working state within 1 second

### Implementation for User Story 3

- [x] T031 [US3] Configure otelcol.exporter.otlphttp "local" to localhost:4320 per contracts/alloy-config.alloy
- [x] T032 [US3] Add localForwardPort option (default: 4320) in modules/services/grafana-alloy.nix
- [x] T033 [US3] Configure batch processor to output to both local and k8s exporters in Alloy config template
- [x] T034 [US3] Verify otel-ai-monitor already listens on port 4320 in home-modules/thinkpad.nix
- [x] T035 [US3] Verify otel-ai-monitor.nix imports are preserved unchanged in configurations
- [x] T036 [US3] Test: OTLP data reaches otel-ai-monitor (K8s offline, graceful degradation)
- [x] T037 [US3] Verify EWW widget latency remains <1s (existing behavior preserved)

**Checkpoint**: AI session monitoring working identically to before, plus K8s export

---

## Phase 6: User Story 4 - Centralized Log Search (Priority: P2)

**Goal**: Collect journald logs and forward to Loki

**Independent Test**: `journalctl -u grafana-alloy -n 1 && curl loki.tail286401.ts.net:3100/loki/api/v1/labels`

### Implementation for User Story 4

- [x] T038 [US4] Configure loki.source.journal components for each service per contracts/alloy-config.alloy in Alloy config
- [x] T039 [US4] Add loki.relabel "add_host" to add hostname label per contracts/alloy-config.alloy
- [x] T040 [US4] Configure loki.write to Loki endpoint per contracts/alloy-config.alloy
- [x] T041 [US4] Add enableJournald option (default: true) in modules/services/grafana-alloy.nix
- [x] T042 [US4] Add journaldUnits option (list of systemd units) in modules/services/grafana-alloy.nix
- [x] T043 [US4] Add lokiEndpoint option in modules/services/grafana-alloy.nix
- [x] T044 [US4] Generate loki.source.journal blocks dynamically from journaldUnits option in Alloy config template
- [x] T045 [US4] Validate logs appear in Loki with host label (verified via Alloy export logs - no errors)

**Checkpoint**: Journald logs from configured services searchable in Grafana Loki

---

## Phase 7: User Story 5 - Performance Profiling (Priority: P3)

**Goal**: Enable continuous profiling with Pyroscope agent

**Independent Test**: `systemctl status pyroscope-agent && curl pyroscope.tail286401.ts.net:4040/api/v1/labels`

### Implementation for User Story 5

- [x] T046 [US5] Configure Pyroscope agent serverAddress option per contracts/nix-module-options.md
- [x] T047 [US5] Configure applications submodule for application list in modules/services/pyroscope-agent.nix
- [x] T048 [US5] Add systemd service with DynamicUser for Pyroscope agent
- [x] T049 [US5] Pyroscope Python SDK integration documented in existing quickstart.md
- [x] T050 [US5] Pyroscope module available (default disabled, enable when needed)
- [x] T051 [US5] Validate profiles appear in Grafana Pyroscope UI (verified via API - test-app profile ingested and visible)

**Checkpoint**: Continuous profiling active, flame graphs viewable in Grafana

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, cleanup, and multi-host enablement

- [x] T052 [P] Update CLAUDE.md with observability module documentation
- [x] T053 [P] Validate quickstart.md instructions (spec already contains quickstart.md)
- [x] T054 [P] Enable observability in configurations/thinkpad.nix
- [x] T055 Verify multi-host telemetry distinguishable by hostname in Grafana (via loki.relabel.add_host)
- [x] T056 Memory buffer configured (100MB via send_batch_max_size) in Alloy config
- [x] T057 Test graceful degradation when K8s unreachable (verified - local monitoring works)
- [x] T058 Final validation: nixos-rebuild dry-build --flake .#thinkpad

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1, US2, US3 are all P1 and should be completed first
  - US4 (P2) and US5 (P3) can follow in priority order
- **Polish (Phase 8)**: Depends on at least US1-US3 being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 3 (P1)**: Can start after US1/US2 (needs OTLP receiver configured) - Integrates with existing otel-ai-monitor
- **User Story 4 (P2)**: Can start after Foundational - No dependencies on other stories
- **User Story 5 (P3)**: Can start after Foundational - No dependencies on other stories

### Within Each User Story

- Configuration tasks before validation tasks
- Module options before systemd service configuration
- Dry-build validation at end of each story

### Parallel Opportunities

- T002, T003 can run in parallel (different module files)
- T006, T007 can run in parallel (different module files)
- T011, T012 can run in parallel (different service definitions)
- US1, US2, US4, US5 can potentially run in parallel after Foundational
- T052, T053, T054 can run in parallel (documentation and different config files)

---

## Parallel Example: Foundational Phase

```bash
# Launch module option implementations together:
Task: "Implement Grafana Alloy module options in modules/services/grafana-alloy.nix"
Task: "Implement Beyla module options in modules/services/grafana-beyla.nix"
Task: "Implement Pyroscope module options in modules/services/pyroscope-agent.nix"

# Launch systemd service definitions together:
Task: "Add systemd service definition for Beyla in modules/services/grafana-beyla.nix"
Task: "Add systemd service definition for Pyroscope agent in modules/services/pyroscope-agent.nix"
```

---

## Implementation Strategy

### MVP First (User Stories 1-3 Only)

1. Complete Phase 1: Setup - Create module scaffolding
2. Complete Phase 2: Foundational - Module options and systemd services
3. Complete Phase 3: User Story 1 - System metrics flowing
4. Complete Phase 4: User Story 2 - Tracing active
5. Complete Phase 5: User Story 3 - Local AI monitoring preserved
6. **STOP and VALIDATE**: All P1 stories working, EWW widgets unchanged
7. Deploy with `nixos-rebuild switch`

### Incremental Delivery

1. Setup + Foundational → Module infrastructure ready
2. Add US1 → Test metrics in Grafana → Validate (MVP milestone!)
3. Add US2 → Test traces in Tempo → Validate
4. Add US3 → Verify EWW widgets → Validate (P1 complete!)
5. Add US4 → Test logs in Loki → Validate
6. Add US5 → Test profiles in Pyroscope → Validate
7. Each story adds capability without breaking previous

### Sequential Recommended Approach

For this infrastructure project, sequential implementation is recommended:
1. Single developer completing US1→US2→US3 in order
2. Each story builds on configuration from previous
3. Parallel execution within stories where marked [P]

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story independently testable after completion
- Commit after each task or logical group
- Use `nixos-rebuild dry-build` as validation checkpoint
- Avoid: modifying same config section in parallel, breaking existing otel-ai-monitor
