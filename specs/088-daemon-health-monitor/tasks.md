# Tasks: Daemon Health Monitoring System

**Input**: Design documents from `/home/vpittamp/nixos-088-daemon-health-monitor/specs/088-daemon-health-monitor/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Tests**: Tests are NOT included in this task list (not explicitly requested in specification)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and test infrastructure setup

- [x] T001 Create test directory structure at `tests/088-daemon-health-monitor/unit/`, `tests/088-daemon-health-monitor/integration/`, `tests/088-daemon-health-monitor/fixtures/`
- [x] T002 [P] Create mock systemctl output fixtures in `tests/088-daemon-health-monitor/fixtures/mock_systemctl_output.json` with sample active, failed, disabled, and socket-activated service data
- [x] T003 [P] Create sample monitor profile fixtures in `tests/088-daemon-health-monitor/fixtures/sample_monitor_profiles.json` for local-only, local+1vnc, dual, triple profiles

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Service registry and health classification logic that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Define SERVICE_REGISTRY constant in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` with all 17 services categorized into core/ui/system/optional with metadata (name, display_name, is_user_service, socket_activated, conditional, etc.)
- [x] T005 [P] Implement `read_monitor_profile()` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to read current profile from `~/.config/sway/monitor-profile.current`
- [x] T006 [P] Implement `get_monitored_services(monitor_profile)` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to filter service list based on current monitor profile
- [x] T007 Implement `classify_health_state(load_state, active_state, sub_state, unit_file_state, restart_count, is_conditional, should_be_active)` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to map systemd states to health states (healthy/degraded/critical/disabled/unknown)
- [x] T008 [P] Implement `format_uptime(uptime_seconds)` helper function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to convert seconds to human-friendly format (e.g., "5h 23m")
- [x] T009 [P] Implement `get_status_icon(health_state)` helper function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to map health states to icons (✓/⚠/✗/○/?)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Quick Health Status Check (Priority: P1) 🎯 MVP

**Goal**: Display all critical daemon status indicators with current health state (healthy/degraded/critical) in the Health tab after system reboot

**Independent Test**: Perform a NixOS rebuild, reboot the system, open monitoring panel (Mod+M), switch to Health tab (Alt+4), verify all service indicators show current health state with service names visible

### Implementation for User Story 1

