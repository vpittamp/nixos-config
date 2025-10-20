# Tasks: i3 Project System Testing & Debugging Framework

**Feature**: 018-create-a-new
**Input**: Design documents from `/specs/018-create-a-new/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Tests are OPTIONAL in this feature - only included where explicitly needed for validation framework itself.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- Python packages: `home-modules/tools/i3_project_monitor/` (existing), `home-modules/tools/i3-project-test/` (new)
- NixOS modules: `home-modules/tools/i3-project-test.nix` (new)
- Scripts: `scripts/i3-project-test` (new wrapper)
- Daemon enhancements: `home-modules/desktop/i3-project-event-daemon/ipc_server.py`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create directory structure for test framework at `home-modules/tools/i3-project-test/`
- [X] T002 Create directory structure for test framework subdirectories: `scenarios/`, `assertions/`, `reporters/`
- [X] T003 [P] Create `__init__.py` files for all new Python packages
- [X] T004 [P] Create directory structure for monitor tool validators at `home-modules/tools/i3_project_monitor/validators/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core shared infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create base models in `home-modules/tools/i3_project_monitor/models.py` - Add OutputState and WorkspaceAssignment dataclasses
- [X] T006 Create workspace validator in `home-modules/tools/i3_project_monitor/validators/workspace_validator.py` - Validates workspace-to-output assignments using i3 GET_WORKSPACES
- [X] T007 [P] Create output validator in `home-modules/tools/i3_project_monitor/validators/output_validator.py` - Validates monitor configuration using i3 GET_OUTPUTS
- [X] T008 [P] Create `__init__.py` for validators package at `home-modules/tools/i3_project_monitor/validators/__init__.py`
- [X] T009 Add new JSON-RPC method `get_diagnostic_state` to daemon in `home-modules/desktop/i3-project-event-daemon/ipc_server.py` - Single-call diagnostic capture

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Manual Interactive Testing with Live Monitoring (Priority: P1) 🎯 MVP

**Goal**: Enable developers to run project commands while observing real-time system state changes in tmux split panes, including monitor/output tracking

**Independent Test**: Run monitor in one tmux pane, execute `i3-project-switch nixos` in another pane, and visually confirm:
- Live monitor shows "Active Project: nixos" within 1 second
- Event stream displays tick event with project change payload
- Window table updates to show only nixos-scoped windows
- Monitor panel shows correct workspace-to-output assignments using i3's GET_OUTPUTS and GET_WORKSPACES data

### Implementation for User Story 1

- [X] T010 [P] [US1] Enhance live display to query i3 GET_OUTPUTS in `home-modules/tools/i3_project_monitor/displays/live.py` - Add `_render_outputs_panel()` method
- [X] T011 [P] [US1] Enhance live display to query i3 GET_WORKSPACES in `home-modules/tools/i3_project_monitor/displays/live.py` - Add `_render_workspaces_panel()` method
- [X] T012 [US1] Update live display layout to include outputs and workspaces panels in `home-modules/tools/i3_project_monitor/displays/live.py` - Modify `_create_layout()` to add new panels
- [X] T013 [US1] Update live display `_fetch_and_render()` to call validators in `home-modules/tools/i3_project_monitor/displays/live.py` - Integrate workspace_validator and output_validator
- [X] T014 [US1] Add i3 IPC connection to DaemonClient in `home-modules/tools/i3_project_monitor/daemon_client.py` - Add `get_i3_outputs()` and `get_i3_workspaces()` methods using i3ipc.aio
- [X] T015 [US1] Test live monitor display with tmux split-pane setup - Manually verify AS1.1 through AS1.5 from spec.md

**Checkpoint**: At this point, User Story 1 should be fully functional - live monitor displays complete state including monitors/workspaces

---

## Phase 4: User Story 2 - Automated State Validation Testing (Priority: P2)

**Goal**: Provide automated test framework that simulates workflows and validates state correctness

**Independent Test**: Run `i3-project-test verify-state` which creates test project, switches to it, validates daemon reports correct active project, windows marked correctly, and workspace-to-output assignments match i3 IPC data

### Implementation for User Story 2

#### Test Framework Core

- [X] T016 [P] [US2] Create BaseScenario class in `home-modules/tools/i3-project-test/scenarios/base_scenario.py` - Abstract base class with setup/execute/validate/cleanup methods
- [X] T017 [P] [US2] Create TestResult and AssertionResult models in `home-modules/tools/i3-project-test/models.py` - Data structures for test outcomes
- [X] T018 [P] [US2] Create test runner in `home-modules/tools/i3-project-test/test_runner.py` - Load scenarios, execute, collect results

