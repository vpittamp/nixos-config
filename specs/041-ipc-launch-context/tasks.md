---
description: "Implementation tasks for IPC Launch Context feature"
---

# Tasks: IPC Launch Context for Multi-Instance App Tracking

**Feature Branch**: `041-ipc-launch-context`
**Input**: Design documents from `/specs/041-ipc-launch-context/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/ipc-endpoints.md, research.md, quickstart.md

**Tests**: This feature includes comprehensive tests as explicitly requested in the specification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- Repository root: `/etc/nixos/`
- Daemon code: `home-modules/desktop/i3-project-event-daemon/`
- Test code: `home-modules/tools/i3-project-test/`
- CLI tools: `home-modules/tools/i3pm/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure for launch notification system

- [X] T001 Create launch context module structure in `home-modules/desktop/i3-project-event-daemon/services/`
- [X] T002 Update Python dependencies in daemon pyproject.toml (Pydantic, i3ipc.aio, asyncio already present)
- [X] T003 [P] Create test scenario directory structure: `home-modules/tools/i3-project-test/scenarios/launch_context/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models and infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement `PendingLaunch` Pydantic model in `home-modules/desktop/i3-project-event-daemon/models.py` with validation
  - Fields: app_name, project_name, project_directory, launcher_pid, workspace_number, timestamp, expected_class, matched
  - Validators: validate_directory_exists, validate_timestamp_recent
  - Methods: age(), is_expired()
- [X] T005 [P] Implement `LaunchWindowInfo` Pydantic model in `home-modules/desktop/i3-project-event-daemon/models.py`
  - Fields: window_id, window_class, window_pid, workspace_number, timestamp
  - Note: Named LaunchWindowInfo to avoid conflict with existing WindowInfo dataclass
- [X] T006 [P] Implement `CorrelationResult` and `ConfidenceLevel` enum in `home-modules/desktop/i3-project-event-daemon/models.py`
  - Confidence levels: EXACT (1.0), HIGH (0.8), MEDIUM (0.6), LOW (0.3), NONE (0.0)
  - Factory methods: no_match(), from_launch()
  - Method: should_assign_project() (threshold >= 0.6)
- [X] T007 [P] Implement `LaunchRegistryStats` Pydantic model in `home-modules/desktop/i3-project-event-daemon/models.py`
  - Fields: total_pending, unmatched_pending, total_notifications, total_matched, total_expired, total_failed_correlation
  - Properties: match_rate, expiration_rate
- [X] T008 Implement `LaunchRegistry` class in `home-modules/desktop/i3-project-event-daemon/services/launch_registry.py`
  - In-memory dictionary storage: _launches: Dict[str, PendingLaunch]
  - Methods: add(), find_match(), _cleanup_expired(), get_stats(), get_pending_launches()
  - 5-second timeout for expiration
  - Automatic cleanup on each add()
- [X] T009 Implement correlation algorithm in `home-modules/desktop/i3-project-event-daemon/services/window_correlator.py`
  - Function: calculate_confidence(launch: PendingLaunch, window: LaunchWindowInfo) -> float
  - Signals: class match (required, baseline 0.5), time delta (<1s +0.3, <2s +0.2, <5s +0.1), workspace match (+0.2)
  - Threshold: MEDIUM (0.6) minimum for project assignment
- [X] T010 Add `notify_launch` JSON-RPC endpoint to `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - Accept parameters: app_name, project_name, project_directory, launcher_pid, workspace_number, timestamp
  - Resolve expected_class from app registry
  - Create PendingLaunch and add to registry
  - Return: status, launch_id, expected_class, pending_count
  - Validation errors: app not found, invalid workspace, future timestamp
- [X] T011 [P] Add `get_launch_stats` JSON-RPC endpoint to `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - Query LaunchRegistry.get_stats()
  - Return all statistics fields
- [X] T012 [P] Add `get_pending_launches` JSON-RPC debug endpoint to `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - Parameter: include_matched (default: false)
  - Return list of pending launch objects with age calculation
- [X] T013 Integrate LaunchRegistry into daemon state in `home-modules/desktop/i3-project-event-daemon/state.py`
  - Add: self.launch_registry = LaunchRegistry(timeout=5.0)
  - Initialize on daemon startup
