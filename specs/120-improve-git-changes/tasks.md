# Tasks: Enhanced Git Worktree Status Indicators

**Input**: Design documents from `/specs/120-improve-git-changes/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Tests**: Not explicitly requested in specification - omitted per task generation rules.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify existing infrastructure and validate integration points

- [x] T001 Verify existing git_utils.py exports in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T002 Verify existing monitoring_data.py structure in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T003 [P] Verify existing eww-monitoring-panel.nix widget structure in home-modules/desktop/eww-monitoring-panel.nix

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Add get_diff_stats() function to home-modules/tools/i3_project_manager/services/git_utils.py (parses git diff --numstat HEAD, returns (additions, deletions) tuple, 2s timeout)
- [x] T005 [P] Extend WorktreeMetadata model with additions, deletions, diff_error fields in home-modules/tools/i3_project_manager/models/worktree.py
- [x] T006 Add format_count() helper function (caps at 9999) in home-modules/tools/i3_project_manager/services/git_utils.py

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Quick Status Assessment at a Glance (Priority: P1) 🎯 MVP

**Goal**: Enable developers to immediately identify worktree status (dirty/clean, merged, stale, conflicts) without clicking or hovering

**Independent Test**: View monitoring panel with multiple worktrees in various states - verify status indicators clearly differentiate between clean, dirty, merged, stale, and conflicted worktrees

### Implementation for User Story 1

- [x] T007 [US1] Add git_is_dirty, git_is_merged, git_is_stale, git_has_conflicts, git_status_error fields to worktree display data in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T008 [US1] Add git_dirty_indicator (●), git_merged_indicator (✓), git_stale_indicator (💤), git_conflict_indicator (⚠), git_error_indicator (?) string fields in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T009 [US1] Add git_ahead, git_behind integer fields and git_sync_indicator (↑N ↓M) string field in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T010 [US1] Implement status indicator computation logic with priority ordering (conflicts > dirty > sync > stale > merged) in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T011 [US1] Add worktree-status-indicators box widget with visibility guards for each indicator in home-modules/desktop/eww-monitoring-panel.nix
- [x] T012 [US1] Add CSS classes for status indicators (.git-conflict, .git-dirty, .git-sync-ahead, .git-sync-behind, .badge-stale, .badge-merged) using Catppuccin colors in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: At this point, worktree cards display all status indicators in priority order - US1 fully functional

---

## Phase 4: User Story 2 - Worktree Header Status in Windows View (Priority: P2)

**Goal**: Show git status information in project headers on the Windows tab without requiring navigation to worktree tab

**Independent Test**: View Windows tab with projects that have worktrees - verify git status indicators appear in project headers

### Implementation for User Story 2

- [x] T013 [US2] Add header_git_dirty, header_git_ahead, header_git_behind, header_git_merged, header_git_has_conflicts fields to project display data in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T014 [US2] Implement first-worktree status extraction logic for project headers (uses worktrees[0] if available) in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T015 [US2] Add project-header-git-status box widget in windows view with compact indicators in home-modules/desktop/eww-monitoring-panel.nix
- [x] T016 [US2] Add CSS classes for compact header indicators (.git-dirty-small, .git-sync-small, .badge-merged-small) in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: At this point, Windows view project headers show git status - US1 and US2 both functional

---

## Phase 5: User Story 3 - Actionable Status Context (Priority: P3)

**Goal**: Provide tooltips and context that suggest appropriate actions (commit, push, pull, resolve conflicts)

**Independent Test**: Hover over status indicators - verify contextual information suggests appropriate actions

### Implementation for User Story 3

- [x] T017 [US3] Add git_status_tooltip field with multi-line status summary in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T018 [US3] Implement tooltip generation with actionable suggestions (e.g., "2 commits behind - pull needed", "Uncommitted changes - commit or stash") in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T019 [US3] Add git_last_commit_relative and git_last_commit_message fields in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T020 [US3] Add tooltip attribute to status indicator widgets using git_status_tooltip in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: At this point, status indicators have actionable tooltips - US1, US2, US3 all functional

---

## Phase 6: User Story 4 - Git Diff Statistics Display (Priority: P4)

**Goal**: Display visual diff bar showing additions (green) and deletions (red) with line counts

**Independent Test**: Make changes of varying sizes in worktrees - verify visual diff indicator accurately represents scale of additions vs deletions

### Implementation for User Story 4

- [x] T021 [US4] Add git_additions, git_deletions, git_diff_total integer fields in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T022 [US4] Add git_additions_display (+N), git_deletions_display (-N) string fields with 9999 cap in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T023 [US4] Add git_diff_tooltip field ("+123 additions, -45 deletions") in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T024 [US4] Call get_diff_stats() from monitoring data generation and populate diff fields in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T025 [US4] Add header_git_additions, header_git_deletions fields to project display data in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T026 [US4] Create diff-bar widget with proportional green/red boxes using CSS flex in home-modules/desktop/eww-monitoring-panel.nix
- [x] T027 [US4] Add CSS classes for diff bar (.diff-bar-container, .diff-bar-additions, .diff-bar-deletions) using Catppuccin green/red in home-modules/desktop/eww-monitoring-panel.nix
- [x] T028 [US4] Integrate diff-bar widget into worktree card layout in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: All user stories (US1-US4) now fully functional

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final integration, validation, and edge case handling

- [x] T029 [P] Handle detached HEAD state - display "detached" indicator with commit hash in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T030 [P] Handle worktrees with no remote - omit sync status arrows in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T031 [P] Handle git command timeout - display "?" status with error indicator in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T032 [P] Handle long branch names - truncate with ellipsis, full name in tooltip in home-modules/desktop/eww-monitoring-panel.nix
- [x] T033 Run dry-build validation: sudo nixos-rebuild dry-build --flake .#hetzner
- [x] T034 Create NixOS integration test: tests/sway-integration/monitoring-panel-git-status.nix
- [x] T035 Create devenv CI configuration: devenv.nix, devenv.yaml, .github/workflows/integration-tests.yml

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can then proceed in priority order (P1 → P2 → P3 → P4)
  - US1 is MVP - delivers core value
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories - **MVP**
- **User Story 2 (P2)**: Can start after US1 completes (reuses indicator infrastructure) - Adds header display
- **User Story 3 (P3)**: Can start after US1 completes (extends indicator data) - Adds tooltips
- **User Story 4 (P4)**: Can start after Foundational (uses get_diff_stats) - Adds diff visualization

### Within Each User Story

- Backend data fields before widget implementation
- Status computation before indicator widgets
- CSS classes alongside or after widget markup

### Parallel Opportunities

**Within Phase 1 (Setup)**:
- T001, T002, T003 can run in parallel

**Within Phase 2 (Foundational)**:
- T005 can run in parallel with T004, T006

**Within User Story 1**:
- T007, T008, T009 are data fields - can be parallelized
- T011, T012 are widget + CSS - can be parallelized after T010

**Within User Story 4**:
- T021, T022, T023 are data fields - can be parallelized
- T026, T027 are widget + CSS - can be parallelized

**Within Polish Phase**:
- T029, T030, T031, T032 are edge cases - all can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all data field tasks for User Story 1 together:
Task: "T007 Add git_is_dirty, git_is_merged... fields in monitoring_data.py"
Task: "T008 Add git_dirty_indicator, git_merged_indicator... fields in monitoring_data.py"
Task: "T009 Add git_ahead, git_behind, git_sync_indicator fields in monitoring_data.py"

# After T010 completes, launch widget tasks together:
Task: "T011 Add worktree-status-indicators widget in eww-monitoring-panel.nix"
Task: "T012 Add CSS classes for status indicators in eww-monitoring-panel.nix"
```

