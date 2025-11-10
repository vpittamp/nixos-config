# Tasks: Declarative Workspace-to-Monitor Assignment with Floating Window Configuration

**Feature**: 001-declarative-workspace-monitor
**Input**: Design documents from `/etc/nixos/specs/001-declarative-workspace-monitor/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Tests**: Test tasks included per Constitution Principle XIV (Test-Driven Development) and Principle XV (Sway Test Framework Standards)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md Project Structure:
- **Nix Config Extensions**: `/etc/nixos/home-modules/desktop/`, `/etc/nixos/shared/`
- **Python Daemon Extensions**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/`
- **Tests**: `/etc/nixos/tests/001-declarative-workspace-monitor/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and test structure

- [X] T001 Create test directory structure at `/etc/nixos/tests/001-declarative-workspace-monitor/` with subdirectories: `unit/`, `integration/`, `sway-tests/`
- [X] T002 [P] Configure pytest fixtures for async i3ipc in `/etc/nixos/tests/001-declarative-workspace-monitor/conftest.py`
- [X] T003 [P] Create JSON schema validation helper for testing in `/etc/nixos/tests/001-declarative-workspace-monitor/unit/test_schema_validation.py`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models and utilities that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create MonitorRole enum in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/monitor_config.py`
- [X] T005 [P] Create FloatingSize enum in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/floating_config.py`
- [X] T006 [P] Create Scope enum in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/floating_config.py`
- [X] T007 Create OutputInfo Pydantic model in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/monitor_config.py`
- [X] T008 [P] Create MonitorRoleConfig Pydantic model in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/monitor_config.py`
- [X] T009 [P] Create MonitorRoleAssignment Pydantic model in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/monitor_config.py`
- [X] T010 [P] Create WorkspaceAssignment Pydantic model in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/monitor_config.py`
- [X] T011 [P] Create FloatingWindowConfig Pydantic model in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/floating_config.py`
- [X] T012 Create MonitorStateV2 Pydantic model with migration logic from v1.0 in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/monitor_config.py`
- [X] T013 Create floating size preset mapping constant (FLOATING_SIZE_DIMENSIONS) in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/models/floating_config.py`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Declarative Monitor Role Assignment for Applications (Priority: P1) 🎯 MVP

**Goal**: Enable declaring `preferred_monitor_role` in `app-registry-data.nix` for workspace-to-monitor assignment

**Independent Test**: Add `preferred_monitor_role = "primary"` to VS Code app definition, rebuild system, verify workspace 2 appears on primary monitor (HEADLESS-1)

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T014 [P] [US1] Create pytest unit test for MonitorRoleConfig parsing from Nix in `/etc/nixos/tests/001-declarative-workspace-monitor/unit/test_monitor_role_config.py`
- [X] T015 [P] [US1] Create pytest unit test for monitor role validation (primary/secondary/tertiary) in `/etc/nixos/tests/001-declarative-workspace-monitor/unit/test_monitor_role_validation.py`
- [X] T016 [P] [US1] Create sway-test JSON for VS Code on primary monitor in `/etc/nixos/tests/001-declarative-workspace-monitor/sway-tests/test_vs_code_primary_monitor.json`
- [X] T017 [P] [US1] Create sway-test JSON for multiple apps with same monitor role in `/etc/nixos/tests/001-declarative-workspace-monitor/sway-tests/test_multiple_apps_same_role.json`

### Implementation for User Story 1

- [X] T018 [US1] Add `preferred_monitor_role` field to mkApp function in `/etc/nixos/home-modules/desktop/app-registry-data.nix` with validation
- [X] T019 [US1] Add Nix validation function for monitor role enum in `/etc/nixos/home-modules/desktop/app-registry-data.nix`
- [X] T020 [US1] Create MonitorRoleResolver class with resolve_role() method in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/monitor_role_resolver.py`
- [X] T021 [US1] Implement connection order-based role assignment logic in MonitorRoleResolver.resolve_role()
- [X] T022 [US1] Implement workspace-to-role inference logic (WS 1-2→primary, 3-5→secondary, 6+→tertiary) in MonitorRoleResolver
- [X] T023 [US1] Add logging for monitor role assignments at INFO level in MonitorRoleResolver
- [X] T024 [US1] Create workspace-assignments.json generation script that reads from app-registry-data.nix in `/etc/nixos/home-modules/desktop/sway.nix`
- [X] T025 [US1] Integrate MonitorRoleResolver with Feature 049's workspace_assignment_manager.py to use monitor roles for output resolution

**Checkpoint**: At this point, User Story 1 should be fully functional - apps can declare monitor roles in Nix config