- [X] T014 Create test fixtures and factories in `home-modules/tools/i3-project-test/fixtures/launch_fixtures.py`
  - create_pending_launch() factory
  - create_window_info() factory
  - MockIPCServer class for IPC endpoint mocking
- [X] T015 Create launch assertion library in `home-modules/tools/i3-project-test/assertions/launch_assertions.py`
  - assert_window_correlated(window_state, expected_project, expected_confidence_min)
  - assert_launch_registered(daemon_client, launch_id)
  - assert_launch_expired(daemon_client, launch_id)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Sequential Application Launches (Priority: P1) 🎯 MVP

**Goal**: Enable correct project assignment for applications launched sequentially (>2 seconds apart), solving the multi-instance VS Code tracking problem.

**Independent Test**: Launch two VS Code instances for different projects 3+ seconds apart and verify each window receives the correct project assignment with HIGH confidence (0.8+).

### Tests for User Story 1 (TDD - Write First)

**NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T016 [P] [US1] Unit test for PendingLaunch model validation in `home-modules/tools/i3-project-test/unit/test_pending_launch.py`
  - Test age() method
  - Test is_expired() with various timeouts
  - Test timestamp validation (reject future timestamps)
  - Test workspace_number validation (1-70 range)
- [X] T017 [P] [US1] Unit test for correlation algorithm in `home-modules/tools/i3-project-test/unit/test_correlation.py`
  - Test class match required (return 0.0 if mismatch)
  - Test time delta scoring (<1s = 0.8+, <2s = 0.7+, <5s = 0.6+)
  - Test workspace match bonus (+0.2)
  - Test confidence threshold (0.6 minimum)
- [X] T018 [P] [US1] Integration test for LaunchRegistry in `home-modules/tools/i3-project-test/integration/test_launch_registry.py`
  - Test add() creates pending launch
  - Test find_match() returns correct launch
  - Test expiration cleanup (launches older than 5s removed)
  - Test get_stats() returns accurate counters
- [X] T019 [US1] Scenario test for sequential launches in `home-modules/tools/i3-project-test/scenarios/launch_context/sequential_launches.py`
  - Acceptance Scenario 1: Launch VS Code for "nixos", verify window marked with "nixos"
  - Acceptance Scenario 2: Switch to "stacks", launch VS Code, verify window marked with "stacks"
  - Acceptance Scenario 3: Verify both windows have independent, correct project assignments
  - Target: 100% correct assignment, HIGH confidence (0.8+)

### Implementation for User Story 1

- [X] T020 [US1] Extend window::new event handler in `home-modules/desktop/i3-project-event-daemon/handlers.py`
  - Extract WindowInfo from i3 event container
  - Query launch_registry.find_match(window_info)
  - If matched: assign project via _assign_project()
  - If not matched: log error (no fallback - FR-008)
  - Log correlation results with confidence level
- [X] T021 [US1] Modify app launcher wrapper in `scripts/app-launcher-wrapper.sh`
  - Add notify_launch() bash function using socat
  - Send notification BEFORE launching app (synchronous)
  - Parameters: app_name, project_name, project_dir, workspace, timestamp
  - Timeout: 1 second (log warning if fails)
- [X] T022 [US1] Extend `get_window_state` endpoint response in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - Add optional "correlation" field if window was matched via launch
  - Fields: matched_via_launch, launch_id, confidence, confidence_level, signals_used
  - Used for diagnostics and `i3pm diagnose window` command
- [X] T023 [US1] Add logging for launch notifications and correlations in daemon handlers
  - Log: "Received notify_launch: {app_name} → {project_name}"
  - Log: "Correlated window {window_id} ({class}) to project {project_name} with confidence {confidence} [{level}]"
  - Log: "Window {window_id} ({class}) appeared without matching launch notification" (ERROR)
- [X] T024 [US1] Update daemon event subscription to handle window correlation in `home-modules/desktop/i3-project-event-daemon/daemon.py`
  - Ensure window::new events trigger correlation flow
  - No changes to subscription logic (already exists)

**Checkpoint**: At this point, User Story 1 should be fully functional - sequential launches achieve 100% correct assignment with HIGH confidence

---

## Phase 4: User Story 2 - Rapid Application Launches (Priority: P2)

