# Tasks: Eww Monitoring Widget Improvements

**Input**: Design documents from `/specs/119-fix-window-close-actions/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Manual testing per quickstart.md (no automated tests required)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **NixOS Module**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Claude Hooks Scripts**: `scripts/claude-hooks/`
- **Spec Docs**: `specs/119-fix-window-close-actions/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Read and understand existing code structure before making changes

- [x] T001 Read existing closeWorktreeScript implementation in home-modules/desktop/eww-monitoring-panel.nix (lines ~2400-2500)
- [x] T002 Read existing closeAllWindowsScript implementation in home-modules/desktop/eww-monitoring-panel.nix
- [x] T003 Read existing individual window close onclick handler in home-modules/desktop/eww-monitoring-panel.nix (line ~4006)
- [x] T004 Read existing focusWindowScript implementation in home-modules/desktop/eww-monitoring-panel.nix (lines 2073-2131) - this is the reference implementation
- [x] T005 [P] Read existing swaync-action-callback.sh in scripts/claude-hooks/swaync-action-callback.sh
- [x] T006 [P] Read existing stop-notification.sh in scripts/claude-hooks/stop-notification.sh

**Checkpoint**: Full understanding of existing implementations

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure changes that enable user story implementations

**⚠️ CRITICAL**: The close window script must be created before any close action improvements can be implemented

- [x] T007 Create new closeWindowScript shell derivation in home-modules/desktop/eww-monitoring-panel.nix for individual window close with rate limiting
- [x] T008 Add debug_mode eww variable definition `(defvar debug_mode false)` in home-modules/desktop/eww-monitoring-panel.nix (in defvar section)

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Reliable Window Closing (Priority: P1) 🎯 MVP

**Goal**: Fix unreliable window close actions at project/worktree and individual window levels

**Independent Test**: Open multiple windows in a project, use close actions at individual and project levels, verify all windows close reliably without race conditions

### Implementation for User Story 1

- [x] T009 [US1] Update closeWindowScript to implement rate limiting (prevent double-clicks within 200ms) in home-modules/desktop/eww-monitoring-panel.nix
- [x] T010 [US1] Update closeWindowScript to add state validation after close in home-modules/desktop/eww-monitoring-panel.nix
- [x] T011 [US1] Update closeWindowScript to handle missing window gracefully in home-modules/desktop/eww-monitoring-panel.nix
- [x] T012 [US1] Update closeWorktreeScript to replace lock file with rate limiter in home-modules/desktop/eww-monitoring-panel.nix
- [x] T013 [US1] Update closeWorktreeScript to add explicit error handling for swaymsg failures in home-modules/desktop/eww-monitoring-panel.nix
- [x] T014 [US1] Update closeWorktreeScript to add confirmation via Sway tree re-query in home-modules/desktop/eww-monitoring-panel.nix
- [x] T015 [US1] Update closeWorktreeScript to update panel state after confirmed close in home-modules/desktop/eww-monitoring-panel.nix
- [x] T016 [US1] Apply same improvements from closeWorktreeScript to closeAllWindowsScript in home-modules/desktop/eww-monitoring-panel.nix
- [x] T017 [US1] Update individual window close onclick to use closeWindowScript instead of inline swaymsg (line ~4006) in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T018 [US1] Test individual window close per quickstart.md manual testing checklist
- [ ] T019 [US1] Test rapid close per quickstart.md manual testing checklist
- [ ] T020 [US1] Test project close per quickstart.md manual testing checklist

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 4 - Fix Return-to-Window Notification (Priority: P1)

**Goal**: Fix the "Return to Window" notification callback to correctly focus Claude Code terminal windows with proper project switching

**Independent Test**: Run Claude Code in a project terminal, wait for "Ready" notification, click "Return to Window", verify correct terminal is focused with correct project active

### Implementation for User Story 4

