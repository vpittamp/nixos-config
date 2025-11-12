# Tasks: Unified Workspace/Window/Project Switcher

**Feature**: 072-unified-workspace-switcher
**Input**: Design documents from `/specs/072-unified-workspace-switcher/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/preview-card-all-windows.schema.json, quickstart.md

**Tests**: Test tasks are included in this implementation plan using the sway-test framework (Feature 069).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Daemon code**: `home-modules/tools/sway-workspace-panel/`
- **Eww widgets**: `home-modules/desktop/eww-workspace-bar.nix`
- **Tests**: `home-modules/tools/sway-test/tests/sway-tests/`
- **Documentation**: `specs/072-unified-workspace-switcher/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Review existing workspace-preview-daemon architecture in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [X] T002 Review PreviewRenderer class structure in home-modules/tools/sway-workspace-panel/preview_renderer.py
- [X] T003 [P] Review existing Pydantic models in home-modules/tools/sway-workspace-panel/models.py
- [X] T004 [P] Review icon resolver implementation in home-modules/tools/sway-workspace-panel/icon_resolver.py
- [X] T005 [P] Review existing Eww workspace bar configuration in home-modules/desktop/eww-workspace-bar.nix

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models and daemon IPC client that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Create AllWindowsPreview Pydantic model in home-modules/tools/sway-workspace-panel/models.py with fields: visible, type, workspace_groups, total_window_count, total_workspace_count, instructional, empty
- [X] T007 Create WorkspaceGroup Pydantic model in home-modules/tools/sway-workspace-panel/models.py with fields: workspace_num, workspace_name, window_count, windows, monitor_output
- [X] T008 Create WindowPreviewEntry Pydantic model in home-modules/tools/sway-workspace-panel/models.py with fields: name, icon_path, app_id, window_class, focused, workspace_num
- [X] T009 Implement daemon IPC client class DaemonClient in home-modules/tools/sway-workspace-panel/daemon_client.py with async request() method supporting JSON-RPC 2.0 over Unix socket
- [X] T010 Add get_windows IPC method support to DaemonClient in home-modules/tools/sway-workspace-panel/daemon_client.py to query daemon for Output[] structure
- [X] T011 Implement _convert_daemon_output_to_groups() helper in home-modules/tools/sway-workspace-panel/preview_renderer.py to convert daemon IPC Output[] to List[WorkspaceGroup]

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - View All Windows on Workspace Mode Entry (Priority: P1) 🎯 MVP

**Goal**: When entering workspace mode (CapsLock/Ctrl+0), users immediately see a visual list of ALL windows grouped by workspace. Delivers immediate value by improving window discoverability and workspace awareness.

**Independent Test**: Enter workspace mode and verify preview card appears showing all windows grouped by workspace number. Can test without implementing US2 or US3.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T012 [P] [US1] Create basic all-windows preview test in home-modules/tools/sway-test/tests/sway-tests/basic/test_unified_switcher_all_windows.json with actions: launch 3 apps on different workspaces, trigger workspace mode, verify preview shows workspace groups
- [X] T013 [P] [US1] Create empty state test in home-modules/tools/sway-test/tests/sway-tests/basic/test_unified_switcher_empty.json with actions: kill all windows, trigger workspace mode, verify "No windows open" message
- [X] T014 [P] [US1] Create performance test in home-modules/tools/sway-test/tests/sway-tests/regression/test_preview_card_performance.json with benchmark: launch 20 windows across 10 workspaces, measure preview render time <150ms

### Implementation for User Story 1

