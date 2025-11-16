# Tasks: Enhanced Project Selection in Eww Preview Dialog

**Input**: Design documents from `/specs/078-eww-preview-improvement/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are included per Constitution Principle XIV (Test-Driven Development) and Principle XV (Sway Test Framework Standards).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Python daemon**: `home-modules/desktop/i3-project-event-daemon/`
- **Workspace preview daemon**: `home-modules/tools/sway-workspace-panel/`
- **Eww widget**: `home-modules/desktop/eww-workspace-bar.nix`
- **Tests**: `tests/078-eww-preview-improvement/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and test directory structure

- [x] T001 Create test directory structure at tests/078-eww-preview-improvement/
- [x] T002 [P] Create sway-test directory at tests/078-eww-preview-improvement/sway-tests/
- [x] T003 [P] Create fixtures directory at tests/078-eww-preview-improvement/fixtures/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Add FilterState Pydantic model in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T005 [P] Add ProjectListItem Pydantic model in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T006 [P] Add ScoredMatch Pydantic model in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T007 [P] Add ProjectPreviewData model in home-modules/tools/sway-workspace-panel/models.py
- [x] T008 Add project_list type to workspace_preview_data schema in home-modules/tools/sway-workspace-panel/models.py
- [x] T009 [P] Create mock project fixtures at tests/078-eww-preview-improvement/fixtures/mock_projects.json
- [x] T010 Implement project file loading service in home-modules/desktop/i3-project-event-daemon/project_filter_service.py

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Quick Project Switch via Fuzzy Search (Priority: P1) 🎯 MVP

**Goal**: Enable fast project switching by typing ":" and filtering with fuzzy search

**Independent Test**: Activate workspace mode, type ":" followed by project name characters, verify project switch occurs with <50ms filter response

### Tests for User Story 1

- [x] T011 [P] [US1] Unit test for fuzzy matching algorithm at tests/078-eww-preview-improvement/test_fuzzy_matching.py
- [x] T012 [P] [US1] Unit test for priority scoring (exact > prefix > substring) at tests/078-eww-preview-improvement/test_fuzzy_matching.py
- [x] T013 [P] [US1] Integration test for project list rendering at tests/078-eww-preview-improvement/test_project_list_rendering.py
- [x] T014 [US1] End-to-end test for project switch workflow at tests/078-eww-preview-improvement/test_project_switch_workflow.py

### Implementation for User Story 1

- [x] T015 [US1] Implement fuzzy_match_projects() function in home-modules/desktop/i3-project-event-daemon/project_filter_service.py
- [x] T016 [US1] Add ":" character handling in add_char() method in home-modules/desktop/i3-project-event-daemon/workspace_mode.py (already existed)
- [x] T017 [US1] Implement project list loading on project mode entry in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [x] T018 [US1] Add real-time filter update on character input in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [x] T019 [US1] Implement _emit_project_list_event() for full project list in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [x] T020 [US1] Add project_list event handler in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [x] T021 [US1] Implement emit_project_list_preview() in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [x] T022 [US1] Add project list scroll widget in home-modules/desktop/eww-workspace-bar.nix
- [x] T023 [US1] Add project item template with name and icon in home-modules/desktop/eww-workspace-bar.nix
- [x] T024 [US1] Implement best match highlighting (first item selected) in home-modules/desktop/eww-workspace-bar.nix
- [x] T025 [US1] Add "No matching projects" empty state in home-modules/desktop/eww-workspace-bar.nix
- [x] T026 [US1] Implement execute() for project switch when Enter pressed (already exists in workspace_mode.py)
- [x] T027 [US1] Add backspace handling to remove filter characters (already exists in workspace_mode.py)

**Checkpoint**: ✅ User Story 1 MVP COMPLETE - users can switch projects via fuzzy search with full list display

---

## Phase 4: User Story 2 - Visual Worktree Relationship Display (Priority: P2)

**Goal**: Show root vs worktree distinction and parent relationships

**Independent Test**: View project list, verify worktree badges and parent relationships display correctly for known worktree projects

### Tests for User Story 2

- [ ] T028 [P] [US2] Unit test for worktree detection at tests/078-eww-preview-improvement/test_project_metadata.py
- [ ] T029 [P] [US2] Unit test for parent project resolution at tests/078-eww-preview-improvement/test_project_metadata.py

### Implementation for User Story 2