- [x] T021 [US4] Rewrite swaync-action-callback.sh to read current project from active-worktree.json in scripts/claude-hooks/swaync-action-callback.sh
- [x] T022 [US4] Update swaync-action-callback.sh to only switch projects if notification's project differs from current in scripts/claude-hooks/swaync-action-callback.sh
- [x] T023 [US4] Update swaync-action-callback.sh to use synchronous project switch (remove arbitrary sleep) in scripts/claude-hooks/swaync-action-callback.sh
- [x] T024 [US4] Update swaync-action-callback.sh to focus window immediately after project switch completes in scripts/claude-hooks/swaync-action-callback.sh
- [x] T025 [US4] Update swaync-action-callback.sh to verify window exists before focusing in scripts/claude-hooks/swaync-action-callback.sh
- [x] T026 [US4] Update swaync-action-callback.sh to show error notification if window no longer exists in scripts/claude-hooks/swaync-action-callback.sh
- [x] T027 [US4] Update swaync-action-callback.sh to clear badge file after successful focus in scripts/claude-hooks/swaync-action-callback.sh
- [x] T028 [US4] Update swaync-action-callback.sh to handle tmux window selection if applicable in scripts/claude-hooks/swaync-action-callback.sh
- [x] T029 [US4] Verify stop-notification.sh correctly captures I3PM_PROJECT_NAME in scripts/claude-hooks/stop-notification.sh
- [ ] T030 [US4] Test basic return-to-window flow per quickstart.md
- [ ] T031 [US4] Test cross-project return-to-window per quickstart.md
- [ ] T032 [US4] Test same-project return-to-window per quickstart.md

**Checkpoint**: At this point, User Stories 1 AND 4 (both P1) should both work independently

---

## Phase 5: User Story 2 - Debug Mode Toggle (Priority: P2)

**Goal**: Gate JSON and environment variable features behind debug toggle

**Independent Test**: Toggle debug mode on/off, verify JSON and environment variable UI elements appear/disappear accordingly

### Implementation for User Story 2

- [x] T033 [US2] Add debug toggle button to panel header widget in home-modules/desktop/eww-monitoring-panel.nix
- [x] T034 [US2] Gate JSON expand icon visibility with `:visible {debug_mode && ...}` in home-modules/desktop/eww-monitoring-panel.nix
- [x] T035 [US2] Gate JSON panel revealer visibility with `:visible {debug_mode && ...}` in home-modules/desktop/eww-monitoring-panel.nix
- [x] T036 [US2] Gate environment variable trigger icon visibility with `:visible {debug_mode && ...}` in home-modules/desktop/eww-monitoring-panel.nix
- [x] T037 [US2] Gate environment variable panel visibility with `:visible {debug_mode && ...}` in home-modules/desktop/eww-monitoring-panel.nix
- [x] T038 [US2] Add logic to collapse debug panels when debug_mode toggled OFF in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T039 [US2] Test debug mode toggle per quickstart.md manual testing checklist

**Checkpoint**: At this point, User Stories 1, 4, AND 2 should all work independently

---

## Phase 6: User Story 3 - Reduced Panel Width (Priority: P2)

**Goal**: Reduce default panel width by ~33%

**Independent Test**: Open panel, verify width is reduced (~307px non-ThinkPad, ~213px ThinkPad), verify content is still readable

### Implementation for User Story 3

- [x] T040 [P] [US3] Update panelWidth option default for non-ThinkPad from 460px to 307px in home-modules/desktop/eww-monitoring-panel.nix
- [x] T041 [P] [US3] Update panelWidth option default for ThinkPad from 320px to 213px in home-modules/desktop/eww-monitoring-panel.nix
- [x] T042 [US3] Review and adjust any fixed-width CSS that breaks at narrower width in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T043 [US3] Test panel width on non-ThinkPad configuration per quickstart.md
- [ ] T044 [US3] Test content readability at new width

**Checkpoint**: At this point, User Stories 1, 4, 2, AND 3 should all work independently

---

## Phase 7: User Story 5 - Cleaner UI Without Workspace Badges and Labels (Priority: P3)

**Goal**: Remove unused workspace badges and PRJ/WS/WIN text labels

**Independent Test**: Open panel, verify no workspace badges (WS5) visible on window rows, verify no PRJ/WS/WIN text in header count badges

### Implementation for User Story 5

