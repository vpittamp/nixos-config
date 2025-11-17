# Tasks: Preview Pane User Experience

**Input**: Design documents from `/specs/079-preview-pane-user-experience/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are included for critical user stories per Constitution Principle XIV (Test-Driven Development).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- **Python Daemon**: `home-modules/desktop/i3-project-event-daemon/`
- **Eww Widgets**: `home-modules/desktop/eww-workspace-bar.nix`, `home-modules/desktop/eww-top-bar/`
- **Deno CLI**: `home-modules/tools/i3pm/src/`
- **Preview Daemon**: `home-modules/tools/sway-workspace-panel/workspace-preview-daemon`
- **Tests**: `tests/079-preview-pane-user-experience/`
- **Sway Config**: `home-modules/desktop/sway.nix`

---

## Phase 1: Setup

**Purpose**: Project initialization and test infrastructure

- [x] T001 Create test directory structure at tests/079-preview-pane-user-experience/
- [x] T002 [P] Create pytest configuration for Feature 079 tests in tests/079-preview-pane-user-experience/conftest.py
- [x] T003 [P] Create mock fixtures for FilterState and ProjectListItem in tests/079-preview-pane-user-experience/fixtures/mock_models.py

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core model enhancements that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Add branch_number field to ProjectListItem in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T005 [P] Add branch_type field to ProjectListItem in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T006 [P] Add full_branch_name field to ProjectListItem in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T007 Add Pydantic validator for branch_number extraction (regex ^(\d+)-) in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T008 Add Pydantic validator for branch_type classification in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T009 Add formatted_display_name() method to ProjectListItem in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T010 Update project_filter_service.py to populate new ProjectListItem fields in home-modules/desktop/i3-project-event-daemon/project_filter_service.py
- [x] T011 Add GitStatus model to home-modules/desktop/i3-project-event-daemon/models/project_filter.py

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Arrow Key Navigation (Priority: P1) 🎯 MVP

**Goal**: Enable users to navigate project list with Up/Down arrow keys

**Independent Test**: Enter project mode, press Down arrow, verify selection moves to next item with visual highlight update

### Tests for User Story 1

- [x] T012 [P] [US1] Unit test for NavigationHandler.handle_arrow_key_event() with project_list mode in tests/079-preview-pane-user-experience/test_arrow_navigation.py
- [x] T013 [P] [US1] Unit test for FilterState.navigate_down() circular wrapping in tests/079-preview-pane-user-experience/test_arrow_navigation.py
- [x] T014 [P] [US1] Unit test for FilterState.navigate_up() circular wrapping in tests/079-preview-pane-user-experience/test_arrow_navigation.py

### Implementation for User Story 1

- [x] T015 [US1] Add _project_filter_state property to NavigationHandler in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [x] T016 [US1] Add _last_project_preview_data property to NavigationHandler in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [x] T017 [US1] Modify NavigationHandler.handle_arrow_key_event() to check mode and route to project list navigation in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [x] T018 [US1] Add _emit_project_list_with_selection() method to NavigationHandler in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [x] T019 [US1] Update project_mode event handler to cache FilterState in NavigationHandler in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [x] T020 [US1] Verify arrow key events include mode parameter for routing in home-modules/tools/sway-workspace-panel/workspace-preview-daemon

**Checkpoint**: Arrow key navigation should now work in project selection mode (independently testable)

---

## Phase 4: User Story 2 - Backspace Exit (Priority: P1)

**Goal**: Exit project selection mode when backspace removes ":"

**Independent Test**: Enter project mode, press backspace to remove ":", verify return to workspace mode

### Tests for User Story 2

- [x] T021 [P] [US2] Unit test for backspace() detecting empty filter in tests/079-preview-pane-user-experience/test_backspace_exit.py
- [x] T022 [P] [US2] Unit test for exit_mode flag in event payload in tests/079-preview-pane-user-experience/test_backspace_exit.py

### Implementation for User Story 2

- [x] T023 [US2] Add exit_mode field to project_mode.backspace event payload in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [x] T024 [US2] Modify backspace() to check if accumulated_chars is empty after deletion in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [x] T025 [US2] Add transition to workspace_preview mode when filter becomes empty in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [x] T026 [US2] Handle exit_mode flag in workspace-preview-daemon to hide project list in home-modules/tools/sway-workspace-panel/workspace-preview-daemon

**Checkpoint**: Backspace now exits project mode when ":" is removed (independently testable)

---

## Phase 5: User Story 3 - Numeric Prefix Filtering (Priority: P1)

**Goal**: Filter projects by typing branch number prefix (e.g., ":79" finds "079-*")

**Independent Test**: Type ":79", verify "079-preview-pane-user-experience" is highlighted as top match

### Tests for User Story 3

- [x] T027 [P] [US3] Unit test for numeric-only filter matching branch_number in tests/079-preview-pane-user-experience/test_numeric_prefix_filter.py
- [x] T028 [P] [US3] Unit test for exact prefix scoring (1000 points) in tests/079-preview-pane-user-experience/test_numeric_prefix_filter.py
- [x] T029 [P] [US3] Unit test for partial numeric match scoring in tests/079-preview-pane-user-experience/test_numeric_prefix_filter.py

### Implementation for User Story 3

- [x] T030 [US3] Add filter_by_prefix() method to FilterState in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T031 [US3] Modify _compute_match_score() to prioritize branch_number matches in home-modules/desktop/i3-project-event-daemon/project_filter_service.py
- [x] T032 [US3] Add detection for numeric-only filter input in home-modules/desktop/i3-project-event-daemon/project_filter_service.py
- [x] T033 [US3] Update match scoring to give 1000 points for exact branch_number prefix in home-modules/desktop/i3-project-event-daemon/project_filter_service.py

**Checkpoint**: Numeric prefix filtering now works (independently testable)

---

## Phase 6: User Story 4 - Branch Number Display (Priority: P2)

**Goal**: Display branch number prefix in project list entries

**Independent Test**: View project list, verify entries show "079 - Preview Pane UX" format

### Implementation for User Story 4

- [x] T034 [P] [US4] Update Eww project list widget to include branch_number in display in home-modules/desktop/eww-workspace-bar.nix
- [x] T035 [P] [US4] Add formatted label rendering "{branch_number} - {display_name}" in home-modules/desktop/eww-workspace-bar.nix
- [x] T036 [US4] Handle missing branch_number gracefully (show display_name only) in home-modules/desktop/eww-workspace-bar.nix

**Checkpoint**: Branch numbers now display in project list (independently testable)

---

## Phase 7: User Story 5 - Worktree Hierarchy (Priority: P2)

**Goal**: Display worktrees grouped under parent projects

**Independent Test**: View project list with worktrees, verify visual nesting under parent

### Tests for User Story 5

- [x] T037 [P] [US5] Unit test for FilterState.group_by_parent() method in tests/079-preview-pane-user-experience/test_worktree_hierarchy.py
- [x] T038 [P] [US5] Unit test for indentation_level calculation in tests/079-preview-pane-user-experience/test_worktree_hierarchy.py

### Implementation for User Story 5

- [x] T039 [US5] Add group_by_parent() method to FilterState in home-modules/desktop/i3-project-event-daemon/models/project_filter.py
- [x] T040 [US5] Add hierarchy structure to Eww variable schema in home-modules/tools/sway-workspace-panel/workspace-preview-daemon
- [x] T041 [P] [US5] Update Eww widget to render hierarchical project list in home-modules/desktop/eww-workspace-bar.nix
- [x] T042 [P] [US5] Add indentation CSS for worktree children in home-modules/desktop/eww-workspace-bar.nix
- [x] T043 [US5] Add folder icon for root projects and branch icon for worktrees in home-modules/desktop/eww-workspace-bar.nix

**Checkpoint**: Worktree hierarchy now displays correctly (independently testable)

---

## Phase 8: User Story 6 - Worktree List Command (Priority: P2)

**Goal**: Implement `i3pm worktree list` CLI command

**Independent Test**: Run `i3pm worktree list`, verify JSON output with branch, path, parent_repo, git_status

### Tests for User Story 6

- [x] T044 [P] [US6] Unit test for worktree list JSON output schema in tests/079-preview-pane-user-experience/test_worktree_list_command.ts

### Implementation for User Story 6

- [x] T045 [US6] Add WorktreeItemSchema with Zod validation in home-modules/tools/i3pm/src/models/worktree.ts
- [x] T046 [US6] Implement worktree list command to read all project JSON files in home-modules/tools/i3pm/src/commands/worktree.ts
- [x] T047 [US6] Filter for is_worktree === true in list command in home-modules/tools/i3pm/src/commands/worktree.ts
- [x] T048 [US6] Extract git metadata via worktree-metadata.ts service in home-modules/tools/i3pm/src/commands/worktree.ts
- [x] T049 [US6] Format output as JSON array with branch, path, parent_repo, git_status in home-modules/tools/i3pm/src/commands/worktree.ts

**Checkpoint**: Worktree list command now works (independently testable)

---

## Phase 9: User Story 7 - Top Bar Enhancement (Priority: P2)

**Goal**: Display project icon and branch number in top bar with accent styling

**Independent Test**: Switch projects, verify top bar shows icon + "079 - Preview Pane UX" with accent background

### Implementation for User Story 7

- [x] T050 [P] [US7] Add TopBarProjectData model fields (branch_number, icon, is_worktree) in home-modules/desktop/eww-top-bar/scripts/active-project.py
- [x] T051 [P] [US7] Modify active-project.py to extract branch_number from project JSON in home-modules/desktop/eww-top-bar/scripts/active-project.py
- [x] T052 [US7] Update Eww top bar widget to include icon in project label in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T053 [US7] Add formatted_label display "{icon} {branch_number} - {display_name}" in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T054 [US7] Add accent color background CSS for project label in home-modules/desktop/eww-top-bar/eww.scss
- [x] T055 [US7] Apply Catppuccin Mocha peach (#fab387) styling in home-modules/desktop/eww-top-bar/eww.scss

**Checkpoint**: Top bar now shows enhanced project label (independently testable)

---

## Phase 10: User Story 8 - Environment Variables (Priority: P3)

**Goal**: Inject worktree metadata as environment variables

**Independent Test**: Launch app in worktree context, verify I3PM_IS_WORKTREE, I3PM_PARENT_PROJECT, I3PM_BRANCH_TYPE in process env

### Tests for User Story 8

- [x] T056 [P] [US8] Unit test for WorktreeEnvironment.to_env_dict() in tests/079-preview-pane-user-experience/test_environment_injection.py
- [x] T057 [P] [US8] Unit test for boolean to string conversion ("true"/"false") in tests/079-preview-pane-user-experience/test_environment_injection.py

### Implementation for User Story 8

- [x] T058 [US8] Create WorktreeEnvironment model in home-modules/desktop/i3-project-event-daemon/models/worktree_environment.py
- [x] T059 [US8] Add to_env_dict() method returning all env variables in home-modules/desktop/i3-project-event-daemon/models/worktree_environment.py
- [x] T060 [US8] Modify _prepare_launch_environment() to inject I3PM_IS_WORKTREE in home-modules/desktop/i3-project-event-daemon/services/app_launcher.py
- [x] T061 [US8] Inject I3PM_PARENT_PROJECT environment variable in home-modules/desktop/i3-project-event-daemon/services/app_launcher.py
- [x] T062 [US8] Inject I3PM_BRANCH_TYPE environment variable in home-modules/desktop/i3-project-event-daemon/services/app_launcher.py

**Checkpoint**: Environment variables now include worktree metadata (independently testable)

---

## Phase 11: User Story 9 - Notification Click (Priority: P3)

**Goal**: Click notification to navigate to source tmux window

**Independent Test**: Trigger Claude Code notification, click "Return to Window", verify focus shifts to correct tmux window

### Tests for User Story 9

- [x] T063 [P] [US9] Unit test for NotificationContext.window_identifier() in tests/079-preview-pane-user-experience/test_notification_click.py
- [x] T064 [P] [US9] Unit test for to_notify_send_args() with action flags in tests/079-preview-pane-user-experience/test_notification_click.py

### Implementation for User Story 9

- [x] T065 [US9] Extract tmux session and window in stop-notification.sh in scripts/claude-hooks/stop-notification.sh
- [x] T066 [US9] Pass TMUX_SESSION and TMUX_WINDOW to handler script in scripts/claude-hooks/stop-notification.sh
- [x] T067 [US9] Add notify-send action buttons ("Return to Window", "Dismiss") in scripts/claude-hooks/stop-notification-handler.sh
- [x] T068 [US9] Implement response handling for "focus" action in scripts/claude-hooks/stop-notification-handler.sh
- [x] T069 [US9] Add tmux select-window command with session:window in scripts/claude-hooks/stop-notification-handler.sh
- [x] T070 [US9] Add error handling for non-existent tmux session in scripts/claude-hooks/stop-notification-handler.sh

**Checkpoint**: Notification click navigation now works (independently testable)

---

## Phase 12: User Story 10 - Space Handling (Priority: P3)

**Goal**: Ensure spaces in filter input match hyphenated branch names

**Independent Test**: Type ":preview pane", verify matches "079-preview-pane-user-experience"

### Implementation for User Story 10

- [x] T071 [US10] Add space-to-word-boundary normalization in filter matching in home-modules/desktop/i3-project-event-daemon/project_filter_service.py
- [x] T072 [US10] Treat space as equivalent to hyphen for fuzzy matching in home-modules/desktop/i3-project-event-daemon/project_filter_service.py
- [x] T073 [US10] Update _compute_match_score() to normalize spaces in query in home-modules/desktop/i3-project-event-daemon/project_filter_service.py

**Checkpoint**: Space handling now works seamlessly (independently testable)

---

## Phase 13: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and cleanup

- [x] T074 [P] Update CLAUDE.md with Feature 079 quickstart commands
- [x] T075 [P] Add Feature 079 to Recent Changes section in CLAUDE.md
- [x] T076 Run nixos-rebuild dry-build to validate configuration
- [x] T077 Run all pytest tests for Feature 079
- [x] T078 Validate quickstart.md manual testing checklist
- [x] T079 Clean up any TODO comments in implementation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-12)**: All depend on Foundational phase completion
  - User stories can proceed in parallel (if staffed) or sequentially by priority
- **Polish (Phase 13)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Arrow Navigation - No dependencies on other stories
- **User Story 2 (P1)**: Backspace Exit - No dependencies on other stories
- **User Story 3 (P1)**: Numeric Filtering - Depends on foundational branch_number field
- **User Story 4 (P2)**: Branch Display - Depends on foundational branch_number field
- **User Story 5 (P2)**: Worktree Hierarchy - Depends on foundational is_worktree field
- **User Story 6 (P2)**: CLI Command - Independent, uses existing project JSONs
- **User Story 7 (P2)**: Top Bar - Depends on foundational branch_number field
- **User Story 8 (P3)**: Environment Vars - Independent, extends existing injection
- **User Story 9 (P3)**: Notification Click - Independent, enhances existing hooks
- **User Story 10 (P3)**: Space Handling - Builds on User Story 3 filtering logic

### Within Each User Story

- Tests MUST be written and FAIL before implementation (per Constitution Principle XIV)
- Models/schemas before services
- Services before UI components
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

**Within Phase 2 (Foundational)**:
- T005, T006 can run in parallel (different fields)
- T004 must complete before T007, T008, T009

**Within Each User Story**:
- Test tasks marked [P] can run in parallel
- Model tasks marked [P] can run in parallel
- Different user stories can be worked on in parallel

**Cross-Story Parallelism**:
- US1 (Arrow Navigation) and US2 (Backspace Exit) are completely independent
- US4 (Display) and US7 (Top Bar) both need branch_number but touch different files
- US8 (Env Vars) and US9 (Notifications) are completely independent

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Unit test for NavigationHandler.handle_arrow_key_event() with project_list mode in tests/079-preview-pane-user-experience/test_arrow_navigation.py"
Task: "Unit test for FilterState.navigate_down() circular wrapping in tests/079-preview-pane-user-experience/test_arrow_navigation.py"
Task: "Unit test for FilterState.navigate_up() circular wrapping in tests/079-preview-pane-user-experience/test_arrow_navigation.py"
```