- [ ] T030 [US2] Add is_worktree computed field in ProjectListItem at home-modules/desktop/i3-project-event-daemon/models.py
- [ ] T031 [US2] Add parent_project_name resolution in project_service.py at home-modules/desktop/i3-project-event-daemon/project_service.py
- [ ] T032 [US2] Map repository_path to parent project name in home-modules/desktop/i3-project-event-daemon/project_service.py
- [ ] T033 [US2] Add worktree badge widget (🌿 worktree) in home-modules/desktop/eww-workspace-bar.nix
- [ ] T034 [US2] Add root badge widget (📁 root) for non-worktree projects in home-modules/desktop/eww-workspace-bar.nix
- [ ] T035 [US2] Add parent relationship label (← ParentName) in home-modules/desktop/eww-workspace-bar.nix
- [ ] T036 [US2] Style worktree indicators with distinct colors in home-modules/desktop/eww-workspace-bar.nix

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - project list shows worktree relationships

---

## Phase 5: User Story 3 - Project Metadata at a Glance (Priority: P3)

**Goal**: Display git status, relative time, and enhanced metadata

**Independent Test**: View project list entries, verify git status indicators and relative time display correctly

### Tests for User Story 3

- [ ] T037 [P] [US3] Unit test for relative time formatting at tests/078-eww-preview-improvement/test_project_metadata.py
- [ ] T038 [P] [US3] Unit test for git status indicator generation at tests/078-eww-preview-improvement/test_project_metadata.py

### Implementation for User Story 3

- [ ] T039 [US3] Implement format_relative_time() in home-modules/desktop/i3-project-event-daemon/project_service.py
- [ ] T040 [US3] Add relative_time field to ProjectListItem in home-modules/desktop/i3-project-event-daemon/models.py
- [ ] T041 [US3] Extract git status from worktree metadata in home-modules/desktop/i3-project-event-daemon/project_service.py
- [ ] T042 [US3] Add git_status field to ProjectListItem in home-modules/desktop/i3-project-event-daemon/models.py
- [ ] T043 [US3] Add git status badges (✓ clean, ✗ dirty) in home-modules/desktop/eww-workspace-bar.nix
- [ ] T044 [US3] Add ahead/behind indicators (↑N, ↓N) in home-modules/desktop/eww-workspace-bar.nix
- [ ] T045 [US3] Add relative time label (2h ago, 3d ago) in home-modules/desktop/eww-workspace-bar.nix
- [ ] T046 [US3] Display display_name prominently in project item in home-modules/desktop/eww-workspace-bar.nix
- [ ] T047 [US3] Add directory_exists validation and warning indicator in home-modules/desktop/i3-project-event-daemon/project_service.py
- [ ] T048 [US3] Show ⚠️ missing badge for invalid directories in home-modules/desktop/eww-workspace-bar.nix

**Checkpoint**: All user stories with metadata should now be independently functional

---

## Phase 6: User Story 4 - Keyboard-Driven Navigation (Priority: P3)

**Goal**: Arrow key navigation through project list with circular wrapping

**Independent Test**: Type ":", use Up/Down arrows to navigate list, verify highlight moves and Enter selects highlighted project

### Tests for User Story 4

- [ ] T049 [P] [US4] Unit test for circular navigation (wrap at bounds) at tests/078-eww-preview-improvement/test_project_list_selection.py
- [ ] T050 [P] [US4] Integration test for arrow key event handling at tests/078-eww-preview-improvement/test_project_list_selection.py

### Implementation for User Story 4

- [ ] T051 [US4] Implement navigate_up() with circular wrapping in FilterState at home-modules/desktop/i3-project-event-daemon/models.py
- [ ] T052 [US4] Implement navigate_down() with circular wrapping in FilterState at home-modules/desktop/i3-project-event-daemon/models.py
- [ ] T053 [US4] Add user_navigated tracking flag in FilterState at home-modules/desktop/i3-project-event-daemon/models.py
- [ ] T054 [US4] Handle Up/Down arrow events in workspace_mode.py at home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [ ] T055 [US4] Emit nav event on arrow key press in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [ ] T056 [US4] Update selected property on all ProjectListItems after navigation in home-modules/desktop/i3-project-event-daemon/models.py
- [ ] T057 [US4] Handle nav event in workspace-preview-daemon at home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [ ] T058 [US4] Apply highlight class to selected project item in home-modules/desktop/eww-workspace-bar.nix
- [ ] T059 [US4] Ensure Enter switches to arrow-selected project (not filter best match) in home-modules/desktop/i3-project-event-daemon/workspace_mode.py