- [x] T045 [US5] Remove workspace badge label from window row (lines ~3925-3926) in home-modules/desktop/eww-monitoring-panel.nix
- [x] T046 [US5] Remove "PRJ" text from header count badge (keep number only) in home-modules/desktop/eww-monitoring-panel.nix
- [x] T047 [US5] Remove "WS" text from header count badge (keep number only) in home-modules/desktop/eww-monitoring-panel.nix
- [x] T048 [US5] Remove "WIN" text from header count badge (keep number only) in home-modules/desktop/eww-monitoring-panel.nix
- [x] T049 [US5] Remove `.badge-workspace` CSS class definition in home-modules/desktop/eww-monitoring-panel.nix
- [x] T050 [US5] Verify PWA badges still display correctly in home-modules/desktop/eww-monitoring-panel.nix
- [x] T051 [US5] Verify notification badges still work correctly
- [ ] T052 [US5] Test UI cleanup per quickstart.md manual testing checklist

**Checkpoint**: All user stories should now be independently functional

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup

- [x] T053 Run full rebuild: `sudo nixos-rebuild dry-build --flake .#thinkpad` (and .#hetzner)
- [ ] T054 Apply changes: `sudo nixos-rebuild switch --flake .#thinkpad`
- [ ] T055 Restart eww monitoring panel: `systemctl --user restart eww-monitoring-panel`
- [ ] T056 Run complete quickstart.md validation (all test scenarios)
- [ ] T057 Clean up any stale lock files in /tmp/eww-close-*
- [ ] T058 Update spec.md status from Draft to Implemented

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - read and understand code
- **Foundational (Phase 2)**: Depends on Setup completion - creates shared infrastructure
- **User Story 1 (Phase 3)**: Depends on Foundational - P1 Critical
- **User Story 4 (Phase 4)**: Depends on Foundational - P1 Critical (can run in parallel with US1)
- **User Story 2 (Phase 5)**: Depends on Foundational - P2
- **User Story 3 (Phase 6)**: Depends on Foundational - P2 (can run in parallel with US2)
- **User Story 5 (Phase 7)**: Depends on Foundational - P3 (can run after P2 stories)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 4 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories, different files (scripts vs nix)
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Depends on T008 (debug_mode variable)
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 5 (P3)**: Can start after Foundational (Phase 2) - No dependencies on other stories

### Within Each User Story

- Core implementation before integration
- Test at checkpoints
- Story complete before moving to next priority

### Parallel Opportunities

- Setup tasks T005 and T006 can run in parallel (different files)
- User Story 1 (Phase 3) and User Story 4 (Phase 4) can run in parallel (different files: nix vs shell scripts)
- User Story 2 (Phase 5) and User Story 3 (Phase 6) can run in parallel (different sections of same file but no conflicts)
- T040 and T041 can run in parallel (different config sections)

---

## Parallel Example: User Stories 1 and 4 (Both P1)

```bash
# These can be implemented in parallel since they touch different files:

# User Story 1 tasks (eww-monitoring-panel.nix):
Task: "T009 Update closeWindowScript with rate limiting"
Task: "T012 Update closeWorktreeScript to replace lock file"

# User Story 4 tasks (scripts/claude-hooks/):
Task: "T021 Rewrite swaync-action-callback.sh"
Task: "T029 Verify stop-notification.sh captures I3PM_PROJECT_NAME"
```

---

## Implementation Strategy

### MVP First (User Stories 1 and 4 - Both P1 Critical)

1. Complete Phase 1: Setup (read existing code)
2. Complete Phase 2: Foundational (create closeWindowScript, add debug_mode variable)
3. Complete Phase 3: User Story 1 (window close reliability)
4. Complete Phase 4: User Story 4 (return-to-window fix)
5. **STOP and VALIDATE**: Test both P1 stories independently
6. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Window close works (MVP Part 1)
3. Add User Story 4 → Test independently → Return-to-window works (MVP Part 2)
4. Add User Story 2 → Test independently → Debug toggle works
5. Add User Story 3 → Test independently → Panel width reduced
6. Add User Story 5 → Test independently → UI cleaned up (Complete!)
7. Polish phase → Final validation

### Single Developer Strategy

1. Complete Setup + Foundational
2. Work on P1 stories (US1 and US4) - both critical
3. Work on P2 stories (US2 and US3) - enhancements
4. Work on P3 story (US5) - cosmetic cleanup
5. Polish and final validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Test on both hetzner-sway (reference) and thinkpad (variant) configurations if possible
- Dynamic resize feature is DEFERRED per research.md (eww limitation)
