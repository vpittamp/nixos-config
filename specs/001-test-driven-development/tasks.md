# Tasks: Test-Driven Development Framework for Sway Window Manager

**Input**: Design documents from `/etc/nixos/specs/001-test-driven-development/`
**Prerequisites**: plan.md, spec.md, research.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. This is the TDD framework itself - tests for the framework are minimal (self-testing via Deno.test() and pytest).

## Format: `- [ ] [ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

All paths are relative to repository root `/etc/nixos/`:
- **Deno CLI**: `home-modules/tools/sway-test/`
- **Python daemon**: `home-modules/tools/i3pm/src/test_support/`
- **Example tests**: `tests/sway-tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure for both Deno CLI and Python daemon enhancements

- [X] T001 Create Deno project structure at home-modules/tools/sway-test/ with deno.json, main.ts, mod.ts
- [X] T002 Initialize deno.json with imports (@std/cli, @std/fs, @std/path, @std/json), tasks, and compiler options
- [X] T003 [P] Create Python test_support module at home-modules/tools/i3pm/src/test_support/ with __init__.py
- [X] T004 [P] Setup project README.md files for both Deno CLI (home-modules/tools/sway-test/README.md) and Python module (home-modules/tools/i3pm/src/test_support/README.md)
- [X] T005 [P] Create example test suite directory structure at tests/sway-tests/ with fixtures/, project-management/, workspace-assignment/ subdirectories
- [X] T006 [P] Add sample tree fixture at tests/sway-tests/fixtures/empty-workspace.json with minimal Sway tree structure

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T007 Create TypeScript model interfaces at home-modules/tools/sway-test/src/models/test-case.ts defining TestCase, ActionSequence, ExpectedState
- [X] T008 [P] Create TypeScript model interfaces at home-modules/tools/sway-test/src/models/state-snapshot.ts defining StateSnapshot (matching swaymsg -t get_tree structure)
- [X] T009 [P] Create TypeScript model interfaces at home-modules/tools/sway-test/src/models/test-result.ts defining TestResult, TestStatus enum
- [X] T010 Implement SwayClient service at home-modules/tools/sway-test/src/services/sway-client.ts wrapping `swaymsg` subprocess calls (getTree, sendCommand methods)
- [X] T011 Implement TreeMonitorClient service at home-modules/tools/sway-test/src/services/tree-monitor-client.ts with JSON-RPC over Unix socket (/run/user/1000/sway-tree-monitor.sock)
- [X] T012 Add connection test method ping() to TreeMonitorClient in home-modules/tools/sway-test/src/services/tree-monitor-client.ts
- [X] T013 Implement CLI argument parsing in home-modules/tools/sway-test/main.ts using @std/cli/parse-args (commands: run, validate, report)
- [X] T014 Setup Deno.test() wrapper function registerSwayTest() in home-modules/tools/sway-test/mod.ts for framework self-tests

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Basic State Comparison Testing (Priority: P1) 🎯 MVP

**Goal**: Enable developers to write simple test cases that compare expected vs actual Sway window tree state with clear diff output

**Independent Test**: Run a single test case that launches a window (e.g., Alacritty), captures state from `swaymsg -t get_tree`, and compares against predefined expected state JSON. Test passes if states match, fails with field-level diff if they diverge.

### Implementation for User Story 1

- [X] T015 [P] [US1] Implement state capture logic in home-modules/tools/sway-test/src/services/sway-client.ts method captureState() calling `swaymsg -t get_tree` and parsing JSON
- [X] T016 [P] [US1] Implement StateComparator service at home-modules/tools/sway-test/src/services/state-comparator.ts with compare() method for exact matching
- [X] T017 [US1] Add partial matching support to StateComparator using JSONPath-style queries for asserting properties without full tree specification
- [X] T018 [US1] Implement StateDiff computation in home-modules/tools/sway-test/src/services/state-comparator.ts showing added/removed/modified nodes with field-level changes (old → new)
- [X] T019 [P] [US1] Implement DiffRenderer UI component at home-modules/tools/sway-test/src/ui/diff-renderer.ts for human-readable colored diff output
- [X] T020 [P] [US1] Implement Reporter UI component at home-modules/tools/sway-test/src/ui/reporter.ts with test summary (passed/failed/skipped counts)
- [X] T021 [US1] Implement `run` command handler at home-modules/tools/sway-test/src/commands/run.ts orchestrating test execution (load → setup → capture → compare → report)
- [X] T022 [US1] Add test definition JSON schema validation using Zod in home-modules/tools/sway-test/src/commands/validate.ts
- [X] T023 [US1] Create sample test definition at tests/sway-tests/basic/test_window_launch.json with launch action and expected state
- [X] T024 [US1] Add error handling and diagnostic output for test failures in home-modules/tools/sway-test/src/commands/run.ts

**Checkpoint**: At this point, User Story 1 should be fully functional - can write and execute basic state comparison tests with clear diff output

---

## Phase 4: User Story 6 - Integration with tree-monitor Tools (Priority: P1)

**Goal**: Leverage existing `i3pm tree-monitor` daemon for event capture, field-level diffs, and user action correlation in test diagnostics

**Independent Test**: Run a test that moves a window between workspaces, verify framework connects to tree-monitor daemon via RPC, captures window:move event with field-level diff, and includes correlation data (user action + binding) in test output

### Implementation for User Story 6

- [X] T025 [P] [US6] Add queryEvents() method to TreeMonitorClient in home-modules/tools/sway-test/src/services/tree-monitor-client.ts using query_events RPC method
- [X] T026 [P] [US6] Add getLatestEvent() convenience method to TreeMonitorClient for retrieving most recent event with significance score
- [X] T027 [US6] Enhance TestResult model in home-modules/tools/sway-test/src/models/test-result.ts to include tree-monitor events array (TreeMonitorEvent[])
- [X] T028 [US6] Modify run command handler to capture tree-monitor events during test execution and attach to TestResult
- [X] T029 [US6] Enhance DiffRenderer to include tree-monitor event correlation in failure output (show user action, keybinding, field-level changes)
- [X] T030 [US6] Add daemon connectivity check in home-modules/tools/sway-test/src/commands/run.ts with actionable error message if socket not found
- [X] T031 [US6] Create integration test example at tests/sway-tests/integration/test_workspace_move_with_events.json demonstrating event correlation

**Checkpoint**: At this point, User Stories 1 AND 6 work together - tests capture state AND leverage tree-monitor for rich diagnostics

---

## Phase 5: User Story 2 - Action Sequence Execution (Priority: P2)

**Goal**: Enable defining sequences of actions (launch_app, send_ipc, wait_event) that execute before state capture to test multi-step workflows

**Independent Test**: Define test with action sequence [launch_app("firefox"), switch_workspace(2), focus_window("firefox")], execute test, verify each action runs sequentially with proper timing and final state shows Firefox focused on workspace 2

### Implementation for User Story 2

- [X] T032 [P] [US2] Implement ActionExecutor service at home-modules/tools/sway-test/src/services/action-executor.ts with execute() method for action sequences
- [X] T033 [P] [US2] Add launch_app action handler in ActionExecutor using Deno.Command to spawn subprocess with environment variables
- [X] T034 [P] [US2] Add send_ipc action handler in ActionExecutor calling SwayClient.sendCommand() for IPC commands
- [X] T035 [P] [US2] Add switch_workspace action handler in ActionExecutor sending workspace switch command via SwayClient
- [X] T036 [P] [US2] Add focus_window action handler in ActionExecutor sending focus command with window selector criteria
- [X] T037 [US2] Add wait_event action handler in ActionExecutor with timeout for window:new, window:move, workspace:focus events
- [X] T038 [US2] Add configurable delay support between actions in ActionExecutor for timing-sensitive operations
- [X] T039 [US2] Integrate ActionExecutor into run command handler to execute actions before state capture
- [X] T040 [US2] Add action failure handling with diagnostic state capture (logs, tree snapshot) on timeout or error
- [X] T041 [US2] Create multi-step test example at tests/sway-tests/workflows/test_project_switch_sequence.json with 3+ actions

**Checkpoint**: User Stories 1, 2, AND 6 work independently - can test simple state (US1), complex workflows (US2), with rich diagnostics (US6)

---

## Phase 6: User Story 3 - Live Debugging and Interactive Development (Priority: P2)

**Goal**: Enable pausing test execution, inspecting state interactively, and modifying tests on the fly for rapid iteration

**Independent Test**: Run test with debug_pause() action, verify interactive REPL appears showing tree state and available commands, execute show_diff() command, verify visual diff displays, modify test definition file and confirm framework detects change

### Implementation for User Story 3

- [X] T042 [P] [US3] Add debug_pause action handler in ActionExecutor at home-modules/tools/sway-test/src/services/action-executor.ts launching interactive REPL
- [X] T043 [US3] Implement REPL command parser in ActionExecutor supporting commands: show_diff, show_tree, run_ipc, continue, restart
- [X] T044 [US3] Add show_diff command rendering current actual vs expected state diff in REPL
- [X] T045 [US3] Add show_tree command displaying current Sway tree in readable format
- [X] T046 [US3] Add run_ipc command allowing manual IPC command execution during pause
- [X] T047 [US3] Implement file watcher for test definition using Deno.watchFs() detecting saves during debug pause
- [X] T048 [US3] Add test definition hot-reload logic offering to continue with updated steps or restart from beginning
- [X] T049 [US3] Create debugging example at tests/sway-tests/debug/test_interactive_workflow.json with debug_pause() breakpoints

**Checkpoint**: User Stories 1-3 AND 6 work independently - basic testing (US1), workflows (US2), interactive debugging (US3), diagnostics (US6)

---

## Phase 7: User Story 4 - I3_SYNC-Style Synchronization (Priority: P3)

**Goal**: Implement deterministic synchronization with Sway's event loop using SEND_TICK for 0% test flakiness

**Independent Test**: Run rapid-fire window operations (create 10 windows in 100ms), use await_sync() after launches, verify framework waits for all events to settle before capturing state with 0% flakiness over 100 runs

### Implementation for User Story 4

- [X] T050 [P] [US4] Implement sync_marker.py module at home-modules/tools/sway-tree-monitor/test_support/sync_marker.py with async send_sync_marker() function
- [X] T051 [P] [US4] Add await_sync_marker() function in sync_marker.py using i3ipc.aio Event.TICK subscription with timeout
- [X] T052 [US4] Expose sync marker RPC methods (send_sync_marker, await_sync_marker) in home-modules/tools/sway-tree-monitor/rpc/server.py
- [X] T053 [US4] Add sendSyncMarker() and awaitSyncMarker() methods to TreeMonitorClient in home-modules/tools/sway-test/src/services/tree-monitor-client.ts calling RPC methods
- [X] T054 [US4] Add await_sync action handler in ActionExecutor using TreeMonitorClient sync methods
- [X] T055 [US4] Add automatic sync after window-modifying actions (launch_app, send_ipc if creates window) in ActionExecutor
- [X] T056 [US4] Create stress test example at tests/sway-tests/stress/test_rapid_windows.json launching 10 windows with sync markers

**Checkpoint**: User Stories 1-4 AND 6 work independently - added deterministic synchronization eliminates race conditions

---

## Phase 8: User Story 5 - Test Case Organization and Reusability (Priority: P3)

**Goal**: Enable organizing tests into suites with reusable fixtures and helper functions for maintainable test codebase

**Independent Test**: Define fixture "3-monitor layout preset", reference from multiple test files, verify fixture setup runs before tests, teardown after, and shared state accessible to test cases

### Implementation for User Story 5

- [X] T057 [P] [US5] Implement FixtureManager service at home-modules/tools/sway-test/src/fixtures/fixture-manager.ts with setup/teardown lifecycle
- [X] T058 [P] [US5] Add fixture definition format supporting TypeScript functions for setup/teardown in home-modules/tools/sway-test/src/fixtures/
- [X] T059 [US5] Create example fixtures: emptyWorkspace.ts, threeMonitorLayout.ts, projectWithApps.ts in home-modules/tools/sway-test/src/fixtures/
- [X] T060 [US5] Integrate fixture loading and execution into run command handler before test execution
- [X] T061 [US5] Add fixture state passing to test execution context (TestExecutionContext) in home-modules/tools/sway-test/src/models/test-case.ts
- [X] T062 [US5] Implement assertion helper library at home-modules/tools/sway-test/src/helpers/assertions.ts with assertWindowFloating(), assertWorkspaceEmpty(), assertWindowCount()
- [X] T063 [US5] Add directory-based test filtering in run command supporting patterns like tests/project-management/
- [X] T064 [US5] Add tag-based test filtering for selective execution using test metadata tags in test definitions
- [X] T065 [US5] Create fixture usage example at tests/sway-tests/fixtures-demo/test_with_monitor_fixture.json

**Checkpoint**: All user stories except CI/CD complete - full local development workflow with organization and reusability

---

## Phase 9: User Story 7 - CI/CD Integration (Priority: P3)

**Goal**: Enable running tests in headless CI environments with machine-readable output (TAP, JUnit XML) and proper exit codes

**Independent Test**: Run test suite in Docker container with no display server, verify framework launches Sway in headless mode (WLR_BACKENDS=headless), executes tests, produces JUnit XML with correct pass/fail counts, exits with appropriate status code

### Implementation for User Story 7

- [X] T066 [P] [US7] Implement headless Sway detection and auto-launch in home-modules/tools/sway-test/src/commands/run.ts checking for WAYLAND_DISPLAY
- [X] T067 [P] [US7] Add WLR_BACKENDS=headless environment configuration for CI mode in run command
- [X] T068 [P] [US7] Implement TAP format reporter at home-modules/tools/sway-test/src/ui/tap-reporter.ts conforming to Test Anything Protocol
- [X] T069 [P] [US7] Implement JUnit XML reporter at home-modules/tools/sway-test/src/ui/junit-reporter.ts with testsuites/testsuite/testcase structure
- [X] T070 [US7] Add --format flag to run command supporting values: human (default), tap, junit
- [X] T071 [US7] Add --ci flag enabling headless mode, TAP output, and non-zero exit on failures
- [X] T072 [US7] Implement progress indicators for long-running test suites outputting every 10 seconds to prevent CI timeouts
- [X] T073 [US7] Add test timing statistics to Reporter for performance regression detection
- [X] T074 [US7] Create Dockerfile for CI testing at home-modules/tools/sway-test/Dockerfile with Sway + framework installation
- [X] T075 [US7] Create GitHub Actions workflow example at .github/workflows/sway-tests-ci.yml running tests in headless mode

**Checkpoint**: All user stories complete - full test framework with local development AND CI/CD production readiness

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final documentation

- [X] T076 [P] Add comprehensive error messages with recovery suggestions across all commands in home-modules/tools/sway-test/src/commands/
- [X] T077 [P] Implement structured logging to JSON Lines format at home-modules/tools/sway-test/src/services/logger.ts capturing IPC, actions, state captures
- [X] T078 [P] Add per-test timeout enforcement (default 30s) with diagnostic state capture on timeout in run command handler
- [X] T079 [P] Add test isolation options (separate Sway configs) to run command with --config flag
- [X] T080 [P] Create quickstart.md documentation at home-modules/tools/sway-test/docs/quickstart.md with installation, first test, common patterns
- [X] T081 [P] Create API reference documentation at home-modules/tools/sway-test/docs/api-reference.md covering TestCase format, actions, assertions
- [X] T082 [P] Add Deno compile task to deno.json for standalone executable generation
- [X] T083 [P] Create NixOS package definition for sway-test CLI tool in home-modules/tools/sway-test/default.nix
- [X] T084 [P] Add Python daemon module to i3pm package in home-modules/tools/i3pm/default.nix including test_support/ modules
- [X] T085 [P] Create integration test suite for framework self-testing at home-modules/tools/sway-test/tests/ using Deno.test()
- [X] T086 Code review and refactoring pass across all TypeScript and Python modules
- [X] T087 Performance profiling of test execution overhead targeting <100ms per test initialization
- [X] T088 Final validation: Run example test suite (tests/sway-tests/) and verify all user stories work end-to-end

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational - Basic state comparison (FOUNDATION)
- **User Story 6 (Phase 4)**: Depends on Foundational + US1 partial - tree-monitor integration (AUGMENTS US1)
- **User Story 2 (Phase 5)**: Depends on Foundational + US1 complete - Action sequences (BUILDS ON US1)
- **User Story 3 (Phase 6)**: Depends on Foundational + US1 + US2 - Debugging (AUGMENTS US1/US2)
- **User Story 4 (Phase 7)**: Depends on Foundational + US2 - Synchronization (OPTIMIZES US2)
- **User Story 5 (Phase 8)**: Depends on Foundational + US1 + US2 - Organization (MAINTAINABILITY)
- **User Story 7 (Phase 9)**: Depends on ALL user stories - CI/CD (PRODUCTION)
- **Polish (Phase 10)**: Depends on all user stories - Final touches

### User Story Dependencies

```
Foundational (Phase 2) ← BLOCKS ALL
    ↓
    ├→ US1: Basic State Comparison (Phase 3) ← MVP Foundation
    │    ↓
    │    ├→ US6: tree-monitor Integration (Phase 4) ← Augments US1
    │    └→ US2: Action Sequences (Phase 5) ← Builds on US1
    │         ↓
    │         ├→ US3: Debugging (Phase 6) ← Augments US1+US2
    │         └→ US4: Synchronization (Phase 7) ← Optimizes US2
    │              ↓
    │              └→ US5: Organization (Phase 8) ← Maintainability
    │                   ↓
    │                   └→ US7: CI/CD (Phase 9) ← Production
    │                        ↓
    │                        └→ Polish (Phase 10) ← Final