- [x] T010 [P] [US1] Implement `query_service_health(service_name, is_user_service, socket_name)` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to query systemctl for service properties (LoadState, ActiveState, SubState, UnitFileState, MainPID, TriggeredBy) and return dict
- [x] T011 [P] [US1] Implement `parse_systemctl_output(stdout)` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to parse KEY=VALUE format from systemctl show command into dict
- [x] T012 [US1] Implement `build_service_health(service_def, systemctl_props, monitor_profile)` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to construct ServiceHealth object from service definition and systemctl properties (depends on T010, T011)
- [x] T013 [US1] Enhance `query_health_data()` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to query all services from registry, build ServiceHealth objects, and group into ServiceCategory objects (depends on T012)
- [x] T014 [US1] Implement `build_system_health(categories, monitor_profile)` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to aggregate category health into SystemHealth response with timestamp and error handling
- [x] T015 [US1] Update `query_health_data()` to return SystemHealth JSON response matching data-model.md schema (depends on T013, T014)
- [x] T016 [US1] Update Health tab UI in `home-modules/desktop/eww-monitoring-panel.nix` to consume health data via defpoll, render service categories with health cards showing service name and status icon
- [x] T017 [US1] Add Catppuccin Mocha color styling for health states in `home-modules/desktop/eww-monitoring-panel.nix` (healthy=green #a6e3a1, degraded=yellow #f9e2af, critical=red #f38ba8, disabled=gray #6c7086, unknown=orange #fab387)

**Checkpoint**: At this point, User Story 1 should be fully functional - all service health indicators visible in Health tab with correct colors

---

## Phase 4: User Story 2 - Identify Failed Services After Rebuild (Priority: P1)

**Goal**: Show failed daemons with critical/red indicators and display timestamp of last known healthy state

**Independent Test**: Intentionally break a service configuration (invalid path in service definition), run nixos-rebuild switch, view Health tab to verify broken service is flagged as critical with error details

### Implementation for User Story 2

- [x] T018 [P] [US2] Implement `calculate_uptime(active_enter_timestamp)` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to parse ActiveEnterTimestamp and calculate uptime_seconds from current time
- [x] T019 [P] [US2] Add uptime calculation to `build_service_health()` in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` by querying ActiveEnterTimestamp property and calling calculate_uptime() (depends on T018)
- [x] T020 [P] [US2] Add memory usage query to `query_service_health()` in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` by including MemoryCurrent property and converting bytes to MB
- [x] T021 [P] [US2] Add restart count query to `query_service_health()` in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` by including NRestarts property
- [x] T022 [US2] Update Health tab UI in `home-modules/desktop/eww-monitoring-panel.nix` to display uptime_friendly string next to each service indicator
- [x] T023 [US2] Update Health tab UI in `home-modules/desktop/eww-monitoring-panel.nix` to show last_active_time timestamp for failed/stopped services
- [x] T024 [US2] Add visual differentiation in `home-modules/desktop/eww-monitoring-panel.nix` for multiple failed services (ensure each appears as separate card with distinct borders)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - failed services clearly visible with timestamps

---

## Phase 5: User Story 3 - Restart Failed Services Quickly (Priority: P2)

**Goal**: Provide one-click restart buttons for failed services with automatic sudo prompting for system services

**Independent Test**: Stop a user service (systemctl --user stop eww-top-bar), view Health tab, click restart button, verify service restarts and indicator updates to healthy within 5 seconds

### Implementation for User Story 3

- [x] T025 [P] [US3] Create restart script `home-modules/desktop/restart-service.sh` that takes service name and is_user_service flag, executes systemctl restart with appropriate flags (--user or sudo), and sends notify-send on success/failure
- [x] T026 [P] [US3] Add restart script to system packages in appropriate Nix module to make it available in PATH
- [x] T027 [US3] Update `build_service_health()` in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to set can_restart field (false if health_state is disabled or unknown with load_state not-found)
- [x] T028 [US3] Add restart button to health cards in `home-modules/desktop/eww-monitoring-panel.nix` with onclick handler calling restart-service.sh script with service name and is_user_service parameters
- [x] T029 [US3] Add visual feedback in `home-modules/desktop/eww-monitoring-panel.nix` to hide restart button when service is healthy or cannot be restarted (can_restart=false)
- [x] T030 [US3] Update Health tab UI in `home-modules/desktop/eww-monitoring-panel.nix` to show restart button only when status is not "active" (visible attribute conditional on service.status != "active")

**Checkpoint**: All user stories 1, 2, and 3 should now work independently - users can view health, identify failures, and restart services

---

## Phase 6: User Story 4 - Monitor Service Performance Metrics (Priority: P3)

**Goal**: Display memory usage and restart counters for each service to identify performance degradation or resource leaks

**Independent Test**: Run system for 24+ hours, view Health tab, verify uptime, memory usage, and restart count are displayed accurately for long-running daemons

### Implementation for User Story 4

- [x] T031 [P] [US4] Update Health tab UI in `home-modules/desktop/eww-monitoring-panel.nix` to display memory_usage_mb in health card (e.g., "165 MB" next to service name)
- [x] T032 [P] [US4] Add visual warning state in `home-modules/desktop/eww-monitoring-panel.nix` for high restart counts (yellow background if restart_count >= 3)
- [x] T033 [P] [US4] Add tooltip or secondary line in health cards in `home-modules/desktop/eww-monitoring-panel.nix` showing "Restarts: N" if restart_count > 0
- [x] T034 [US4] Implement degraded health state highlighting in `home-modules/desktop/eww-monitoring-panel.nix` for services with health_state="degraded" (yellow border, warning icon)

**Checkpoint**: All four user stories complete - full health monitoring with status, restart capabilities, and performance metrics

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements, documentation, and cleanup affecting multiple user stories

- [x] T035 [P] Add error handling to `query_health_data()` in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to catch subprocess timeouts and systemctl failures, populate error field in SystemHealth response
- [x] T036 [P] Add logging to health query functions in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` using Python logging module with appropriate log levels (INFO for queries, ERROR for failures)
- [x] T037 [P] Update `home-modules/tools/i3_project_manager/cli/README.md` to document --mode health query format and response schema
- [x] T038 [P] Add timeout protection (2-5s) to all subprocess.run calls in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to prevent hanging on systemctl failures
- [x] T039 Identify and remove legacy services (FR-008) by auditing systemd service definitions for obsolete i3-project-event-listener or other deprecated services, remove from SERVICE_REGISTRY
- [ ] T040 [P] Validate Health tab UI responsiveness on standard display sizes (1080p/1200p) - ensure all service indicators visible without scrolling per SC-006
- [ ] T041 [P] Test conditional service detection across monitor profiles (local-only, local+1vnc, dual, triple) - verify WayVNC services show as disabled vs critical appropriately
- [ ] T042 [P] Test socket-activated service detection for i3-project-daemon.socket - verify healthy status when socket is active but service is inactive
- [x] T043 Run NixOS rebuild dry-build on both platforms to validate configuration changes: `nixos-rebuild dry-build --flake .#m1 --impure` and `nixos-rebuild dry-build --flake .#hetzner-sway`
- [ ] T044 Perform end-to-end validation per quickstart.md - reboot system, verify health indicators, restart a service, check performance metrics

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P1 → P2 → P3)
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories - MVP target
- **User Story 2 (P1)**: Can start after Foundational (Phase 2) - Builds on US1 by adding uptime/timestamp display, but independently testable
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - Adds restart functionality, independent of US2 metrics
- **User Story 4 (P3)**: Can start after Foundational (Phase 2) - Adds performance metrics, independent of US3 restart