**Checkpoint**: Keyboard navigation fully functional with circular wrapping

---

## Phase 7: User Story 5 - Cancel and Return to Previous Mode (Priority: P4)

**Goal**: Safe exit from project mode via Escape or backspace

**Independent Test**: Enter project mode, type characters, press Escape, verify no project switch and dialog closes

### Tests for User Story 5

- [ ] T060 [P] [US5] Unit test for Escape cancellation at tests/078-eww-preview-improvement/test_project_list_selection.py
- [ ] T061 [P] [US5] Unit test for backspace exit (removing ":") at tests/078-eww-preview-improvement/test_project_list_selection.py

### Implementation for User Story 5

- [ ] T062 [US5] Handle Escape key in project mode in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [ ] T063 [US5] Emit cancel event on Escape in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [ ] T064 [US5] Implement backspace exit (when removing ":" prefix) in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [ ] T065 [US5] Reset FilterState on cancel in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [ ] T066 [US5] Handle cancel event in workspace-preview-daemon at home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [ ] T067 [US5] Return to workspace mode (all_windows view) on cancel at home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [ ] T068 [US5] Validate input characters (ignore invalid chars) in home-modules/desktop/i3-project-event-daemon/workspace_mode.py

**Checkpoint**: All user stories complete - full project selection functionality delivered

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T069 [P] Update CLAUDE.md with Feature 078 quick reference in CLAUDE.md
- [ ] T070 [P] Add keyboard hints for project mode (: prefix, arrows, Enter, Esc) in home-modules/tools/sway-workspace-panel/keyboard_hint_manager.py
- [x] T071 Validate NixOS configuration builds with nixos-rebuild dry-build --flake .#m1 --impure
- [ ] T072 Performance validation: Test filter response <50ms with 100 mock projects
- [ ] T073 Performance validation: Test arrow navigation response <16ms
- [ ] T074 [P] Run quickstart.md validation - test all documented workflows
- [ ] T075 Clean up unused code paths from old single-match project mode

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3 → P4)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Enhances US1 display but independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Enhances US1/US2 display but independently testable
- **User Story 4 (P3)**: Can start after US1 complete - Requires project list to exist for navigation
- **User Story 5 (P4)**: Can start after Foundational (Phase 2) - Error recovery independent of other stories

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models before services
- Services before IPC events
- IPC events before UI widgets
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- Once Foundational phase completes, US1, US2, US3, US5 can start in parallel
- US4 should wait for US1 (needs project list functionality)
- All tests for a user story marked [P] can run in parallel
- Models within a story marked [P] can run in parallel
- Different user stories can be worked on in parallel by different team members

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Unit test for fuzzy matching algorithm at tests/078-eww-preview-improvement/test_fuzzy_matching.py"
Task: "Unit test for priority scoring at tests/078-eww-preview-improvement/test_fuzzy_matching.py"
Task: "Integration test for project list rendering at tests/078-eww-preview-improvement/test_project_list_rendering.py"

# Launch parallel foundational models:
Task: "Add FilterState Pydantic model in home-modules/desktop/i3-project-event-daemon/models.py"
Task: "Add ProjectListItem Pydantic model in home-modules/desktop/i3-project-event-daemon/models.py"
Task: "Add ScoredMatch Pydantic model in home-modules/desktop/i3-project-event-daemon/models.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T010)
3. Complete Phase 3: User Story 1 (T011-T027)
4. **STOP and VALIDATE**: Test project switch via fuzzy search independently
5. Deploy/demo if ready - core functionality delivered

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo (worktree relationships visible)
4. Add User Story 3 → Test independently → Deploy/Demo (rich metadata display)
5. Add User Story 4 → Test independently → Deploy/Demo (arrow navigation)
6. Add User Story 5 → Test independently → Deploy/Demo (error recovery)
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (Phase 1-2)
2. Once Foundational is done:
   - Developer A: User Story 1 (core fuzzy search)
   - Developer B: User Story 2 (worktree badges)
   - Developer C: User Story 3 (metadata display)
   - Developer D: User Story 5 (cancellation)
3. Developer A completes US1 → Developer E starts US4 (arrow navigation)
4. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing (Constitution Principle XIV)
- Use sway-test framework for end-to-end tests (Constitution Principle XV)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Run `nixos-rebuild dry-build` after Eww widget changes (Constitution Principle III)
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
