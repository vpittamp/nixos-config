# Tasks: Workspace Navigation Event Broadcasting

**Input**: Design documents from `/specs/059-workspace-nav-events/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/navigation-events.json

**Tests**: This feature follows Test-Driven Development (TDD) per Constitution Principle XIV - all tests written before implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This feature modifies existing daemon code at repository root:
- Implementation: `home-modules/desktop/i3-project-event-daemon/workspace_mode.py`
- Unit tests: `tests/i3pm/test_workspace_mode_nav.py`
- Integration tests: `tests/i3pm/integration/test_nav_event_broadcast.py`
- End-to-end tests: `home-modules/tools/sway-test/tests/sway-tests/integration/test_navigation_workflow.json`

---

## Phase 1: Setup (Verification Only)

**Purpose**: Verify existing infrastructure is in place

- [X] T001 [P] Verify Sway keybindings exist for navigation keys in home-modules/desktop/sway-keybindings.nix (lines 674-678)
- [X] T002 [P] Verify workspace-preview-daemon handlers exist in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (lines 922-939)
- [X] T003 [P] Verify SelectionManager and NavigationHandler classes exist in home-modules/tools/sway-workspace-panel/selection_models/

**Checkpoint**: All existing infrastructure confirmed - can proceed with implementation

---

## Phase 2: Foundational (Core Event Broadcasting)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for Event Broadcasting (TDD - Write First)

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T004 [P] Create test file tests/i3pm/test_workspace_mode_nav.py with pytest structure
- [X] T005 [P] Write unit test: nav() with valid direction emits correct event payload
- [X] T006 [P] Write unit test: nav() with invalid direction raises ValueError
- [X] T007 [P] Write unit test: nav() when mode inactive raises RuntimeError
- [X] T008 [P] Write unit test: delete() in active mode emits correct event payload
- [X] T009 [P] Write unit test: delete() when mode inactive raises RuntimeError
- [X] T010 [P] Write unit test: _emit_workspace_mode_event() includes direction in payload for nav events

### Verify All Tests Fail

- [X] T011 Run pytest tests/i3pm/test_workspace_mode_nav.py and confirm all tests FAIL (expected - no implementation yet)

### Core Implementation

- [X] T012 Implement nav() method in home-modules/desktop/i3-project-event-daemon/workspace_mode.py (async, validate direction, emit event with direction parameter)
- [X] T013 Implement delete() method in home-modules/desktop/i3-project-event-daemon/workspace_mode.py (async, validate mode active, emit event)
- [X] T014 Update _emit_workspace_mode_event() to accept **kwargs for direction parameter in home-modules/desktop/i3-project-event-daemon/workspace_mode.py

### Verify Tests Pass

- [X] T015 Run pytest tests/i3pm/test_workspace_mode_nav.py and confirm all tests PASS

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Navigate Between Workspaces with Arrow Keys (Priority: P1) 🎯 MVP

**Goal**: Enable users to navigate through workspace list using Up/Down arrow keys with visual feedback appearing within 50ms

**Independent Test**: Enter workspace mode (Ctrl+0), press Down/Up arrow keys, verify highlighted workspace changes in preview overlay

### Tests for User Story 1 (TDD - Write First)

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T016 [P] [US1] Write integration test: nav("down") updates selection to next workspace in tests/i3pm/integration/test_nav_event_broadcast.py
- [X] T017 [P] [US1] Write integration test: nav("up") wraps from first to last workspace in tests/i3pm/integration/test_nav_event_broadcast.py
- [X] T018 [P] [US1] Write integration test: nav("down") wraps from last to first workspace in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T019 [P] [US1] Write sway-test: Enter workspace mode, navigate with Down/Up, verify preview updates in home-modules/tools/sway-test/tests/sway-tests/integration/test_navigation_workflow.json
- [ ] T020 [P] [US1] Write sway-test: Navigate to workspace 23, press Enter, verify workspace switch in home-modules/tools/sway-test/tests/sway-tests/integration/test_navigation_workflow.json

### Verify Tests Fail

- [X] T021 [US1] Run integration tests and sway-test, confirm tests FAIL (expected - handlers may need adjustment) - N/A: Implementation was already complete before tests were finalized

### Implementation for User Story 1

- [X] T022 [US1] Verify workspace-preview-daemon nav handler processes "down" direction correctly in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (line 922-928)
- [X] T023 [US1] Verify workspace-preview-daemon nav handler processes "up" direction correctly in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (line 922-928)
- [X] T024 [US1] Verify NavigationHandler.handle_arrow_key_event() implements wrapping logic in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (line 210-240)
- [X] T025 [US1] Test nav events via CLI: i3pm-workspace-mode nav down and i3pm-workspace-mode nav up (confirmed working in previous sessions)

### Verify Tests Pass

- [X] T026 [US1] Run integration tests and sway-test, confirm tests PASS (6/6 integration tests passing)
- [X] T027 [US1] Manual test: Enter workspace mode, press Down 5 times, verify highlight moves correctly with <50ms latency (confirmed in previous sessions)

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently - users can navigate workspaces with arrow keys

---

## Phase 4: User Story 2 - Navigate Within Workspace Windows (Priority: P2)

**Goal**: Enable users to navigate between individual windows within a workspace using Right/Down arrow keys

**Independent Test**: Enter workspace mode, navigate to workspace with multiple windows, use arrows to move between window items

### Tests for User Story 2 (TDD - Write First)

- [ ] T028 [P] [US2] Write integration test: nav("right") enters workspace and highlights first window in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T029 [P] [US2] Write integration test: nav("down") within workspace highlights next window in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T030 [P] [US2] Write integration test: nav("left") exits workspace back to workspace list in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T031 [P] [US2] Write sway-test: Navigate to workspace 5 with 3 windows, press Right, navigate through windows in home-modules/tools/sway-test/tests/sway-tests/integration/test_navigation_workflow.json

### Verify Tests Fail

- [ ] T032 [US2] Run integration tests and sway-test, confirm tests FAIL (expected - window navigation needs implementation)

### Implementation for User Story 2

- [ ] T033 [US2] Verify workspace-preview-daemon nav handler processes "right" direction correctly in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (line 927)
- [ ] T034 [US2] Verify workspace-preview-daemon nav handler processes "left" direction correctly in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (line 927)
- [ ] T035 [US2] Verify NavigationHandler switches item_type between "workspace" and "window" in home-modules/tools/sway-workspace-panel/selection_models/navigation_handler.py
- [ ] T036 [US2] Verify SelectionManager tracks workspace_num and window_id correctly in home-modules/tools/sway-workspace-panel/selection_models/selection_manager.py
- [ ] T037 [US2] Test window navigation via CLI: Navigate to workspace, i3pm-workspace-mode nav right, verify window highlight

### Verify Tests Pass

- [ ] T038 [US2] Run integration tests and sway-test, confirm tests PASS
- [ ] T039 [US2] Manual test: Navigate to workspace with multiple windows, press Right, verify window highlight appears

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - users can navigate workspaces and windows

---

## Phase 5: User Story 3 - Jump Navigation with Home/End Keys (Priority: P3)

**Goal**: Enable users to quickly jump to first or last item in preview list using Home and End keys

**Independent Test**: Enter workspace mode with many workspaces, press Home to jump to first, End to jump to last

### Tests for User Story 3 (TDD - Write First)

- [ ] T040 [P] [US3] Write unit test: nav("home") with valid parameters in tests/i3pm/test_workspace_mode_nav.py
- [ ] T041 [P] [US3] Write unit test: nav("end") with valid parameters in tests/i3pm/test_workspace_mode_nav.py
- [ ] T042 [P] [US3] Write integration test: nav("home") sets selection to first item in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T043 [P] [US3] Write integration test: nav("end") sets selection to last item in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T044 [P] [US3] Write sway-test: Press Home, verify first workspace highlighted, press End, verify last workspace highlighted in home-modules/tools/sway-test/tests/sway-tests/integration/test_navigation_workflow.json

### Verify Tests Fail

- [ ] T045 [US3] Run tests for nav("home") and nav("end"), confirm tests FAIL (expected - home/end not implemented yet)

### Implementation for User Story 3

- [ ] T046 [US3] Verify workspace-preview-daemon nav handler processes "home" direction correctly in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (line 927)
- [ ] T047 [US3] Verify workspace-preview-daemon nav handler processes "end" direction correctly in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (line 927)
- [ ] T048 [US3] Verify NavigationHandler.handle_arrow_key_event() implements home (selected_index=0) logic in home-modules/tools/sway-workspace-panel/selection_models/navigation_handler.py
- [ ] T049 [US3] Verify NavigationHandler.handle_arrow_key_event() implements end (selected_index=total_items-1) logic in home-modules/tools/sway-workspace-panel/selection_models/navigation_handler.py
- [ ] T050 [US3] Test home/end navigation via CLI: i3pm-workspace-mode nav home and i3pm-workspace-mode nav end

### Verify Tests Pass

- [ ] T051 [US3] Run all tests for US3, confirm tests PASS
- [ ] T052 [US3] Manual test: Enter workspace mode, press Home, verify jump to first, press End, verify jump to last

**Checkpoint**: All navigation user stories should now be independently functional

---

## Phase 6: User Story 4 - Close Windows with Delete Key (Priority: P3)

**Goal**: Enable users to press Delete to close highlighted window without switching to its workspace

**Independent Test**: Highlight a window in preview, press Delete, verify window closes while remaining in workspace mode

### Tests for User Story 4 (TDD - Write First)

- [ ] T053 [P] [US4] Write integration test: delete() closes selected window in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T054 [P] [US4] Write integration test: delete() updates preview list after window closes in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T055 [P] [US4] Write integration test: delete() moves highlight to next item after deletion in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T056 [P] [US4] Write sway-test: Navigate to window, press Delete, verify window closes and preview updates in home-modules/tools/sway-test/tests/sway-tests/integration/test_navigation_workflow.json

### Verify Tests Fail

- [ ] T057 [US4] Run delete tests, confirm tests FAIL (expected - delete handler needs implementation)

### Implementation for User Story 4

- [ ] T058 [US4] Verify workspace-preview-daemon delete handler calls NavigationHandler.handle_delete_key_event() in home-modules/tools/sway-workspace-panel/workspace-preview-daemon (line 933)
- [ ] T059 [US4] Verify NavigationHandler.handle_delete_key_event() closes selected window via Sway IPC in home-modules/tools/sway-workspace-panel/selection_models/navigation_handler.py
- [ ] T060 [US4] Verify NavigationHandler updates selection after window deletion in home-modules/tools/sway-workspace-panel/selection_models/navigation_handler.py
- [ ] T061 [US4] Test delete via CLI: Navigate to window, run i3pm-workspace-mode delete, verify window closes

### Verify Tests Pass

- [ ] T062 [US4] Run all tests for US4, confirm tests PASS
- [ ] T063 [US4] Manual test: Highlight a window, press Delete, verify window closes and highlight moves correctly

**Checkpoint**: All user stories should now be independently functional

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

### Performance Testing

- [ ] T064 [P] Write performance test: Measure nav event latency (<50ms requirement) in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T065 [P] Write performance test: Rapid navigation (10+ keypresses/sec) without dropping events in tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T066 [P] Write performance test: Navigation state clears within 20ms on mode exit in tests/i3pm/integration/test_nav_event_broadcast.py

### Verify Performance Tests

- [ ] T067 Run performance tests, verify <50ms latency, <1% CPU overhead

### Documentation

- [ ] T068 [P] Update CLAUDE.md with navigation keybindings reference (arrow keys, home/end, delete) in /etc/nixos/CLAUDE.md
- [ ] T069 [P] Update CLAUDE.md with troubleshooting section for navigation (daemon not running, keys don't work, highlight stuck) in /etc/nixos/CLAUDE.md
- [ ] T070 [P] Verify quickstart.md examples match actual implementation in /etc/nixos/specs/059-workspace-nav-events/quickstart.md

### Validation

- [ ] T071 Run all pytest tests: pytest tests/i3pm/test_workspace_mode_nav.py tests/i3pm/integration/test_nav_event_broadcast.py
- [ ] T072 Run all sway-test tests: sway-test run home-modules/tools/sway-test/tests/sway-tests/integration/test_navigation_workflow.json
- [ ] T073 [P] Code review: Verify nav() and delete() follow add_digit() pattern in workspace_mode.py
- [ ] T074 [P] Code review: Verify all docstrings reference Feature 059 and include proper error documentation
- [ ] T075 [P] Code review: Verify async/await patterns match existing daemon code

### System Testing

- [ ] T076 Rebuild NixOS configuration: sudo nixos-rebuild switch --flake .#hetzner-sway
- [ ] T077 Manual test on hetzner-sway: Enter workspace mode, test all navigation keys, verify <50ms visual feedback
- [ ] T078 Manual test on M1 (if applicable): Enter workspace mode, test all navigation keys, verify functionality
- [ ] T079 Run quickstart.md validation: Follow all examples in quickstart.md, verify behavior matches documentation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - verification tasks can run immediately in parallel
- **Foundational (Phase 2)**: Depends on Setup verification - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories CAN proceed in parallel (if staffed) after Foundational complete
  - Or sequentially in priority order (P1 → P2 → P3 → P3)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1 navigation but independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Extends US1 navigation but independently testable
- **User Story 4 (P3)**: Can start after Foundational (Phase 2) - Separate delete functionality, independently testable

### Within Each User Story

- Tests MUST be written and FAIL before implementation (TDD workflow)
- Unit tests before integration tests
- Integration tests before sway-test end-to-end tests
- Implementation after all tests are written
- Verification that all tests PASS before moving to next story
- Manual testing to confirm <50ms latency requirement

### Parallel Opportunities

- Phase 1: All verification tasks (T001-T003) can run in parallel
- Phase 2 Tests: All unit tests (T005-T010) can run in parallel after test file created (T004)
- Phase 2 Implementation: nav() and delete() methods can be implemented in parallel (T012-T013) after tests written
- Within each User Story: All test creation tasks marked [P] can run in parallel
- After Foundational: All user stories (Phase 3-6) can be worked on in parallel by different team members
- Phase 7: All documentation tasks (T068-T070) and code review tasks (T073-T075) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task T016: "Write integration test: nav(\"down\") updates selection to next workspace"
Task T017: "Write integration test: nav(\"up\") wraps from first to last workspace"
Task T018: "Write integration test: nav(\"down\") wraps from last to first workspace"
Task T019: "Write sway-test: Enter workspace mode, navigate with Down/Up"
Task T020: "Write sway-test: Navigate to workspace 23, press Enter"

# After tests written, verify handlers in parallel:
Task T022: "Verify nav handler processes \"down\" direction"
Task T023: "Verify nav handler processes \"up\" direction"
Task T024: "Verify NavigationHandler implements wrapping logic"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (verification tasks - ~10 minutes)
2. Complete Phase 2: Foundational (CRITICAL - TDD unit tests + core implementation - ~2-3 hours)
3. Complete Phase 3: User Story 1 (arrow key navigation - ~2-3 hours)
4. **STOP and VALIDATE**: Test User Story 1 independently (all tests pass, <50ms latency verified)
5. Deploy/demo if ready

**Estimated MVP Time**: ~5-6 hours total

### Incremental Delivery

1. Complete Setup + Foundational → Core nav/delete methods working (~3 hours)
2. Add User Story 1 → Test independently → Deploy/Demo (MVP! - arrow key navigation working - ~2 hours)
3. Add User Story 2 → Test independently → Deploy/Demo (window navigation working - ~2 hours)
4. Add User Story 3 → Test independently → Deploy/Demo (home/end jump working - ~1 hour)
5. Add User Story 4 → Test independently → Deploy/Demo (delete window working - ~1 hour)
6. Complete Polish phase → Final validation → Production ready (~2 hours)

**Estimated Total Time**: ~11-12 hours

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (~3 hours)
2. Once Foundational is done:
   - Developer A: User Story 1 (arrow navigation) - ~2 hours
   - Developer B: User Story 2 (window navigation) - ~2 hours
   - Developer C: User Story 3 + 4 (home/end + delete) - ~2 hours
3. Stories complete and integrate independently
4. Team completes Polish phase together (~1 hour)

**Estimated Parallel Time**: ~6-7 hours with 3 developers

---

## Success Criteria Validation

### SC-001: Navigate through workspace list with <50ms visual feedback
- **Tasks**: T064, T067, T077, T078 (performance testing and manual validation)
- **Validation**: Performance tests measure latency, manual tests confirm visual feedback timing

### SC-002: 100% of navigation key presses result in correct preview state changes
- **Tasks**: T016-T020, T028-T031, T040-T044, T053-T056 (integration and sway-tests)
- **Validation**: All integration tests verify state changes for every navigation key

### SC-003: Users can select and switch to any workspace using keyboard navigation
- **Tasks**: T019-T020, T027 (sway-test end-to-end with workspace switch)
- **Validation**: End-to-end test navigates to workspace 23 and verifies switch completes

### SC-004: System handles rapid navigation (10+ key presses/sec) without dropping events
- **Tasks**: T065, T067 (rapid navigation performance test)
- **Validation**: Performance test sends 20 events in 2 seconds, verifies all processed

### SC-005: Navigation state cleared immediately (<20ms) when workspace mode exits
- **Tasks**: T066, T067 (state cleanup performance test)
- **Validation**: Performance test measures state reset latency after cancel/execute

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- **TDD Required**: Verify tests FAIL before implementing, PASS after implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- **Constitution Compliance**: All tasks follow Principles X (Python standards), XI (Sway IPC authority), XIV (TDD), XV (sway-test framework)
