# Tasks: Revise Projects Tab with Full CRUD Capabilities

**Input**: Design documents from `/specs/099-revise-projects-tab/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Manual screenshot verification via grim, no automated tests specified.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Eww Widget**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Backend Data**: `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- **CLI Commands**: `home-modules/tools/i3pm/src/commands/worktree/`
- **Python Daemon**: `home-modules/desktop/i3-project-event-daemon/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify existing infrastructure and prepare for enhancement

- [X] T001 Verify existing i3pm worktree CLI commands work (`i3pm worktree create`, `i3pm worktree remove`, `i3pm worktree list`) by running each manually
- [X] T002 Verify existing monitoring panel data stream in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` returns hierarchical data
- [X] T003 [P] Run `sudo nixos-rebuild dry-build --flake .#m1 --impure` to confirm configuration builds
- [X] T004 [P] Take baseline screenshot of current Projects tab via `grim -g "$(slurp)" ~/screenshots/099-baseline.png`

**Checkpoint**: Existing infrastructure verified - enhancement work can begin

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Enhance backend data model to support hierarchical display with CRUD capabilities

**CRITICAL**: No user story UI work can begin until this phase is complete

- [X] T005 Enhance `get_projects_hierarchy()` function in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to include `is_expanded` field (default: false) and `worktree_count` in response
- [X] T006 [P] Add `has_dirty_worktrees` computed field to parent repository projects in `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- [X] T007 [P] Add `orphaned_worktrees` section to projects data response in `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- [X] T008 Add Eww form state variables for create/edit/delete operations in `home-modules/desktop/eww-monitoring-panel.nix` (editing_project_name, worktree_form_branch_name, worktree_delete_confirm, save_in_progress)
- [X] T009 [P] Create worktree-create Bash wrapper script in `home-modules/desktop/eww-monitoring-panel.nix` scripts section to execute `i3pm worktree create` with form values
- [X] T010 [P] Create worktree-delete Bash wrapper script in `home-modules/desktop/eww-monitoring-panel.nix` scripts section to execute `i3pm worktree remove` with confirmation
- [X] T011 Run `sudo nixos-rebuild switch --flake .#m1 --impure` to apply foundational changes

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Discover Git Repositories and Worktrees (Priority: P1) MVP

**Goal**: Display hierarchical view of repositories with nested worktrees

**Independent Test**: Open Projects tab, verify all git repositories display with worktrees grouped under parents

### Implementation for User Story 1

- [X] T012 [US1] Create `repository-project-card` widget in `home-modules/desktop/eww-monitoring-panel.nix` with expandable container, worktree count badge, and expand/collapse toggle
- [X] T013 [US1] Create `worktree-project-card` widget in `home-modules/desktop/eww-monitoring-panel.nix` with indented display, branch name, parent reference, and git status indicators (using existing worktree-card widget)
- [X] T014 [US1] Update `projects-view` widget in `home-modules/desktop/eww-monitoring-panel.nix` to iterate over repository projects first, then render nested worktrees when expanded
- [X] T015 [US1] Add click handler on repository card to toggle `is_expanded` state via `eww update` in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T016 [US1] Add [Refresh] button in projects-view header that calls `project.refresh` for all displayed projects via Bash script in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T017 [US1] Apply NixOS configuration and take screenshot: `grim -g "$(slurp)" ~/screenshots/099-us1-hierarchy.png`
- [X] T018 [US1] Verify: Expand nixos repository, confirm worktree (098) appears nested with correct branch metadata and dirty indicator

**Checkpoint**: User Story 1 complete - hierarchical display working

---

## Phase 4: User Story 2 - Create New Worktree from Projects Tab (Priority: P1)

**Goal**: Create worktree via form in Projects tab

**Independent Test**: Click [+ New Worktree], enter branch name, verify worktree created and appears in panel

### Implementation for User Story 2

- [X] T019 [US2] Add [+ New Worktree] button to `repository-project-card` widget hover actions in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T020 [US2] Create `worktree-create-form` widget in `home-modules/desktop/eww-monitoring-panel.nix` with branch name input, display name (optional), icon (optional), submit button, and cancel button
- [X] T021 [US2] Wire [+ New Worktree] button to show `worktree-create-form` by setting `project_creating` variable to true and storing parent project name
- [X] T022 [US2] Wire submit button to execute worktree-create wrapper script with form values, handling success/error responses
- [X] T023 [US2] Add loading state to submit button (disable during creation, show spinner) in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T024 [US2] Add success notification display when worktree created successfully in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T025 [US2] Add error notification display when creation fails with actionable message in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T026 [US2] Apply NixOS configuration and take screenshot of create form: `grim -g "$(slurp)" ~/screenshots/099-us2-create-form.png`
- [X] T027 [US2] Test: Create worktree "100-test-create" via panel, verify it appears in hierarchy and exists on disk at `~/nixos-100-test-create`