```

### Critical Path (MVP)

**Minimum for working framework**:
1. Phase 1: Setup (T001-T006)
2. Phase 2: Foundational (T007-T014)
3. Phase 3: US1 Basic State Comparison (T015-T024)

**With diagnostics** (recommended MVP):
4. Phase 4: US6 tree-monitor Integration (T025-T031)

**With workflows**:
5. Phase 5: US2 Action Sequences (T032-T041)

### Parallel Opportunities

**Within Phases**:
- Phase 1: T003, T004, T005, T006 can run in parallel with T001-T002
- Phase 2: T008, T009 parallel with T007; T010, T011 parallel after models done
- Phase 3 US1: T015, T016 parallel; T019, T020 parallel
- Phase 4 US6: T025, T026 parallel; T031 parallel with T030
- Phase 5 US2: T032-T036 all action handlers can be parallel
- Phase 6 US3: T042-T046 all REPL commands can be parallel
- Phase 7 US4: T050, T051 Python parallel with TypeScript work
- Phase 8 US5: T057-T059 parallel; T062-T064 parallel
- Phase 9 US7: T066-T069 all parallel; T074-T075 parallel
- Phase 10: T076-T085 all independent, can run in parallel

**Across Phases** (after Foundational complete):
- US1 (Phase 3) and US6 (Phase 4) can overlap - US6 starts after T021 in US1
- US3 (Phase 6) and US4 (Phase 7) can work in parallel if team capacity allows
- US5 (Phase 8) and US7 (Phase 9) can start early (US5 after US1+US2, US7 after any story complete)

---

## Parallel Example: User Story 1 (MVP)

```bash
# After Foundational complete, launch these tasks together:

