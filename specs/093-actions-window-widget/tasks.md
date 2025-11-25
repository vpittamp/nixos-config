# Tasks: Interactive Monitoring Widget Actions

**Input**: Design documents from `/specs/093-actions-window-widget/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md

**Tests**: This feature uses sway-test framework for end-to-end validation per Principle XIV & XV. Test tasks are included and should be written FIRST before implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Nix modules**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Test files**: `tests/093-actions-window-widget/*.json`
- **Spec documentation**: `specs/093-actions-window-widget/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create supporting documentation and verify existing infrastructure

- [ ] T001 Create data-model.md in specs/093-actions-window-widget/ documenting WindowMetadata, ClickAction, and EwwClickState entities
- [ ] T002 Create quickstart.md in specs/093-actions-window-widget/ with user guide for click interactions
- [ ] T003 [P] Create contracts/ directory in specs/093-actions-window-widget/ with bash script interface specifications
- [ ] T004 [P] Create contracts/focus-window-action.sh.md in specs/093-actions-window-widget/contracts/ documenting input/output contract
- [ ] T005 [P] Create contracts/switch-project-action.sh.md in specs/093-actions-window-widget/contracts/ documenting input/output contract
- [ ] T006 [P] Create contracts/eww-click-events.schema.json in specs/093-actions-window-widget/contracts/ with Eww variable state schema
- [ ] T007 Verify existing monitoring panel infrastructure is functional (systemctl --user status eww-monitoring-panel)
- [ ] T008 Create test directory tests/093-actions-window-widget/ for sway-test JSON definitions

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core bash scripts and Eww variable infrastructure that MUST be complete before ANY user story UI can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T009 Implement focusWindowScript bash wrapper in home-modules/desktop/eww-monitoring-panel.nix using pkgs.writeShellScriptBin pattern
- [ ] T010 Add lock file mechanism to focusWindowScript for debouncing in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T011 Add project comparison logic to focusWindowScript (i3pm project current --json | jq) in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T012 Add conditional project switch (if different project) to focusWindowScript in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T013 Add swaymsg focus command execution to focusWindowScript in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T014 Add SwayNC notification on success to focusWindowScript in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T015 Add SwayNC notification on error to focusWindowScript in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T016 [P] Implement switchProjectScript bash wrapper in home-modules/desktop/eww-monitoring-panel.nix using pkgs.writeShellScriptBin pattern
- [ ] T017 [P] Add lock file mechanism to switchProjectScript for debouncing in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T018 [P] Add current project check to switchProjectScript in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T019 [P] Add i3pm project switch execution to switchProjectScript in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T020 [P] Add SwayNC notifications (success/error) to switchProjectScript in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T021 Add Eww defvar declarations for clicked_window_id (initial: 0) in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T022 Add Eww defvar declarations for clicked_project (initial: "") in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T023 Add Eww defvar declarations for click_in_progress (initial: false) in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: Foundation ready - bash scripts available, Eww variables initialized, user story implementation can now begin

---

## Phase 3: User Story 1 - Click Window to Focus (Priority: P1) 🎯 MVP

**Goal**: Users can click any window in the monitoring panel to immediately focus it, with automatic project switching if needed

**Independent Test**: Open multiple windows across different projects, open monitoring panel (Mod+M), click on a window not currently focused, verify Sway switches to window's workspace/project and focuses it

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T024 [P] [US1] Create test_window_focus_same_project.json in tests/093-actions-window-widget/ with sway-test definition for same-project window click
- [ ] T025 [P] [US1] Create test_window_focus_cross_project.json in tests/093-actions-window-widget/ with sway-test definition for cross-project window click
- [ ] T026 [P] [US1] Create test_window_focus_different_workspace.json in tests/093-actions-window-widget/ for same-project different-workspace click
- [ ] T027 [P] [US1] Create test_window_focus_scratchpad.json in tests/093-actions-window-widget/ for hidden/scratchpad window restoration
- [ ] T028 [P] [US1] Run sway-test validate on all US1 test files to verify JSON schema correctness

### Implementation for User Story 1

- [ ] T029 [US1] Add CSS hover states for .window-row class in home-modules/desktop/eww-monitoring-panel.nix (background rgba opacity 40% → 50%, 150ms transition)
- [ ] T030 [US1] Add CSS .window-row.clicked class in home-modules/desktop/eww-monitoring-panel.nix (blue background rgba 30%, box-shadow glow)
- [ ] T031 [US1] Wrap window row widget with (eventbox) in monitoringPanelYuck definition in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T032 [US1] Add :cursor "pointer" attribute to window row eventbox in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T033 [US1] Add :onclick handler to window row calling focus-window-action with window.project_name and window.id in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T034 [US1] Add dynamic CSS class binding for .clicked state using clicked_window_id == window.id in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T035 [US1] Add auto-reset mechanism for clicked_window_id after 2s using inline shell script in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T036 [US1] Test all US1 scenarios: Run sway-test run tests/093-actions-window-widget/test_window_focus_*.json
- [ ] T037 [US1] Verify performance: Window focus same-project completes <300ms, cross-project <500ms

**Checkpoint**: At this point, User Story 1 should be fully functional - clicking windows focuses them with automatic project switching

---

## Phase 4: User Story 2 - Click Project to Switch Context (Priority: P2)

**Goal**: Users can click on project name/header in monitoring panel to switch entire project context

**Independent Test**: Create multiple projects with scoped windows, open monitoring panel, click on different project name, verify i3pm switches context (hides old scoped windows, shows new scoped windows)

### Tests for User Story 2

- [ ] T038 [P] [US2] Create test_project_switch_click.json in tests/093-actions-window-widget/ with sway-test definition for project header click
- [ ] T039 [P] [US2] Create test_project_switch_already_current.json in tests/093-actions-window-widget/ for clicking already-active project (should do nothing)
- [ ] T040 [P] [US2] Create test_project_switch_global_only.json in tests/093-actions-window-widget/ for project with no scoped windows
- [ ] T041 [P] [US2] Run sway-test validate on all US2 test files

### Implementation for User Story 2

- [ ] T042 [P] [US2] Add CSS hover states for .project-header class in home-modules/desktop/eww-monitoring-panel.nix (background rgba 60% → 80%, border blue, 200ms transition)
- [ ] T043 [P] [US2] Add CSS .project-header.clicked class in home-modules/desktop/eww-monitoring-panel.nix (blue background rgba 30%, box-shadow glow)
- [ ] T044 [US2] Wrap project header widget with (eventbox) in monitoringPanelYuck in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T045 [US2] Add :cursor "pointer" attribute to project header eventbox in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T046 [US2] Add :onclick handler to project header calling switch-project-action with project.name in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T047 [US2] Add dynamic CSS class binding for .clicked state using clicked_project == project.name in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T048 [US2] Add auto-reset mechanism for clicked_project after 2s in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T049 [US2] Test all US2 scenarios: Run sway-test run tests/093-actions-window-widget/test_project_switch_*.json
- [ ] T050 [US2] Verify performance: Project switch click completes <350ms total

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - windows clickable, project headers clickable

---

## Phase 5: User Story 3 - Visual Feedback for Click Actions (Priority: P3)

**Goal**: Users receive immediate visual feedback when clicking windows/projects including hover states, animations, and error notifications

**Independent Test**: Hover over and click windows/projects in monitoring panel, observe CSS hover states, click ripple effects, watch for success/error notifications via SwayNC

### Tests for User Story 3

- [ ] T051 [P] [US3] Create test_hover_visual_feedback.json in tests/093-actions-window-widget/ verifying CSS hover states appear on cursor enter
- [ ] T052 [P] [US3] Create test_click_animation_feedback.json in tests/093-actions-window-widget/ verifying click highlight appears and resets
- [ ] T053 [P] [US3] Create test_error_notification_closed_window.json in tests/093-actions-window-widget/ verifying error notification on window close
- [ ] T054 [P] [US3] Create test_success_notification.json in tests/093-actions-window-widget/ verifying success notification on focus complete
- [ ] T055 [P] [US3] Create test_panel_update_after_action.json in tests/093-actions-window-widget/ verifying deflisten updates panel <100ms
- [ ] T056 [P] [US3] Run sway-test validate on all US3 test files

### Implementation for User Story 3

- [ ] T057 [P] [US3] Add CSS :hover pseudo-class selectors for .window-row in home-modules/desktop/eww-monitoring-panel.nix (box-shadow 0 2px 6px rgba(0,0,0,0.2))
- [ ] T058 [P] [US3] Add CSS :hover pseudo-class selectors for .project-header in home-modules/desktop/eww-monitoring-panel.nix (border-color blue 60%, box-shadow 0 0 8px blue)
- [ ] T059 [US3] Enhance focusWindowScript error notification messages with specific failure reasons in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T060 [US3] Enhance switchProjectScript error notification messages with specific failure reasons in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T061 [US3] Add success notification to focusWindowScript showing target project name in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T062 [US3] Add success notification to switchProjectScript showing target project name in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T063 [US3] Verify deflisten stream updates panel after Sway IPC changes (existing mechanism, verify not broken)
- [ ] T064 [US3] Test all US3 scenarios: Run sway-test run tests/093-actions-window-widget/test_*_feedback.json
- [ ] T065 [US3] Verify visual feedback timing: Hover state <50ms, click highlight visible for 2s, panel updates <100ms

**Checkpoint**: All user stories should now be independently functional with full visual feedback

---

## Phase 6: Edge Cases & Robustness

**Purpose**: Handle edge cases and error scenarios identified in spec.md

- [ ] T066 [P] Create test_rapid_click_debouncing.json in tests/093-actions-window-widget/ verifying lock file prevents duplicate commands
- [ ] T067 [P] Create test_click_during_project_switch.json in tests/093-actions-window-widget/ verifying queue or rejection with notification
- [ ] T068 [P] Create test_floating_window_focus.json in tests/093-actions-window-widget/ verifying floating windows focus without workspace change
- [ ] T069 [P] Run sway-test validate on all edge case test files
- [ ] T070 Add rapid click detection to focusWindowScript with "Previous action still in progress" notification in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T071 Add rapid click detection to switchProjectScript with "Previous action still in progress" notification in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T072 Add exit code checks to focusWindowScript swaymsg command with error notification "Window no longer available" in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T073 Add exit code checks to switchProjectScript i3pm command with error notification "Project switch failed" in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T074 Test all edge case scenarios: Run sway-test run tests/093-actions-window-widget/test_*_debouncing.json and test_*_during_*.json
- [ ] T075 Verify 95% edge case handling success rate per SC-005

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, testing validation, and final polish

- [ ] T076 [P] Update CLAUDE.md with Feature 093 section documenting click interactions (keys: Mod+M to open panel, click to focus)
- [ ] T077 [P] Update CLAUDE.md "Live Window/Project Monitoring Panel" section with click interaction instructions
- [ ] T078 [P] Add troubleshooting section to quickstart.md with common errors and solutions
- [ ] T079 Run dry-build test: sudo nixos-rebuild dry-build --flake .#hetzner-sway to verify Nix builds
- [ ] T080 Run dry-build test: sudo nixos-rebuild dry-build --flake .#m1 --impure to verify M1 builds
- [ ] T081 Run full sway-test suite: sway-test run tests/093-actions-window-widget/ and verify all tests pass
- [ ] T082 Performance validation: Measure and verify all success criteria SC-002 through SC-006
- [ ] T083 Manual testing on Hetzner Cloud (VNC access) to verify remote desktop click functionality
- [ ] T084 Manual testing on M1 (local display) to verify native display click functionality
- [ ] T085 Create Git commit with message following project standards (feature summary + "🤖 Generated with Claude Code")

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3, 4, 5)**: All depend on Foundational phase completion
  - User stories can proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Edge Cases (Phase 6)**: Depends on at least US1 being complete
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - No dependencies on US1 (independently testable)
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Enhances US1 & US2 but independently testable

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- CSS styles before widget modifications
- Widget modifications before onclick handlers
- Core onclick before auto-reset mechanisms
- Implementation before performance validation
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1 (Setup)**: All tasks T003-T006 can run in parallel (different files)
- **Phase 2 (Foundational)**: Tasks T009-T015 (focusWindowScript) can run in parallel with T016-T020 (switchProjectScript)
- **Phase 3 (US1)**: All test creation tasks T024-T027 can run in parallel, all CSS tasks T029-T030 can run in parallel
- **Phase 4 (US2)**: All test creation tasks T038-T040 can run in parallel, CSS tasks T042-T043 can run in parallel
- **Phase 5 (US3)**: All test creation tasks T051-T055 can run in parallel, CSS tasks T057-T058 can run in parallel
- **Phase 6 (Edge Cases)**: All test creation tasks T066-T068 can run in parallel
- **Phase 7 (Polish)**: Documentation tasks T076-T078 can run in parallel
- **Once Foundational completes**: All three user stories (Phases 3, 4, 5) can start in parallel if team capacity allows

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Create test_window_focus_same_project.json in tests/093-actions-window-widget/"
Task: "Create test_window_focus_cross_project.json in tests/093-actions-window-widget/"
Task: "Create test_window_focus_different_workspace.json in tests/093-actions-window-widget/"
Task: "Create test_window_focus_scratchpad.json in tests/093-actions-window-widget/"

# Launch CSS tasks together (different class definitions):
Task: "Add CSS hover states for .window-row class in home-modules/desktop/eww-monitoring-panel.nix"
Task: "Add CSS .window-row.clicked class in home-modules/desktop/eww-monitoring-panel.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (documentation)
2. Complete Phase 2: Foundational (bash scripts, Eww variables) - CRITICAL
3. Complete Phase 3: User Story 1 (window focus click)
4. **STOP and VALIDATE**: Test User Story 1 independently with sway-test
5. Deploy/demo window click functionality

**Rationale**: User Story 1 delivers the core value - clickable windows with automatic project switching. This can be demoed immediately.

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP - window clicks work!)
3. Add User Story 2 → Test independently → Deploy/Demo (project headers now clickable too!)
4. Add User Story 3 → Test independently → Deploy/Demo (full visual feedback!)
5. Add Edge Cases → Deploy/Demo (production-ready robustness)
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (window focus clicks)
   - Developer B: User Story 2 (project header clicks)
   - Developer C: User Story 3 (visual feedback polish)
3. Stories complete and integrate independently
4. Final integration testing with all three stories enabled

---

## Notes

- [P] tasks = different files or independent CSS classes, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Tests use sway-test framework with declarative JSON definitions (Principle XV)
- Tests use partial mode state comparison (focusedWorkspace, windowCount, workspace structure)
- Verify tests fail before implementing
- Commit after completing each user story phase
- Stop at any checkpoint to validate story independently
- All file paths are in home-modules/desktop/eww-monitoring-panel.nix (single Nix module)
- Bash scripts use pkgs.writeShellScriptBin pattern for declarative configuration
- CSS uses Catppuccin Mocha color palette (surface0, surface1, blue, overlay0)
- Performance targets: <300ms same-project, <500ms cross-project, <50ms hover, <100ms panel refresh

## Test-Driven Development Workflow

For each user story:

1. **Write tests first** (T024-T028 for US1, T038-T041 for US2, etc.)
2. **Run tests and verify they FAIL** (sway-test run should show failures)
3. **Implement feature** (T029-T035 for US1, T042-T048 for US2, etc.)
4. **Run tests and verify they PASS** (sway-test run should show success)
5. **Validate performance** (T037 for US1, T050 for US2, etc.)
6. **Move to next story**

This ensures each user story is testable, functional, and meets acceptance criteria before proceeding.
