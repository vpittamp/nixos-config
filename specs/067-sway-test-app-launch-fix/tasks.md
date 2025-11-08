# Tasks: Sway Test Framework - App Launch Integration & Sync Fixes

**Feature**: 067-sway-test-app-launch-fix
**Input**: Design documents from `/specs/067-sway-test-app-launch-fix/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are NOT explicitly requested in spec.md - focusing on implementation tasks only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure: `/etc/nixos/home-modules/tools/sway-test/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Review existing sway-test framework structure at /etc/nixos/home-modules/tools/sway-test/
- [X] T002 Create new service modules directory: /etc/nixos/home-modules/tools/sway-test/src/services/ (if not exists)
- [X] T003 [P] Create helpers directory: /etc/nixos/home-modules/tools/sway-test/src/helpers/ (if not exists)
- [X] T004 [P] Create integration test directory: /etc/nixos/home-modules/tools/sway-test/tests/integration/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create app-registry-reader.ts service in /etc/nixos/home-modules/tools/sway-test/src/services/app-registry-reader.ts (loads and validates application registry JSON with Zod)
- [X] T006 [P] Create event-subscriber.ts service in /etc/nixos/home-modules/tools/sway-test/src/services/event-subscriber.ts (Sway IPC event subscription via swaymsg subprocess)
- [X] T007 [P] Create environment-validator.ts helper in /etc/nixos/home-modules/tools/sway-test/src/helpers/environment-validator.ts (read /proc/<pid>/environ and validate I3PM_* variables)
- [X] T008 Enhance sway-client.ts in /etc/nixos/home-modules/tools/sway-test/src/services/sway-client.ts (add event subscription support)
- [X] T009 Enhance tree-monitor-client.ts in /etc/nixos/home-modules/tools/sway-test/src/services/tree-monitor-client.ts (add RPC method introspection with system.listMethods)
- [X] T010 Update test-case.ts model in /etc/nixos/home-modules/tools/sway-test/src/models/test-case.ts (add LaunchAppParams and WaitEventParams types with Zod schemas)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Realistic App Launch Testing (Priority: P1) 🎯 MVP

**Goal**: Enable test framework to launch applications using app-launcher-wrapper.sh mechanism with proper I3PM environment variables and workspace assignment

**Independent Test**: Write a test that launches Firefox via wrapper, verifies window appears on workspace 3 (not random), and checks daemon logs show I3PM environment variables from /proc/<pid>/environ

### Implementation for User Story 1

- [X] T011 [US1] Replace launch_app action in /etc/nixos/home-modules/tools/sway-test/src/services/action-executor.ts (remove direct command execution, ALWAYS use app-launcher-wrapper.sh with app_name parameter)
- [X] T012 [US1] Implement launchApp() function in /etc/nixos/home-modules/tools/sway-test/src/services/action-executor.ts (validates app exists in registry, invokes wrapper at ~/.local/bin/app-launcher-wrapper.sh)
- [X] T013 [US1] Add environment variable injection support in launchApp() (set I3PM_PROJECT_NAME and I3PM_TARGET_WORKSPACE from params)
- [X] T014 [US1] Update test_walker_app_launch.json in /etc/nixos/home-modules/tools/sway-test/tests/sway-tests/basic/test_walker_app_launch.json (change to use app_name parameter instead of bash wrapper call)
- [X] T015 [P] [US1] Create integration test test_wrapper_launch.ts in /etc/nixos/home-modules/tools/sway-test/tests/integration/test_wrapper_launch.ts (validates wrapper invocation with registry lookup)
- [X] T016 [P] [US1] Create example test test_firefox_workspace.json in /etc/nixos/home-modules/tools/sway-test/tests/sway-tests/integration/test_firefox_workspace.json (Firefox launches on workspace 3)
- [X] T017 [P] [US1] Create example test test_vscode_scoped.json in /etc/nixos/home-modules/tools/sway-test/tests/sway-tests/integration/test_vscode_scoped.json (VS Code with project context)

**Checkpoint**: At this point, User Story 1 should be fully functional - tests can launch apps via wrapper with proper I3PM environment variables

---

## Phase 4: User Story 2 - Reliable Event Synchronization (Priority: P1)

**Goal**: Implement wait_event action to wait for Sway IPC events deterministically without arbitrary timeouts, using event subscription instead of fixed delays

**Independent Test**: Launch VS Code (slow-starting app), use wait_event(window::new, timeout=10000), verify test waits up to 10 seconds and proceeds immediately when window appears (not after full timeout)

**Dependencies**: User Story 1 NOT required (can be implemented in parallel after Foundational phase)

### Implementation for User Story 2