---

## Parallel Example: User Story 4

```bash
# Launch all data field tasks for User Story 4 together:
Task: "T021 Add git_additions, git_deletions, git_diff_total fields"
Task: "T022 Add git_additions_display, git_deletions_display fields"
Task: "T023 Add git_diff_tooltip field"

# After T024 completes, launch widget tasks together:
Task: "T026 Create diff-bar widget"
Task: "T027 Add CSS classes for diff bar"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (verify existing code)
2. Complete Phase 2: Foundational (add get_diff_stats, extend model)
3. Complete Phase 3: User Story 1 (status indicators in worktree cards)
4. **STOP and VALIDATE**: Test US1 independently - can identify dirty/clean/merged/stale worktrees at a glance
5. Deploy/demo if ready - core value delivered

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy (MVP: status indicators in worktree cards)
3. Add User Story 2 → Test independently → Deploy (status in Windows view headers)
4. Add User Story 3 → Test independently → Deploy (actionable tooltips)
5. Add User Story 4 → Test independently → Deploy (visual diff bar)
6. Polish phase → Edge cases handled → Final deploy

### File Change Summary

| File | Tasks | Changes |
|------|-------|---------|
| `services/git_utils.py` | T004, T006 | Add get_diff_stats(), format_count() |
| `models/worktree.py` | T005 | Extend with additions, deletions, diff_error |
| `cli/monitoring_data.py` | T007-T010, T013-T014, T017-T019, T021-T025, T029-T031 | All data transformation logic |
| `eww-monitoring-panel.nix` | T011-T012, T015-T016, T020, T026-T028, T032 | Widgets and CSS |

---

## Notes

- [P] tasks = different files or independent sections, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Polling interval is 10 seconds (existing defpoll mechanism)
- Git command timeout is 2 seconds
- Color scheme follows Catppuccin Mocha palette (existing)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