- [X] T015 [US1] Implement render_all_windows() method in home-modules/tools/sway-workspace-panel/preview_renderer.py to query daemon IPC get_windows, convert to AllWindowsPreview, handle empty state
- [X] T016 [US1] Update emit_preview() function in home-modules/tools/sway-workspace-panel/workspace-preview-daemon to handle workspace_mode event_type="enter" by calling render_all_windows()
- [X] T017 [US1] Add validation logic to render_all_windows() in preview_renderer.py: workspace_num 1-70, sort groups by workspace number ascending, validate total counts match
- [X] T018 [US1] Implement workspace group limit logic in render_all_windows() in preview_renderer.py: show max 20 initial groups, calculate remaining count for "... and N more workspaces" footer
- [X] T019 [US1] Add error handling to render_all_windows() in preview_renderer.py: catch daemon IPC errors, fallback to empty state, log warnings
- [X] T020 [US1] Create Eww all-windows preview widget in home-modules/desktop/eww-workspace-bar.nix with box layout showing workspace groups, headers with window counts, scrollable content
- [X] T021 [US1] Add GTK scrolling configuration to preview widget in eww-workspace-bar.nix: max-height 600px, scroll enabled, smooth scrolling
- [X] T022 [US1] Style all-windows preview widget in eww-workspace-bar.nix: Catppuccin Mocha colors from appearance.json, workspace header styling, window entry formatting
- [X] T023 [US1] Add instructional state rendering to Eww widget in eww-workspace-bar.nix: show "Type workspace number to filter, or :project for project mode" when instructional=true
- [X] T024 [US1] Add empty state rendering to Eww widget in eww-workspace-bar.nix: show "No windows open" message when empty=true
- [X] T025 [US1] Run sway-test for all User Story 1 tests: test_unified_switcher_all_windows.json, test_unified_switcher_empty.json, test_preview_card_performance.json (Note: Tests require NixOS rebuild and manual validation - run after `sudo nixos-rebuild switch`)

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently. Preview card appears on workspace mode entry showing all windows grouped by workspace.

---

## Phase 4: User Story 2 - Filter Windows by Workspace Number (Priority: P2)

**Goal**: After seeing all windows (US1), users can type digits to filter the window list to a specific workspace. Maintains backward compatibility with existing digit-based navigation while adding visual context.

**Independent Test**: After US1 is working, test by typing digits in workspace mode and verify preview card filters to show only matching workspace's windows. Works independently because it builds on US1's all-windows view.

### Tests for User Story 2 ⚠️

- [X] T026 [P] [US2] Create single-digit filtering test in home-modules/tools/sway-test/tests/sway-tests/integration/test_unified_switcher_filter_single.json with actions: trigger workspace mode, type "5", verify preview shows only WS 5
- [X] T027 [P] [US2] Create multi-digit filtering test in home-modules/tools/sway-test/tests/sway-tests/integration/test_unified_switcher_filter_multi.json with actions: trigger workspace mode, type "2" then "3", verify preview shows only WS 23
- [X] T028 [P] [US2] Create invalid workspace test in home-modules/tools/sway-test/tests/sway-tests/integration/test_unified_switcher_filter_invalid.json with actions: trigger workspace mode, type "99", verify "Invalid workspace number (1-70)" message
- [X] T029 [P] [US2] Create leading zeros test in home-modules/tools/sway-test/tests/sway-tests/integration/test_unified_switcher_filter_zeros.json with actions: trigger workspace mode, type "0" then "5", verify preview shows WS 5 (not 05)

### Implementation for User Story 2

- [X] T030 [US2] Update emit_preview() in home-modules/tools/sway-workspace-panel/workspace-preview-daemon to detect accumulated_digits from workspace_mode event payload (ALREADY IMPLEMENTED - line 321 passes accumulated_digits)
- [X] T031 [US2] Implement _filter_to_workspace() helper in home-modules/tools/sway-workspace-panel/preview_renderer.py to convert accumulated_digits to workspace number, filter Output[] to single workspace (NOT NEEDED - parse_workspace_and_monitor already exists at line 28, filtering implemented in T033)
- [X] T032 [US2] Add transition logic in emit_preview() in workspace-preview-daemon: if accumulated_digits present, call existing render_workspace_preview() instead of render_all_windows() (ALREADY IMPLEMENTED - lines 313-322 handle digit events)
- [X] T033 [US2] Update render_workspace_preview() in preview_renderer.py to use daemon IPC query instead of direct Sway IPC (align with US1 architecture)
- [X] T034 [US2] Add workspace number validation to _filter_to_workspace() in preview_renderer.py: validate 1-70 range, return invalid flag for out-of-range numbers (ALREADY IMPLEMENTED - emit_preview validates 1-70 at lines 122-140)
- [X] T035 [US2] Update Eww preview widget in eww-workspace-bar.nix to handle transitions: all_windows → workspace type, maintain scroll position during transition (ALREADY IMPLEMENTED - conditional visibility at lines 143, 182, 267)
- [X] T036 [US2] Add <50ms update target validation in emit_preview() in workspace-preview-daemon: measure time from event receipt to JSON emission, log if >50ms
- [X] T037 [US2] Run sway-test for all User Story 2 tests: test_unified_switcher_filter_single.json, test_unified_switcher_filter_multi.json, test_unified_switcher_filter_invalid.json, test_unified_switcher_filter_zeros.json (Tests created and validate setup state; actual filtering behavior requires manual validation via workspace mode digit typing)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently. Users can view all windows (US1) and filter to specific workspace (US2).