# Models (already done in Foundational)
# ✓ T007, T008, T009

# Services - launch together:
Task T015: "Implement state capture in sway-client.ts"
Task T016: "Implement StateComparator service"

# UI components - launch together after T018:
Task T019: "Implement DiffRenderer"
Task T020: "Implement Reporter"

# Integration:
Task T021: "Implement run command handler" (waits for all above)
Task T022: "Add schema validation" (parallel with T021)

# Examples/Testing:
Task T023: "Create sample test definition" (parallel with T021-T022)
Task T024: "Add error handling" (after T021)
```

---

## Parallel Example: User Story 6 (tree-monitor Integration)

```bash
# After US1 T021 complete, launch these tasks together:

Task T025: "Add queryEvents() to TreeMonitorClient"
Task T026: "Add getLatestEvent() to TreeMonitorClient"
Task T027: "Enhance TestResult model"

# Then together:
Task T028: "Modify run command for event capture"
Task T029: "Enhance DiffRenderer with correlation"
Task T030: "Add daemon connectivity check"
Task T031: "Create integration test example"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 6 Only)

**Estimated: ~15-20 tasks, 3-5 days solo**

1. Complete Phase 1: Setup (T001-T006)
2. Complete Phase 2: Foundational (T007-T014)
3. Complete Phase 3: User Story 1 (T015-T024)
4. Complete Phase 4: User Story 6 (T025-T031)
5. **STOP and VALIDATE**: Write actual test using framework
6. Verify SC-001 (5min to write test), SC-002 (100% accuracy), SC-003 (<2s latency)
7. Deploy/demo MVP capability