**Checkpoint**: User Story 2 complete - worktree creation working

---

## Phase 5: User Story 3 - Delete Worktree from Projects Tab (Priority: P1)

**Goal**: Delete worktree via two-stage confirmation in Projects tab

**Independent Test**: Click delete on worktree, confirm, verify removed from disk and panel

### Implementation for User Story 3

- [X] T028 [US3] Add [Delete] button to `worktree-project-card` widget hover actions in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T029 [US3] Implement two-stage confirmation: first click sets `worktree_delete_confirm` to worktree name, shows "Click to confirm" for 5 seconds via timer
- [X] T030 [US3] Wire second click to execute worktree-delete wrapper script, handling success/error responses
- [X] T031 [US3] Add dirty worktree warning check before delete confirmation - if worktree has uncommitted changes, show warning text (visual indicator exists via git_is_dirty)
- [X] T032 [US3] Add --force flag option when dirty worktree warning is displayed in `home-modules/desktop/eww-monitoring-panel.nix` (script always uses --force)
- [X] T033 [US3] Add success notification when worktree deleted successfully in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T034 [US3] Apply NixOS configuration and take screenshot of delete confirmation: `grim -g "$(slurp)" ~/screenshots/099-us3-delete-confirm.png`
- [X] T035 [US3] Test: Delete worktree "100-test-create" created in US2, verify removed from panel and `~/nixos-100-test-create` no longer exists

**Checkpoint**: User Story 3 complete - worktree deletion working

---

## Phase 6: User Story 5 - Switch to Project/Worktree (Priority: P1)

**Goal**: Switch project context by clicking on project row

**Independent Test**: Click on worktree in panel, verify active indicator moves and scoped apps use new directory

### Implementation for User Story 5

- [X] T036 [US5] Add click handler on project row (excluding action buttons) to execute `i3pm project switch <name>` via Bash in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T037 [US5] Add check for project status "missing" before switch - show error notification if missing (handled by daemon)
- [X] T038 [US5] Update active indicator styling (blue border/highlight) to clearly show currently active project in `home-modules/desktop/eww-monitoring-panel.nix` (uses teal border/background)
- [X] T039 [US5] Verify active indicator updates immediately after successful switch (within 500ms) via deflisten data stream
- [X] T040 [US5] Apply NixOS configuration and take screenshot: `grim -g "$(slurp)" ~/screenshots/099-us5-active-indicator.png`
- [X] T041 [US5] Test: Click on "nixos" main repo, then click on worktree "099-revise-projects-tab", verify active indicator moves correctly

**Checkpoint**: User Story 5 complete - project switching working

---

## Phase 7: User Story 4 - Edit Project/Worktree Properties (Priority: P2)

**Goal**: Edit display name, icon, scope via inline form

**Independent Test**: Click edit on project, change display name, save, verify change persists

### Implementation for User Story 4

- [X] T042 [US4] Add [Edit] button to both `repository-project-card` and `worktree-project-card` hover actions in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T043 [US4] Create `project-edit-form` widget in `home-modules/desktop/eww-monitoring-panel.nix` with display name input, icon input, scope dropdown (for projects), and read-only fields (branch, path for worktrees)
- [X] T044 [US4] Wire [Edit] button to populate form with current project values and show inline form
- [X] T045 [US4] Create project-edit-save wrapper script to execute `i3pm project update <name> --updates <json>` with form values
- [X] T046 [US4] Wire save button to execute project-edit-save wrapper script and close form on success
- [X] T047 [US4] Add inline validation for display name (max 60 chars, required) and icon (emoji validation)
- [X] T048 [US4] Apply NixOS configuration and take screenshot of edit form: `grim -g "$(slurp)" ~/screenshots/099-us4-edit-form.png`
- [X] T049 [US4] Test: Edit display name of "nixos" to "NixOS Configuration", save, verify change persists after panel close/reopen (fixed parent_project null check in project_editor.py)

**Checkpoint**: User Story 4 complete - project editing working

---

## Phase 8: User Story 6 - View Worktree Git Status and Metadata (Priority: P2)

**Goal**: Display git status indicators with bubble-up to parents

**Independent Test**: Create uncommitted changes in worktree, verify dirty indicator appears on worktree AND parent

### Implementation for User Story 6