---

## Phase 4: User Story 2 - Automatic Fallback for Reduced Monitor Configurations (Priority: P1)

**Goal**: Implement automatic workspace reassignment when monitors disconnect (tertiary→secondary→primary fallback)

**Independent Test**: Configure apps for 3 monitors, disconnect tertiary monitor, verify workspaces reassign to secondary within 1 second

### Tests for User Story 2

- [X] T026 [P] [US2] Create pytest integration test for tertiary→secondary fallback in `/etc/nixos/tests/001-declarative-workspace-monitor/integration/test_monitor_fallback.py`
- [X] T027 [P] [US2] Create pytest integration test for secondary→primary fallback in `/etc/nixos/tests/001-declarative-workspace-monitor/integration/test_monitor_fallback.py`
- [X] T028 [P] [US2] Create sway-test JSON for monitor disconnect/reconnect scenario in `/etc/nixos/tests/001-declarative-workspace-monitor/sway-tests/test_monitor_disconnect_fallback.json`
- [X] T029 [P] [US2] Create pytest integration test for automatic workspace restoration on reconnect in `/etc/nixos/tests/001-declarative-workspace-monitor/integration/test_monitor_fallback.py`

### Implementation for User Story 2

- [X] T030 [US2] Implement fallback chain logic in MonitorRoleResolver.apply_fallback() method in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/monitor_role_resolver.py`
- [X] T031 [US2] Add fallback_applied boolean tracking to MonitorRoleAssignment model usage in MonitorRoleResolver
- [X] T032 [US2] Subscribe to Sway output events (connect/disconnect) in i3pm daemon main loop in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/main.py`
- [X] T033 [US2] Implement event debouncing (500ms) for rapid output events in output event handler
- [X] T034 [US2] Trigger workspace reassignment on output event with automatic fallback in output event handler
- [X] T035 [US2] Add logging for fallback applications at WARNING level in MonitorRoleResolver.apply_fallback()
- [X] T036 [US2] Update MonitorStateV2 persistence with fallback metadata after each reassignment in workspace_assignment_manager.py

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - apps declare roles AND system handles monitor changes

---

## Phase 5: User Story 3 - PWA-Specific Monitor Preferences (Priority: P2)

**Goal**: Enable PWAs to declare monitor preferences in `pwa-sites.nix` alongside workspace assignments

**Independent Test**: Add `preferred_monitor_role = "secondary"` to YouTube PWA in pwa-sites.nix, launch PWA, verify it appears on secondary monitor

### Tests for User Story 3

- [X] T037 [P] [US3] Create pytest unit test for PWA monitor role parsing in `/etc/nixos/tests/001-declarative-workspace-monitor/unit/test_pwa_monitor_role.py`
- [X] T038 [P] [US3] Create sway-test JSON for PWA on secondary monitor in `/etc/nixos/tests/001-declarative-workspace-monitor/sway-tests/test_youtube_pwa_secondary_monitor.json`
- [X] T039 [P] [US3] Create pytest integration test for PWA preference override (PWA wins over app) in `/etc/nixos/tests/001-declarative-workspace-monitor/integration/test_pwa_preference_override.py`

### Implementation for User Story 3

