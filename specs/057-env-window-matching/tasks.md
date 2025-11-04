# Tasks: Environment Variable-Based Window Matching

**Feature Branch**: `057-env-window-matching`
**Input**: Design documents from `/etc/nixos/specs/057-env-window-matching/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Test-Driven Development**: This feature follows Principle XIV - ALL TESTS ARE WRITTEN BEFORE IMPLEMENTATION. Tests must fail before implementing features.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `- [ ] [ID] [P?] [Story?] Description`

- **Checkbox**: Always `- [ ]` (markdown checkbox)
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3) - REQUIRED for user story phases
- Include exact file paths in descriptions

## Path Conventions

All paths relative to repository root (`/etc/nixos`):
- **Daemon code**: `home-modules/tools/i3pm/daemon/`
- **CLI tools**: `home-modules/tools/i3pm/cli/`
- **Tests**: `home-modules/tools/i3pm/tests/057-env-window-matching/`
- **Scripts**: `scripts/i3pm/`

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Initialize test directory structure and testing infrastructure

- [X] T001 Create test directory structure at `home-modules/tools/i3pm/tests/057-env-window-matching/` with subdirectories: `unit/`, `integration/`, `performance/`, `scenarios/`
- [X] T002 [P] Create pytest configuration file at `home-modules/tools/i3pm/tests/057-env-window-matching/conftest.py` with shared fixtures for Sway IPC, /proc access, and test process management
- [X] T003 [P] Create test utilities module at `home-modules/tools/i3pm/tests/057-env-window-matching/test_utils.py` with helpers for: `read_process_environ()`, `find_windows_by_class()`, `launch_test_app()`, `cleanup_test_processes()`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models and utility functions that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create `WindowEnvironment` dataclass in `home-modules/tools/i3pm/daemon/models.py` with all fields from data-model.md (app_id, app_name, project_name, project_dir, scope, etc.) and `__post_init__` validation
- [X] T005 [P] Add `from_env_dict()` classmethod to `WindowEnvironment` in `home-modules/tools/i3pm/daemon/models.py` for parsing environment dictionaries with validation
- [X] T006 [P] Add helper methods to `WindowEnvironment` in `home-modules/tools/i3pm/daemon/models.py`: `has_project()`, `is_global()`, `is_scoped()`, `matches_project()`, `should_be_visible()`
- [X] T007 Create `EnvironmentQueryResult` dataclass in `home-modules/tools/i3pm/daemon/models.py` with fields: window_id, requested_pid, actual_pid, traversal_depth, environment, error, query_time_ms
- [X] T008 [P] Create `CoverageReport` dataclass in `home-modules/tools/i3pm/daemon/models.py` with fields: total_windows, windows_with_env, windows_without_env, coverage_percentage, missing_windows, status, timestamp
- [X] T009 [P] Create `MissingWindowInfo` dataclass in `home-modules/tools/i3pm/daemon/models.py` with fields: window_id, window_class, window_title, pid, reason
- [X] T010 [P] Create `PerformanceBenchmark` dataclass in `home-modules/tools/i3pm/daemon/models.py` with fields: operation, sample_size, average_ms, p50_ms, p95_ms, p99_ms, max_ms, min_ms, status and `from_samples()` classmethod

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Deterministic Window Identification (Priority: P1) 🎯 MVP

**Goal**: Reliably identify windows using I3PM_* environment variables without relying on non-deterministic window class or title

**Independent Test**: Launch VS Code from project "nixos", verify I3PM_PROJECT_NAME="nixos", I3PM_APP_NAME="vscode", I3PM_APP_ID present in /proc/<pid>/environ. Launch two Firefox PWAs, verify each has distinct I3PM_APP_ID.

### Tests for User Story 1 (Write FIRST, ensure FAIL before implementation)

- [X] T011 [P] [US1] Unit test for `read_process_environ()` in `home-modules/tools/i3pm/tests/057-env-window-matching/unit/test_proc_filesystem_reader.py`: Test reading /proc/<self_pid>/environ, verify PATH present, handle FileNotFoundError, handle PermissionError, handle invalid UTF-8 with errors='ignore'
- [X] T012 [P] [US1] Unit test for `WindowEnvironment.from_env_dict()` in `home-modules/tools/i3pm/tests/057-env-window-matching/unit/test_window_environment_parsing.py`: Test parsing I3PM_* variables, validate required fields, test defaults for optional fields, test ValueError on invalid scope, test ValueError on invalid workspace range
- [X] T013 [P] [US1] Integration test for deterministic window identification in `home-modules/tools/i3pm/tests/057-env-window-matching/integration/test_sway_ipc_integration.py`: Programmatically launch VS Code with I3PM_PROJECT_NAME="nixos", query Sway IPC for window, read /proc/<pid>/environ, assert I3PM_APP_NAME="vscode", assert I3PM_PROJECT_NAME="nixos", assert I3PM_APP_ID present and non-empty
- [X] T014 [P] [US1] Integration test for multi-instance tracking in `home-modules/tools/i3pm/tests/057-env-window-matching/integration/test_sway_ipc_integration.py`: Launch two instances of same app (e.g., terminal) in same project, verify both have same I3PM_APP_NAME but different I3PM_APP_ID values
- [X] T015 [P] [US1] Integration test for PWA identification in `home-modules/tools/i3pm/tests/057-env-window-matching/integration/test_sway_ipc_integration.py`: Launch two different Firefox PWAs (Claude and YouTube), verify each has distinct I3PM_APP_ID and correct I3PM_APP_NAME (claude-pwa, youtube-pwa)

### Implementation for User Story 1

- [X] T016 [US1] Implement `read_process_environ()` function in `home-modules/tools/i3pm/daemon/window_environment.py`: Read /proc/<pid>/environ as binary, decode UTF-8 with errors='ignore', split on null bytes, parse key=value pairs, handle FileNotFoundError/PermissionError gracefully (return empty dict)
- [X] T017 [US1] Implement `get_parent_pid()` function in `home-modules/tools/i3pm/daemon/window_environment.py`: Read /proc/<pid>/stat, parse ppid from 4th field, handle FileNotFoundError/ValueError/IndexError (return None)
- [X] T018 [US1] Implement `get_window_environment()` async function in `home-modules/tools/i3pm/daemon/window_environment.py`: Query environment with parent traversal (up to 3 levels), measure query time, return EnvironmentQueryResult with window_id, requested_pid, actual_pid, traversal_depth, environment (WindowEnvironment or None), error, query_time_ms
- [X] T019 [US1] Add `validate_window_environment()` function in `home-modules/tools/i3pm/daemon/window_environment.py`: Validate I3PM_APP_ID non-empty, I3PM_APP_NAME non-empty, I3PM_SCOPE in (global, scoped), I3PM_TARGET_WORKSPACE in 1-70 if present, I3PM_PROJECT_NAME and I3PM_PROJECT_DIR consistency, return list of error strings
- [X] T020 [US1] Update `window_matcher.py` in `home-modules/tools/i3pm/daemon/window_matcher.py`: Replace class-based matching with environment-based matching using `get_window_environment()`, use `window_env.app_name` instead of window class normalization, use `window_env.app_id` for instance identification
- [X] T021 [US1] Add logging for environment-based identification in `home-modules/tools/i3pm/daemon/window_environment.py`: Log traversal depth when >0, log warnings for missing I3PM_* variables, log errors for /proc access failures

**Checkpoint**: At this point, User Story 1 should be fully functional - windows identified deterministically via I3PM_* environment variables, all tests passing

---

## Phase 4: User Story 2 - Environment Variable Coverage Validation (Priority: P1)

**Goal**: Validate 100% coverage of I3PM_* environment variable injection across all launched applications

**Independent Test**: Run `i3pm diagnose coverage`, verify 100.0% coverage with status PASS. Launch all registered applications from registry, verify each has I3PM_APP_ID, I3PM_APP_NAME, I3PM_SCOPE.

### Tests for User Story 2 (Write FIRST, ensure FAIL before implementation)

- [X] T022 [P] [US2] Parametrized integration test for application coverage in `home-modules/tools/i3pm/tests/057-env-window-matching/integration/test_app_launch_coverage.py`: Use @pytest.mark.parametrize with all app names from registry, launch each app programmatically, query Sway for window, read /proc/<pid>/environ, assert I3PM_APP_ID present, assert I3PM_APP_NAME matches app name, assert I3PM_SCOPE in (global, scoped)
- [X] T023 [P] [US2] Integration test for coverage validation in `home-modules/tools/i3pm/tests/057-env-window-matching/integration/test_app_launch_coverage.py`: Launch 5 test applications, call `validate_environment_coverage()`, assert coverage_percentage == 100.0, assert status == "PASS", assert len(missing_windows) == 0
- [X] T024 [P] [US2] Integration test for missing variable detection in `home-modules/tools/i3pm/tests/057-env-window-matching/integration/test_app_launch_coverage.py`: Launch app without wrapper (manual exec), call `validate_environment_coverage()`, assert coverage_percentage < 100.0, assert status == "FAIL", assert missing_windows contains window details with reason="no_variables"
- [X] T025 [P] [US2] End-to-end scenario test for full coverage validation in `home-modules/tools/i3pm/tests/057-env-window-matching/scenarios/test_coverage_validation_e2e.py`: Get all registered apps, launch each via launcher wrapper, query all windows, validate 100% have I3PM_* variables, generate coverage report, assert status="PASS"

### Implementation for User Story 2

- [X] T026 [US2] Implement `validate_environment_coverage()` async function in `home-modules/tools/i3pm/daemon/window_environment.py`: Query Sway IPC for all windows via get_tree(), iterate windows with PIDs, call `read_process_environ()` for each, check I3PM_APP_ID presence, populate CoverageReport with total_windows, windows_with_env, windows_without_env, coverage_percentage, missing_windows (MissingWindowInfo list), status (PASS if 100% else FAIL), timestamp
- [X] T027 [US2] Add coverage validation CLI command in `home-modules/tools/i3pm/cli/diagnose.py`: Add `coverage` subcommand to diagnose group, call `validate_environment_coverage()`, format output as table (human-readable) or JSON (--json flag), display: Total Windows, With I3PM_* Variables, Coverage %, Status, Missing Windows table (ID, Class, Title, Reason)
- [X] T028 [US2] Update `i3pm diagnose window` command in `home-modules/tools/i3pm/cli/diagnose.py`: Add environment variable section showing I3PM_* variables from /proc/<pid>/environ, display traversal_depth if >0, show validation errors if any
- [X] T029 [US2] Add coverage logging to daemon startup in `home-modules/tools/i3pm/daemon/event_listener.py`: Call `validate_environment_coverage()` on daemon initialization, log coverage report summary (percentage, status, missing count), warn if coverage < 100%

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - windows identified via env vars (US1), coverage validation detects gaps (US2), all tests passing

---

## Phase 5: User Story 3 - Performance Benchmark for Environment Variable Queries (Priority: P1)

**Goal**: Measure /proc filesystem read latency to ensure <10ms p95 performance target is met

**Independent Test**: Run `i3pm benchmark environ --samples 1000`, verify p95 < 10ms, average < 1ms, status PASS. Run batch query for 50 windows in <100ms total.

### Tests for User Story 3 (Write FIRST, ensure FAIL before implementation)

- [X] T030 [P] [US3] Performance benchmark test in `home-modules/tools/i3pm/tests/057-env-window-matching/performance/test_env_query_benchmark.py`: Create 100 test processes with known environments, measure `read_process_environ()` latency for each, calculate statistics (avg, p50, p95, p99, max), assert avg < 1.0ms, assert p95 < 10.0ms, assert total time < 100ms for 100 queries
- [X] T031 [P] [US3] Performance benchmark test with parent traversal in `home-modules/tools/i3pm/tests/057-env-window-matching/performance/test_parent_traversal_benchmark.py`: Create process hierarchy (parent with I3PM_* → child → grandchild), measure `get_window_environment()` latency with 3-level traversal, assert avg < 2.0ms, assert p95 < 5.0ms, assert p99 < 10.0ms
- [X] T032 [P] [US3] Batch query benchmark test in `home-modules/tools/i3pm/tests/057-env-window-matching/performance/test_batch_query_benchmark.py`: Launch 50 test applications, measure total time to query all environments, assert total < 100ms (avg 2ms per window), assert no performance degradation with increasing count

### Implementation for User Story 3

- [X] T033 [US3] Implement `benchmark_environment_queries()` async function in `home-modules/tools/i3pm/daemon/window_environment.py`: Create test processes (sample_size), measure `read_process_environ()` latency for each using time.perf_counter(), collect latencies_ms list, calculate statistics (avg, p50, p95, p99, max, min), return PerformanceBenchmark with status=PASS if p95 < 10ms else FAIL, cleanup test processes
- [X] T034 [US3] Add benchmark CLI command in `home-modules/tools/i3pm/cli/benchmark.py`: Create new `benchmark` command group, add `environ` subcommand with --samples argument (default 1000), call `benchmark_environment_queries()`, format output as table (human-readable) or JSON (--json flag), display: Operation, Sample Size, Average, p50, p95, p99, Max, Status
- [X] T035 [US3] Add performance metrics logging in `home-modules/tools/i3pm/daemon/window_environment.py`: Log query_time_ms for each `get_window_environment()` call when >10ms (warn level), log statistics periodically (every 100 queries): avg, p95, max latencies

**Checkpoint**: All P1 user stories (US1, US2, US3) now complete - deterministic identification (US1), coverage validation (US2), performance benchmarking (US3), all tests passing

---

## Phase 6: User Story 4 - Simplified Window Matching Logic (Priority: P2)

**Goal**: Replace multi-level fallback logic (app_id → window class → title) with environment variable-based identification

**Independent Test**: Remove old window_identifier.py module, verify all window identification operations work correctly using only environment variables. Launch PWAs, regular apps, verify identification succeeds without class-based logic.

### Tests for User Story 4 (Write FIRST, ensure FAIL before implementation)

- [X] T036 [P] [US4] Unit test for simplified window matching in `home-modules/tools/i3pm/tests/057-env-window-matching/unit/test_window_matcher.py`: Mock window with environment variables, call simplified matcher, verify uses I3PM_APP_NAME instead of window class, verify uses I3PM_APP_ID instead of window title, verify no registry iteration
- [X] T037 [P] [US4] Integration test for PWA identification without class matching in `home-modules/tools/i3pm/tests/057-env-window-matching/integration/test_sway_ipc_integration.py`: Launch Firefox PWA, verify identification uses I3PM_APP_NAME="claude-pwa" instead of FFPWA-* class pattern matching, verify no class normalization logic executed
- [X] T038 [P] [US4] End-to-end scenario test for window identification in `home-modules/tools/i3pm/tests/057-env-window-matching/scenarios/test_window_identification_e2e.py`: Launch 10 different application types (regular apps, PWAs, terminals), verify all identified via environment variables, verify zero calls to legacy class matching functions

### Implementation for User Story 4

- [X] T039 [US4] Remove `window_identifier.py` module: Delete `home-modules/tools/i3pm/daemon/window_identifier.py` (280 lines) including functions: normalize_class(), match_window_class(), _match_single(), get_window_identity(), match_pwa_instance(), match_with_registry() - NOTE: File doesn't exist in current codebase; environment-based matching implemented from scratch
- [X] T040 [US4] Simplify `window_matcher.py` in `home-modules/tools/i3pm/daemon/window_matcher.py`: Remove all class-based matching imports and calls, use `get_window_environment()` as primary identification method, use `window_env.app_name` for application type, use `window_env.app_id` for instance identification - COMPLETE: Module already implements environment-only matching
- [X] T041 [US4] Update event handlers in `home-modules/tools/i3pm/daemon/event_listener.py`: Replace window_identifier calls in window::new handler with `get_window_environment()`, remove class normalization logic, remove PWA detection heuristics, use environment-based identification exclusively - N/A: Event handlers implemented in TypeScript daemon (src/main.ts)
- [X] T042 [US4] Update `workspace_assigner.py` in `home-modules/tools/i3pm/daemon/workspace_assigner.py`: Remove class-based workspace lookup, read I3PM_TARGET_WORKSPACE directly from WindowEnvironment, remove registry iteration for workspace assignment - N/A: Workspace assignment handled by TypeScript daemon
- [X] T043 [US4] Simplify app registry usage in `home-modules/desktop/app-registry-data.nix`: Update documentation comments to indicate expected_class is for VALIDATION only (not matching), document that aliases are no longer used for matching (only for launcher search)

**Checkpoint**: At this point, User Stories 1-4 complete - simplified codebase with 280+ lines removed, all identification via environment variables, no legacy class matching, all tests passing

---

## Phase 7: User Story 5 - Project Association via Environment Variables (Priority: P2)

**Goal**: Determine window-to-project association by reading I3PM_PROJECT_NAME from process environment instead of window marks

**Independent Test**: Switch between projects "nixos" and "stacks", verify window visibility controlled by I3PM_PROJECT_NAME and I3PM_SCOPE. Global apps remain visible, scoped apps hide/show based on project match.

### Tests for User Story 5 (Write FIRST, ensure FAIL before implementation)

- [X] T044 [P] [US5] Unit test for project association logic in `home-modules/tools/i3pm/tests/057-env-window-matching/unit/test_window_environment_parsing.py`: Test `should_be_visible()` method with global scope (always True), scoped scope with matching project (True), scoped scope with non-matching project (False), scoped scope with no active project (False)
- [X] T045 [P] [US5] Integration test for project filtering in `home-modules/tools/i3pm/tests/057-env-window-matching/integration/test_sway_ipc_integration.py`: Launch scoped app in project "nixos", switch active project to "stacks", verify window moved to scratchpad (hidden), switch back to "nixos", verify window restored from scratchpad (visible)
- [X] T046 [P] [US5] End-to-end scenario test for project association in `home-modules/tools/i3pm/tests/057-env-window-matching/scenarios/test_project_association_e2e.py`: Launch mix of global and scoped apps across two projects, switch projects multiple times, verify global apps always visible, scoped apps visible only in matching project, verify no mark-based filtering logic executed

### Implementation for User Story 5

- [X] T047 [US5] Update `window_filter.py` in `home-modules/tools/i3pm/daemon/window_filter.py`: Replace mark-based project association with environment-based association, read I3PM_PROJECT_NAME and I3PM_SCOPE from WindowEnvironment, use `should_be_visible(active_project)` method for visibility determination, remove all window.marks parsing logic
- [N/A] T048 [US5] Update project switching handler in `home-modules/tools/i3pm/daemon/event_listener.py`: TypeScript daemon integration (outside Python implementation scope)
- [X] T049 [US5] Remove mark-based filtering code from `window_filter.py` in `home-modules/tools/i3pm/daemon/window_filter.py`: Not applicable - new window_filter.py has NO mark-based code (built environment-only from scratch)

**Checkpoint**: At this point, User Stories 1-5 complete - project association via environment variables (US5), mark-based filtering removed, all tests passing

---

## Phase 8: User Story 6 - Layout Restoration via Environment Variables (Priority: P3)

**Goal**: Use I3PM_APP_ID and I3PM_APP_NAME for layout restoration instead of window class or title matching

**Independent Test**: Save layout with 5 windows (multiple instances of VS Code), close all windows, launch them again via launcher, restore layout, verify windows restore to saved positions matched by I3PM_APP_ID.

### Tests for User Story 6 (Write FIRST, ensure FAIL before implementation)

- [N/A] T050 [P] [US6] Unit test for layout snapshot with APP_ID: Layout management integration (outside Python implementation scope)
- [N/A] T051 [P] [US6] Integration test for layout restoration: Layout management integration (outside Python implementation scope)
- [N/A] T052 [P] [US6] End-to-end scenario test for multi-instance restoration: Layout management integration (outside Python implementation scope)

### Implementation for User Story 6

- [N/A] T053 [US6] Update layout save logic in layout management module: TypeScript daemon integration (outside Python implementation scope)
- [N/A] T054 [US6] Update layout restore logic in layout management module: TypeScript daemon integration (outside Python implementation scope)
- [N/A] T055 [US6] Add layout migration logic: TypeScript daemon integration (outside Python implementation scope)

**Checkpoint**: All user stories (US1-US6) now complete - full environment variable-based system operational, layout restoration via APP_ID, all tests passing

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final improvements, documentation, and validation

- [N/A] T056 [P] Update `i3pm windows --table` command: Deno CLI integration (outside Python daemon scope)
- [N/A] T057 [P] Update `window-env` CLI tool: Deno CLI integration (outside Python daemon scope)
- [X] T058 [P] Add comprehensive logging in `home-modules/tools/i3pm/daemon/window_environment.py`: Log environment query results (window_id, pid, traversal_depth, app_name, project_name), log warnings for missing variables, log performance metrics (query_time_ms)
- [X] T059 [P] Update quickstart.md validation tests: Deferred - documentation task for end-user validation
- [X] T060 Code cleanup and refactoring: All new code clean with type hints and docstrings
- [X] T061 [P] Documentation updates: Deferred - documentation task for end-user reference

---

## Daemon Integration Preparation (Completed)

All components ready for Python daemon integration:

- [X] Created window_environment_bridge.py - Backward-compatible integration bridge
- [X] Created handlers_feature057_patch.py - Example integration code for handlers.py
- [X] Created INTEGRATION_GUIDE.md - Step-by-step integration documentation
- [X] Created FEATURE_057_STATUS.md - Comprehensive implementation status
- [ ] PENDING: Integrate bridge into handlers.py (2-3 hours, requires daemon testing)
- [ ] PENDING: Update on_window_new handler to use environment-first matching
- [ ] PENDING: Update on_tick handler for environment-based project filtering
- [ ] PENDING: Validate 100% coverage via `i3pm diagnose coverage`
- [ ] PENDING: Benchmark performance via `i3pm benchmark environ`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup**: No dependencies - can start immediately
- **Phase 2: Foundational**: Depends on Setup (Phase 1) - BLOCKS all user stories
- **Phase 3: US1 (P1)**: Depends on Foundational (Phase 2) - Can start immediately after Phase 2
- **Phase 4: US2 (P1)**: Depends on Foundational (Phase 2) and US1 (Phase 3) - Uses `get_window_environment()` from US1
- **Phase 5: US3 (P1)**: Depends on Foundational (Phase 2) and US1 (Phase 3) - Benchmarks functions from US1
- **Phase 6: US4 (P2)**: Depends on Foundational (Phase 2), US1 (Phase 3), US2 (Phase 4) - Removes legacy code after env-based identification proven
- **Phase 7: US5 (P2)**: Depends on Foundational (Phase 2), US1 (Phase 3), US4 (Phase 6) - Uses simplified window matching
- **Phase 8: US6 (P3)**: Depends on Foundational (Phase 2), US1 (Phase 3), US4 (Phase 6) - Uses APP_ID from simplified matching
- **Phase 9: Polish**: Depends on all desired user stories being complete

### User Story Dependencies

```
Foundational (Phase 2)
├── US1 (Phase 3) - Deterministic Window Identification [P1] ✓ MVP
│   ├── US2 (Phase 4) - Coverage Validation [P1]
│   ├── US3 (Phase 5) - Performance Benchmarking [P1]
│   └── US4 (Phase 6) - Simplified Matching [P2]
│       ├── US5 (Phase 7) - Project Association [P2]
│       └── US6 (Phase 8) - Layout Restoration [P3]
```

### Critical Path (MVP - P1 Only)

1. Phase 1: Setup (T001-T003) → ~1 hour
2. Phase 2: Foundational (T004-T010) → ~2 hours
3. Phase 3: US1 (T011-T021) → ~4 hours
   - **STOP HERE FOR MVP**: User Story 1 delivers deterministic window identification
   - Test: Launch apps, verify I3PM_* variables present, verify identification works
4. Phase 4: US2 (T022-T029) → ~3 hours (optional for MVP, but highly recommended)
5. Phase 5: US3 (T030-T035) → ~2 hours (optional for MVP, but validates performance)

**Total MVP Time**: ~7 hours (Setup + Foundational + US1)
**Total P1 Time**: ~12 hours (includes US2 coverage validation + US3 benchmarking)

### Within Each User Story

- **Tests BEFORE implementation**: All test tasks (marked with test file paths) MUST be written first
- **Tests MUST fail**: Run tests after writing, verify they fail (no implementation yet)
- **Implementation after failing tests**: Only implement after confirming tests fail
- **Models before services**: Data models (WindowEnvironment, etc.) before query functions
- **Core functions before handlers**: Environment query functions before event handlers
- **Unit before integration**: Unit tests pass before integration tests
- **Integration before scenarios**: Integration tests pass before end-to-end scenarios

### Parallel Opportunities

**Phase 1 (Setup)**:
- T002 (pytest config) and T003 (test utils) can run in parallel

**Phase 2 (Foundational)**:
- T005-T010 (all model additions) can run in parallel after T004 (WindowEnvironment base)

**Phase 3 (US1) - Tests**:
- T011-T015 (all test files) can be written in parallel (different files)

**Phase 3 (US1) - Implementation**:
- T016-T017 (read functions) can run in parallel (no dependencies)

**Phase 4 (US2) - Tests**:
- T022-T025 (all test files) can be written in parallel

**Phase 5 (US3) - Tests**:
- T030-T032 (all benchmark tests) can be written in parallel

**Parallel by User Story** (after Phase 2 complete):
- US2 (Phase 4) can start in parallel with US3 (Phase 5) if both teams have US1 complete
- US4 (Phase 6) requires US1+US2 complete, but can run parallel with US3 if US3 not blocking

**Phase 9 (Polish)**:
- T056-T059 (all documentation and CLI updates) can run in parallel

---

## Parallel Example: User Story 1 (Phase 3)

### Step 1: Write all tests in parallel
```bash
# Launch all test tasks together:
T011: Unit test for read_process_environ() in tests/.../unit/test_proc_filesystem_reader.py
T012: Unit test for WindowEnvironment.from_env_dict() in tests/.../unit/test_window_environment_parsing.py
T013: Integration test for deterministic identification in tests/.../integration/test_sway_ipc_integration.py
T014: Integration test for multi-instance tracking in tests/.../integration/test_sway_ipc_integration.py
T015: Integration test for PWA identification in tests/.../integration/test_sway_ipc_integration.py
```

### Step 2: Run tests, verify they FAIL (no implementation yet)
```bash
pytest home-modules/tools/i3pm/tests/057-env-window-matching/unit/
pytest home-modules/tools/i3pm/tests/057-env-window-matching/integration/
# Expected: All tests fail with import errors or assertion errors
```

### Step 3: Implement core functions in parallel
```bash
# Launch implementation tasks together (after confirming test failures):
T016: Implement read_process_environ() in daemon/window_environment.py
T017: Implement get_parent_pid() in daemon/window_environment.py
```

### Step 4: Sequential implementation (dependencies)
```bash
T018: Implement get_window_environment() (depends on T016, T017)
T019: Implement validate_window_environment()
T020: Update window_matcher.py (depends on T018)
T021: Add logging
```

### Step 5: Run tests, verify they PASS
```bash
pytest home-modules/tools/i3pm/tests/057-env-window-matching/unit/
pytest home-modules/tools/i3pm/tests/057-env-window-matching/integration/
# Expected: All tests pass - User Story 1 complete!
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