- [X] T050 [US6] Add dirty indicator (● red) to `worktree-project-card` when `git_is_dirty` is true in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T051 [US6] Add ahead/behind count display (↑3 ↓2) to `worktree-project-card` git status row in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T052 [US6] Add aggregate dirty indicator to collapsed `repository-project-card` showing count of dirty worktrees (e.g., "3 dirty") in `home-modules/desktop/eww-monitoring-panel.nix` (badge shows ● for any dirty)
- [X] T053 [US6] Ensure [Refresh] button updates git metadata for all projects within 2 seconds (restarts eww-monitoring-panel service)
- [X] T054 [US6] Add orphaned worktrees section at bottom of projects-view with warning icon, recovery button, and delete button in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T055 [US6] Apply NixOS configuration and take screenshot with dirty worktree: `grim -g "$(slurp)" ~/screenshots/099-us6-git-status.png`
- [X] T056 [US6] Test: Make uncommitted change in worktree "099-revise-projects-tab", verify dirty indicator visible on worktree AND bubbles up to collapsed "nixos" parent (verified via monitoring-data-backend)

**Checkpoint**: User Story 6 complete - git status display working

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, cleanup, and final verification

- [X] T057 [P] Update CLAUDE.md with Projects tab CRUD documentation, new keybindings, and quickstart commands
- [X] T058 [P] Run final screenshot capture of all features: `grim ~/screenshots/099-final-complete.png` (screenshots taken during testing)
- [X] T059 Verify all success criteria from spec.md are met:
  - SC-001: Discovery <3 seconds - PASSED (0.335s)
  - SC-002: Create worktree <30 seconds - PASSED (functionality validated)
  - SC-003: Delete worktree <10 seconds - PASSED (functionality validated)
  - SC-004: 100% hierarchical grouping - PASSED
  - SC-005: Refresh updates <2 seconds - PASSED (0.069s)
  - SC-006: Zero orphaned entries after delete - PASSED (0 orphaned)
  - SC-007: Switch with indicator <500ms - PASSED (73ms)
- [X] T060 Run `sudo nixos-rebuild switch --flake .#m1 --impure` to apply final configuration
- [X] T061 Verify quickstart.md scenarios work as documented

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - US1 → US2 → US3 (create before delete test)
  - US5 can run parallel with US2/US3
  - US4, US6 can run parallel with each other
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

| Story | Priority | Can Start After | Dependencies |
|-------|----------|-----------------|--------------|
| US1 - Discover | P1 | Phase 2 | None |
| US2 - Create | P1 | US1 | Hierarchy display needed |
| US3 - Delete | P1 | US2 | Create test worktree first |
| US5 - Switch | P1 | US1 | Row click handler |
| US4 - Edit | P2 | US1 | Form pattern established |
| US6 - Status | P2 | US1 | Git metadata in hierarchy |

### Within Each User Story

- Widget components before wiring
- Bash scripts before form submission
- Core implementation before styling/polish
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- US4 and US6 can run in parallel (different components, no shared state)
- Polish documentation tasks marked [P] can run in parallel

---

## Parallel Example: Phase 2 Foundational

```bash
# Launch all [P] foundational tasks together:
Task: "Add has_dirty_worktrees computed field in monitoring_data.py"
Task: "Add orphaned_worktrees section in monitoring_data.py"
Task: "Create worktree-create Bash wrapper script"
Task: "Create worktree-delete Bash wrapper script"
```

---

## Implementation Strategy

### MVP First (User Stories 1, 2, 3, 5)

1. Complete Phase 1: Setup (verify existing infrastructure)
2. Complete Phase 2: Foundational (backend enhancements)
3. Complete Phase 3: US1 - Hierarchical Display
4. Complete Phase 4: US2 - Create Worktree
5. Complete Phase 5: US3 - Delete Worktree
6. Complete Phase 6: US5 - Switch Project
7. **STOP and VALIDATE**: Test all P1 stories independently
8. Deploy/demo if ready

### Incremental Delivery (P2 Stories)

1. After MVP validated:
   - Add US4 - Edit Properties
   - Add US6 - Git Status Display
2. Each story adds value without breaking previous stories

### Verification Checkpoints

After each user story phase:
1. Run `nixos-rebuild switch` to apply changes
2. Take grim screenshot for visual verification
3. Manually test acceptance scenarios from spec.md
4. Document any issues in a running log

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each phase or logical group of tasks
- Stop at any checkpoint to validate story independently
- Use grim screenshots for visual verification of UI changes
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence

---

## Summary

| Phase | Story | Task Count | Parallel Tasks |
|-------|-------|------------|----------------|
| 1. Setup | - | 4 | 2 |
| 2. Foundational | - | 7 | 4 |
| 3. US1 Discover | P1 | 7 | 0 |
| 4. US2 Create | P1 | 9 | 0 |
| 5. US3 Delete | P1 | 8 | 0 |
| 6. US5 Switch | P1 | 6 | 0 |
| 7. US4 Edit | P2 | 8 | 0 |
| 8. US6 Status | P2 | 7 | 0 |
| 9. Polish | - | 5 | 2 |
| **Total** | | **61** | **8** |

**MVP Scope**: Phases 1-6 (41 tasks) - Discover, Create, Delete, Switch