- [X] T040 [P] [US3] Add `preferred_monitor_role` field to PWA definition schema in `/etc/nixos/shared/pwa-sites.nix`
- [X] T041 [US3] Extend workspace-assignments.json generation to include PWA definitions with source="pwa-sites" in `/etc/nixos/home-modules/desktop/sway.nix`
- [X] T042 [US3] Implement PWA preference priority (PWA > app) in MonitorRoleResolver conflict resolution in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/monitor_role_resolver.py`
- [X] T043 [US3] Add conflict detection logging for duplicate workspace assignments in MonitorRoleResolver

**Checkpoint**: All workspace assignment sources (apps + PWAs) now support declarative monitor roles

---

## Phase 6: User Story 4 - Declarative Floating Window Configuration (Priority: P2)

**Goal**: Enable declaring floating window behavior and size presets in app-registry-data.nix

**Independent Test**: Add `floating = true` and `floating_size = "medium"` to btop app, launch it, verify 1200×800 centered floating window on workspace 7

### Tests for User Story 4

- [ ] T044 [P] [US4] Create pytest unit test for FloatingWindowConfig validation in `/etc/nixos/tests/001-declarative-workspace-monitor/unit/test_floating_window_config.py`
- [ ] T045 [P] [US4] Create pytest unit test for floating size preset dimensions in `/etc/nixos/tests/001-declarative-workspace-monitor/unit/test_floating_size_presets.py`
- [ ] T046 [P] [US4] Create sway-test JSON for floating window size and positioning in `/etc/nixos/tests/001-declarative-workspace-monitor/sway-tests/test_floating_window_medium_size.json`
- [ ] T047 [P] [US4] Create pytest integration test for scoped floating window hiding on project switch in `/etc/nixos/tests/001-declarative-workspace-monitor/integration/test_floating_window_project_filtering.py`
- [ ] T048 [P] [US4] Create pytest integration test for global floating window persistence across projects in `/etc/nixos/tests/001-declarative-workspace-monitor/integration/test_floating_window_project_filtering.py`

### Implementation for User Story 4

- [ ] T049 [P] [US4] Add `floating` boolean field to mkApp function in `/etc/nixos/home-modules/desktop/app-registry-data.nix`
- [ ] T050 [P] [US4] Add `floating_size` field with preset validation to mkApp function in `/etc/nixos/home-modules/desktop/app-registry-data.nix`
- [ ] T051 [US4] Create FloatingWindowManager class in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/floating_window_manager.py`
- [ ] T052 [US4] Implement Sway for_window rule generation for floating windows in FloatingWindowManager
- [ ] T053 [US4] Add floating window size mapping logic (preset → dimensions) in FloatingWindowManager
- [ ] T054 [US4] Implement centered positioning logic for floating windows in FloatingWindowManager
- [ ] T055 [US4] Extend window-rules.json generation to include floating rules in `/etc/nixos/home-modules/desktop/sway.nix`
- [ ] T056 [US4] Integrate FloatingWindowManager with project filtering (scope field) in window filtering handler
- [ ] T057 [US4] Add floating window tracking via Sway marks (e.g., `mark floating:btop`) in FloatingWindowManager

**Checkpoint**: Floating window configuration now fully declarative with size presets and project filtering

---

## Phase 7: User Story 5 - Monitor Role to Output Name Mapping (Priority: P3)

**Goal**: Allow users to specify preferred physical outputs for monitor roles (e.g., HDMI-A-1 always primary)

**Independent Test**: Define `output_preferences = { primary = ["HDMI-A-1"]; }`, connect monitors in different order, verify HDMI-A-1 assigned primary role

### Tests for User Story 5

- [ ] T058 [P] [US5] Create pytest unit test for output preference parsing in `/etc/nixos/tests/001-declarative-workspace-monitor/unit/test_output_preferences.py`
- [ ] T059 [P] [US5] Create pytest integration test for preferred output assignment in `/etc/nixos/tests/001-declarative-workspace-monitor/integration/test_output_preferences.py`
- [ ] T060 [P] [US5] Create pytest integration test for fallback when preferred output disconnected in `/etc/nixos/tests/001-declarative-workspace-monitor/integration/test_output_preferences.py`

### Implementation for User Story 5

- [ ] T061 [US5] Add optional output_preferences configuration to daemon config schema in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/config.py`
- [ ] T062 [US5] Extend MonitorRoleResolver.resolve_role() to check output_preferences before connection order in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/monitor_role_resolver.py`
- [ ] T063 [US5] Add preferred_output field usage to MonitorRoleAssignment model in MonitorRoleResolver
- [ ] T064 [US5] Add logging for output preference matches and misses in MonitorRoleResolver.resolve_role()

**Checkpoint**: All user stories now complete - full declarative monitor role and floating window configuration

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Integration, documentation, and validation

- [ ] T065 [P] Create quickstart.md validation script to test all examples in `/etc/nixos/tests/001-declarative-workspace-monitor/validate_quickstart.sh`
- [ ] T066 [P] Add CLI commands for monitor role status (`i3pm monitors status`) in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/cli.py`
- [ ] T067 [P] Add CLI command for manual reassignment (`i3pm monitors reassign`) in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/cli.py`
- [ ] T068 [P] Add CLI command for monitor config display (`i3pm monitors config`) in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/cli.py`
- [ ] T069 Update CLAUDE.md with Feature 001 quick reference and CLI commands in `/etc/nixos/CLAUDE.md`
- [ ] T070 Remove hardcoded workspace distribution rules from Feature 049 (forward-only development) in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/workspace_assignment_manager.py`
- [ ] T071 Add performance monitoring (<1s reassignment, <10ms role resolution overhead) in workspace_assignment_manager.py
- [ ] T072 [P] Add error handling for invalid monitor role values with graceful fallback in MonitorRoleResolver
- [ ] T073 [P] Add error handling for invalid floating size presets with fallback to medium in FloatingWindowManager
- [ ] T074 Run full test suite (pytest unit + integration, sway-test E2E) and verify >95% pass rate
- [ ] T075 Commit all changes with feature branch message and push for review

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 (P1): Core monitor role assignment - no dependencies on other stories
  - US2 (P1): Fallback logic - depends on US1 MonitorRoleResolver
  - US3 (P2): PWA support - depends on US1 (extends same infrastructure)
  - US4 (P2): Floating windows - independent of US1-3, can start after Foundational
  - US5 (P3): Output preferences - depends on US1 MonitorRoleResolver
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1)**: Depends on US1 (extends MonitorRoleResolver) - Sequential dependency
- **User Story 3 (P2)**: Depends on US1 (reuses MonitorRoleResolver) - Sequential dependency
- **User Story 4 (P2)**: Can start after Foundational (Phase 2) - No dependencies on US1-3, PARALLEL opportunity
- **User Story 5 (P3)**: Depends on US1 (extends MonitorRoleResolver) - Sequential dependency