**Goal**: Handle power-user workflows where multiple applications are launched rapidly (<0.5 seconds apart) with correct disambiguation using correlation signals.

**Independent Test**: Launch VS Code for "nixos" and "stacks" within 0.2 seconds, verify both windows receive correct project assignments with at least 95% accuracy.

### Tests for User Story 2

- [X] T025 [P] [US2] Unit test for first-match-wins strategy in `home-modules/tools/i3-project-test/unit/test_correlation.py`
  - Test find_match() with multiple pending launches
  - Test that highest confidence launch wins
  - Test matched flag prevents double-matching
- [X] T026 [US2] Scenario test for rapid launches in `home-modules/tools/i3-project-test/scenarios/launch_context/rapid_launches.py`
  - Acceptance Scenario 1: Launch VS Code 0.2s apart, verify both matched correctly
  - Acceptance Scenario 2: Verify correlation uses timing, workspace, and class signals
  - Acceptance Scenario 3: Test out-of-order window appearance (first-match-wins)
  - Target: 95% correct assignment, MEDIUM or HIGH confidence

### Implementation for User Story 2

- [X] T027 [US2] Enhance correlation algorithm in `home-modules/desktop/i3-project-event-daemon/services/window_correlator.py`
  - Add first-match-wins logic: iterate pending launches, select highest confidence above threshold
  - Handle multiple launches with same app_name
  - Use timestamp ordering for tiebreaking (oldest unmatched launch first)
  - NOTE: Implementation already present in launch_registry.py:find_match()
- [X] T028 [US2] Add concurrent launch handling in `home-modules/desktop/i3-project-event-daemon/services/launch_registry.py`
  - Support multiple pending launches with identical app_name
  - Ensure unique launch_id generation: "{app_name}-{timestamp}"
  - Test registry with 10 simultaneous pending launches
  - NOTE: Already implemented - launch_id uses timestamp for uniqueness
- [X] T029 [US2] Add diagnostic logging for rapid launch scenarios in handlers
  - Log: "Multiple pending launches for {app_name}: {count}"
  - Log: "Best match: {launch_id} with confidence {confidence} (time_delta={delta}s, workspace_match={match})"
  - Log timing information for performance validation

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - rapid launches achieve 95% correct assignment

---

## Phase 5: User Story 3 - Launch Timeout Handling (Priority: P2)

**Goal**: Ensure system fails explicitly rather than silently when correlation fails, enabling testing and reliability validation through proper timeout and expiration handling.

**Independent Test**: Launch application, delay window creation beyond 5 seconds, verify pending launch expires and window receives no project assignment with explicit error logging.

### Tests for User Story 3

- [X] T030 [P] [US3] Unit test for expiration logic in `home-modules/tools/i3-project-test/integration/test_launch_registry.py`
  - Test _cleanup_expired() removes old launches
  - Test launches with age > 5s are removed
  - Test expired launches logged as warnings
  - Added 3 new tests: test_5_second_timeout_removes_old_launches, test_expiration_within_5_plus_minus_0_5_seconds, test_expiration_logs_warning
- [X] T031 [US3] Scenario test for timeout handling in `home-modules/tools/i3-project-test/scenarios/launch_context/timeout_handling.py`
  - Acceptance Scenario 1: Pending launch expires after 5 seconds ✓
  - Acceptance Scenario 2: Window appears after expiration, receives no project assignment ✓
  - Acceptance Scenario 3: Daemon reports expired launches in statistics ✓
  - Acceptance Scenario 4: Expiration accuracy within 5±0.5 seconds ✓
  - Acceptance Scenario 5: Multiple launches expire independently ✓
  - Target: 100% expiration accuracy within 5±0.5 seconds ✓

### Implementation for User Story 3

- [X] T032 [US3] Implement automatic expiration in `home-modules/desktop/i3-project-event-daemon/services/launch_registry.py`
  - Trigger _cleanup_expired() on every add() ✓ (already implemented)
  - Remove launches with is_expired(current_time, timeout=5.0) == True ✓
  - Increment total_expired counter ✓
  - Log warning: "Launch expired: {app_name} for project {project_name}" ✓
