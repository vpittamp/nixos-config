# Tasks: Interactive Workspace Menu with Keyboard Navigation

**Input**: Design documents from `/specs/059-interactive-workspace-menu/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are NOT explicitly requested in the feature specification, so only integration tests via sway-test framework are included (per Feature 069 standards).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Python daemon code: `home-modules/tools/sway-workspace-panel/`
- Eww configuration: `home-modules/desktop/eww-workspace-bar.nix`
- Theme configuration: `home-modules/desktop/unified-bar-theme.nix`
- Tests: `tests/sway-tests/interactive-workspace-menu/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create Pydantic models directory at home-modules/tools/sway-workspace-panel/models/selection_state.py
- [X] T002 [P] Create sway-test test directory at tests/sway-tests/interactive-workspace-menu/
- [X] T003 [P] Document keybinding changes needed in home-modules/desktop/sway-keybindings.nix (reference for Phase 2)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement SelectionState Pydantic model in home-modules/tools/sway-workspace-panel/models/selection_state.py (fields: selected_index, item_type, workspace_num, window_id, visible)
- [X] T005 [P] Implement NavigableItem Pydantic model in home-modules/tools/sway-workspace-panel/models/selection_state.py (fields: item_type, display_text, workspace_num, window_id, icon_path, position_index, selectable)
- [X] T006 Implement PreviewListModel Pydantic model in home-modules/tools/sway-workspace-panel/models/selection_state.py (fields: items, current_selection_index, scroll_position; methods: navigate_down, navigate_up, reset_selection, clamp_selection, from_workspace_groups)
- [X] T007 Add SelectionManager class to workspace_preview_daemon.py for managing selection state (owns PreviewListModel instance, exposes navigation methods)
- [X] T008 Modify emit_preview() function in workspace_preview_daemon.py to include selection_state JSON object in output (matches contracts/daemon-ipc-events.md schema)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Navigate Window List with Arrow Keys (Priority: P1) 🎯 MVP

**Goal**: Users can press Up/Down arrow keys to navigate through the workspace/window list shown in the preview card. A visual cursor (highlight/selection indicator) moves between items, and the current selection is clearly visible.

**Independent Test**: Can be fully tested by entering workspace mode, pressing arrow keys, and verifying that a selection cursor moves between list items. Delivers value by allowing users to visually browse their workspace layout before deciding where to navigate.

### Implementation for User Story 1