- [X] T018 [US2] Implement waitForEvent() function in /etc/nixos/home-modules/tools/sway-test/src/services/event-subscriber.ts (Promise.race pattern with timeout and event arrival)
- [X] T019 [US2] Implement event criteria matching in /etc/nixos/home-modules/tools/sway-test/src/services/event-subscriber.ts (filter events by change, app_id, window_class, workspace)
- [X] T020 [US2] Implement subscribeToEvents() function in /etc/nixos/home-modules/tools/sway-test/src/services/event-subscriber.ts (spawn swaymsg subprocess, parse JSON lines, call callback on match)
- [X] T021 [US2] Replace wait_event placeholder in /etc/nixos/home-modules/tools/sway-test/src/services/action-executor.ts (remove 1-second sleep, use waitForEvent with actual timeout parameter)
- [X] T022 [US2] Add timeout error handling in waitForEvent() (capture last Sway tree state, throw WaitEventTimeoutError with diagnostic context)
- [X] T023 [US2] Add AbortController cleanup in waitForEvent() (cancel subscription on timeout or success)
- [X] T024 [P] [US2] Create integration test test_wait_event.ts in /etc/nixos/home-modules/tools/sway-test/tests/integration/test_wait_event.ts (validates event subscription, timeout, immediate return)

**Checkpoint**: At this point, User Story 2 should be fully functional - tests can wait for events with configurable timeout and immediate return on event arrival

---

## Phase 5: User Story 3 - Fix Auto-Sync RPC Errors (Priority: P1)

**Goal**: Gracefully handle daemon connectivity without "Method not found" errors by detecting missing RPC methods via introspection and falling back to timeout-based sync

**Independent Test**: Run any test with tree-monitor daemon running, verify no "Method not found" errors in output, confirm test passes. If daemon down, test should warn once but not fail.

**Dependencies**: User Story 1 and 2 NOT required (can be implemented in parallel after Foundational phase)

### Implementation for User Story 3

- [X] T025 [US3] Implement checkMethodAvailability() in /etc/nixos/home-modules/tools/sway-test/src/services/tree-monitor-client.ts (call system.listMethods RPC, cache result in Set)
- [X] T026 [US3] Implement sendSyncMarkerSafe() in /etc/nixos/home-modules/tools/sway-test/src/services/tree-monitor-client.ts (check method availability before calling, return null if unavailable)
- [X] T027 [US3] Add session-level method cache in tree-monitor-client.ts (memoize introspection result to avoid per-test overhead)
- [X] T028 [US3] Update auto-sync logic in /etc/nixos/home-modules/tools/sway-test/src/services/action-executor.ts (use sendSyncMarkerSafe, fall back to timeout-based delay when null returned)
- [X] T029 [US3] Add graceful degradation logging (log single warning on first unavailability, suppress repeated errors)
- [X] T030 [P] [US3] Create integration test test_rpc_graceful.ts in /etc/nixos/home-modules/tools/sway-test/tests/integration/test_rpc_graceful.ts (validates RPC introspection, fallback behavior, no error spam)

**Checkpoint**: All P1 user stories (1, 2, 3) should now be independently functional - tests use wrapper, wait for events, and handle RPC gracefully

---

## Phase 6: User Story 4 - Workspace Assignment Validation (Priority: P2)

**Goal**: Validate that apps launched via wrapper appear on their configured preferred_workspace, catching regressions in event-driven workspace assignment

**Independent Test**: Launch 3 apps with different preferred workspaces (firefox→WS3, vscode→WS2, thunar→WS6), verify each window appears on correct workspace

**Dependencies**: Requires User Story 1 (wrapper launches) and User Story 2 (event waiting)

### Implementation for User Story 4

- [X] T031 [US4] Implement validate_workspace_assignment action in /etc/nixos/home-modules/tools/sway-test/src/services/action-executor.ts (check window with I3PM_APP_NAME exists on expected workspace)
- [X] T032 [US4] Implement validate_environment action in /etc/nixos/home-modules/tools/sway-test/src/services/action-executor.ts (read /proc/<pid>/environ, assert I3PM_* variables)
- [X] T033 [US4] Add window PID extraction from Sway tree in /etc/nixos/home-modules/tools/sway-test/src/services/sway-client.ts (extract container.pid from tree output)
- [X] T034 [P] [US4] Create example test test_multi_app_workspaces.json in /etc/nixos/home-modules/tools/sway-test/tests/sway-tests/integration/test_multi_app_workspaces.json (3 apps on different workspaces)
- [X] T035 [P] [US4] Create example test test_pwa_workspace.json in /etc/nixos/home-modules/tools/sway-test/tests/sway-tests/integration/test_pwa_workspace.json (PWA with custom app_id on workspace 52)
- [X] T036 [P] [US4] Create example test test_env_validation.json in /etc/nixos/home-modules/tools/sway-test/tests/sway-tests/integration/test_env_validation.json (validates I3PM_* environment variables)

**Checkpoint**: User Story 4 complete - tests can validate workspace assignment and environment variables

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, cleanup, and validation