#### Tmux Integration

- [X] T019 [US2] Create TmuxManager in `home-modules/tools/i3-project-test/tmux_manager.py` - Session creation, pane management, output capture, cleanup

#### Assertion Framework

- [X] T020 [P] [US2] Create daemon state assertions in `home-modules/tools/i3-project-test/assertions/state_assertions.py` - Assert active project, window count, project exists, window marked
- [X] T021 [P] [US2] Create i3 IPC assertions in `home-modules/tools/i3-project-test/assertions/i3_assertions.py` - Assert workspace visible, workspace on output, output active, output exists, window exists, mark exists
- [X] T022 [P] [US2] Create output/workspace assertions in `home-modules/tools/i3-project-test/assertions/output_assertions.py` - Assert workspace assignment valid, daemon-i3 state match
- [X] T023 [P] [US2] Create `__init__.py` for assertions at `home-modules/tools/i3-project-test/assertions/__init__.py`

#### Test Scenarios

- [X] T024 [P] [US2] Create project lifecycle scenario in `home-modules/tools/i3-project-test/scenarios/project_lifecycle.py` - Test create/delete/switch projects (implements AS2.1)
- [X] T025 [P] [US2] Create window management scenario in `home-modules/tools/i3-project-test/scenarios/window_management.py` - Test window marking and visibility (implements AS2.2)
- [X] T026 [P] [US2] Create monitor configuration scenario in `home-modules/tools/i3-project-test/scenarios/monitor_configuration.py` - Test workspace-to-output validation (implements AS2.5, AS2.6)
- [X] T027 [P] [US2] Create event stream scenario in `home-modules/tools/i3-project-test/scenarios/event_stream.py` - Test event recording and ordering (implements AS2.4)
- [X] T028 [P] [US2] Create `__init__.py` for scenarios at `home-modules/tools/i3-project-test/scenarios/__init__.py`

#### Reporting

- [X] T029 [P] [US2] Create terminal reporter in `home-modules/tools/i3-project-test/reporters/terminal_reporter.py` - Human-readable output with rich library
- [X] T030 [P] [US2] Create JSON reporter in `home-modules/tools/i3-project-test/reporters/json_reporter.py` - Machine-readable JSON/TAP output
- [X] T031 [P] [US2] Create `__init__.py` for reporters at `home-modules/tools/i3-project-test/reporters/__init__.py`

#### CLI and Integration

- [X] T032 [US2] Create CLI entry point in `home-modules/tools/i3-project-test/__main__.py` - Argument parsing, scenario selection, reporter selection, test execution
- [X] T033 [US2] Create NixOS home-manager module at `home-modules/tools/i3-project-test.nix` - Package test framework, add to PATH
- [X] T034 [US2] Create wrapper script at `scripts/i3-project-test` - Invoke Python module with proper environment
- [X] T035 [US2] Update `home-modules/profiles/base-home.nix` to import i3-project-test.nix module
- [X] T036 [US2] Test automated scenarios - Run `i3-project-test run --all` and verify AS2.1 through AS2.6

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - can manually monitor OR run automated tests

---

## Phase 5: User Story 3 - Diagnostic Reporting and State Inspection (Priority: P3)

**Goal**: Capture complete system state snapshot for post-mortem debugging

**Independent Test**: Run `i3-project-monitor diagnose --output=report.json` which captures daemon status, projects, windows, events, i3 tree, GET_OUTPUTS, GET_WORKSPACES - test succeeds if report contains all expected sections and is valid JSON

### Implementation for User Story 3

- [X] T037 [P] [US3] Create diagnose display mode in `home-modules/tools/i3_project_monitor/displays/diagnose.py` - Implement diagnostic capture logic
- [X] T038 [US3] Add diagnose mode to CLI in `home-modules/tools/i3_project_monitor/__main__.py` - Add argparse subcommand for diagnose
- [X] T039 [US3] Implement diagnostic snapshot assembly in `home-modules/tools/i3_project_monitor/displays/diagnose.py` - Call `get_diagnostic_state` JSON-RPC method, query i3 GET_TREE, assemble complete snapshot
- [X] T040 [US3] Implement JSON serialization with schema versioning in `home-modules/tools/i3_project_monitor/displays/diagnose.py` - Output to file with indent=2, include schema_version field
- [X] T041 [US3] Implement diagnostic comparison mode in `home-modules/tools/i3_project_monitor/displays/diagnose.py` - Add `--compare` flag to diff two snapshots
- [X] T042 [US3] Test diagnostic capture - Run `i3-project-monitor diagnose --output=test.json` and verify AS3.1 through AS3.5