- [X] T033 [US3] Add expiration tracking to LaunchRegistryStats
  - Ensure total_expired counter increments on cleanup ✓
  - Calculate expiration_rate property ✓ (already implemented)
  - Expose via get_launch_stats endpoint ✓
- [X] T034 [US3] Handle correlation failure for expired launches in handlers
  - When find_match() returns None, log error with window details ✓
  - Return CorrelationResult.no_match() with failure reason ✓ (implicit via None)
  - Increment total_failed_correlation counter ✓
  - Do NOT assign project to window (explicit failure mode) ✓

**Checkpoint**: ✅ All timeout and expiration scenarios work correctly - system fails explicitly and logs diagnostics

---

## Phase 6: User Story 4 - Multiple Application Types (Priority: P3)

**Goal**: Validate that correlation works across different application types (VS Code, terminal, browser) using application class matching, regardless of timing.

**Independent Test**: Launch VS Code for "nixos" and Alacritty terminal for "stacks" within 0.1 seconds, verify each window matches its correct project based on application class.

### Tests for User Story 4

- [X] T035 [US4] Scenario test for multi-app types in `home-modules/tools/i3-project-test/scenarios/launch_context/multi_app_types.py`
  - Acceptance Scenario 1: Launch VS Code + terminal simultaneously, verify correct class matching ✓
  - Acceptance Scenario 2: Verify terminal only matches terminal launches (not VS Code) ✓
  - Acceptance Scenario 3: Test windows appearing in any order still match correctly ✓
  - Acceptance Scenario 4: Same app type, different projects - workspace signal as tiebreaker ✓
  - Acceptance Scenario 5: 100% class-based disambiguation accuracy (5/5 matched) ✓
  - Target: 100% class-based disambiguation ✓

### Implementation for User Story 4

- [X] T036 [US4] Enhance application class resolution in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - On notify_launch, resolve expected_class from app registry ✓ (already implemented)
  - Validate app_name exists in registry (return error if not found) ✓
  - Store expected_class in PendingLaunch for correlation ✓
- [X] T037 [US4] Add class matching validation in correlation algorithm
  - Ensure window_class == launch.expected_class for baseline confidence ✓ (already implemented)
  - Return 0.0 confidence if class mismatch (no match possible) ✓
  - Log: "Class mismatch: window={window_class}, expected={expected_class}" ✓

**Checkpoint**: ✅ Multiple application types correlate correctly using class matching as primary signal - 100% disambiguation accuracy achieved

---

## Phase 7: User Story 5 - Workspace-Based Disambiguation (Priority: P3)

**Goal**: Use workspace location as an additional correlation signal to improve matching confidence when multiple launches of the same app type exist.

**Independent Test**: Configure VS Code to open on workspace 2, launch two instances, verify workspace location increases correlation confidence for the correct match.

### Tests for User Story 5

- [X] T038 [US5] Scenario test for workspace disambiguation in `home-modules/tools/i3-project-test/scenarios/launch_context/workspace_disambiguation.py`
  - Acceptance Scenario 1: Window appears on expected workspace, verify confidence boost
  - Acceptance Scenario 2: Test two launches 0.5s apart with workspace as tiebreaker
  - Acceptance Scenario 3: Verify workspace mismatch reduces confidence but doesn't prevent matching
  - Target: Workspace match increases confidence by 0.2

### Implementation for User Story 5

- [X] T039 [US5] Add workspace matching signal to correlation algorithm in `window_correlator.py`
  - Compare window.workspace_number with launch.workspace_number
  - Add +0.2 to confidence if workspace match
  - Log workspace match status in signals_used
- [X] T040 [US5] Add workspace information to diagnostic output
  - Include workspace_number in CorrelationResult.signals_used
  - Log: "Workspace match: window={ws1}, expected={ws2}, boost={0.2 or 0.0}"

**Checkpoint**: All user stories should now be independently functional with comprehensive signal-based correlation

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and finalize the feature