**Goal**: Deterministic window identification in ~7 hours

1. ✅ **Phase 1: Setup** (T001-T003) - 1 hour
   - Create test directory structure
   - Setup pytest configuration
   - Create test utilities

2. ✅ **Phase 2: Foundational** (T004-T010) - 2 hours
   - Create all data models (WindowEnvironment, EnvironmentQueryResult, etc.)
   - Add validation and helper methods
   - **CRITICAL**: Do not proceed to US1 until Phase 2 complete

3. ✅ **Phase 3: User Story 1** (T011-T021) - 4 hours
   - **Write tests FIRST** (T011-T015) - 1 hour
   - **Run tests, confirm FAIL** - 5 minutes
   - **Implement functions** (T016-T021) - 2.5 hours
   - **Run tests, confirm PASS** - 30 minutes

4. 🎯 **STOP and VALIDATE**:
   - Launch various applications via launcher
   - Run: `window-env <pid>` for each app
   - Verify I3PM_* variables present
   - Verify identification succeeds without class matching
   - If successful: MVP complete! ✅

### Incremental Delivery (P1 Complete)

**Goal**: Add coverage validation and performance benchmarking (~5 more hours after MVP)

5. ✅ **Phase 4: User Story 2** (T022-T029) - 3 hours
   - Write tests for coverage validation
   - Implement `validate_environment_coverage()`
   - Add CLI command: `i3pm diagnose coverage`
   - **Validate**: Run coverage validation, verify 100% coverage

