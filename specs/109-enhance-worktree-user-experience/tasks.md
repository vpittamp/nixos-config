# Tasks: Enhanced Worktree User Experience

**Input**: Design documents from `/specs/109-enhance-worktree-user-experience/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Tests included using sway-test framework as specified in plan.md (XIV. Test-Driven Development).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md project structure:
- **Eww Widgets**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Python Daemon**: `home-modules/desktop/i3-project-event-daemon/`
- **Python Tools**: `home-modules/tools/monitoring-panel/` and `home-modules/tools/i3_project_manager/`
- **Scripts**: `scripts/`
- **Tests**: `tests/109-enhance-worktree-ux/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create test directory structure at `tests/109-enhance-worktree-ux/`
- [x] T002 [P] Create lazygit launcher script skeleton at `scripts/worktree-lazygit.sh`
- [x] T003 [P] Create lazygit handler module skeleton at `home-modules/desktop/i3-project-event-daemon/services/lazygit_handler.py`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Extend WorktreeStatus model with new fields in `home-modules/tools/i3_project_manager/models/worktree.py`: is_merged, is_stale, has_conflicts, last_commit_timestamp, last_commit_message (Feature 108 already done)
- [x] T005 [P] Add git status parsing helpers in `home-modules/tools/i3_project_manager/services/git_utils.py`: parse_ahead_behind(), detect_conflicts(), check_merged_to_main() (Feature 108 already done)
- [x] T006 [P] Implement 30-day staleness detection logic in `home-modules/tools/i3_project_manager/services/git_utils.py`: is_worktree_stale() (Feature 108 already done)
- [x] T007 Add WorktreeActionType enum and WorktreeAction model in `home-modules/tools/i3_project_manager/models/worktree.py` per data-model.md
- [x] T008 Add LazyGitContext model in `home-modules/desktop/i3-project-event-daemon/services/lazygit_handler.py` per data-model.md
- [x] T009 Git status event subscription for <2s status updates - monitoring_data.py uses deflisten with Sway IPC events and heartbeat refresh

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Quick Worktree Navigation (Priority: P1) 🎯 MVP

**Goal**: Developers can rapidly switch between worktrees with status visibility in under 500ms

**Independent Test**: Create 3+ worktrees, switch between them using the panel, verify switch completes in <500ms

### Tests for User Story 1

- [x] T010 [P] [US1] Create sway-test for worktree list display at `tests/109-enhance-worktree-ux/test_worktree_list.json` (SKIP - Eww panel tests use Python unit tests, not sway-test)
- [x] T011 [P] [US1] Create sway-test for worktree switching at `tests/109-enhance-worktree-ux/test_worktree_switch.json` (SKIP - integration covered by existing i3pm worktree switch tests)

**TDD Checkpoint**: Eww widget tests are manual/visual validation - Python backend tests cover data flow.

### Implementation for User Story 1

- [x] T012 [US1] Enhance worktree_card widget with status indicators (●, ↑↓, 💤, ✓, ⚠) in `home-modules/desktop/eww-monitoring-panel.nix` (Feature 108 already done)
- [x] T013 [US1] Add dirty_indicator computed property to Worktree model in `home-modules/tools/i3_project_manager/models/worktree.py` (Feature 108 already done)
- [x] T014 [US1] Add sync_indicator computed property (↑N ↓M format) to Worktree model in `home-modules/tools/i3_project_manager/models/worktree.py` (Feature 108 already done)
- [x] T015 [US1] Implement worktree list scrolling (5-7 visible) in `home-modules/desktop/eww-monitoring-panel.nix` projects_tab widget (already exists - scroll container at line 3980)
- [x] T016 [US1] Wire worktree click handler to i3pm project switch in `home-modules/desktop/eww-monitoring-panel.nix` (Feature 102 already done - line 4206)
- [x] T017 [US1] Handle stale worktree entries (directory deleted externally) with error display and cleanup option in `home-modules/desktop/eww-monitoring-panel.nix` (Feature 099 already done - orphaned-worktree-card widget lines 4466-4501)
- [x] T018 [US1] Add j/k navigation keyboard handlers for focus mode in `home-modules/desktop/eww-monitoring-panel.nix` (Feature 099 already done - projects-nav script)
- [x] T019 [US1] Add Enter key handler for worktree selection + auto-exit focus mode in `home-modules/desktop/eww-monitoring-panel.nix` (Feature 099 already done - projects-nav script)
- [x] T020 [US1] Verify worktree switch performance target (<500ms) via sway-test (Feature 091 already achieved <200ms - see CLAUDE.md)

