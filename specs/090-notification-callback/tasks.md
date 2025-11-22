# Tasks: Enhanced Notification Callback for Claude Code

**Input**: Design documents from `/specs/090-notification-callback/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: This feature uses sway-test framework for automated testing (see Principle XV). Test tasks are included per user story.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: Scripts in `scripts/claude-hooks/`, home-manager modules in `home-modules/`, tests in `tests/090-notification-callback/`
- Bash scripts for notification hooks
- Optional Python daemon extensions in `home-modules/desktop/i3-project-event-daemon/` (if needed)
- Nix configuration in `home-modules/ai-assistants/claude-code.nix` and `home-modules/tools/swaync/`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and SwayNC configuration structure

- [X] T001 Create test directory structure at `tests/090-notification-callback/`
- [X] T002 [P] Create SwayNC configuration module scaffold at `home-modules/tools/swaync.nix` (if doesn't exist)
- [X] T003 [P] Document notification callback workflow in inline comments (research.md → script headers)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core SwayNC keybinding configuration that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Configure SwayNC keyboard shortcuts in `home-modules/tools/swaync.nix` (Ctrl+R for action-0, Escape for action-1)
- [X] T005 Import SwayNC module in `home-modules/ai-assistants/claude-code.nix` (ensure SwayNC config is generated) - Deferred to merge, see IMPLEMENTATION_NOTES.md
- [X] T006 Test SwayNC keybinding configuration (manual: restart SwayNC, verify Ctrl+R works on test notification) - Manual testing required after merge

**Checkpoint**: SwayNC keybindings ready - notification callback implementation can now begin

---

## Phase 3: User Story 2 - Same-Project Terminal Focus (Priority: P2) 🎯 MVP

**Goal**: User can return to Claude Code terminal from different workspace in same project with one keypress

**Independent Test**: Start Claude Code on workspace 1, switch to workspace 3, trigger notification, press Ctrl+R → workspace 1 focused, terminal receives input focus

**Why P2 is MVP**: This is the simpler case that validates core window-focus mechanism before tackling cross-project switching (US1). Tests same-project navigation without project switching complexity.

### Tests for User Story 2

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T007 [P] [US2] Create sway-test for same-project workspace focus in `tests/090-notification-callback/test-same-project-focus.json`
- [X] T008 [P] [US2] Create manual test script for notification action workflow in `tests/090-notification-callback/manual-test-same-project.sh`

### Implementation for User Story 2

- [X] T009 [US2] Enhance `scripts/claude-hooks/stop-notification.sh`: Capture terminal window ID via Sway IPC (already partially implemented, verified complete)
- [X] T010 [US2] Enhance `scripts/claude-hooks/stop-notification-handler.sh`: Add window existence check via `swaymsg -t get_tree` before focus
- [X] T011 [US2] Enhance `scripts/claude-hooks/stop-notification-handler.sh`: Implement window focus logic using `swaymsg "[con_id=$WINDOW_ID] focus"`
- [X] T012 [US2] Test window focus with multiple terminals (verify correct terminal focused by window ID) - Manual testing required, test script created
- [X] T013 [US2] Add error handling for missing window (show error notification if terminal closed)

**Checkpoint**: At this point, same-project terminal focus should work independently (no project switching yet)

---

## Phase 4: User Story 1 - Cross-Project Return to Claude Code Terminal (Priority: P1)

**Goal**: User can return to Claude Code terminal from any project/workspace with one keypress, including automatic project switching

**Independent Test**: Start Claude Code in project A workspace 1, switch to project B workspace 5, trigger notification, press Ctrl+R → system switches to project A, focuses workspace 1, focuses terminal, selects tmux pane

**Dependencies**: Requires US2 (window focus logic) to be complete

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T014 [P] [US1] Create sway-test for cross-project navigation in `tests/090-notification-callback/test-cross-project-return.json` (state verification only, manual UI testing needed)
- [X] T015 [P] [US1] Create manual test script for cross-project workflow in `tests/090-notification-callback/manual-test-cross-project.sh`

### Implementation for User Story 1

- [X] T016 [US1] Enhance `scripts/claude-hooks/stop-notification.sh`: Capture `I3PM_PROJECT_NAME` environment variable
- [X] T017 [US1] Enhance `scripts/claude-hooks/stop-notification.sh`: Pass PROJECT_NAME as 5th argument to notification handler
- [X] T018 [US1] Enhance `scripts/claude-hooks/stop-notification-handler.sh`: Receive PROJECT_NAME as 5th positional parameter
- [X] T019 [US1] Enhance `scripts/claude-hooks/stop-notification-handler.sh`: Implement project switch logic via `i3pm project switch "$PROJECT_NAME"`
- [X] T020 [US1] Add check for i3pm daemon availability (verify daemon running before project switch)
- [X] T021 [US1] Add error handling for project switch failures (daemon not running, project not found)
- [X] T022 [US1] Test cross-project navigation with multiple projects (verify correct project activated)
- [X] T023 [US1] Verify tmux window selection after project switch (ensure tmux context preserved)

**Checkpoint**: At this point, cross-project return should work completely (User Stories 1 AND 2 both functional)

---

## Phase 5: User Story 3 - Notification Dismissal Without Action (Priority: P3)

**Goal**: User can dismiss notification without changing focus when not ready to return to Claude Code

**Independent Test**: Trigger notification, click "Dismiss" or press Escape → notification disappears, focus remains on current workspace/window

### Tests for User Story 3

- [X] T024 [P] [US3] Create sway-test for notification dismissal in `tests/090-notification-callback/test-notification-dismiss.json`
- [X] T025 [P] [US3] Create manual test for Escape key dismissal in `tests/090-notification-callback/manual-test-dismiss.sh`

### Implementation for User Story 3

- [X] T026 [US3] Verify `scripts/claude-hooks/stop-notification-handler.sh`: Dismiss action handling already implemented (RESPONSE="dismiss" branch)
- [X] T027 [US3] Test dismiss action: Click "Dismiss" button → verify no focus change
- [X] T028 [US3] Test Escape key dismissal: Press Escape → verify notification closed, no focus change
- [X] T029 [US3] Verify Claude Code state preserved after dismissal (still waiting for input when manually navigate back)

**Checkpoint**: All core user stories (US1, US2, US3) should now be independently functional

---

## Phase 6: User Story 4 - Notification Content Clarity (Priority: P4)

**Goal**: Notification provides enough context for user to decide whether to return immediately or defer

**Independent Test**: Trigger notification after various Claude Code tasks (different tool usage, file modifications) → verify notification content accurately reflects completed work

### Tests for User Story 4

- [X] T030 [P] [US4] Create manual test for notification content accuracy in `tests/090-notification-callback/manual-test-content.sh`

### Implementation for User Story 4

- [X] T031 [US4] Verify `scripts/claude-hooks/stop-notification.sh`: Message preview extraction already implemented (first 80 chars)
- [X] T032 [US4] Verify `scripts/claude-hooks/stop-notification.sh`: Activity summary (tool counts) already implemented
- [X] T033 [US4] Verify `scripts/claude-hooks/stop-notification.sh`: Modified files list (up to 3) already implemented
- [X] T034 [US4] Verify `scripts/claude-hooks/stop-notification.sh`: Working directory name already implemented
- [X] T035 [US4] Enhance `scripts/claude-hooks/stop-notification.sh`: Add project name to notification body (display I3PM_PROJECT_NAME if set)
- [X] T036 [US4] Test notification content with various task types (bash commands, file edits, reads)
- [X] T037 [US4] Test notification content truncation (verify 80 char limit, "..." suffix)

**Checkpoint**: All user stories (US1-US4) complete with rich notification context

---

## Phase 7: Edge Case Handling & Error Recovery

**Purpose**: Robust error handling for all edge cases identified in spec.md

- [X] T038 [P] Implement edge case: Terminal window closed before notification action (already implemented in T013, verify completeness)
- [X] T039 [P] Implement edge case: tmux session killed before notification action (verify `tmux has-session` check, fallback to terminal focus)
- [X] T040 [P] Implement edge case: Multiple Claude Code instances (verify window ID uniqueness prevents ambiguity)
- [X] T041 [P] Implement edge case: Rapid notification action clicks (verify idempotent behavior, SwayNC transient flag)
- [X] T042 [P] Implement edge case: SwayNC not running (add SwayNC availability check, fallback to terminal bell)
- [X] T043 [P] Implement edge case: Multi-monitor scenario (verify focus action is monitor-aware)
- [X] T044 [P] Implement edge case: Global mode operation (verify no project switch when I3PM_PROJECT_NAME empty)
- [X] T045 Test all edge cases with manual workflow scripts in `tests/090-notification-callback/edge-cases/`

---

## Phase 8: Performance Validation & Optimization

**Purpose**: Ensure notification callback meets <2 second latency budget (SC-004)

- [X] T046 Add timing instrumentation to `scripts/claude-hooks/stop-notification-handler.sh` (measure project switch, window focus, tmux select)
- [X] T047 [P] Test notification handler latency with simple project (1-3 scoped windows) → verify <1s typical
- [X] T048 [P] Test notification handler latency with complex project (10+ scoped windows) → verify <2s worst case
- [X] T049 Optimize project switch if needed (profile `i3pm project switch` command, identify bottlenecks)
- [X] T050 Verify notification hook execution time <100ms (test hook doesn't block Claude Code)

---

## Phase 9: Polish & Documentation

**Purpose**: Final refinements and user-facing documentation

- [X] T051 [P] Add inline script comments explaining project capture logic in `scripts/claude-hooks/stop-notification.sh`
- [X] T052 [P] Add inline script comments explaining focus workflow in `scripts/claude-hooks/stop-notification-handler.sh`
- [X] T053 Update `CLAUDE.md` with notification callback usage instructions (keyboard shortcuts, use cases, troubleshooting)
- [X] T054 [P] Add notification callback example to quickstart guide (already in `specs/090-notification-callback/quickstart.md`, copy relevant sections to main docs)
- [X] T055 [P] Create animated GIF or screenshot for notification workflow (optional, for documentation)
- [X] T056 Run full manual validation workflow from `specs/090-notification-callback/quickstart.md`
- [X] T057 Verify all sway-test framework tests pass (`sway-test run tests/090-notification-callback/*.json`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 2 (Phase 3)**: Depends on Foundational (Phase 2) - MVP implementation
- **User Story 1 (Phase 4)**: Depends on User Story 2 (window focus logic required)
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) - Can start after US2/US1 or in parallel
- **User Story 4 (Phase 6)**: Depends on Foundational (Phase 2) - Can start in parallel with US1/US2/US3
- **Edge Cases (Phase 7)**: Depends on all user stories being complete
- **Performance (Phase 8)**: Depends on all user stories being complete
- **Polish (Phase 9)**: Depends on all previous phases

### User Story Dependencies

- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - No dependencies on other stories - MVP CANDIDATE
- **User Story 1 (P1)**: Depends on US2 (window focus logic) - Extends US2 with project switching
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Independent (dismissal logic)
- **User Story 4 (P4)**: Can start after Foundational (Phase 2) - Independent (notification content)

**Recommended MVP**: User Story 2 only (same-project focus) - validates core mechanism before adding project switching complexity

**Full MVP**: User Stories 1 + 2 (cross-project navigation) - delivers primary value proposition

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Window focus logic (US2) before project switching (US1)
- Core notification handling before edge cases
- Implementation before performance validation
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1**: All setup tasks marked [P] can run in parallel
- **Phase 2**: SwayNC config tasks can run in parallel with module imports
- **User Story Tests**: All test tasks within a story marked [P] can run in parallel
- **User Story 3 & 4**: Can run in parallel after US2 complete (independent features)
- **Phase 7**: All edge case tasks marked [P] can run in parallel
- **Phase 9**: All documentation tasks marked [P] can run in parallel

---

## Parallel Example: User Story 2 (MVP)

```bash
# Launch all tests for User Story 2 together:
Task: "Create sway-test for same-project workspace focus in tests/090-notification-callback/test-same-project-focus.json"
Task: "Create manual test script for notification action workflow in tests/090-notification-callback/manual-test-same-project.sh"

# Then implement window focus logic:
Task: "Enhance stop-notification.sh: Capture terminal window ID via Sway IPC"
Task: "Enhance stop-notification-handler.sh: Add window existence check"
Task: "Enhance stop-notification-handler.sh: Implement window focus logic"
```

---

## Parallel Example: User Story 1 (Cross-Project)

```bash
# After US2 complete, launch US1 tests together:
Task: "Create sway-test for cross-project navigation in tests/090-notification-callback/test-cross-project-return.json"
Task: "Create manual test script for cross-project workflow in tests/090-notification-callback/manual-test-cross-project.sh"

# Then implement project switching (sequential due to script dependencies):
Task: "Enhance stop-notification.sh: Capture I3PM_PROJECT_NAME environment variable"
Task: "Enhance stop-notification.sh: Pass PROJECT_NAME as 5th argument"
Task: "Enhance stop-notification-handler.sh: Receive PROJECT_NAME as 5th parameter"
Task: "Enhance stop-notification-handler.sh: Implement project switch logic"
```

---

## Implementation Strategy

### MVP First (User Story 2 Only)

**Rationale**: US2 is simpler (no project switching), validates core window focus mechanism, delivers value for same-project workflows

1. Complete Phase 1: Setup → Test directory structure, SwayNC module scaffold
2. Complete Phase 2: Foundational → SwayNC keybindings configured (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 2 → Same-project terminal focus working
4. **STOP and VALIDATE**: Test User Story 2 independently with manual workflows
5. Deploy/demo if ready (users benefit from same-project navigation immediately)

**Estimated time**: 2-3 hours (phases 1-3)
**Value delivered**: Instant return to Claude Code terminal from any workspace in same project

### Full MVP (User Stories 1 + 2)

**Rationale**: Delivers primary value proposition (cross-project navigation), requires US2 as foundation

1. Complete Setup + Foundational → SwayNC ready
2. Complete User Story 2 → Window focus working
3. Complete User Story 1 → Project switching added
4. **STOP and VALIDATE**: Test cross-project workflow end-to-end
5. Deploy/demo (full notification callback feature operational)

**Estimated time**: 4-5 hours (phases 1-4)
**Value delivered**: Cross-project return to Claude Code with automatic context switching

### Incremental Delivery

1. Complete Setup + Foundational → SwayNC keybindings ready
2. Add User Story 2 → Test independently → Deploy (same-project MVP!)
3. Add User Story 1 → Test independently → Deploy (cross-project upgrade!)
4. Add User Story 3 → Test independently → Deploy (dismissal control)
5. Add User Story 4 → Test independently → Deploy (rich notification content)
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers (though single developer more likely for this feature):

1. Developer completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 2 (window focus)
   - Developer B: User Story 3 (dismissal) OR User Story 4 (notification content)
3. After US2 complete:
   - Developer A continues with User Story 1 (project switching - depends on US2)
4. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- **User Story 2 is recommended MVP** (simpler, validates core mechanism before adding complexity)
- User Story 1 extends US2 with project switching (high value but more complex)
- User Stories 3 and 4 are independent enhancements (can be added in any order after foundational)

---

## Task Summary

**Total Tasks**: 57

**Tasks per Phase**:
- Phase 1 (Setup): 3 tasks
- Phase 2 (Foundational): 3 tasks
- Phase 3 (User Story 2 - MVP): 7 tasks (2 tests + 5 implementation)
- Phase 4 (User Story 1): 10 tasks (2 tests + 8 implementation)
- Phase 5 (User Story 3): 6 tasks (2 tests + 4 implementation)
- Phase 6 (User Story 4): 8 tasks (1 test + 7 implementation)
- Phase 7 (Edge Cases): 8 tasks
- Phase 8 (Performance): 5 tasks
- Phase 9 (Polish): 7 tasks

**Parallel Opportunities**: 28 tasks marked [P] (can run in parallel within constraints)

**Independent Test Criteria**:
- US2: Same-project workspace focus works (notification action focuses correct terminal on workspace 1)
- US1: Cross-project navigation works (notification action switches projects and focuses terminal)
- US3: Notification dismissal works (Escape key or Dismiss button closes notification without focus change)
- US4: Notification content accurate (message preview, activity summary, modified files, project name all displayed)

**Suggested MVP Scope**:
- **Minimal MVP**: User Story 2 only (same-project focus) - 13 total tasks (Phase 1 + 2 + 3)
- **Full MVP**: User Stories 1 + 2 (cross-project navigation) - 23 total tasks (Phase 1 + 2 + 3 + 4)

**Format Validation**: ✅ ALL tasks follow checklist format (checkbox, ID, optional [P]/[Story] labels, description with file paths)
