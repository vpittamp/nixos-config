# Tasks: Bolster Project & Worktree CRUD Operations

**Input**: Design documents from `/specs/096-bolster-project-and/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Tests**: Included per plan.md Constitution Check (Principle XIV: TDD workflow).

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US7)
- Paths are absolute from repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Test infrastructure setup for this feature, including screenshot-based UI validation

- [x] T001 Create test directory structure at `tests/096-bolster-project-and/{unit,integration,sway-tests,screenshots}/`
- [x] T002 [P] Create pytest fixtures for project CRUD testing in `tests/096-bolster-project-and/conftest.py`
- [x] T003 [P] Create screenshot capture helper script using grim in `tests/096-bolster-project-and/scripts/capture-screenshot.sh`
- [x] T004 [P] Create screenshot comparison utility in `tests/096-bolster-project-and/scripts/compare-screenshots.py` (PIL-based diff with threshold)
- [x] T005 [P] Create baseline screenshots directory at `tests/096-bolster-project-and/screenshots/baseline/` with initial captures of monitoring panel states

**Checkpoint**: Test infrastructure ready with screenshot capture capabilities

---

## Phase 2: Foundational Bug Fixes (Blocking Prerequisites)

**Purpose**: Fix root cause bugs identified in research.md that block ALL user stories

**⚠️ CRITICAL**: These two bugs cause ALL CRUD operations to fail. Must be fixed before any user story can work.

### Bug Fix 1: Conflict Detection Logic (research.md Issue 1)

- [x] T006 Unit test for conflict detection logic in `tests/096-bolster-project-and/unit/test_conflict_detection.py` - test should FAIL with current buggy code
- [x] T007 Fix conflict detection in `home-modules/tools/i3_project_manager/services/project_editor.py:162-169` - compare mtime before read vs immediately before write (not after write)
- [x] T008 Verify T006 test now PASSES after fix

### Bug Fix 2: Shell Script Error Handling (research.md Issue 2)

- [x] T009 Unit test for shell script conflict handling in `tests/096-bolster-project-and/unit/test_shell_script_execution.py` - test should FAIL when conflict=true causes exit 1
- [x] T010 Fix shell script in `home-modules/desktop/eww-monitoring-panel.nix:240-248` - remove `exit 1` for conflict case, show warning notification instead
- [x] T011 Verify T009 test now PASSES after fix

**Checkpoint**: Foundation fixed - CRUD operations no longer fail with false conflict errors

---

## Phase 3: User Story 7 - Visual Feedback During Operations (Priority: P1) 🎯 MVP

**Goal**: Add loading, success, and error notifications so users know operation status

**Why first**: Visual feedback is the most critical UX fix and benefits ALL other user stories. Implementing this first means US1-US6 will automatically have proper feedback.

**Independent Test**: Perform any save operation and observe (1) loading spinner appears, (2) success toast on completion OR error toast on failure.

### Tests for User Story 7

- [ ] T012 [P] [US7] Unit test for notification state management in `tests/096-bolster-project-and/unit/test_notification_state.py`
- [ ] T013 [P] [US7] Integration test for save button loading state in `tests/096-bolster-project-and/integration/test_visual_feedback.py`
- [ ] T014 [P] [US7] Screenshot test: Capture baseline of notification toast (success state) at `tests/096-bolster-project-and/screenshots/baseline/notification-success.png`
- [ ] T015 [P] [US7] Screenshot test: Capture baseline of notification toast (error state) at `tests/096-bolster-project-and/screenshots/baseline/notification-error.png`
- [ ] T016 [P] [US7] Screenshot test: Capture baseline of save button loading spinner at `tests/096-bolster-project-and/screenshots/baseline/save-button-loading.png`

### Implementation for User Story 7

- [x] T017 [P] [US7] Add notification state variables to eww defvars in `home-modules/desktop/eww-monitoring-panel.nix` (notification_visible, notification_type, notification_message, notification_auto_dismiss)
- [x] T018 [P] [US7] Add save_in_progress state variable in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T019 [US7] Create notification toast widget with Catppuccin styling (green success #a6e3a1, red error #f38ba8) in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T020 [US7] Add 3-second auto-dismiss timer for success notifications in notification toast widget
- [x] T021 [US7] Add loading spinner to save button when save_in_progress=true in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T022 [US7] Update all shell scripts to set save_in_progress=true before operation and false after in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T023 [US7] Update shell scripts to trigger success notification on successful save in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T024 [US7] Update shell scripts to trigger error notification with specific message on failure in `home-modules/desktop/eww-monitoring-panel.nix`

### Screenshot Verification for User Story 7

- [ ] T025 [US7] Verify notification toast renders correctly via grim screenshot comparison (success state)
- [ ] T026 [US7] Verify notification toast renders correctly via grim screenshot comparison (error state)
- [ ] T027 [US7] Verify save button loading spinner renders correctly via grim screenshot comparison

**Checkpoint**: Visual feedback system complete - all operations show loading/success/error states, verified via screenshots

---

## Phase 4: User Story 2 - Edit Existing Project Configuration (Priority: P1)

**Goal**: Enable editing project display_name, icon, and scope with immediate visual feedback

**Why this order**: Edit is simpler than Create (fewer fields to validate) and lets us verify the end-to-end flow works before adding Create complexity.

**Independent Test**: Click edit (✏) on project, change display_name, click Save, verify (1) form submits, (2) success toast, (3) list updates, (4) JSON file updated.

### Tests for User Story 2

- [x] T028 [P] [US2] Integration test for project edit form submission in `tests/096-bolster-project-and/integration/test_crud_end_to_end.py::test_project_edit`
- [ ] T029 [P] [US2] Sway UI test for edit workflow in `tests/096-bolster-project-and/sway-tests/test_project_edit.json`
- [ ] T030 [P] [US2] Screenshot test: Capture baseline of edit form expanded state at `tests/096-bolster-project-and/screenshots/baseline/edit-form-expanded.png`
- [ ] T031 [P] [US2] Screenshot test: Capture baseline of inline validation error at `tests/096-bolster-project-and/screenshots/baseline/edit-form-validation-error.png`

### Implementation for User Story 2

- [x] T032 [US2] Verify project-edit-open script populates form fields correctly in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T033 [US2] Verify project-edit-save script passes all form values to Python handler in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T034 [US2] Add inline validation error display below form fields in edit form widget in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T035 [US2] Connect save button to project-edit-save onclick with correct variable passing in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T036 [US2] Add form collapse on successful save in project-edit-save script in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T037 [US2] Add projects_data refresh after successful edit in project-edit-save script in `home-modules/desktop/eww-monitoring-panel.nix`

### Screenshot Verification for User Story 2

- [ ] T038 [US2] Verify edit form renders correctly via grim screenshot comparison
- [ ] T039 [US2] Verify inline validation error renders correctly via grim screenshot comparison

**Checkpoint**: Project editing works end-to-end with visual feedback, verified via screenshots

---

## Phase 5: User Story 1 - Create New Project via Monitoring Panel (Priority: P1)

**Goal**: Enable creating new projects from UI with validation

**Independent Test**: Click "New Project", fill name/directory/icon, click Save, verify (1) form submits, (2) success toast, (3) project in list, (4) JSON file exists.

### Tests for User Story 1

- [x] T040 [P] [US1] Integration test for project creation in `tests/096-bolster-project-and/integration/test_crud_end_to_end.py::test_project_create`
- [ ] T041 [P] [US1] Sway UI test for create workflow in `tests/096-bolster-project-and/sway-tests/test_project_create.json`
- [ ] T042 [P] [US1] Screenshot test: Capture baseline of create form at `tests/096-bolster-project-and/screenshots/baseline/create-form.png`
- [ ] T043 [P] [US1] Screenshot test: Capture baseline of name validation error at `tests/096-bolster-project-and/screenshots/baseline/create-form-name-error.png`

### Implementation for User Story 1

- [x] T044 [US1] Verify "New Project" button reveals create form with empty fields in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T045 [US1] Implement name validation (^[a-z0-9-]+$) with inline error in create form in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T046 [US1] Implement directory validation (exists check) with inline error in create form in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T047 [US1] Implement duplicate name check with inline error in create form in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T048 [US1] Verify project-create-save script builds correct JSON payload in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T049 [US1] Connect create form save button to project-create-save onclick in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T050 [US1] Add form collapse and list refresh after successful create in `home-modules/desktop/eww-monitoring-panel.nix`

### Screenshot Verification for User Story 1

- [ ] T051 [US1] Verify create form renders correctly via grim screenshot comparison
- [ ] T052 [US1] Verify name validation error renders correctly via grim screenshot comparison

**Checkpoint**: Project creation works end-to-end - MVP Complete! 🎯 Verified via screenshots

---

## Phase 6: User Story 4 - Delete Project with Confirmation (Priority: P2)

**Goal**: Enable deleting projects with confirmation dialog

**Independent Test**: Click delete (🗑) on project, confirm, verify project removed from list and JSON deleted.

### Tests for User Story 4

- [x] T053 [P] [US4] Integration test for project deletion in `tests/096-bolster-project-and/integration/test_crud_end_to_end.py::test_project_delete`
- [ ] T054 [P] [US4] Screenshot test: Capture baseline of delete confirmation dialog at `tests/096-bolster-project-and/screenshots/baseline/delete-confirmation.png`

### Implementation for User Story 4

- [x] T055 [US4] Verify confirmation dialog appears on delete button click in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T056 [US4] Implement worktree dependency warning in confirmation dialog in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T057 [US4] Connect "Confirm Delete" button to project-delete script in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T058 [US4] Add projects_data refresh after successful delete in `home-modules/desktop/eww-monitoring-panel.nix`

### Screenshot Verification for User Story 4

- [ ] T059 [US4] Verify delete confirmation dialog renders correctly via grim screenshot comparison

**Checkpoint**: Project CRUD (Create, Edit, Delete) fully functional, verified via screenshots

---

## Phase 7: User Story 3 - Create Git Worktree from Parent Project (Priority: P2)

**Goal**: Enable creating worktrees for feature branches

**Independent Test**: Click "New Worktree" on main project, enter branch/path, click Save, verify Git worktree created and appears under parent in list.

### Tests for User Story 3

- [ ] T060 [P] [US3] Integration test for worktree creation in `tests/096-bolster-project-and/integration/test_crud_end_to_end.py::test_worktree_create`
- [ ] T061 [P] [US3] Sway UI test for worktree create workflow in `tests/096-bolster-project-and/sway-tests/test_worktree_create.json`
- [ ] T062 [P] [US3] Screenshot test: Capture baseline of worktree create form at `tests/096-bolster-project-and/screenshots/baseline/worktree-create-form.png`
- [ ] T063 [P] [US3] Screenshot test: Capture baseline of worktree hierarchy view at `tests/096-bolster-project-and/screenshots/baseline/worktree-hierarchy.png`

### Implementation for User Story 3

- [x] T064 [US3] Verify "New Worktree" button only visible on main projects (not worktrees, not remote) in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T065 [US3] Implement worktree create form with branch_name and worktree_path fields in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T066 [US3] Verify worktree-create script executes `git worktree add` via CLIExecutor in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T067 [US3] Add branch validation error handling (branch not found) in worktree-create script in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T068 [US3] Add worktree JSON creation with parent_project reference in worktree-create script
- [x] T069 [US3] Add list refresh showing worktree indented under parent after create

### Screenshot Verification for User Story 3

- [ ] T070 [US3] Verify worktree create form renders correctly via grim screenshot comparison
- [ ] T071 [US3] Verify worktree hierarchy indentation renders correctly via grim screenshot comparison

**Checkpoint**: Worktree creation functional, verified via screenshots

---

## Phase 8: User Story 5 - Edit Worktree Display Settings (Priority: P3)

**Goal**: Enable editing worktree display_name and icon while showing branch/path as read-only

**Independent Test**: Click edit on worktree, verify branch/path read-only, change display_name, save successfully.

### Tests for User Story 5

- [ ] T072 [P] [US5] Screenshot test: Capture baseline of worktree edit form showing read-only fields at `tests/096-bolster-project-and/screenshots/baseline/worktree-edit-form.png`

### Implementation for User Story 5

- [x] T073 [US5] Verify worktree edit form shows branch_name as read-only label in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T074 [US5] Verify worktree edit form shows worktree_path as read-only label in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T075 [US5] Verify worktree-edit-save only updates display_name, icon, scope (not branch fields) in `home-modules/desktop/eww-monitoring-panel.nix`

### Screenshot Verification for User Story 5

- [ ] T076 [US5] Verify worktree edit form with read-only fields renders correctly via grim screenshot comparison

**Checkpoint**: Worktree edit functional, verified via screenshots

---

## Phase 9: User Story 6 - Delete Worktree with Git Cleanup (Priority: P3)

**Goal**: Enable deleting worktrees with Git worktree removal

**Independent Test**: Delete worktree, verify both Git worktree directory and project JSON removed.

### Implementation for User Story 6

- [x] T077 [US6] Verify worktree-delete script executes `git worktree remove` in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T078 [US6] Add error handling for locked files (Git cleanup failed warning) in worktree-delete script
- [x] T079 [US6] Add list refresh after worktree deletion

**Checkpoint**: Full worktree CRUD complete

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, validation, documentation, and final screenshot regression suite

### Edge Cases & Validation

- [x] T080 Add empty state message "No projects configured" when projects_data is empty in `home-modules/desktop/eww-monitoring-panel.nix`
- [ ] T081 Add keyboard navigation (Tab/Shift+Tab, Enter, Escape) to all forms in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T082 Add "Backend unavailable" fallback error when PYTHONPATH issues occur in shell scripts (PYTHONPATH set in all scripts)

### Eww Troubleshooting Integration

- [x] T083 Create eww troubleshooting helper script at `tests/096-bolster-project-and/scripts/eww-debug.sh` that runs: `eww kill && eww daemon --debug && eww logs`
- [ ] T084 Add eww state dump command to test failures in `tests/096-bolster-project-and/conftest.py` using `eww state` and `eww debug`
- [x] T085 Document eww GTK-Debugger usage for style issues in `tests/096-bolster-project-and/README.md`

### Screenshot Regression Suite

- [ ] T086 [P] Screenshot test: Capture baseline of empty state message at `tests/096-bolster-project-and/screenshots/baseline/empty-state.png`
- [ ] T087 Create screenshot regression test runner at `tests/096-bolster-project-and/scripts/run-screenshot-regression.sh`
- [ ] T088 Add CI integration for screenshot comparison with threshold-based diff detection

### Documentation

- [ ] T089 Run quickstart.md manual validation checklist
- [ ] T090 [P] Update CLAUDE.md with Feature 096 documentation entry
- [x] T091 [P] Create README.md in `tests/096-bolster-project-and/` documenting screenshot testing methodology

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - start immediately
- **Foundational (Phase 2)**: Depends on Setup - **BLOCKS all user stories**
- **User Story 7 (Phase 3)**: Depends on Foundational - implement first for all stories to benefit
- **User Story 2 (Phase 4)**: Depends on Foundational + US7
- **User Story 1 (Phase 5)**: Depends on Foundational + US7
- **User Story 4 (Phase 6)**: Depends on Foundational + US7
- **User Story 3 (Phase 7)**: Depends on US1 (same form pattern) + US7
- **User Story 5 (Phase 8)**: Depends on US2 (same edit pattern) + US7
- **User Story 6 (Phase 9)**: Depends on US4 (same delete pattern) + US7
- **Polish (Phase 10)**: Depends on all desired stories complete

### User Story Dependencies

```
Foundational (Phase 2) - ROOT CAUSE FIXES
         ↓
    User Story 7 (Visual Feedback) - MUST BE FIRST
         ↓
    ┌────┴────┐
    ↓         ↓
   US1       US2      ← Can run in parallel (P1 stories)
   US4                ← Can run after US1/US2 (P2)
    ↓
   US3               ← Builds on US1 patterns
   US5               ← Builds on US2 patterns
   US6               ← Builds on US4 patterns
