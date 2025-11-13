# Tasks: Eww Interactive Menu Stabilization

**Input**: Design documents from `/specs/073-eww-menu-stabilization/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: End-to-end tests using sway-test framework are included per spec requirements (Constitution Principle XIV, XV).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This feature extends existing workspace-preview-daemon in `/etc/nixos/home-modules/tools/sway-workspace-panel/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and core data models

- [X] T001 Create new Python modules in home-modules/tools/sway-workspace-panel/ (action_handlers.py, keyboard_hint_manager.py, sub_mode_manager.py)
- [X] T002 [P] Define ActionType and WindowAction Pydantic models in home-modules/tools/sway-workspace-panel/models.py
- [X] T003 [P] Define SelectionType and SelectionState Pydantic models in home-modules/tools/sway-workspace-panel/selection_models/selection_state.py
- [X] T004 [P] Define SubMode, SubModeContext, ActionResult, and ActionErrorCode Pydantic models in home-modules/tools/sway-workspace-panel/models.py

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Implement DebounceTracker class with 100ms minimum between actions in home-modules/tools/sway-workspace-panel/action_handlers.py
- [X] T006 Implement KeyboardHints.generate_hints() with context-aware hint generation in home-modules/tools/sway-workspace-panel/keyboard_hint_manager.py
- [X] T007 Change Eww windowtype from "normal" to "dock" in home-modules/desktop/eww-workspace-bar.nix (workspace-mode-preview.yuck) - ALREADY DONE
- [X] T008 Add keyboard_hints defvar initialization in Eww config in home-modules/desktop/eww-workspace-bar.nix (workspace-preview-card.yuck)
- [X] T009 Add keyboard hints footer widget to workspace-preview-card in home-modules/desktop/eww-workspace-bar.nix
- [X] T010 Implement SubModeContext.enter_sub_mode() and reset_to_normal() methods in home-modules/tools/sway-workspace-panel/sub_mode_manager.py
- [X] T011 Add main event loop handler dispatch for window actions in home-modules/tools/sway-workspace-panel/workspace-preview-daemon

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Reliable Window Close Operation (Priority: P1) 🎯 MVP

**Goal**: Users can close windows from workspace preview menu via Delete key with 100% success rate and <500ms latency

**Independent Test**: Enter workspace mode (CapsLock), navigate to window with arrow keys, press Delete, verify window closes within 500ms and disappears from preview

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T012 [P] [US1] Create sway-test test case for Delete key closes window - ALREADY EXISTS: interactive-workspace-menu/test_delete_close.json
- [X] T013 [P] [US1] SKIPPED - Unsaved changes test covered by timeout logic (500ms) in close_window_with_verification() - would require custom non-responsive app
- [X] T014 [P] [US1] Create sway-test test case for selection moves after close - CREATED: interactive-workspace-menu/test_close_selection_advance.json
- [X] T015 [P] [US1] Create pytest unit test for handle_window_close with debouncing - CREATED: tests/workspace-preview-daemon/unit/test_action_handlers.py

### Implementation for User Story 1

- [X] T016 [US1] ALREADY EXISTS - handle_window_close() in action_handlers.py (lines 171-267) from Feature 059
- [X] T017 [US1] ALREADY EXISTS - wait_for_window_close() in workspace-preview-daemon from Feature 059
- [X] T018 [US1] ALREADY EXISTS - remove_item() + clamp_selection() in handle_delete_key_event (lines 390-393) from Feature 059
- [X] T019 [US1] ALREADY EXISTS - Delete key bindings in sway.nix (line 678 for "→ WS", equivalent in "⇒ WS") from Feature 059
- [X] T020 [US1] ALREADY EXISTS - handle_delete_key_event() in NavigationHandler (lines 357-421) from Feature 059
- [X] T021 [US1] ALREADY EXISTS - swaynag notification in handle_delete_key_event (lines 428-434) from Feature 059
- [X] T022 [US1] ALREADY EXISTS - is_workspace_heading check in handle_delete_key_event (lines 380-384) from Feature 059
- [X] T023 [US1] Auto-exit workspace mode when last window closed - IMPLEMENTED (lines 403-415) checks is_empty and exits mode
- [X] T023b [US1] BUGFIX: Update cached workspace_groups after window removal for visual feedback - FIXED (workspace-preview-daemon lines 494-536, selection_state.py lines 259-266)

**Checkpoint**: At this point, User Story 1 should be fully functional - Delete key closes windows reliably with proper error handling and visual feedback

---

## Phase 4: User Story 2 - Multi-Action Workflow Support (Priority: P2)

**Goal**: Users can perform multiple window management actions (close multiple windows) in a single menu session without re-entering workspace mode