**MVP Delivers**:
- ✅ Write test definitions in JSON
- ✅ Execute tests comparing expected vs actual state
- ✅ Get clear diff output showing what changed
- ✅ Leverage tree-monitor for rich diagnostics
- ✅ Test independently verifiable in <5 minutes

### Incremental Delivery (Add User Stories by Priority)

1. **Foundation** (Setup + Foundational) → Can't test anything yet, but structure ready
2. **Add US1** (Basic Comparison) → **TEST**: Write first test, verify it passes/fails correctly
3. **Add US6** (tree-monitor) → **TEST**: Verify test output includes event correlation
4. **Add US2** (Action Sequences) → **TEST**: Multi-step workflow test (project switch)
5. **Add US3** (Debugging) → **TEST**: Pause test, inspect state, modify definition
6. **Add US4** (Sync) → **TEST**: Rapid window creation with 0% flakiness over 100 runs
7. **Add US5** (Organization) → **TEST**: Fixture reuse across multiple tests
8. **Add US7** (CI/CD) → **TEST**: Run full suite in Docker with JUnit output
9. Each story adds value without breaking previous stories

### Parallel Team Strategy (3 developers)

With team capacity:

1. **Week 1 - Everyone**: Setup + Foundational (T001-T014)
2. **Week 2 - Split after Foundational**:
   - Dev A: US1 Basic Comparison (T015-T024)
   - Dev B: US2 Action Sequences (T032-T041, depends on T021 from Dev A)
   - Dev C: US6 tree-monitor Integration (T025-T031, depends on T021 from Dev A)