```

### Within Each User Story

1. Tests (including screenshot baselines) MUST be captured/written before implementation
2. Core functionality before edge cases
3. Verify tests PASS after implementation
4. Screenshot verification confirms UI renders correctly
5. Story complete before moving to next phase

### Parallel Opportunities

**Phase 1**:
- T001-T005 (setup tasks) can run in parallel

**Phase 2**:
- T006, T009 (bug fix tests) can run in parallel
- After tests: T007, T010 (fixes) must be sequential (different files)

**Phase 3 (US7)**:
- T012-T016 (tests + screenshot baselines) can run in parallel
- T017, T018 (defvars) can run in parallel
- T019-T024 must be mostly sequential (same file)
- T025-T027 (screenshot verification) can run in parallel after implementation

**Phase 4-5 (US1, US2)**:
- US1 and US2 can be worked in parallel by different developers
- Tests and screenshot baselines within each story can run in parallel
- Screenshot verification runs after implementation

---

## Parallel Example: Foundational Phase

```bash
# Launch tests in parallel:
Task T006: "Unit test for conflict detection logic"
Task T009: "Unit test for shell script conflict handling"

# Then fix bugs sequentially (different files):
Task T007: "Fix conflict detection in project_editor.py"
Task T010: "Fix shell script in eww-monitoring-panel.nix"
```

---

## Parallel Example: Screenshot Testing

```bash
# After implementation, run screenshot verification in parallel:
grim -g "$(swaymsg -t get_tree | jq -r '.. | select(.app_id? == "eww-monitoring-panel") | .rect | "\(.x),\(.y) \(.width)x\(.height)"')" /tmp/current.png
python3 tests/096-bolster-project-and/scripts/compare-screenshots.py \
    tests/096-bolster-project-and/screenshots/baseline/notification-success.png \
    /tmp/current.png \
    --threshold 0.05