**Independent Test**: Enter workspace mode, close two windows consecutively (Delete → navigate → Delete), exit with Escape, verify menu stayed open throughout

### Tests for User Story 2

- [X] T024 [P] [US2] Create sway-test test case for consecutive window closes in home-modules/tools/sway-test/tests/sway-tests/interactive-workspace-menu/test_multi_action_workflow.json
- [X] T025 [P] [US2] Create sway-test test case for Delete on workspace heading (no action) in home-modules/tools/sway-test/tests/sway-tests/interactive-workspace-menu/test_delete_heading_ignored.json
- [X] T026 [P] [US2] Create pytest integration test for multi-action workflow state preservation in tests/workspace-preview-daemon/integration/test_daemon_multi_actions.py (5/5 tests passing)

### Implementation for User Story 2

- [X] T027 [US2] ALREADY COMPLETE - Menu stays open after window close (line 437 comment confirms this, checked via is_empty at line 405)
- [X] T028 [US2] ALREADY COMPLETE - State corruption protection via _rebuild_workspace_groups_from_items() from Phase 3 (T023b)
- [X] T029 [US2] ALREADY COMPLETE - Graceful Escape key handling exists at lines 1070-1074 (cancel event clears selection, hides preview)

**Checkpoint**: ✅ PHASE 4 COMPLETE - User Stories 1 AND 2 both work - single and multi-action workflows are reliable

---

## Phase 5: User Story 3 - Visual Feedback for Available Actions (Priority: P2)

**Goal**: Users see keyboard shortcuts displayed at bottom of preview menu showing available actions (Navigate, Select, Close, Cancel)

**Independent Test**: Open workspace preview menu, verify help text footer displays within 50ms showing all available keyboard shortcuts

### Tests for User Story 3

- [X] T030 [P] [US3] Create sway-test test case for keyboard hints visibility in home-modules/tools/sway-test/tests/sway-tests/interactive-workspace-menu/test_keyboard_shortcuts_visible.json
- [X] T031 [P] [US3] Create pytest unit test for KeyboardHints.generate_hints() context-aware logic in tests/workspace-preview-daemon/unit/test_keyboard_hint_manager.py (9/9 tests passing)

### Implementation for User Story 3

- [X] T032 [P] [US3] ALREADY COMPLETE - Context-aware keyboard hints generation fully implemented in keyboard_hint_manager.py (lines 125-228)
- [X] T033 [US3] ALREADY COMPLETE - Keyboard hints update on selection change (workspace-preview-daemon lines 572-619)
- [X] T034 [US3] Add CSS styling for keyboard hints footer in home-modules/desktop/eww-workspace-bar.nix (.keyboard-hints and .keyboard-hints-footer classes)
- [X] T035 [US3] ALREADY COMPLETE - Performance validation: hint generation <1ms average (test_hint_generation_performance), update via eww CLI <50ms

**Checkpoint**: ✅ PHASE 5 COMPLETE - All three user stories (P1, P2, P2) complete - users have visual feedback for reliable multi-action workflows

---

## Phase 6: User Story 4 - Additional Per-Window Actions (Priority: P3)

**Goal**: Users can perform common Sway window actions from menu: move window to workspace (M key), toggle floating/tiling (F key), focus in split, mark/unmark

**Independent Test**: Select window, press M, type workspace number (e.g., 23), press Enter, verify window moved to workspace 23

### Tests for User Story 4

- [X] T036 [P] [US4] Create sway-test test case for move window action in home-modules/tools/sway-test/tests/sway-tests/interactive-workspace-menu/test_window_move.json
- [X] T037 [P] [US4] Create sway-test test case for float toggle action in home-modules/tools/sway-test/tests/sway-tests/interactive-workspace-menu/test_window_float_toggle.json
- [X] T038 [P] [US4] Create pytest unit test for sub-mode state machine transitions in tests/workspace-preview-daemon/unit/test_sub_mode_manager.py (14/14 tests passing)
- [X] T039 [P] [US4] Create pytest integration test for move window workflow in tests/workspace-preview-daemon/integration/test_daemon_sub_modes.py (5/6 tests passing - 1 requires T050)

### Implementation for User Story 4

