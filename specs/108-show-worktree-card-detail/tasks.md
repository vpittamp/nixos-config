# Tasks: Enhanced Worktree Card Status Display

**Input**: Design documents from `/specs/108-show-worktree-card-detail/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are included per Constitution Principle XIV (Test-Driven Development). Tests should be written with implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `home-modules/tools/i3_project_manager/services/git_utils.py`, `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- **Frontend**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Tests**: `tests/108-show-worktree-card-detail/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and test structure

- [x] T001 Create test directory structure at tests/108-show-worktree-card-detail/
- [x] T002 [P] Create test fixtures file at tests/108-show-worktree-card-detail/fixtures/sample_worktree_states.py
- [x] T003 [P] Create conftest.py with shared fixtures at tests/108-show-worktree-card-detail/conftest.py

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Enhanced git metadata extraction - MUST be complete before any UI work

**⚠️ CRITICAL**: No user story work can begin until git_utils.py enhancement is complete

### Backend Foundation

- [x] T004 Add `is_merged` detection to get_git_metadata() in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T005 Add `is_stale` detection (30-day threshold) to get_git_metadata() in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T006 Add `last_commit_timestamp` and `last_commit_message` to get_git_metadata() in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T007 Add `staged_count`, `modified_count`, `untracked_count` parsing to get_git_metadata() in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T008 Add `has_conflicts` detection (UU/AA/DD status codes) to get_git_metadata() in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T009 Add helper function `format_relative_time(timestamp: int) -> str` to git_utils.py for "2h ago" formatting

### Unit Tests for Foundation

- [x] T010 [P] Create unit test for is_merged detection in tests/108-show-worktree-card-detail/unit/test_git_status_enhanced.py
- [x] T011 [P] Create unit test for is_stale detection in tests/108-show-worktree-card-detail/unit/test_git_status_enhanced.py
- [x] T012 [P] Create unit test for status count parsing in tests/108-show-worktree-card-detail/unit/test_git_status_enhanced.py
- [x] T013 [P] Create unit test for conflict detection in tests/108-show-worktree-card-detail/unit/test_git_status_enhanced.py
- [x] T014 [P] Create unit test for format_relative_time() in tests/108-show-worktree-card-detail/unit/test_git_status_enhanced.py

**Checkpoint**: Foundation ready - get_git_metadata() returns all enhanced fields

---

## Phase 3: User Story 1 - At-a-Glance Worktree Health Status (Priority: P1) 🎯 MVP

**Goal**: Display dirty/clean, ahead/behind, merge status, and conflict indicators on worktree cards visible without hover

**Independent Test**: Open Projects tab with worktrees in various git states, verify each state is visually distinguishable at a glance

### Implementation for User Story 1

- [x] T015 [US1] Add computed worktree indicator fields to monitoring_data.py query_projects_data() in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T016 [US1] Add `git_is_merged` and `git_merged_indicator` ("✓") to worktree data in monitoring_data.py
- [x] T017 [US1] Add `git_has_conflicts` and `git_conflict_indicator` ("⚠") to worktree data in monitoring_data.py
- [x] T018 [US1] Add merge badge label to discovered-worktree-card widget in home-modules/desktop/eww-monitoring-panel.nix
- [x] T019 [US1] Add conflict indicator label to discovered-worktree-card widget in home-modules/desktop/eww-monitoring-panel.nix
- [x] T020 [US1] Add CSS styles for .badge-merged (teal #94e2d5) in eww-monitoring-panel.nix SCSS section
- [x] T021 [US1] Add CSS styles for .badge-conflict (red #f38ba8) in eww-monitoring-panel.nix SCSS section
- [x] T022 [US1] Verify existing dirty indicator styling uses red (#f38ba8) in eww-monitoring-panel.nix

### Integration Test for User Story 1

- [x] T023 [US1] Create integration test verifying worktree data includes new fields in tests/108-show-worktree-card-detail/integration/test_monitoring_data_enhanced.py

**Checkpoint**: User Story 1 complete - dirty, sync, merge, and conflict indicators visible at-a-glance

---

## Phase 4: User Story 2 - Detailed Status on Hover/Expand (Priority: P2)

**Goal**: Show detailed status breakdown (file counts, commit info) via tooltips on hover

**Independent Test**: Hover over dirty indicator, verify tooltip shows "2 staged, 3 modified, 1 untracked" breakdown

### Implementation for User Story 2

- [x] T024 [US2] Add `git_staged_count`, `git_modified_count`, `git_untracked_count` to worktree data in monitoring_data.py
- [x] T025 [US2] Add `git_last_commit_relative` and `git_last_commit_message` to worktree data in monitoring_data.py
- [x] T026 [US2] Build `git_status_tooltip` multi-line string in monitoring_data.py
- [x] T027 [US2] Add tooltip attribute to dirty indicator showing file count breakdown in eww-monitoring-panel.nix
- [x] T028 [US2] Add tooltip attribute to sync indicator showing "N commits to push, M to pull" in eww-monitoring-panel.nix
- [x] T029 [US2] Add last commit info (relative time + message) to worktree card hover area in eww-monitoring-panel.nix

### Unit Test for User Story 2

- [x] T030 [P] [US2] Create unit test for git_status_tooltip formatting in tests/108-show-worktree-card-detail/unit/test_status_indicators.py

**Checkpoint**: User Story 2 complete - detailed tooltips appear on hover with file counts and commit info

---

## Phase 5: User Story 3 - Stale Worktree Detection (Priority: P2)

**Goal**: Display subtle staleness indicator (💤) for worktrees with no commits in 30+ days

**Independent Test**: Create worktree with old commits, verify staleness indicator appears

### Implementation for User Story 3

- [x] T031 [US3] Add `git_is_stale` and `git_stale_indicator` ("💤") to worktree data in monitoring_data.py
- [x] T032 [US3] Add staleness indicator label to discovered-worktree-card widget in eww-monitoring-panel.nix
- [x] T033 [US3] Add CSS styles for .badge-stale (gray #6c7086, slightly faded opacity) in eww-monitoring-panel.nix
- [x] T034 [US3] Add tooltip to stale indicator showing "Last activity: X days ago" in eww-monitoring-panel.nix

### Unit Test for User Story 3

- [x] T035 [P] [US3] Create unit test for stale indicator logic (30-day threshold) in tests/108-show-worktree-card-detail/unit/test_status_indicators.py

**Checkpoint**: User Story 3 complete - stale worktrees show 💤 with tooltip

---

## Phase 6: User Story 4 - Branch Merge Status (Priority: P2)

**Goal**: Display merge status badge when branch has been merged into main

**Independent Test**: Merge a branch into main, verify "✓" badge appears on worktree card

### Implementation for User Story 4

- [x] T036 [US4] Ensure merge detection skips main branch itself (don't show ✓ merged on main) in monitoring_data.py
- [x] T037 [US4] Add tooltip to merge badge showing "Branch merged into main" in eww-monitoring-panel.nix
- [x] T038 [US4] Verify merge badge positioning doesn't conflict with other badges in status row

### Integration Test for User Story 4

- [x] T039 [US4] Create integration test for merge detection logic with various branch states in tests/108-show-worktree-card-detail/integration/test_monitoring_data_enhanced.py

**Checkpoint**: User Story 4 complete - merged branches show ✓ badge

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, documentation, and final validation

- [x] T040 [P] Handle offline/unreachable remote gracefully (show "?" for sync status) in monitoring_data.py
- [x] T041 [P] Handle detached HEAD state (show "detached @ abc123") in monitoring_data.py
- [x] T042 [P] Handle no remote configured (hide sync indicators) in monitoring_data.py
- [x] T043 Verify all indicators fit in single row without truncation in eww-monitoring-panel.nix
- [x] T044 Run dry-build test: `sudo nixos-rebuild dry-build --flake .#<target>`
- [x] T045 Manual validation per quickstart.md scenarios
- [x] T046 Update CLAUDE.md with Feature 108 documentation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-6)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Uses same data as US1 but independent
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - Independent staleness feature
- **User Story 4 (P2)**: Can start after Foundational (Phase 2) - Extends US1 merge indicator