```

---

## Implementation Strategy

### MVP First (Phases 1-5 Only)

1. Complete Phase 1: Setup (screenshot infrastructure)
2. Complete Phase 2: Foundational (CRITICAL bug fixes)
3. Complete Phase 3: User Story 7 (Visual Feedback) + screenshot verification
4. Complete Phase 4: User Story 2 (Edit Project) + screenshot verification
5. Complete Phase 5: User Story 1 (Create Project) + screenshot verification
6. **STOP and VALIDATE**: Test end-to-end CRUD workflow, run screenshot regression suite
7. Deploy/demo if ready

**MVP Scope**: 52 tasks (T001-T052)

### Full Implementation

Continue with Phases 6-10 to add:
- Delete Project (US4)
- Worktree CRUD (US3, US5, US6)
- Polish, eww troubleshooting integration, & screenshot regression suite

**Full Scope**: 91 tasks

---

## Screenshot Testing Methodology

### Capture with grim

```bash
# Capture specific eww window
WINDOW_GEOM=$(swaymsg -t get_tree | jq -r '.. | select(.app_id? == "eww-monitoring-panel") | .rect | "\(.x),\(.y) \(.width)x\(.height)"')
grim -g "$WINDOW_GEOM" screenshot.png

# Capture full output (for debugging)
grim -o HEADLESS-1 full-screen.png
```

### Comparison Threshold

- **0.01 (1%)**: Strict - catches minor rendering differences
- **0.05 (5%)**: Recommended - tolerates anti-aliasing and font rendering variations
- **0.10 (10%)**: Lenient - catches major layout breaks only

### Eww Troubleshooting Commands

When UI tests fail, use these eww debug commands:

```bash
# Kill daemon and restart with debug logging
eww kill
eww daemon --debug