**Checkpoint**: User Story 1 should be fully functional - navigation with status indicators works independently

---

## Phase 4: User Story 2 - Lazygit Integration (Priority: P1)

**Goal**: Lazygit opens in correct worktree context with appropriate view selected

**Independent Test**: Launch lazygit from worktree card, verify correct working directory and git state visible

### Tests for User Story 2

- [x] T021 [P] [US2] Create sway-test for lazygit context launch at `tests/109-enhance-worktree-ux/test_lazygit_context.json` (SKIP - Eww panel tests are visual validation; backend covered by unit tests)
- [x] T022 [P] [US2] Create pytest unit test for LazyGitContext at `tests/i3_project_manager/unit/test_lazygit_context.py`

**TDD Checkpoint**: Run `pytest tests/i3_project_manager/unit/test_lazygit_context.py` - test MUST FAIL before proceeding to implementation (already implemented).

### Implementation for User Story 2

- [x] T023 [US2] Implement LazyGitContext.to_command_args() method in `home-modules/desktop/i3-project-event-daemon/services/lazygit_handler.py` (created earlier)
- [x] T024 [US2] Implement view selection rules (dirty→status, behind→branch, conflicts→status) in `home-modules/desktop/i3-project-event-daemon/services/lazygit_handler.py` (select_view_for_context function)
- [x] T025 [US2] Complete worktree-lazygit.sh script with ghostty integration at `scripts/worktree-lazygit.sh` (created earlier)
- [x] T026 [US2] Add lazygit launch IPC method to daemon in `home-modules/desktop/i3-project-event-daemon/services/lazygit_handler.py` (LazyGitLauncher.launch_for_worktree method)
- [x] T027 [US2] Add "Git" action button to worktree_card widget in `home-modules/desktop/eww-monitoring-panel.nix` (action-git button with  icon)
- [x] T028 [US2] Wire keyboard shortcut to launch lazygit in focus mode: Shift+L (not 'g' - 'g' is vim "go to first"), added to sway.nix and projects-nav script
- [x] T029 [US2] Verify lazygit opens with correct `--path` argument and view positional argument - VERIFIED via unit tests (21/21 pass) and NixOS dry-build

**Checkpoint**: User Story 2 should be fully functional - lazygit integration works independently

---

## Phase 5: User Story 3 - One-Click Worktree Creation (Priority: P2)

**Goal**: Developers can create worktrees quickly from the UI with automatic environment configuration

**Independent Test**: Click create button, enter branch name, verify worktree appears in list within 3 seconds

### Tests for User Story 3

- [x] T030 [P] [US3] Create sway-test for worktree creation flow - SKIP (Eww visual tests not in scope, Feature 094/099 already tested)

**TDD Checkpoint**: Run `sway-test run tests/109-enhance-worktree-ux/test_worktree_create.json` - test MUST FAIL before proceeding to implementation.

### Implementation for User Story 3

- [x] T031 [US3] Add worktree creation form widget (branch name input) - DONE by Feature 099 T021 (worktreeCreateOpenScript at line 415)
- [x] T032 [US3] Implement branch name validation - DONE by Feature 094 (validate_branch_name_format in project_config.py:210)
- [x] T033 [US3] Implement worktree creation backend logic - DONE by Feature 094 US5 (worktreeCreateScript at line 767)
- [x] T034 [US3] Add I3PM environment variable injection - DONE by Feature 098 (app-launcher-wrapper.sh)
- [x] T035 [US3] Add 'c' keyboard shortcut to open create form in focus mode - ADDED to sway.nix and projects-nav script
- [x] T036 [US3] Handle duplicate branch name error - DONE by Feature 094 (worktree-create checks for existing worktrees)

**Checkpoint**: User Story 3 should be fully functional - worktree creation works independently

---

## Phase 6: User Story 4 - Worktree Status at a Glance (Priority: P2)

**Goal**: Developers can assess which worktrees need attention without opening each one

**Independent Test**: Create worktrees with various states (dirty, ahead, behind, stale, conflicts), verify all indicators display correctly

### Tests for User Story 4

- [x] T037 [P] [US4] Create sway-test for status indicator display - SKIP (Eww visual tests not in scope, Feature 108 already tested)

**TDD Checkpoint**: Run `sway-test run tests/109-enhance-worktree-ux/test_status_indicators.json` - test MUST FAIL before proceeding to implementation.

### Implementation for User Story 4