### Within Each User Story

- US1: T010, T011 can run in parallel → T012 → T013, T014 sequential → T015 → T016, T017 in parallel
- US2: T018, T019, T020, T021 can run in parallel → T022, T023, T024 sequential
- US3: T025, T026, T027 can run in parallel → T028, T029, T030 sequential
- US4: T031, T032, T033 can run in parallel → T034

### Parallel Opportunities

- **Phase 1 (Setup)**: T002, T003 can run in parallel
- **Phase 2 (Foundational)**: T005, T006, T008, T009 can run in parallel after T004
- **User Stories**: Once Foundational phase completes, US1, US2, US3, US4 can start in parallel if team capacity allows
- **Within US1**: T010, T011 in parallel; T016, T017 in parallel
- **Within US2**: T018, T019, T020, T021 all in parallel; T022, T023, T024 in parallel
- **Within US3**: T025, T026, T027 all in parallel; T028, T029, T030 in parallel
- **Within US4**: T031, T032, T033 all in parallel
- **Phase 7 (Polish)**: T035, T036, T037, T038, T040, T041, T042 can all run in parallel

---

## Parallel Example: Foundational Phase

```bash
# After T004 completes, launch these tasks in parallel:
Task: "Implement read_monitor_profile() in monitoring_data.py"
Task: "Implement get_monitored_services() in monitoring_data.py"
Task: "Implement format_uptime() in monitoring_data.py"
Task: "Implement get_status_icon() in monitoring_data.py"
```

## Parallel Example: User Story 1

```bash
# Launch service query and parsing functions in parallel:
Task: "Implement query_service_health() in monitoring_data.py"
Task: "Implement parse_systemctl_output() in monitoring_data.py"

# After T015 completes, launch UI tasks in parallel:
Task: "Update Health tab UI to consume health data in eww-monitoring-panel.nix"
Task: "Add Catppuccin Mocha color styling in eww-monitoring-panel.nix"
```

## Parallel Example: User Story 2

```bash
# Launch all metric collection enhancements in parallel:
Task: "Implement calculate_uptime() in monitoring_data.py"
Task: "Add uptime calculation to build_service_health() in monitoring_data.py"
Task: "Add memory usage query to query_service_health() in monitoring_data.py"
Task: "Add restart count query to query_service_health() in monitoring_data.py"
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only - Both P1)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T009) - CRITICAL
3. Complete Phase 3: User Story 1 (T010-T017) - Core health display
4. Complete Phase 4: User Story 2 (T018-T024) - Failed service identification
5. **STOP and VALIDATE**: Test US1 and US2 independently via quickstart.md
6. Deploy/demo if ready

**Rationale**: Both US1 and US2 are P1 priority and form the essential diagnostic capability. Users can view health and identify failures without restart functionality.

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Basic health visibility (MVP increment 1)
3. Add User Story 2 → Test independently → Failure identification with timestamps (MVP increment 2)
4. Add User Story 3 → Test independently → Restart capability (Enhancement 1)
5. Add User Story 4 → Test independently → Performance metrics (Enhancement 2)
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T009)
2. Once Foundational is done:
   - Developer A: User Story 1 (T010-T017)
   - Developer B: User Story 2 (T018-T024)
   - Developer C: User Story 3 (T025-T030)
   - Developer D: User Story 4 (T031-T034)
3. Stories complete and integrate independently
4. Team completes Polish together (T035-T044)

---

## Task Summary

**Total Tasks**: 44
- Setup (Phase 1): 3 tasks
- Foundational (Phase 2): 6 tasks (BLOCKS all user stories)
- User Story 1 (Phase 3, P1): 8 tasks
- User Story 2 (Phase 4, P1): 7 tasks
- User Story 3 (Phase 5, P2): 6 tasks
- User Story 4 (Phase 6, P3): 4 tasks
- Polish (Phase 7): 10 tasks

**Parallel Opportunities**: 24 tasks marked [P] can run concurrently with other [P] tasks in same phase

**Independent Test Criteria**:
- US1: All service health indicators visible with correct colors after reboot
- US2: Failed services show with timestamps and critical indicators
- US3: Restart buttons functional for both user and system services
- US4: Memory usage and restart counts displayed accurately

**Suggested MVP Scope**: Phase 1 + Phase 2 + Phase 3 (US1) + Phase 4 (US2) = 24 tasks for core diagnostic capability

**Format Validation**: ✅ All 44 tasks follow checklist format with checkbox, ID, [P] marker (where applicable), [Story] label (for user story phases), and file paths

---

## Notes

- [P] tasks = different files/functions, no dependencies on incomplete tasks in same phase
- [Story] label maps task to specific user story for traceability (US1/US2/US3/US4)
- Each user story should be independently completable and testable
- Constitution Principle XII (Forward-Only Development): T039 removes legacy services completely, no backwards compatibility
- Constitution Principle III (Test-Before-Apply): T043 validates with dry-build before applying
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence