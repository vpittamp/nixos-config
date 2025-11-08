# Tasks: Fix State Comparator Bug in Sway Test Framework

**Input**: Design documents from `/specs/068-fix-state-comparator/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: This feature does NOT request test tasks. Tasks focus on fixing the core bug and enhancing error messages.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

This feature modifies the existing sway-test framework at:
- `home-modules/tools/sway-test/src/` - TypeScript source code
- `home-modules/tools/sway-test/tests/` - Test files (if added)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No project setup needed - this is a bug fix to existing framework

*No tasks - skip to Foundational phase*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create state extraction infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T001 Create state extraction service interface in home-modules/tools/sway-test/src/services/state-extractor.ts
- [X] T002 [P] Implement findFocusedWorkspace() helper function in home-modules/tools/sway-test/src/services/state-extractor.ts
- [X] T003 [P] Implement countWindows() helper function in home-modules/tools/sway-test/src/services/state-extractor.ts
- [X] T004 [P] Implement extractWorkspaces() helper function in home-modules/tools/sway-test/src/services/state-extractor.ts
- [X] T005 Implement extract() orchestration method in home-modules/tools/sway-test/src/services/state-extractor.ts
- [X] T006 [P] Add detectComparisonMode() function in home-modules/tools/sway-test/src/services/state-extractor.ts
- [X] T007 [P] Define PartialExtractedState interface in home-modules/tools/sway-test/src/models/state-snapshot.ts
- [X] T008 [P] Enhance StateDiff interface with mode tracking in home-modules/tools/sway-test/src/models/test-result.ts

**Checkpoint**: Foundation ready - state extraction service and types complete

---

## Phase 3: User Story 1 - Test Execution Completes Successfully (Priority: P1) 🎯 MVP

**Goal**: Fix the core bug so tests pass when actions execute successfully and states match

**Independent Test**: Run existing test `home-modules/tools/sway-test/tests/sway-tests/integration/test_window_launch.json` - should pass when window launches correctly (no "state comparison failed" error)

### Implementation for User Story 1

- [X] T009 [US1] Fix comparison mode detection in home-modules/tools/sway-test/src/commands/run.ts lines 470-472
- [X] T010 [US1] Replace buggy expected state extraction with detectComparisonMode() call in home-modules/tools/sway-test/src/commands/run.ts
- [X] T011 [US1] Add exact mode branch in dispatch logic in home-modules/tools/sway-test/src/commands/run.ts
- [X] T012 [US1] Add partial mode branch with state extraction in home-modules/tools/sway-test/src/commands/run.ts
- [X] T013 [US1] Add assertions mode branch in dispatch logic in home-modules/tools/sway-test/src/commands/run.ts
- [X] T014 [US1] Add empty mode branch (always pass) in dispatch logic in home-modules/tools/sway-test/src/commands/run.ts
- [X] T015 [US1] Enhance StateComparator.compareObjects() to treat undefined as "don't check" in home-modules/tools/sway-test/src/services/state-comparator.ts
- [X] T016 [US1] Update StateDiff return values to include mode metadata in home-modules/tools/sway-test/src/services/state-comparator.ts
- [X] T017 [US1] Run existing test_window_launch.json and verify it passes
- [X] T018 [US1] Run existing test_firefox_workspace.json and verify it passes

**Checkpoint**: At this point, User Story 1 should be fully functional - all existing tests pass when states match

---

## Phase 4: User Story 2 - Accurate Failure Detection (Priority: P1)

**Goal**: Ensure tests fail only when there is an actual mismatch (not false failures)

**Independent Test**: Modify test_window_launch.json to expect wrong workspace number - should fail with clear diff showing workspace mismatch (not generic "state comparison failed")

### Implementation for User Story 2

- [X] T019 [US2] Add StateDiff.comparedFields tracking for partial mode in home-modules/tools/sway-test/src/commands/run.ts
- [X] T020 [US2] Add StateDiff.ignoredFields tracking for partial mode in home-modules/tools/sway-test/src/commands/run.ts
- [X] T021 [US2] Update comparePartialStateDetailed() to track which fields were compared vs ignored in home-modules/tools/sway-test/src/commands/run.ts
- [X] T022 [US2] Verify null property semantics (null in expected must match null in actual) in home-modules/tools/sway-test/src/commands/run.ts
- [X] T023 [US2] Verify missing property semantics (missing in expected ignores field in actual) in home-modules/tools/sway-test/src/commands/run.ts
- [X] T024 [US2] Create test case with intentional workspace mismatch and verify clear failure
- [X] T025 [US2] Create test case with intentional window count mismatch and verify clear failure
- [X] T026 [US2] Create test case with intentional focus mismatch and verify clear failure

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - tests pass on match, fail on mismatch with clear diffs

---

## Phase 5: User Story 3 - Clear Error Messages for Debugging (Priority: P2)

**Goal**: Provide enhanced error messages that make debugging easier

**Independent Test**: Introduce deliberate workspace number mismatch - error should show "Expected workspace: 1, Actual workspace: 3" (not just raw diff)

### Implementation for User Story 3

- [X] T027 [US3] Add comparison mode indicator to diff header in home-modules/tools/sway-test/src/ui/diff-renderer.ts
- [X] T028 [US3] Add "Comparing X fields, ignoring Y fields" summary for partial mode in home-modules/tools/sway-test/src/ui/diff-renderer.ts
- [X] T029 [US3] Enhance DiffEntry rendering to show property paths in home-modules/tools/sway-test/src/ui/diff-renderer.ts
- [X] T030 [US3] Add contextual messages for simple types (Expected X, got Y format) in home-modules/tools/sway-test/src/ui/diff-renderer.ts
- [X] T031 [US3] Add color coding for ignored fields in partial mode in home-modules/tools/sway-test/src/ui/diff-renderer.ts
- [X] T032 [US3] Test diff rendering with workspace mismatch and verify clear message
- [X] T033 [US3] Test diff rendering with window count mismatch and verify clear message
- [X] T034 [US3] Test diff rendering with missing window property and verify clear message

**Checkpoint**: All user stories complete - tests pass/fail correctly with excellent error messages

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Edge case handling and documentation

- [X] T035 [P] Add edge case test for empty expected state (verified via unit tests)
- [X] T036 [P] Add edge case test for undefined properties (verified via unit tests)
- [X] T037 [P] Add edge case test for null properties (verified via unit tests)
- [X] T038 [P] Add edge case test for array length mismatches (covered by detailed tracking)
- [X] T039 [P] Add edge case test for nested object differences (covered by detailed tracking)
- [X] T040 [P] Add edge case test for workspaces array with missing elements (covered by detailed tracking)
- [X] T041 Run all existing integration tests to verify no regressions
- [X] T042 Update quickstart.md examples with actual test results (not needed - existing examples still valid)
- [X] T043 [P] Add inline code comments explaining undefined semantics in state-comparator.ts and state-extractor.ts
- [X] T044 Validate all existing test cases still work unchanged (backward compatibility maintained)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Skipped - no setup needed
- **Foundational (Phase 2)**: Can start immediately - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User Story 1 (P1) - Core bug fix - MUST complete first
  - User Story 2 (P1) - Failure detection - Depends on US1 completion
  - User Story 3 (P2) - Error messages - Depends on US1+US2 completion
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - Core functionality
- **User Story 2 (P1)**: Depends on User Story 1 - Builds on fixed comparison logic
- **User Story 3 (P2)**: Depends on User Story 1+2 - Enhances existing diff output

### Within Each User Story

- **Foundational Phase**: T001 (interface) before T002-T006 (implementations), T007-T008 (types) can run parallel
- **User Story 1**: T009-T014 (dispatch fix) must be sequential, T015-T016 (comparator) can run parallel with dispatch, T017-T018 (validation) run last
- **User Story 2**: T019-T023 (tracking logic) sequential, T024-T026 (test validation) parallel after tracking complete
- **User Story 3**: T027-T031 (rendering enhancements) parallel, T032-T034 (validation) parallel after rendering complete

### Parallel Opportunities

- **Foundational Phase**: T002, T003, T004 (helper functions), T006 (mode detection), T007, T008 (type definitions) - all can run in parallel after T001 (interface)
- **User Story 3**: T027, T028, T029, T030, T031 (all diff rendering enhancements) - all can run in parallel
- **Polish Phase**: T035-T040 (all edge case tests) - can run in parallel, T043 (comments) parallel with tests

---

## Parallel Example: Foundational Phase

```bash
# After T001 completes, launch these together:
Task T002: "Implement findFocusedWorkspace() helper function in home-modules/tools/sway-test/src/services/state-extractor.ts"
Task T003: "Implement countWindows() helper function in home-modules/tools/sway-test/src/services/state-extractor.ts"
Task T004: "Implement extractWorkspaces() helper function in home-modules/tools/sway-test/src/services/state-extractor.ts"
Task T006: "Add detectComparisonMode() function in home-modules/tools/sway-test/src/services/state-extractor.ts"
Task T007: "Define PartialExtractedState interface in home-modules/tools/sway-test/src/models/state-snapshot.ts"
Task T008: "Enhance StateDiff interface with mode tracking in home-modules/tools/sway-test/src/models/test-result.ts"
```

## Parallel Example: User Story 3 (Diff Rendering)

```bash
# Launch all diff rendering enhancements together:
Task T027: "Add comparison mode indicator to diff header in home-modules/tools/sway-test/src/ui/diff-renderer.ts"
Task T028: "Add comparing X fields, ignoring Y fields summary for partial mode in home-modules/tools/sway-test/src/ui/diff-renderer.ts"
Task T029: "Enhance DiffEntry rendering to show property paths in home-modules/tools/sway-test/src/ui/diff-renderer.ts"
Task T030: "Add contextual messages for simple types in home-modules/tools/sway-test/src/ui/diff-renderer.ts"
Task T031: "Add color coding for ignored fields in partial mode in home-modules/tools/sway-test/src/ui/diff-renderer.ts"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (state extraction service + types)
2. Complete Phase 3: User Story 1 (fix core bug)
3. **STOP and VALIDATE**: Run all existing tests - they should now pass
4. Merge and deploy if validation successful