### Within Each User Story

- Models/data before UI
- Backend (monitoring_data.py) before frontend (eww-monitoring-panel.nix)
- Core implementation before edge cases
- Story complete before moving to next priority

### Parallel Opportunities

- T002, T003 can run in parallel (different fixture files)
- T010-T014 can run in parallel (different test functions)
- T024-T026 can run in parallel with T027-T029 (backend and frontend separate)
- T031-T034 can run in parallel (US3 is independent of US2)
- T040-T042 can run in parallel (different edge cases)

---

## Parallel Example: Foundational Phase

```bash
# Launch all unit tests together:
Task: "Create unit test for is_merged detection"
Task: "Create unit test for is_stale detection"
Task: "Create unit test for status count parsing"
Task: "Create unit test for conflict detection"
Task: "Create unit test for format_relative_time()"
```

## Parallel Example: User Story 2

```bash
# Backend tasks (can parallelize different monitoring_data.py sections):
Task: "Add git_staged_count, git_modified_count, git_untracked_count"
Task: "Add git_last_commit_relative and git_last_commit_message"
Task: "Build git_status_tooltip multi-line string"

# Frontend tasks (after backend complete):
Task: "Add tooltip to dirty indicator"
Task: "Add tooltip to sync indicator"
Task: "Add last commit info to card"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test US1 independently - dirty, sync, merge, conflict indicators visible
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Tooltips add detail
4. Add User Stories 3 & 4 → Stale detection + merge refinements
5. Each story adds value without breaking previous stories

### Single Developer Strategy

1. Complete Setup + Foundational
2. User Story 1 (P1 MVP) - at-a-glance indicators
3. User Story 2 (P2) - detailed tooltips
4. User Story 3 (P2) - stale detection
5. User Story 4 (P2) - merge status refinement
6. Polish phase

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Constitution requires `dry-build` before applying changes