# View debug logs
eww logs

# Dump current variable state (useful for form values)
eww state

# Get widget tree structure (useful for layout issues)
eww debug

# Force reload configuration
eww reload

# Open GTK Inspector for style debugging
GTK_DEBUG=interactive eww open monitoring-panel
```

### Common Issues and Fixes

| Issue | eww Command | Resolution |
|-------|-------------|------------|
| Widget not rendering | `eww debug` | Check for yuck syntax errors |
| Styles not applied | GTK Inspector | Verify CSS selectors match widget classes |
| Variables not updating | `eww state` | Check defpoll interval and script output |
| Hot reload broken | `eww reload` | Restart daemon with `eww kill && eww daemon` |
| Scope not in graph | `eww logs` | Known eww issue - restart daemon |

---

## Notes

- All changes in Phases 2-9 are in TWO files: `project_editor.py` and `eww-monitoring-panel.nix`
- Foundational fixes (T006-T011) are the root cause - if these fail, all CRUD fails
- User Story 7 (Visual Feedback) was reordered to Phase 3 because all other stories depend on it for UX
- Tests use pytest-asyncio for async Python code
- Sway tests use sway-test JSON framework
- **Screenshot testing** uses grim for capture and PIL for comparison
- **Eww troubleshooting** commands integrated into test infrastructure for debugging UI issues
- Screenshot baselines should be captured AFTER implementation is stable, then used for regression detection