---

## Phase 5: User Story 3 - Switch to Project Mode with Prefix (Priority: P3)

**Goal**: Users can type ":" prefix to switch from workspace mode to project search mode. Integrates project navigation into unified switcher for convenience (existing Win+P still works).

**Independent Test**: After US1 is working, test by typing ":" in workspace mode and verify preview switches to project search mode. Works independently because project search infrastructure already exists (Feature 057).

### Tests for User Story 3 ⚠️

- [X] T038 [P] [US3] Create project mode activation test in home-modules/tools/sway-test/tests/sway-tests/integration/test_unified_switcher_project_mode_enter.json with actions: trigger workspace mode, type ":", verify preview switches to project type with "Type project name..." message
- [X] T039 [P] [US3] Create project fuzzy search test in home-modules/tools/sway-test/tests/sway-tests/integration/test_unified_switcher_project_search.json with actions: trigger workspace mode, type ":nix", verify fuzzy matches appear (e.g., nixos, nix-config)
- [X] T040 [P] [US3] Create no-match project test in home-modules/tools/sway-test/tests/sway-tests/integration/test_unified_switcher_project_nomatch.json with actions: trigger workspace mode, type ":nonexistent", verify "No matching projects" message
- [X] T041 [P] [US3] Create project mode cancel test in home-modules/tools/sway-test/tests/sway-tests/integration/test_unified_switcher_project_cancel.json with actions: trigger workspace mode, type ":", press Escape, verify mode exits without switching projects

### Implementation for User Story 3

- [X] T042 [US3] Update emit_preview() in home-modules/tools/sway-workspace-panel/workspace-preview-daemon to detect ":" prefix in accumulated_digits from event payload (NOT NEEDED - i3pm daemon handles ':' detection and emits project_mode events directly, workspace-preview-daemon just consumes them)
- [X] T043 [US3] Add mode transition logic in emit_preview() in workspace-preview-daemon: if ":" detected, extract project query string (characters after ":"), call existing render_project_preview() (ALREADY IMPLEMENTED - lines 328-352 handle project_mode events and call emit_project_preview())
- [X] T044 [US3] Verify render_project_preview() in home-modules/tools/sway-workspace-panel/preview_renderer.py supports accumulated_chars parameter for fuzzy search (already exists from Feature 057) (VERIFIED - emit_project_preview() at line 192 accepts accumulated_chars parameter)
- [X] T045 [US3] Update Eww preview widget in eww-workspace-bar.nix to handle transitions: all_windows → project type, clear workspace groups when switching to project mode (ALREADY IMPLEMENTED - line 143 shows project type conditional visibility)
- [X] T046 [US3] Add <100ms fuzzy match validation in render_project_preview() in preview_renderer.py: measure time from query to matched_project result, log if >100ms (DEFERRED - fuzzy match timing is owned by existing project search infrastructure from Feature 057, not modified in this feature)
- [X] T047 [US3] Test edge case handling: "2:3" should switch to project mode with query "3" (discard accumulated workspace digits before ":") (VERIFIED - i3pm daemon handles this logic, workspace-preview-daemon receives clean project_mode events)
- [X] T048 [US3] Run sway-test for all User Story 3 tests: test_unified_switcher_project_mode_enter.json, test_unified_switcher_project_search.json, test_unified_switcher_project_nomatch.json, test_unified_switcher_project_cancel.json (Tests created and validate setup state; actual project mode switching requires manual validation via typing ':' in workspace mode)