3. **Week 3 - Parallel**:
   - Dev A: US3 Debugging (T042-T049)
   - Dev B: US4 Sync (T050-T056, Python + TypeScript)
   - Dev C: US5 Organization (T057-T065)
4. **Week 4 - Converge**:
   - Dev A+B: US7 CI/CD (T066-T075)
   - Dev C: Polish (T076-T088)

---

## Task Count Summary

- **Phase 1 (Setup)**: 6 tasks
- **Phase 2 (Foundational)**: 8 tasks
- **Phase 3 (US1 - P1)**: 10 tasks (MVP core)
- **Phase 4 (US6 - P1)**: 7 tasks (MVP diagnostics)
- **Phase 5 (US2 - P2)**: 10 tasks
- **Phase 6 (US3 - P2)**: 8 tasks
- **Phase 7 (US4 - P3)**: 7 tasks
- **Phase 8 (US5 - P3)**: 9 tasks
- **Phase 9 (US7 - P3)**: 10 tasks
- **Phase 10 (Polish)**: 13 tasks

**Total: 88 tasks**

**MVP Scope (US1 + US6)**: 31 tasks (35% of total)
**Core Framework (US1 + US2 + US6)**: 48 tasks (55% of total)
**Production Ready (All stories)**: 88 tasks (100%)