- [X] T037 [P] Update README.md in /etc/nixos/home-modules/tools/sway-test/README.md (document app_name parameter, breaking changes, new action types)
- [X] T038 [P] Create WALKER_APP_LAUNCH_TESTING.md in /etc/nixos/home-modules/tools/sway-test/docs/WALKER_APP_LAUNCH_TESTING.md (already exists from previous session - verify content matches implementation)
- [X] T039 Update test action JSON Schema in /etc/nixos/specs/067-sway-test-app-launch-fix/contracts/test-actions.json (ensure schema matches implementation)
- [X] T040 [P] Add error types to codebase: WaitEventTimeoutError, AppNotFoundError, EnvironmentValidationError, RPCMethodUnavailableError
- [X] T041 Run existing framework tests in /etc/nixos/home-modules/tools/sway-test/tests/framework_test.ts (ensure no regressions)
- [X] T042 Validate quickstart.md examples in /etc/nixos/specs/067-sway-test-app-launch-fix/quickstart.md (ensure examples work end-to-end)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) completion
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) completion - Can run in parallel with US1
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) completion - Can run in parallel with US1 and US2
- **User Story 4 (Phase 6)**: Depends on US1 and US2 completion (requires wrapper launches and event waiting)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: INDEPENDENT after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: INDEPENDENT after Foundational - Can run in parallel with US1
- **User Story 3 (P1)**: INDEPENDENT after Foundational - Can run in parallel with US1 and US2
- **User Story 4 (P2)**: DEPENDENT on US1 and US2 - Requires wrapper launches (US1) and event waiting (US2)

### Within Each User Story

- Implementation tasks before integration tests
- Core functionality before example tests
- Story complete and tested before moving to next priority

### Parallel Opportunities

**After Foundational Phase (Phase 2) completes:**

- User Story 1, 2, and 3 can ALL run in parallel (independent)
- Within User Story 1: T015, T016, T017 can run in parallel
- Within User Story 4: T034, T035, T036 can run in parallel
- Within Polish phase: T037, T038, T040, T042 can run in parallel

**Example Parallel Execution:**

```bash
# After Phase 2 completes, launch all P1 stories together:
Developer A: Phase 3 (User Story 1 - Wrapper launches)
Developer B: Phase 4 (User Story 2 - Event waiting)
Developer C: Phase 5 (User Story 3 - RPC fixes)

# Each developer completes their story independently, then:
Developer A or B: Phase 6 (User Story 4 - requires US1 and US2)
```

---

## Parallel Example: Foundational Phase (Phase 2)

All foundational tasks marked [P] can run in parallel:

```bash
# Launch together after Phase 1 completes:
Task T006: "Create event-subscriber.ts service"
Task T007: "Create environment-validator.ts helper"
```

---

## Parallel Example: User Story 1 (Phase 3)

Example tests can run in parallel after core implementation:

```bash
# After T014 completes, launch all example tests together:
Task T015: "Create integration test test_wrapper_launch.ts"
Task T016: "Create example test test_firefox_workspace.json"
Task T017: "Create example test test_vscode_scoped.json"
```

---

## Implementation Strategy

### MVP First (User Stories 1, 2, 3 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Wrapper launches)
4. Complete Phase 4: User Story 2 (Event waiting)
5. Complete Phase 5: User Story 3 (RPC fixes)
6. **STOP and VALIDATE**: Test all P1 stories independently
7. Deploy/demo if ready

**Note**: User Stories 1, 2, and 3 are all P1 priority and should be completed for initial release. User Story 4 (P2) can be added later.

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Partial demo (wrapper launches)
3. Add User Story 2 → Test independently → Partial demo (wrapper + events)
4. Add User Story 3 → Test independently → Deploy/Demo (MVP - all P1 stories!)
5. Add User Story 4 → Test independently → Deploy/Demo (workspace validation)
6. Polish → Final release

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (Wrapper launches)
   - Developer B: User Story 2 (Event waiting)
   - Developer C: User Story 3 (RPC fixes)
3. P1 stories complete in parallel
4. One developer adds User Story 4 (requires US1 + US2)
5. Team polishes together

---

## Breaking Changes Summary

### launch_app Action (CRITICAL)

**Old Schema** (no longer supported):
```json
{
  "type": "launch_app",
  "params": {
    "command": "firefox"
  }
}
```

**New Schema** (required):
```json
{
  "type": "launch_app",
  "params": {
    "app_name": "firefox"
  }
}
```

**Migration Required**:
- ALL existing tests must update to use `app_name` parameter
- ALL apps must exist in `~/.config/i3/application-registry.json`
- Direct command execution is NO LONGER SUPPORTED
- No backwards compatibility - this is an optimal replacement per Principle XII

**Justification**: Tests now validate production app launch flow with I3PM environment variables and workspace assignment. This is the OPTIMAL solution - no legacy support needed.

---

## Notes

- [P] tasks = different files, no dependencies, can run in parallel
- [Story] label (e.g., [US1], [US2]) maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- User Stories 1, 2, and 3 (all P1) can be implemented in parallel after Foundational phase
- User Story 4 (P2) depends on User Stories 1 and 2
- Tests are NOT explicitly requested in spec.md - integration tests created for validation only
- Breaking changes are intentional - forward-only development per Principle XII