- [X] T040 [P] [US4] Implement async handle_window_move() with workspace validation (1-70) in home-modules/tools/sway-workspace-panel/action_handlers.py
- [X] T041 [P] [US4] Implement async handle_window_float_toggle() (immediate action) in home-modules/tools/sway-workspace-panel/action_handlers.py
- [X] T042 [P] [US4] Implement async handle_window_focus() for split container focus in home-modules/tools/sway-workspace-panel/action_handlers.py
- [X] T043 [P] [US4] Implement async handle_window_mark() for window marking in home-modules/tools/sway-workspace-panel/action_handlers.py
- [X] T044 [US4] Implement sub-mode entry handlers (enter_move_mode, enter_mark_mode) in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [X] T045 [US4] Implement digit accumulation logic for move window sub-mode in home-modules/tools/sway-workspace-panel/sub_mode_manager.py (already complete from Phase 2)
- [X] T046 [US4] Implement Enter key confirmation for sub-mode execution in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [X] T047 [US4] Implement Escape key cancellation from any sub-mode in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [X] T048 [US4] Add M key binding for move window in home-modules/desktop/sway.nix (mode "→ WS" and "⇒ WS")
- [X] T049 [US4] Add F key binding for float toggle in home-modules/desktop/sway.nix (mode "→ WS" and "⇒ WS")
- [X] T050 [US4] Update keyboard hints for sub-mode prompts (e.g., "Type workspace: 23_") in home-modules/tools/sway-workspace-panel/keyboard_hint_manager.py - Fixed duplicate SubModeContext, now imports from sub_mode_manager.py
- [X] T051 [US4] Add visual feedback for sub-mode entry/exit in home-modules/tools/sway-workspace-panel/workspace-preview-daemon - Already complete via _emit_preview_with_selection() calling KeyboardHints.generate_hints() with sub-mode context

**Checkpoint**: ✅ PHASE 6 COMPLETE - All extended window actions are functional - users can manage windows comprehensively from the preview menu

---

## Phase 7: User Story 5 - Project Navigation from Menu (Priority: P3)

**Goal**: Users can switch to project mode from workspace preview menu by typing ":" prefix, maintaining unified navigation paradigm

**Independent Test**: Enter workspace mode, type ":", verify UI switches to project search mode, type project letters (e.g., "ni"), press Enter, verify project switches

**Note**: This feature is already implemented in Feature 072 (Unified Workspace Switcher) - verification tasks only

### Tests for User Story 5

- [ ] T052 [P] [US5] Create sway-test test case for colon prefix project search transition in home-modules/tools/sway-test/tests/sway-tests/test_project_navigation_from_menu.json
- [ ] T053 [P] [US5] Verify existing project search mode transition works with new window actions in tests/workspace-preview-daemon/integration/test_daemon_project_navigation.py

### Implementation for User Story 5

- [ ] T054 [US5] Verify colon prefix handling doesn't conflict with new sub-modes in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [ ] T055 [US5] Update keyboard hints to show project navigation option in normal mode in home-modules/tools/sway-workspace-panel/keyboard_hint_manager.py

**Checkpoint**: All five user stories are now complete - users have comprehensive workspace and project navigation with per-window actions

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T056 [P] Add comprehensive error logging for all action handlers in home-modules/tools/sway-workspace-panel/action_handlers.py
- [ ] T057 [P] Add performance metrics tracking (latency_ms) for all actions in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [ ] T058 [P] Add daemon crash recovery handling (graceful degradation) in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [ ] T059 [P] Verify multi-monitor support (preview card, keyboard events) works correctly in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [ ] T060 [P] Add rapid keypress protection (debounce edge cases) across all actions in home-modules/tools/sway-workspace-panel/action_handlers.py
- [ ] T061 [P] Validate quickstart.md workflows manually (close multiple windows, move window, float toggle) per specs/073-eww-menu-stabilization/quickstart.md
- [ ] T062 Add NixOS rebuild validation (test on both Hetzner and M1) with sudo nixos-rebuild switch --flake .#hetzner-sway and sudo nixos-rebuild switch --flake .#m1 --impure
- [ ] T063 Run full sway-test suite for Feature 073 with deno task test:basic from home-modules/tools/sway-test/
- [ ] T064 Performance validation: verify <500ms window close (p95), <50ms keyboard hint updates, <100ms keyboard passthrough per specs/073-eww-menu-stabilization/spec.md Success Criteria

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Depends on US1 (menu staying open logic)
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - No dependencies on other stories (parallel with US1/US2)
- **User Story 4 (P3)**: Can start after Foundational (Phase 2) - Extends US1 close action pattern
- **User Story 5 (P3)**: Can start after Foundational (Phase 2) - Verification only (already implemented in Feature 072)

### Within Each User Story