---

## Validation Checklist

Before marking feature complete, verify:

- [X] All 88 tasks completed and committed
- [X] MVP test case (US1) executes successfully with clear diff output
- [X] tree-monitor integration (US6) shows event correlation in output
- [X] Multi-step workflow test (US2) executes actions sequentially
- [X] Interactive debugging (US3) drops into REPL and accepts commands
- [X] Rapid window test (US4) achieves 0% flakiness over 100 runs
- [X] Fixture example (US5) demonstrates reuse across tests
- [X] CI/CD test (US7) runs in Docker producing JUnit XML
- [X] Quickstart.md documentation complete and accurate
- [X] All success criteria from spec.md validated:
  - SC-001: 5min to write basic test ✓
  - SC-002: 100% accuracy across 50+ tests ✓
  - SC-003: <2s latency for simple tests ✓
  - SC-004: 0% flakiness over 1000 runs ✓
  - SC-005: 3min debugging time ✓
  - SC-006: 100% CI pass rate ✓
  - SC-007: 80% code reduction via tree-monitor ✓
  - SC-008: 90% helpful error messages ✓
  - SC-009: <100ms overhead per test ✓
  - SC-010: 100+ test scalability ✓

---

## Notes

- [P] tasks = different files, no dependencies within phase
- [Story] label maps task to specific user story for traceability
- Each user story designed to be independently completable and testable
- Stop at any checkpoint to validate story independently before proceeding
- Commit after each task or logical group for incremental progress
- All paths use absolute references from `/etc/nixos/` repository root
- Python enhancements integrate with existing i3pm daemon structure
- Deno CLI follows Deno Development Standards (Constitution XIII)
- Framework itself is TDD infrastructure - minimal self-testing needed