**Checkpoint**: All three user stories should now be independently functional - manual monitoring, automated testing, and diagnostic capture

---

## Phase 6: User Story 4 - Automated Integration Test Suite (Priority: P4)

**Goal**: Comprehensive test suite for CI/CD pipeline integration

**Independent Test**: Run `i3-project-test suite --ci` in CI environment which sets up test environment, runs all scenarios, validates results, outputs report with exit code 0 for success

### Implementation for User Story 4

- [X] T043 [P] [US4] Add headless mode support to test runner in `home-modules/tools/i3-project-test/test_runner.py` - Add `--no-ui` flag that disables rich terminal output
- [X] T044 [P] [US4] Add CI mode to test runner in `home-modules/tools/i3-project-test/test_runner.py` - Add `--ci` flag that enables strict validation and full scenario execution
- [X] T045 [US4] Implement exit code handling in `home-modules/tools/i3-project-test/__main__.py` - Return 0 for all passed, 1 for failures, 2 for errors
- [X] T046 [US4] Add test result summary to terminal reporter in `home-modules/tools/i3-project-test/reporters/terminal_reporter.py` - Show passed/failed/skipped counts
- [X] T047 [US4] Add diagnostic capture on failure in `home-modules/tools/i3-project-test/test_runner.py` - Add `--capture-on-failure` flag that saves diagnostic snapshot when test fails
- [X] T048 [US4] Add test suite library expansion - Create 10+ test scenarios covering all project management workflows in `scenarios/` directory
- [X] T049 [US4] Test CI integration - Run `i3-project-test suite --ci --no-ui --format=json` and verify AS4.1 through AS4.4

**Checkpoint**: All four user stories should now be complete and independently functional

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T050 [P] Add workspace validation helper command - Create `i3-project-monitor validate-workspaces` subcommand
- [ ] T051 [P] Add connection test helper - Create `i3-project-monitor --test-connection` flag
- [ ] T052 [P] Add error handling improvements across all displays - Ensure clear error messages with troubleshooting hints (EC-001 through EC-009)
- [X] T053 [P] Update quickstart.md with real examples from implementation
- [ ] T054 [P] Add Python docstrings to all public classes and methods
- [ ] T055 [P] Add type hints validation - Run mypy on all Python modules
- [X] T056 Verify test-* namespace isolation - Ensure all test scenarios use TEST_PROJECT_PREFIX
- [X] T057 Run full validation from quickstart.md - Execute all commands in quickstart to verify completeness
- [ ] T058 [P] Add logging configuration - Ensure all modules use consistent logging format
- [X] T059 Performance validation - Verify diagnostic capture completes in <3 seconds, state validation in <2 seconds
- [X] T060 Create GitHub Actions workflow example in quickstart.md for CI/CD integration

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User Story 1 (P1) can start after Foundational - No dependencies on other stories
  - User Story 2 (P2) can start after Foundational - Depends on US1 for tmux workflow patterns but independently testable
  - User Story 3 (P3) can start after Foundational - Uses US1 monitor enhancements but independently testable
  - User Story 4 (P4) can start after US2 complete - Requires test framework from US2
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1) - Manual Monitoring**: Foundation only → Can start immediately after Phase 2
- **User Story 2 (P2) - Automated Testing**: Foundation only → Can start in parallel with US1 after Phase 2
- **User Story 3 (P3) - Diagnostic Capture**: Foundation only → Can start in parallel with US1/US2 after Phase 2
- **User Story 4 (P4) - CI/CD Integration**: Requires US2 test framework → Start after US2 complete

### Within Each User Story

- US1: Validators → Live display enhancements → Integration → Manual testing
- US2: Base classes → Tmux manager → Assertions → Scenarios → Reporters → CLI → Module → Testing
- US3: Diagnose display → CLI integration → Snapshot assembly → JSON serialization → Comparison → Testing
- US4: Headless mode → CI mode → Exit codes → Summary → Capture on failure → Scenario expansion → CI testing

### Parallel Opportunities

**Within Setup (Phase 1)**:
- T003 and T004 can run in parallel (different directories)

**Within Foundational (Phase 2)**:
- T006 and T007 can run in parallel (different files)
- T008 can run after T006/T007

**Within User Story 1 (Phase 3)**:
- T010 and T011 can run in parallel (different methods in same file if careful)
- T014 can run in parallel with T010/T011 (different file)

**Within User Story 2 (Phase 4)**:
- T016, T017, T018 can run in parallel (different files)
- T020, T021, T022 can run in parallel (different files)
- T024, T025, T026, T027 can run in parallel (different files)
- T029, T030 can run in parallel (different files)