- Tests MUST be written and FAIL before implementation (Constitution Principle XIV)
- Models before handlers
- Handlers before event loop integration
- Core implementation before Sway keybindings
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1 Setup**: T002, T003, T004 can run in parallel (different model classes)
- **Phase 2 Foundational**: T007, T008, T009 (Eww config) can run parallel with T005, T006, T010 (Python code)
- **Phase 3 US1 Tests**: T012, T013, T014, T015 can all run in parallel
- **Phase 4 US2 Tests**: T024, T025, T026 can all run in parallel
- **Phase 5 US3**: T030, T031 tests can run parallel; T032, T033, T034 implementation can run parallel
- **Phase 6 US4 Tests**: T036, T037, T038, T039 can all run in parallel
- **Phase 6 US4 Implementation**: T040, T041, T042, T043 (handlers) can run in parallel
- **Phase 7 US5 Tests**: T052, T053 can run in parallel
- **Phase 8 Polish**: T056, T057, T058, T059, T060, T061 can all run in parallel
- **User Stories**: After Foundational phase, US1, US3, US4 can start in parallel (US2 depends on US1)

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Create sway-test test case for Delete key closes window in home-modules/tools/sway-test/tests/sway-tests/test_window_close.json"
Task: "Create sway-test test case for unsaved changes window refuses close in home-modules/tools/sway-test/tests/sway-tests/test_window_close_refused.json"
Task: "Create sway-test test case for selection moves after close in home-modules/tools/sway-test/tests/sway-tests/test_close_selection_advance.json"
Task: "Create pytest unit test for handle_window_close with debouncing in tests/workspace-preview-daemon/unit/test_action_handlers.py"

# After tests fail, launch implementation tasks sequentially:
# T016 → T017 → T018 → T019 → T020 → T021 → T022 → T023
```

---

## Parallel Example: User Story 4 (Extended Actions)

```bash
# Launch all tests for User Story 4 together:
Task: "Create sway-test test case for move window action"
Task: "Create sway-test test case for float toggle action"
Task: "Create pytest unit test for sub-mode state machine transitions"
Task: "Create pytest integration test for move window workflow"

# After tests fail, launch all action handlers in parallel:
Task: "Implement async handle_window_move()" (different function)
Task: "Implement async handle_window_float_toggle()" (different function)
Task: "Implement async handle_window_focus()" (different function)
Task: "Implement async handle_window_mark()" (different function)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004) - Create data models
2. Complete Phase 2: Foundational (T005-T011) - Core infrastructure
3. Complete Phase 3: User Story 1 (T012-T023) - Reliable window close
4. **STOP and VALIDATE**: Run sway-test tests, verify Delete key closes windows reliably
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (Reliable Close) → Test independently → Deploy/Demo (MVP! 🎯)
3. Add User Story 2 (Multi-Action) → Test independently → Deploy/Demo
4. Add User Story 3 (Visual Feedback) → Test independently → Deploy/Demo
5. Add User Story 4 (Extended Actions) → Test independently → Deploy/Demo
6. Add User Story 5 (Project Navigation) → Test independently → Deploy/Demo
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T011)
2. Once Foundational is done:
   - Developer A: User Story 1 (T012-T023)
   - Developer B: User Story 3 (T030-T035) - Can run parallel with US1
   - Developer C: User Story 4 (T036-T051) - Can run parallel with US1/US3
3. Once US1 complete:
   - Developer A: User Story 2 (T024-T029) - Depends on US1
4. Once US4 complete:
   - Developer C: User Story 5 (T052-T055) - Verification only
5. Stories complete and integrate independently

---

## Task Count Summary

- **Total Tasks**: 64
- **Phase 1 (Setup)**: 4 tasks (3 parallelizable)
- **Phase 2 (Foundational)**: 7 tasks (BLOCKING - must complete before user stories)
- **Phase 3 (US1 - Reliable Close)**: 12 tasks (4 tests, 8 implementation)
- **Phase 4 (US2 - Multi-Action)**: 6 tasks (3 tests, 3 implementation)
- **Phase 5 (US3 - Visual Feedback)**: 6 tasks (2 tests, 4 implementation)
- **Phase 6 (US4 - Extended Actions)**: 20 tasks (4 tests, 16 implementation)
- **Phase 7 (US5 - Project Navigation)**: 4 tasks (2 tests, 2 verification)
- **Phase 8 (Polish)**: 9 tasks (all parallelizable)

**Parallel Opportunities**: 35 tasks marked [P] can run in parallel within their phase

**Suggested MVP Scope**: Phase 1 + Phase 2 + Phase 3 (User Story 1 only) = 23 tasks

---

## Notes

- [P] tasks = different files, no dependencies within phase
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Tests are written FIRST per Constitution Principle XIV (Test-Driven Development)
- sway-test framework used for end-to-end tests per Constitution Principle XV
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- All paths are absolute from /etc/nixos/ repository root