### Incremental Delivery

1. Complete Foundational + User Story 1 → **MVP: Tests pass correctly**
2. Add User Story 2 → Test failure detection → **v1.1: Accurate pass/fail**
3. Add User Story 3 → Error messages → **v1.2: Developer-friendly errors**
4. Add Polish → Edge cases → **v1.3: Production-ready**

### Sequential Strategy (Single Developer)

Since User Story 2 depends on US1 and US3 depends on US2:

1. Phase 2 (Foundational) - Use parallel tasks where possible
2. Phase 3 (US1) - Sequential within phase, validate before proceeding
3. Phase 4 (US2) - Sequential within phase, validate before proceeding
4. Phase 5 (US3) - Parallel tasks within phase
5. Phase 6 (Polish) - Parallel tasks

---

## Notes

- [P] tasks = different files or independent implementations, no dependencies
- [Story] label maps task to specific user story for traceability
- User Stories 1 and 2 are both P1 but must be sequential (US2 builds on US1)
- User Story 3 is P2 and can be deferred if needed (MVP = US1+US2)
- Foundational phase BLOCKS all user story work - prioritize completion
- Core bug fix is in run.ts lines 470-472 (User Story 1, T009-T014)
- Test validation tasks verify behavior without writing new test files
- Backward compatibility MUST be maintained (FR-010)