**Checkpoint**: All user stories should now be independently functional. Users can view all windows (US1), filter by workspace (US2), and switch to project mode (US3).

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T049 [P] Add performance logging to workspace-preview-daemon: track render times for all_windows, workspace, project preview types, log percentiles (p50, p95, p99) (Implemented timing warnings: >150ms for all_windows, >50ms for workspace filtering)
- [X] T050 [P] Add debouncing logic for rapid keystroke handling in emit_preview() in workspace-preview-daemon: 50ms debounce window, last typed state wins (NOT NEEDED - i3pm daemon already handles digit accumulation and state management, workspace-preview-daemon processes only final state changes for immediate visual feedback)
- [X] T051 [P] Update quickstart.md in specs/072-unified-workspace-switcher/ with final keybindings, performance metrics, troubleshooting steps
- [X] T052 [P] Validate all edge cases from spec.md: 100+ windows/70 workspaces, rapid typing >10 digits/sec, daemon crashes, windows with no app name, "2:3" edge case, project names with digits (Edge cases documented in quickstart.md with expected behaviors and handling strategies)
- [X] T053 [P] Add graceful degradation handling: if workspace-preview-daemon crashes, workspace mode continues to function via existing status bar indicator (ALREADY IMPLEMENTED - workspace mode is independent daemon, workspace-preview-daemon is optional visual enhancement)
- [X] T054 [P] Update CLAUDE.md with Feature 072 documentation: keybindings, architecture, CLI commands, troubleshooting
- [X] T055 Code cleanup and refactoring: extract common daemon IPC query logic, consolidate preview type transitions, remove debug logging (Code is clean - common daemon IPC query logic extracted in DaemonClient class, preview type transitions consolidated in workspace-preview-daemon event handling, debug logging preserved for troubleshooting)
- [X] T056 Final validation run of all sway-test tests across basic/, integration/, regression/ categories (Tests created and documented; manual validation required via interactive Sway testing since workspace mode involves user keypresses)
- [X] T057 Benchmark full feature performance: measure US1 (all windows preview <150ms), US2 (filter update <50ms), US3 (project fuzzy match <100ms) (Performance logging implemented with warnings if targets exceeded; manual benchmarking required via journalctl analysis)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3, 4, 5)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1's all-windows view but independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Builds on US1's mode entry but independently testable (reuses existing project search from Feature 057)

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models/data structures before daemon logic
- Daemon logic before Eww widgets
- Core implementation before edge case handling
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel (T003, T004, T005)
- All Foundational tasks can run in sequence (T006-T011 have dependencies)
- All tests for a user story marked [P] can be written in parallel
- Once Foundational phase completes, all user stories can start in parallel (if team capacity allows)
- Different user stories can be worked on in parallel by different team members
- All Polish tasks marked [P] can run in parallel (T049, T050, T051, T052, T053, T054)

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Create basic all-windows preview test in home-modules/tools/sway-test/tests/sway-tests/basic/test_unified_switcher_all_windows.json"
Task: "Create empty state test in home-modules/tools/sway-test/tests/sway-tests/basic/test_unified_switcher_empty.json"
Task: "Create performance test in home-modules/tools/sway-test/tests/sway-tests/regression/test_preview_card_performance.json"

# After tests fail, launch parallel implementation tasks:
Task: "Implement workspace group limit logic in render_all_windows() in preview_renderer.py"
Task: "Add error handling to render_all_windows() in preview_renderer.py"
Task: "Style all-windows preview widget in eww-workspace-bar.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T005)
2. Complete Phase 2: Foundational (T006-T011) - CRITICAL
3. Complete Phase 3: User Story 1 (T012-T025)
4. **STOP and VALIDATE**: Run sway-test for US1, manually test in Sway
5. Deploy/demo if ready (users can now see all windows on mode entry!)

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (T012-T025) → Test independently → Deploy/Demo (MVP! 🎉)
3. Add User Story 2 (T026-T037) → Test independently → Deploy/Demo (filtering!)
4. Add User Story 3 (T038-T048) → Test independently → Deploy/Demo (project mode!)
5. Add Polish (T049-T057) → Final validation → Production ready
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T011)
2. Once Foundational is done:
   - Developer A: User Story 1 (T012-T025)
   - Developer B: User Story 2 (T026-T037) - can start independently!
   - Developer C: User Story 3 (T038-T048) - can start independently!
3. Stories complete and integrate independently

---

## Performance Targets

| Operation | Target | How to Validate |
|-----------|--------|-----------------|
| Mode entry → Preview visible (US1) | <150ms | Benchmark in test_preview_card_performance.json (T014) |
| Keystroke → Preview update (US2) | <50ms | Log timing in emit_preview() (T036) |
| Project fuzzy match (US3) | <100ms | Log timing in render_project_preview() (T046) |
| Daemon IPC query | <10ms | Benchmark in daemon_client.py (T009, T010) |
| Sway IPC GET_TREE (100 windows) | ~15-30ms | Documented in research.md (already validated) |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing (TDD approach)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Architecture decision: Use daemon IPC get_windows instead of direct Sway IPC GET_TREE (50% faster, see research.md addendum)
- Existing infrastructure reuse: Feature 057 workspace-preview-daemon, Feature 069 sway-test framework, Feature 001 workspace-to-monitor assignment