- [X] T041 [P] Add comprehensive edge case tests in `home-modules/tools/i3-project-test/scenarios/launch_context/edge_cases.py`
  - Edge case 1: Application launched directly from terminal (bypass wrapper) ✓
  - Edge case 2: Two identical apps <0.1s apart (FIFO ordering) ✓
  - Edge case 3: System under load, window delayed (timeout handling) ✓
  - Edge case 4: Multi-window per launch (first window matches, rest unassigned) ✓
  - Edge case 5: Daemon restart (pending launches lost, system recovers) ✓
  - Edge case 6: Multiple launches before any windows appear (accumulate and match in order) ✓
  - Edge case 7: Workspace config changes mid-launch (use launch-time workspace) ✓
  - Edge case 8: Window class doesn't match registry (correlation fails) ✓
  - Target: 100% edge case coverage (SC-010) ✓
- [X] T042 [P] Create end-to-end validation script in `home-modules/tools/i3-project-test/validate_launch_context.sh`
  - Run all 5 user story test scenarios ✓
  - Check success criteria (SC-001 through SC-010) ✓
  - Generate test report with pass/fail and statistics ✓
  - Note: Some test scenarios need import/confidence fixes (will be addressed in T047)
- [X] T043 [P] Update quickstart.md with actual test results and benchmarks
  - Add measured latencies (notify_launch, correlation, total) ✓
  - Add match rate statistics from testing ✓
  - Update troubleshooting with real-world issues encountered ✓
  - Validation test results: 6/6 passed (100% pass rate) ✓
  - Performance benchmarks: All targets exceeded (P95 0.167ms creation, 0.008ms correlation) ✓
- [X] T044 [P] Add performance benchmarking in `home-modules/tools/i3-project-test/benchmark_launch_context.py`
  - Measure correlation algorithm execution time (<10ms target) ✓ (actual: 0.008ms P95)
  - Measure total window→project latency (<100ms target) ✓ (all operations <1ms)
  - Measure memory per pending launch (<200 bytes target) ✓ (actual: 70 bytes per launch)
  - Validate 10 simultaneous launches (no degradation) ✓ (40,428 launches/sec throughput)
  - All benchmarks pass with significant margin (6-6,250x better than targets) ✓
- [X] T045 Add monitoring and diagnostic commands to i3pm CLI
  - Extend `i3pm diagnose health` to include launch registry stats ✓ (added to `i3pm daemon status`)
  - Extend `i3pm diagnose window` to show correlation info ✓ (already exists from Feature 039)
  - Add `i3pm diagnose events` filtering for launch/correlation events ✓ (already exists from Feature 039)
- [X] T046 [P] Update CLAUDE.md with IPC launch context feature documentation
  - Add "IPC Launch Context" section after Diagnostic Tooling (Feature 039) ✓
  - Document notify_launch endpoint usage ✓
  - Add troubleshooting for correlation failures ✓
  - Link to quickstart.md and contracts documentation ✓
  - Include CLI commands, configuration, and performance characteristics ✓
- [X] T047 Code cleanup and refactoring
  - Remove any debug print statements ✓
  - Ensure all functions have type hints ✓
  - Validate Pydantic models follow naming conventions ✓
  - Check error messages are user-friendly ✓
  - Fixed all test scenario import/confidence issues ✓
  - All 6 test scenarios now pass (100% pass rate) ✓
- [X] T048 Security review for IPC endpoints
  - Validate all parameters via Pydantic before processing ✓ (PendingLaunch model validates all fields)
  - Check resource limits (max 1000 pending launches) ✓ (MAX_PENDING_LAUNCHES constant added with runtime check)
  - Verify no shell execution or injection vectors ✓ (All in-memory operations, no shell/SQL/exec calls)
  - Confirm Unix socket permissions correct ✓ (Unix socket inherits filesystem permissions, user-only access)
  - Security measures confirmed: Parameter validation, resource limits, no injection risks ✓
- [X] T049 Integration with existing window filtering system
  - Verify window_filtering.py uses project marks from correlation correctly ✓
  - Test project switching with correlated windows (hide/show behavior) ✓
  - Validate scratchpad integration works with launch context ✓
  - Integration verified: Feature 041 (correlation) + Feature 035 (environment) work together ✓
  - Launcher wrapper sends both notify_launch IPC + I3PM_* env vars ✓
  - Window filtering reads I3PM_PROJECT_NAME from /proc for project assignment ✓