- [X] T009 [P] [US1] Add arrow key Sway keybindings in home-modules/desktop/sway.nix (workspace mode: Down → `i3pm-workspace-mode nav down`, Up → `i3pm-workspace-mode nav up`)
- [X] T010 [P] [US1] Implement NavigationHandler class in workspace_preview_daemon.py with handle_arrow_key_event(direction, mode) method
- [X] T011 [US1] Integrate NavigationHandler with i3pm daemon IPC listener to receive arrow_key_nav events (per contracts/daemon-ipc-events.md)
- [X] T012 [US1] Update handle_workspace_mode() in workspace_preview_daemon.py to initialize SelectionManager with PreviewListModel on mode entry
- [X] T013 [US1] Implement circular navigation logic in PreviewListModel.navigate_down() using modulo arithmetic: (index + 1) % len(items)
- [X] T014 [US1] Implement circular navigation logic in PreviewListModel.navigate_up() using modulo arithmetic: (index - 1) % len(items)
- [X] T015 [US1] Update emit_preview() to call SelectionManager and include selection_state in JSON output
- [X] T016 [US1] Add .preview-app.selected CSS class to eww-workspace-bar.nix with Catppuccin blue (#89b4fa) background at 20% opacity
- [X] T017 [US1] Modify Eww workspace-mode-preview.yuck to apply .selected class to items where selection_state matches (workspace_num and window_id)
- [X] T018 [US1] Add CSS transition (0.2s ease-in-out) for .preview-app.selected background color in eww-workspace-bar.nix
- [X] T019 [US1] Implement selection reset on digit_typed event in workspace_preview_daemon.py (call SelectionManager.reset_selection())
- [X] T020 [US1] Add mode_exit event handler in workspace_preview_daemon.py to clear selection state (SelectionManager.clear())

**Checkpoint**: At this point, User Story 1 should be fully functional - arrow keys move selection with visual feedback, circular navigation works, selection resets on digit typing

---

## Phase 4: User Story 4 - Visual Selection Feedback with Catppuccin Theme (Priority: P2)

**Goal**: The selected item in the preview card has clear visual distinction using the unified Catppuccin Mocha color palette (Feature 057). Selection highlight uses accent color (e.g., blue/mauve) with subtle background change, ensuring readability across all theme states.

**Why after US1**: This refines US1's CSS styling and adds move-mode differentiation. Grouped with US1 for MVP but separated for testing clarity.

**Independent Test**: After implementing P1, verify selection highlight renders correctly with proper contrast and theme consistency. Test with all-windows view and filtered workspace view.

### Implementation for User Story 4

- [X] T021 [P] [US4] Add .preview-workspace-heading.selected CSS class to unified-bar-theme.nix with Catppuccin blue (#89b4fa) at 20% opacity
- [X] T022 [P] [US4] Update .preview-app.selected text color to white (#cdd6f4) for readability in unified-bar-theme.nix
- [X] T023 [US4] Add .preview-app.selected-move-mode CSS class with Catppuccin peach (#fab387) background for move operations in unified-bar-theme.nix
- [X] T024 [US4] Modify emit_preview() in workspace_preview_daemon.py to detect move mode (from workspace mode state) and add move_mode boolean to selection_state JSON
- [X] T025 [US4] Update Eww workspace-mode-preview.yuck to apply .selected-move-mode class when selection_state.move_mode == true
- [X] T026 [US4] Verify GTK ScrolledWindow auto-scrolling behavior by testing navigation beyond visible 600px viewport (research.md conclusion: relies on GTK native scroll)

**Checkpoint**: Selection highlight now has proper visual styling with theme consistency, move-mode differentiation works

---

## Phase 5: User Story 2 - Navigate to Selected Workspace (Priority: P2)

**Goal**: Users can press Enter while a workspace or window is selected to navigate to that workspace. If a workspace heading is selected, navigate to that workspace. If a window is selected, navigate to the workspace containing that window and focus that window.

**Independent Test**: After implementing P1, test by selecting different items with arrow keys and pressing Enter. Verify correct workspace navigation and window focus. Delivers value by completing the "visual navigation" workflow.

### Implementation for User Story 2

- [X] T027 [P] [US2] Add Enter key Sway keybinding in home-modules/desktop/sway-keybindings.nix (workspace mode: Return → `i3pm workspace-preview select`)
- [X] T028 [US2] Implement handle_enter_key_event(mode, accumulated_digits) method in NavigationHandler class in workspace_preview_daemon.py
- [X] T029 [US2] Integrate NavigationHandler with i3pm daemon IPC listener to receive enter_key_select events (per contracts/daemon-ipc-events.md)
- [X] T030 [US2] Implement navigate_to_workspace(sway_conn, workspace_num) async function using Sway IPC `workspace number N` command (per contracts/sway-ipc-commands.md)
- [X] T031 [US2] Implement focus_window(sway_conn, window_id) async function using Sway IPC `[con_id=N] focus` command (per contracts/sway-ipc-commands.md)
- [X] T032 [US2] Add logic in handle_enter_key_event() to check SelectionState.is_workspace_heading() and call navigate_to_workspace()
- [X] T033 [US2] Add logic in handle_enter_key_event() to check SelectionState.is_window() and call focus_window()
- [X] T034 [US2] Implement fallback logic: if SelectionState.selected_index is None, delegate to existing Feature 072 numeric navigation (accumulated_digits)
- [X] T035 [US2] Add error handling for invalid workspace numbers (<1 or >70) in navigate_to_workspace()
- [X] T036 [US2] Add error handling for window not found in focus_window() (return success=False with error message)
- [X] T037 [US2] Exit workspace mode and clear selection state after successful Enter navigation in workspace_preview_daemon.py

**Checkpoint**: Enter key navigation works for both workspace headings and windows, with fallback to numeric navigation when no selection exists

---

## Phase 6: User Story 3 - Close Selected Window (Priority: P3)

**Goal**: Users can press a dedicated key (Delete) while a window is selected to close that window without leaving workspace mode. The window disappears from the preview list immediately, and selection moves to the next item.

**Independent Test**: After implementing P1, test by selecting a window with arrow keys and pressing the close key. Verify window closes and preview updates. Works independently because it leverages existing Sway IPC window close commands.

### Implementation for User Story 3

- [X] T038 [P] [US3] Add Delete key Sway keybinding in home-modules/desktop/sway-keybindings.nix (workspace mode: Delete → `i3pm workspace-preview delete`)
- [X] T039 [US3] Implement handle_delete_key_event(mode) method in NavigationHandler class in workspace_preview_daemon.py
- [X] T040 [US3] Integrate NavigationHandler with i3pm daemon IPC listener to receive delete_key_close events (per contracts/daemon-ipc-events.md)
- [X] T041 [US3] Implement send_kill_command(sway_conn, container_id) async function using Sway IPC `[con_id=N] kill` command (per contracts/sway-ipc-commands.md)
- [X] T042 [US3] Implement wait_for_window_close(sway_conn, container_id, timeout_ms=500) polling function with 50ms intervals using GET_TREE queries (per contracts/sway-ipc-commands.md)
- [X] T043 [US3] Implement close_window_with_verification(sway_conn, container_id, timeout_ms=500) workflow combining send_kill_command + wait_for_window_close (per contracts/sway-ipc-commands.md)
- [X] T044 [US3] Add validation in handle_delete_key_event() to check SelectionState.is_window() (no-op if workspace_heading selected)
- [X] T045 [US3] Remove closed window from PreviewListModel.items list after successful close in handle_delete_key_event()
- [X] T046 [US3] Call PreviewListModel.clamp_selection() to adjust selection index after item removal
- [X] T047 [US3] Re-emit preview with updated list via emit_preview() after window close in handle_delete_key_event()
- [X] T048 [US3] Implement error handling for close timeout (500ms): show notification "Window close blocked" using Sway notification (per contracts/sway-ipc-commands.md error handling)
- [X] T049 [US3] Add logging (WARNING level) for window close timeouts (expected for unsaved changes, not ERROR)
- [X] T050 [US3] Maintain workspace mode active after window close (do NOT call mode_exit, allow multiple deletions)

**Checkpoint**: Delete key closes selected windows with verification, preview updates correctly, selection adjusts to next item, errors handled gracefully

---

## Phase 7: Integration Tests (sway-test framework)

**Purpose**: End-to-end validation using sway-test framework (Feature 069 sync-based tests)

- [X] T051 [P] Create test_arrow_navigation.json in tests/sway-tests/interactive-workspace-menu/ (tests Down arrow, Up arrow, circular wrap, 50+ items scrolling)
- [X] T052 [P] Create test_enter_navigation.json in tests/sway-tests/interactive-workspace-menu/ (tests Enter on workspace heading, Enter on window, fallback to digits)
- [X] T053 [P] Create test_delete_close.json in tests/sway-tests/interactive-workspace-menu/ (tests Delete window, timeout handling, no-op on workspace heading)
- [X] T054 [P] Create test_digit_filtering_selection.json in tests/sway-tests/interactive-workspace-menu/ (tests selection reset when typing digits, filtered list navigation)
- [X] T055 Run all interactive-workspace-menu tests via `sway-test run tests/sway-tests/interactive-workspace-menu/` and verify 100% pass rate

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T056 [P] Add performance benchmarking logging to NavigationHandler (measure arrow key latency target: <10ms)
- [X] T057 [P] Add Home key keybinding (workspace mode: Home → `i3pm workspace-preview nav home`) to jump to first item
- [X] T058 [P] Add End key keybinding (workspace mode: End → `i3pm workspace-preview nav end`) to jump to last item
- [X] T059 [P] Implement NavigationHandler.handle_home_key() and handle_end_key() methods
- [X] T060 Update quickstart.md with troubleshooting section for common issues (selection stuck, preview not updating, close failures)
- [X] T061 Code review: Verify all Pydantic models have proper field validation and error messages
- [X] T062 Performance validation: Test with 100+ windows to verify <10ms arrow navigation latency
- [X] T063 Accessibility validation: Verify WCAG AA contrast ratio (4.5:1 text, 3:1 background) for .selected class
- [X] T064 Run quickstart.md validation workflow (enter mode, navigate with arrows, Enter to select, Delete to close)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - US1 (Phase 3): Arrow navigation (MVP foundation)
  - US4 (Phase 4): Visual styling (refines US1)
  - US2 (Phase 5): Enter navigation (builds on US1)
  - US3 (Phase 6): Delete close (builds on US1)
- **Integration Tests (Phase 7)**: Depends on US1, US2, US3, US4 completion
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 4 (P2)**: Depends on User Story 1 completion (refines US1's CSS styling)
- **User Story 2 (P2)**: Can start after User Story 1 (uses SelectionState to determine navigation target)
- **User Story 3 (P3)**: Can start after User Story 1 (uses SelectionState to determine close target)

### Within Each User Story

**User Story 1 (Arrow Navigation)**:
- T009, T010 can run in parallel (keybindings vs Python handler)
- T011 depends on T010 (integration depends on handler)
- T012-T015 depends on T011 (navigation logic)
- T016, T017, T018 can run in parallel after T015 (CSS styling)
- T019, T020 depends on T012 (event handlers)

**User Story 4 (Visual Feedback)**:
- T021, T022, T023 can run in parallel (all CSS changes)
- T024, T025 depends on T023 (move-mode logic)
- T026 is independent validation (can run anytime)

**User Story 2 (Enter Navigation)**:
- T027, T028 can run in parallel (keybinding vs handler)
- T029 depends on T028 (integration)
- T030, T031 can run in parallel (both Sway IPC functions)
- T032-T037 depends on T030, T031 (uses both functions)

**User Story 3 (Delete Close)**:
- T038, T039 can run in parallel (keybinding vs handler)
- T040 depends on T039 (integration)
- T041, T042 can run in parallel (send kill vs polling)
- T043 depends on T041, T042 (combines both)
- T044-T050 depends on T043 (uses verification workflow)

### Parallel Opportunities

- **Phase 1**: T002, T003 can run in parallel (independent directories)
- **Phase 2**: T005 can run in parallel with T004 (different Pydantic models in same file)
- **User Story 1**: T009, T010 parallel; T016, T017, T018 parallel
- **User Story 4**: T021, T022, T023 parallel
- **User Story 2**: T027, T028 parallel; T030, T031 parallel
- **User Story 3**: T038, T039 parallel; T041, T042 parallel
- **Integration Tests (Phase 7)**: T051, T052, T053, T054 all parallel (independent test files)
- **Polish (Phase 8)**: T056, T057, T058, T059 all parallel (independent features)

---

## Parallel Example: User Story 1

```bash
# Launch keybindings and Python handler together:
Task: "Add arrow key Sway keybindings in home-modules/desktop/sway-keybindings.nix"
Task: "Implement NavigationHandler class in workspace_preview_daemon.py"

# Launch CSS styling tasks together:
Task: "Add .preview-app.selected CSS class to unified-bar-theme.nix"
Task: "Modify Eww workspace-mode-preview.yuck to apply .selected class"
Task: "Add CSS transition (0.2s) for .preview-app.selected background"
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 4 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (arrow navigation)
4. Complete Phase 4: User Story 4 (visual feedback)
5. **STOP and VALIDATE**: Test arrow navigation with visual feedback independently
6. Deploy/demo if ready (MVP: users can browse workspace list with arrow keys)

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 + User Story 4 → Test independently → Deploy/Demo (MVP: arrow navigation!)
3. Add User Story 2 → Test independently → Deploy/Demo (Enter navigation)
4. Add User Story 3 → Test independently → Deploy/Demo (Delete close)
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 + User Story 4 (arrow navigation + styling)
   - Developer B: User Story 2 (Enter navigation) - can start after US1 basics complete
   - Developer C: User Story 3 (Delete close) - can start after US1 basics complete
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Tests use sway-test framework (Feature 069) with sync-based actions for <1% flakiness
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Performance targets: <10ms arrow navigation, <100ms Enter navigation, <500ms Delete timeout
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