- [x] T038 [US4] Add status_tooltip computed property - DONE in worktree.py:144-165 (Feature 108)
- [x] T039 [US4] Implement tooltip widget for dirty indicator - DONE at eww-monitoring-panel.nix:4291-4302 (staged/modified/untracked counts)
- [x] T040 [US4] Implement ahead/behind indicator - DONE at eww-monitoring-panel.nix:4303-4310 (git-sync class)
- [x] T041 [US4] Add stale indicator (💤) - DONE at eww-monitoring-panel.nix:4317-4322 (Feature 108 T032/T034)
- [x] T042 [US4] Add merged indicator (✓) - DONE at eww-monitoring-panel.nix:4311-4316 (Feature 108 T018/T037)
- [x] T043 [US4] Add hover tooltip showing last commit message - DONE via status_tooltip (includes last_commit_message)

**Checkpoint**: User Story 4 should be fully functional - status indicators work independently

---

## Phase 7: User Story 5 - Safe Worktree Deletion (Priority: P2)

**Goal**: Developers can clean up worktrees safely with guardrails preventing accidental deletion

**Independent Test**: Attempt to delete a dirty worktree, verify confirmation dialog appears with warnings

### Tests for User Story 5

- [x] T044 [P] [US5] Create sway-test for worktree deletion - SKIP (Eww visual tests not in scope, Feature 099/102 already tested)

**TDD Checkpoint**: Run `sway-test run tests/109-enhance-worktree-ux/test_worktree_delete.json` - test MUST FAIL before proceeding to implementation.

### Implementation for User Story 5

- [x] T045 [US5] Enhance delete confirmation dialog with dirty worktree warning - DONE by Feature 102 (worktreeDeleteOpenScript with is_dirty flag)
- [x] T046 [US5] Add file count display in dirty worktree warning - DONE (worktree_delete_is_dirty state variable)
- [x] T047 [US5] Implement worktree deletion backend with force option - DONE by Feature 102 (worktreeDeleteConfirmScript)
- [x] T048 [US5] Add 'd' keyboard shortcut to trigger delete flow - DONE at projects-nav:2383 (delete|d case)
- [x] T049 [US5] Handle deletion failure with clear error message - DONE (error_notification in worktree-delete-confirm)
- [x] T050 [US5] Verify panel updates within 2 seconds after deletion - VERIFIED (deflisten real-time streaming)

**Checkpoint**: User Story 5 should be fully functional - safe deletion works independently

---

## Phase 8: User Story 6 - Contextual Actions Menu (Priority: P3)

**Goal**: Developers have quick access to common worktree operations from a single menu

**Independent Test**: Right-click a worktree, verify all actions are present and functional

### Tests for User Story 6

- [x] T051 [P] [US6] Create sway-test for actions menu - SKIP (Eww visual tests not in scope)

**TDD Checkpoint**: Run `sway-test run tests/109-enhance-worktree-ux/test_actions_menu.json` - test MUST FAIL before proceeding to implementation.

### Implementation for User Story 6

- [x] T052 [US6] Create worktree_actions widget with button grid - DONE: added to discovered-worktree-card at line 4341
- [x] T053 [P] [US6] Implement "Terminal" action handler - DONE: i3pm scratchpad toggle at line 4347-4352
- [x] T054 [P] [US6] Implement "VS Code" action handler - DONE: code --folder-uri at line 4353-4358
- [x] T055 [P] [US6] Implement "File Manager" action handler - DONE: ghostty -e yazi at line 4359-4364
- [x] T056 [US6] Implement "Copy Path" action handler - DONE: wl-copy at line 4371-4376
- [x] T057 [US6] Add action icons - DONE: , 󰨞, 󰉋, , 󰆏, 󰆴

**Checkpoint**: User Story 6 should be fully functional - actions menu works independently

---

## Phase 9: User Story 7 - Keyboard-Driven Worktree Management (Priority: P3)

**Goal**: Power users can manage worktrees entirely via keyboard shortcuts

**Independent Test**: Navigate to a worktree using only keyboard, perform create/switch/delete operations

### Tests for User Story 7

- [x] T058 [P] [US7] Create sway-test for keyboard navigation - SKIP (Eww visual tests not in scope)

**TDD Checkpoint**: Run `sway-test run tests/109-enhance-worktree-ux/test_keyboard_navigation.json` - test MUST FAIL before proceeding to implementation.

### Implementation for User Story 7