### Within Each User Story

- Tests MUST be written and FAIL before implementation (TDD)
- Pydantic models before service classes
- Service classes before integration with daemon
- Core implementation before CLI commands
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1**: T002 and T003 (pytest fixtures and schema helper)
- **Phase 2**: T005-T011 (all Pydantic models can be created in parallel)
- **Phase 3 Tests**: T014-T017 (all US1 tests)
- **Phase 4 Tests**: T026-T029 (all US2 tests)
- **Phase 5 Tests**: T037-T039 (all US3 tests)
- **Phase 6 Tests**: T044-T048 (all US4 tests)
- **Phase 6 Implementation**: T049-T050 (Nix field additions)
- **Phase 7 Tests**: T058-T060 (all US5 tests)
- **Phase 8**: T065-T068 (CLI commands and validation script), T072-T073 (error handling)
- **Cross-Story Parallelism**: US4 (floating windows) can be implemented in parallel with US1-3 if team capacity allows

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Create pytest unit test for MonitorRoleConfig parsing from Nix in tests/unit/test_monitor_role_config.py"
Task: "Create pytest unit test for monitor role validation in tests/unit/test_monitor_role_validation.py"
Task: "Create sway-test JSON for VS Code on primary monitor in sway-tests/test_vs_code_primary_monitor.json"
Task: "Create sway-test JSON for multiple apps with same monitor role in sway-tests/test_multiple_apps_same_role.json"

# Note: Implementation tasks are sequential within US1 due to dependencies
```

## Parallel Example: User Story 4

```bash
# Nix field additions can run in parallel:
Task: "Add `floating` boolean field to mkApp function in app-registry-data.nix"
Task: "Add `floating_size` field with preset validation to mkApp function in app-registry-data.nix"

# All US4 tests can run in parallel:
Task: "Create pytest unit test for FloatingWindowConfig validation"
Task: "Create pytest unit test for floating size preset dimensions"
Task: "Create sway-test JSON for floating window size and positioning"
Task: "Create pytest integration test for scoped floating window hiding"
Task: "Create pytest integration test for global floating window persistence"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T013) - CRITICAL, blocks all stories
3. Complete Phase 3: User Story 1 (T014-T025) - Core monitor role declaration
4. Complete Phase 4: User Story 2 (T026-T036) - Automatic fallback
5. **STOP and VALIDATE**: Test US1 + US2 independently on hetzner-sway (3 monitors) and M1 (1 monitor)
6. Deploy/demo if ready

**MVP Scope**: Declarative monitor role assignment + automatic fallback = core value proposition

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Commit (apps can declare monitor roles)
3. Add User Story 2 → Test independently → Commit (automatic fallback works)
4. **Deploy MVP** (US1 + US2)
5. Add User Story 3 → Test independently → Commit (PWAs support monitor roles)
6. Add User Story 4 → Test independently → Commit (floating window configuration)
7. Add User Story 5 → Test independently → Commit (output preferences)
8. Polish phase → Final validation → Full release

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 + 2 (sequential dependency)
   - Developer B: User Story 4 (parallel, no dependencies)
   - Developer C: Tests for US1, US2, US4
3. After US1 completes:
   - Developer A: User Story 3
   - Developer D: User Story 5
4. Polish phase: All hands

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing (TDD)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- **Constitution Compliance**:
  - Tests written before implementation (Principle XIV)
  - sway-test JSON tests use sync-based actions (Principle XV)
  - Forward-only development: remove Feature 049 hardcoded rules (Principle XII)
  - Modular composition: extend existing modules (Principle I)
  - Declarative config: all assignments in Nix (Principle VI)