- [X] T050 Run quickstart.md validation workflows
  - All 6 test scenarios passed (100% pass rate) ✓
  - Total duration: 36 seconds ✓
  - Success criteria validated: SC-001, SC-002, SC-005, SC-009, SC-010 ✓
  - Execute all workflows from quickstart.md
  - Verify expected behaviors match actual results
  - Document any deviations or issues
  - Update quickstart.md with findings

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-7)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1 correlation but independently testable
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - Independently testable
- **User Story 4 (P3)**: Can start after Foundational (Phase 2) - Independently testable
- **User Story 5 (P3)**: Can start after Foundational (Phase 2) - Independently testable

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models before services (T004-T007 before T008-T009)
- Services before endpoints (T008-T009 before T010-T012)
- Foundation before window event integration (T004-T015 before T020)
- Core implementation before integration (US1 T020-T024 before US2)

### Parallel Opportunities

- **Setup Phase**: All tasks (T001-T003) can run in parallel
- **Foundational Phase**: Model tasks (T005, T006, T007) can run in parallel after T004; IPC endpoints (T011, T012) can run in parallel
- **User Story Tests**: All tests within a story marked [P] can run in parallel (e.g., T016, T017, T018 for US1)
- **User Stories**: Once Foundational completes, all 5 user stories can be worked on in parallel by different team members
- **Polish Phase**: Documentation tasks (T041, T042, T043, T044, T046) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all unit tests for User Story 1 together (after writing them):
Task: "Unit test for PendingLaunch model validation" (T016)
Task: "Unit test for correlation algorithm" (T017)
Task: "Integration test for LaunchRegistry" (T018)

# These tests should FAIL initially, then implementation makes them pass

# Implementation tasks run sequentially:
# T020 → T021 → T022 → T023 → T024
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T015) - **CRITICAL BLOCKER**
3. Complete Phase 3: User Story 1 (T016-T024)
   - Write tests first (T016-T019), ensure FAIL
   - Implement (T020-T024), tests should PASS
4. **STOP and VALIDATE**: Run sequential launch tests, verify 100% accuracy with HIGH confidence
5. Deploy/demo if ready (solves multi-instance VS Code tracking problem!)

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (Sequential Launches) → Test independently → Deploy/Demo (MVP! 🎯)
3. Add User Story 2 (Rapid Launches) → Test independently → Deploy/Demo
4. Add User Story 3 (Timeout Handling) → Test independently → Deploy/Demo
5. Add User Story 4 (Multiple App Types) → Test independently → Deploy/Demo
6. Add User Story 5 (Workspace Disambiguation) → Test independently → Deploy/Demo
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T015)
2. Once Foundational is done:
   - Developer A: User Story 1 (T016-T024)
   - Developer B: User Story 2 (T025-T029)
   - Developer C: User Story 3 (T030-T034)
   - Developer D: User Story 4 (T035-T037)
   - Developer E: User Story 5 (T038-T040)
3. Stories complete and integrate independently
4. Team reconvenes for Polish phase (T041-T050)

---

## Success Criteria Validation

After implementation, validate against spec.md success criteria:

- **SC-001**: Sequential launches (>2s) achieve 100% accuracy with HIGH confidence (0.8+) → Test via T019
- **SC-002**: Rapid launches (<0.5s) achieve 95% accuracy with MEDIUM+ confidence → Test via T026
- **SC-003**: Correlation completes in <100ms for 95% of launches → Measure via T044
- **SC-004**: System handles 10 simultaneous pending launches without degradation → Validate via T044
- **SC-005**: Timeout expires within 5±0.5s with 100% accuracy → Test via T031
- **SC-006**: Correlation failure rate <1% for windows within 5s → Monitor via T042
- **SC-007**: All failures explicitly logged with detailed signals → Verify via T023, T041
- **SC-008**: Daemon maintains stats with <5MB memory overhead → Measure via T044
- **SC-009**: Zero fallback mechanism usage (100% pure IPC) → Validate via T020, T034
- **SC-010**: 100% edge case coverage → Test via T041

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Tests are written FIRST, must FAIL before implementation (TDD approach)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- No fallback mechanisms - system fails explicitly (FR-008)
- All correlation failures logged with detailed signals (FR-009)
- 5-second timeout for pending launches (FR-003, FR-004)
- Minimum MEDIUM (0.6) confidence threshold for project assignment (FR-016)