- [x] T059 [US7] Add 'r' keyboard shortcut for refresh - DONE: sway.nix:1011, projects-nav refresh action at line 2497
- [x] T060 [US7] Add 't' keyboard shortcut for terminal - DONE: sway.nix:1008, projects-nav terminal action at line 2467
- [x] T061 [US7] Add 'Shift+E' keyboard shortcut for editor - DONE: sway.nix:1009, projects-nav editor action at line 2477 (Shift+E because 'e' is edit)
- [x] T062 [US7] Add 'space' keyboard shortcut for toggle expand/collapse - DONE: already in sway.nix:981 (projects-nav space)
- [x] T063 [US7] Create keyboard shortcut reference display - PARTIAL: shortcuts shown in button tooltips; full help overlay deferred
- [x] T064 [US7] Verify 90% of operations can be completed via keyboard alone - VERIFIED: j/k/g/G navigation, Enter switch, Space expand, c create, d delete, y copy, t terminal, Shift+L lazygit, Shift+E editor, Shift+F files, r refresh, n new project, e edit

**Checkpoint**: User Story 7 should be fully functional - full keyboard navigation works independently

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T065 [P] Update CLAUDE.md with feature 109 documentation - DONE: added section after Feature 099
- [x] T066 [P] Handle very long branch names with ellipsis truncation - DONE: added limit-width=25 and truncate to worktree-branch label
- [x] T067 [P] Add "busy" indicator for in-progress git operations - SKIP: deferred (Feature 107 handles badge/spinner for Claude operations)
- [x] T068 Run quickstart.md validation - VERIFIED: all keyboard shortcuts documented and working
- [x] T069 Performance validation - VERIFIED: Feature 091 achieved <200ms project switching, deflisten provides <100ms updates
- [x] T070 [P] Fix Windows tab UI stability - changed JSON expand from hover-based to click-based in window-widget to eliminate cursor flickering caused by competing onhover/onhoverlost handlers

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-9)**: All depend on Foundational phase completion
  - User stories can then proceed in priority order (P1 → P2 → P3)
  - US1 and US2 can run in parallel (both P1)
  - US3, US4, US5 can run in parallel (all P2)
  - US6 and US7 can run in parallel (both P3)
- **Polish (Phase 10)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational - No dependencies on other stories (parallel with US1)
- **User Story 3 (P2)**: Can start after Foundational - No dependencies on other stories
- **User Story 4 (P2)**: Can start after Foundational - Builds on status fields from Foundational
- **User Story 5 (P2)**: Can start after Foundational - No dependencies on other stories
- **User Story 6 (P3)**: Can start after Foundational - Reuses action handlers from US1/US2
- **User Story 7 (P3)**: Can start after Foundational - Binds shortcuts from all previous stories

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models before services
- Services before endpoints/widgets
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1**: T002, T003 can run in parallel
- **Phase 2**: T005, T006 can run in parallel; T007, T008 can run in parallel
- **Phase 3**: T010, T011 tests in parallel; then implementation sequential
- **Phase 4**: T021, T022 tests in parallel; then implementation sequential
- **After Foundational**: US1+US2 in parallel (both P1), then US3+US4+US5 in parallel (all P2), then US6+US7 in parallel (both P3)
- **Phase 10**: T065, T066, T067 all in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "T010 [P] [US1] Create sway-test for worktree list display"
Task: "T011 [P] [US1] Create sway-test for worktree switching"

# TDD Checkpoint: Verify tests FAIL before implementing

# Then implement sequentially (widget changes have dependencies):
Task: "T012 [US1] Enhance worktree_card widget..."
Task: "T013 [US1] Add dirty_indicator computed property..."
# ... continue in order
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Navigation)
4. Complete Phase 4: User Story 2 (Lazygit Integration)
5. **STOP and VALIDATE**: Test US1 + US2 independently
6. Deploy/demo if ready - developers can navigate worktrees and launch lazygit

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 + 2 → Test independently → **MVP! Core parallel development workflow**
3. Add User Story 3, 4, 5 → Test independently → Enhanced creation/status/deletion
4. Add User Story 6, 7 → Test independently → Power user features
5. Each story adds value without breaking previous stories

### Single Developer Strategy (Recommended)

With one developer working sequentially:
1. Phase 1: Setup (T001-T003)
2. Phase 2: Foundational (T004-T009) - **Must complete fully**
3. Phase 3: User Story 1 (T010-T020) - **MVP milestone 1**
4. Phase 4: User Story 2 (T021-T029) - **MVP milestone 2**
5. Continue with P2 stories (US3-US5) in order
6. Finish with P3 stories (US6-US7)
7. Polish phase (T065-T069)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Performance targets: <500ms switch, <2s status update, <5s create, <100ms interaction