---

## Parallel Example: Foundational Phase

```bash
# Launch parallel model enhancements:
Task: "Add branch_type field to ProjectListItem in home-modules/desktop/i3-project-event-daemon/models/project_filter.py"
Task: "Add full_branch_name field to ProjectListItem in home-modules/desktop/i3-project-event-daemon/models/project_filter.py"
Task: "Add GitStatus model to home-modules/desktop/i3-project-event-daemon/models/project_filter.py"
```

---

## Implementation Strategy

### MVP First (User Stories 1-3 Only)

1. Complete Phase 1: Setup (3 tasks)
2. Complete Phase 2: Foundational (8 tasks) - **CRITICAL - blocks all stories**
3. Complete Phase 3: User Story 1 - Arrow Navigation (9 tasks)
4. **STOP and VALIDATE**: Test arrow key navigation independently
5. Complete Phase 4: User Story 2 - Backspace Exit (6 tasks)
6. Complete Phase 5: User Story 3 - Numeric Filtering (7 tasks)
7. **MVP COMPLETE**: Core P1 functionality ready for use

### Incremental Delivery

1. Setup + Foundational → Foundation ready (11 tasks)
2. Add US1 → Arrow keys work → Deploy/Demo (9 tasks)
3. Add US2 → Backspace exits → Deploy/Demo (6 tasks)
4. Add US3 → Numeric filter → Deploy/Demo (7 tasks)
5. Add US4-7 → Visual enhancements → Deploy/Demo (P2 stories)
6. Add US8-10 → Advanced features → Deploy/Demo (P3 stories)

### Parallel Team Strategy

With multiple developers after Foundational phase:

- Developer A: US1 (Arrow Navigation) + US2 (Backspace Exit)
- Developer B: US3 (Numeric Filtering) + US4 (Branch Display)
- Developer C: US6 (CLI Command) + US7 (Top Bar)

Stories complete and integrate independently, minimal conflicts.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Verify tests fail before implementing (TDD per Constitution)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- **Priority**: P1 stories are critical UX fixes, P2 are visual enhancements, P3 are future-proofing