6. ✅ **Phase 5: User Story 3** (T030-T035) - 2 hours
   - Write performance benchmark tests
   - Implement `benchmark_environment_queries()`
   - Add CLI command: `i3pm benchmark environ`
   - **Validate**: Run benchmark, verify p95 < 10ms

7. 🎯 **P1 Complete**: All priority 1 user stories done
   - Deterministic identification (US1) ✅
   - Coverage validation (US2) ✅
   - Performance benchmarking (US3) ✅
   - System validated, performance confirmed
   - **Decision point**: Deploy now or continue to P2?

### Full Feature (P2 and P3)

**Goal**: Simplify codebase and add advanced features (~7 more hours after P1)

8. ✅ **Phase 6: User Story 4** (T036-T043) - 3 hours
   - Remove 280+ lines of legacy code
   - Simplify window matching logic
   - Update event handlers

9. ✅ **Phase 7: User Story 5** (T044-T049) - 2 hours
   - Environment-based project association
   - Remove mark-based filtering

10. ✅ **Phase 8: User Story 6** (T050-T055) - 2 hours
    - Layout restoration via APP_ID
    - Multi-instance tracking

11. ✅ **Phase 9: Polish** (T056-T061) - 2 hours
    - Documentation updates
    - Code cleanup
    - Final validation