**Within User Story 3 (Phase 5)**:
- T037 and T038 can run in parallel if T037 creates the display class and T038 adds CLI integration

**Within User Story 4 (Phase 6)**:
- T043 and T044 can run together (same file, different flags)

**Within Polish (Phase 7)**:
- T050, T051, T052, T053, T054, T055, T058 can all run in parallel (different files/concerns)

**Across User Stories** (after Foundation complete):
- User Stories 1, 2, and 3 can all proceed in parallel if team capacity allows
- User Story 4 must wait for US2 to complete

---

## Parallel Example: User Story 2 (Test Framework)

```bash
# Launch all base framework components in parallel:
Task: "Create BaseScenario class in scenarios/base_scenario.py"
Task: "Create TestResult models in models.py"
Task: "Create test runner in test_runner.py"

# Launch all assertion modules in parallel:
Task: "Create daemon state assertions in assertions/state_assertions.py"
Task: "Create i3 IPC assertions in assertions/i3_assertions.py"
Task: "Create output/workspace assertions in assertions/output_assertions.py"

# Launch all test scenarios in parallel:
Task: "Create project lifecycle scenario in scenarios/project_lifecycle.py"
Task: "Create window management scenario in scenarios/window_management.py"
Task: "Create monitor configuration scenario in scenarios/monitor_configuration.py"
Task: "Create event stream scenario in scenarios/event_stream.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T009) - CRITICAL - blocks all stories
3. Complete Phase 3: User Story 1 (T010-T015)
4. **STOP and VALIDATE**: Test User Story 1 independently using tmux split-pane setup
5. Rebuild NixOS configuration and deploy
6. Demo live monitoring capability with monitor/workspace tracking

### Incremental Delivery (Recommended)

1. Complete Setup + Foundational → Foundation ready (T001-T009)
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!) (T010-T015)
3. Add User Story 2 → Test independently → Deploy/Demo (T016-T036)
4. Add User Story 3 → Test independently → Deploy/Demo (T037-T042)
5. Add User Story 4 → Test independently → Deploy/Demo (T043-T049)
6. Polish phase → Final testing and documentation (T050-T060)

Each story adds value without breaking previous stories.

### Parallel Team Strategy

With multiple developers (not typical for home NixOS config, but if collaborating):

1. Team completes Setup + Foundational together (T001-T009)
2. Once Foundational is done:
   - Developer A: User Story 1 (T010-T015) - Monitor enhancements
   - Developer B: User Story 2 (T016-T036) - Test framework
   - Developer C: User Story 3 (T037-T042) - Diagnostic capture
3. After US2 complete:
   - Developer D: User Story 4 (T043-T049) - CI/CD integration
4. All developers: Polish phase together (T050-T060)

---

## Task Count Summary

- **Total Tasks**: 60
- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Foundational)**: 5 tasks (CRITICAL BLOCKING PHASE)
- **Phase 3 (User Story 1 - MVP)**: 6 tasks
- **Phase 4 (User Story 2)**: 21 tasks
- **Phase 5 (User Story 3)**: 6 tasks
- **Phase 6 (User Story 4)**: 7 tasks
- **Phase 7 (Polish)**: 11 tasks

### Parallel Opportunities Identified

- Setup: 2 parallel groups (50% parallelizable)
- Foundational: 2 parallel groups (40% parallelizable)
- User Story 1: 2 parallel groups (33% parallelizable)
- User Story 2: 4 major parallel groups (52% parallelizable)
- User Story 3: 1 parallel group (17% parallelizable)
- User Story 4: 1 parallel group (29% parallelizable)
- Polish: 7 parallel opportunities (64% parallelizable)

### MVP Scope (Recommended First Delivery)

**Phases 1-3 only** (15 tasks):
- Setup infrastructure
- Foundational validators and daemon enhancement
- User Story 1: Manual interactive testing with live monitoring

**Value**: Enables real-time debugging of i3 project management system with monitor/workspace tracking - immediate value for development workflow.

---

## Notes

- [P] tasks = different files, no dependencies, can be implemented in parallel
- [Story] label maps task to specific user story for traceability (US1, US2, US3, US4)
- Each user story is independently completable and testable per spec.md requirements
- All i3 IPC queries use native message types: GET_OUTPUTS, GET_WORKSPACES, GET_TREE, GET_MARKS
- Test-* namespace prefix enforced in all test scenarios for isolation (T056)
- Diagnostic snapshots use versioned JSON schema (T040)
- Exit codes properly handled for CI/CD integration (T045)
- Commit after each task or logical group for safe rollback
- Stop at any checkpoint to validate story independently before proceeding
- Verify quickstart.md examples work with real implementation (T057)