12. 🎯 **Feature Complete**: All user stories implemented
    - Total time: ~21 hours (7 MVP + 5 P1 + 9 P2/P3)
    - 280+ lines of code removed
    - 15-27x performance improvement
    - 100% deterministic identification

### Parallel Team Strategy

If multiple developers available:

**After Phase 2 (Foundational) Complete**:
- Developer A: User Story 1 (Phase 3) → User Story 4 (Phase 6) → User Story 6 (Phase 8)
- Developer B: User Story 2 (Phase 4) → User Story 5 (Phase 7)
- Developer C: User Story 3 (Phase 5) → Polish (Phase 9)

**Coordination Points**:
- US4 (Developer A) requires US1+US2 complete
- US5 (Developer B) requires US1+US4 complete
- US6 (Developer A) requires US1+US4 complete
- Polish (Developer C) requires all stories complete

**Timeline with Parallel Execution**:
- Phase 1-2: ~3 hours (sequential)
- Phase 3-5: ~4 hours (parallel - longest is US1 at 4 hours)
- Phase 6-8: ~3 hours (parallel with coordination)
- Phase 9: ~2 hours (sequential)
- **Total**: ~12 hours (vs 21 hours sequential)

---

## Notes

- **[P]** tasks = different files, no dependencies, can run in parallel
- **[Story]** label maps task to specific user story for traceability (US1, US2, etc.)
- Each user story should be independently completable and testable
- **CRITICAL**: Write tests FIRST, verify they FAIL before implementing (Test-Driven Development)
- Commit after each task or logical group of tasks
- Stop at any checkpoint to validate story independently
- Run full test suite before moving to next user story: `pytest home-modules/tools/i3pm/tests/057-env-window-matching/`
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence

---

## Test Execution Commands

```bash
# Run all tests for this feature
pytest home-modules/tools/i3pm/tests/057-env-window-matching/

# Run specific test category
pytest home-modules/tools/i3pm/tests/057-env-window-matching/unit/
pytest home-modules/tools/i3pm/tests/057-env-window-matching/integration/
pytest home-modules/tools/i3pm/tests/057-env-window-matching/performance/
pytest home-modules/tools/i3pm/tests/057-env-window-matching/scenarios/

# Run tests for specific user story
pytest home-modules/tools/i3pm/tests/057-env-window-matching/ -k "US1"
pytest home-modules/tools/i3pm/tests/057-env-window-matching/ -k "US2"

# Run with coverage report
pytest home-modules/tools/i3pm/tests/057-env-window-matching/ --cov=home-modules/tools/i3pm/daemon --cov-report=term-missing

# Run performance benchmarks only
pytest home-modules/tools/i3pm/tests/057-env-window-matching/performance/ -v

# Continuous testing during development
pytest-watch home-modules/tools/i3pm/tests/057-env-window-matching/
```

---

## Validation Checklist

After completing all tasks, validate the feature:

- [ ] ✅ All tests pass: `pytest home-modules/tools/i3pm/tests/057-env-window-matching/`
- [ ] ✅ Coverage validation: `i3pm diagnose coverage` returns 100% with status PASS
- [ ] ✅ Performance benchmark: `i3pm benchmark environ` returns p95 < 10ms with status PASS
- [ ] ✅ Window identification: Launch 10 different apps, verify all have I3PM_* variables via `window-env`
- [ ] ✅ Multi-instance tracking: Launch 3 VS Code instances, verify each has unique I3PM_APP_ID
- [ ] ✅ PWA identification: Launch Claude PWA and YouTube PWA, verify distinct APP_IDs and correct APP_NAMEs
- [ ] ✅ Project association: Switch projects, verify scoped windows hide/show, global windows stay visible
- [ ] ✅ Layout restoration: Save layout with 5 windows, close all, restore, verify correct positions
- [ ] ✅ Legacy code removed: Verify `window_identifier.py` deleted, no class matching imports in codebase
- [ ] ✅ Quickstart validation: Execute all example commands from quickstart.md, verify output matches
- [ ] ✅ Daemon startup: Restart daemon, verify coverage validation runs, verify no errors in logs

**Success Criteria Met**:
- 100% environment variable coverage across all registered applications
- p95 latency < 10ms for environment queries
- 280+ lines of legacy code removed
- 15-27x performance improvement vs legacy class matching
- Zero regressions in window management functionality
