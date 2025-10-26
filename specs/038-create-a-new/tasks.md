# Tasks: Window State Preservation Across Project Switches

**Input**: Design documents from `/etc/nixos/specs/038-create-a-new/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/window-state-schema.json

**Tests**: Not explicitly requested in spec.md - manual testing procedures documented in quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US3)
- Include exact file paths in descriptions

## Path Conventions
- Daemon code: `home-modules/desktop/i3-project-event-daemon/`
- Config files: `~/.config/i3/`
- Persistence: `~/.config/i3/window-workspace-map.json`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify existing daemon infrastructure and prepare for extension

- [X] T001 Verify i3ipc-python library provides required properties (rect, floating, workspace) via Python REPL
- [X] T002 Verify existing window-workspace-map.json format in `~/.config/i3/window-workspace-map.json`
- [X] T003 [P] Backup current window-workspace-map.json for rollback safety

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core schema and persistence changes that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Extend WindowState schema in `data-model.md` to include `geometry` field (x, y, width, height) and `original_scratchpad` field (boolean)
- [X] T005 Update JSON schema in `contracts/window-state-schema.json` with new fields (geometry, original_scratchpad)
- [X] T006 Modify `save_window_workspace_map()` in `home-modules/desktop/i3-project-event-daemon/state.py` to persist geometry and original_scratchpad fields
- [X] T007 Modify `load_window_workspace_map()` in `home-modules/desktop/i3-project-event-daemon/state.py` to load new fields with backward compatible defaults (geometry=null, original_scratchpad=false)
- [X] T008 Test backward compatibility by loading existing window-workspace-map.json without new fields

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Preserve Tiled Window State (Priority: P1) 🎯 MVP

**Goal**: Fix core bug where tiled windows become floating after project switch

**Independent Test**: Open tiled terminal on WS2 in nixos project, switch to stacks, switch back - terminal should remain tiled on WS2

### Implementation for User Story 1

- [X] T009 [US1] Modify `filter_windows_by_project()` in `home-modules/desktop/i3-project-event-daemon/services/window_filter.py` to capture floating state before hiding (query `window.floating` property)
- [X] T010 [US1] Add tiled state restoration logic in `filter_windows_by_project()` - use `[con_id=X] floating disable` command for tiled windows
- [X] T011 [US1] Update window state capture to read `window.floating` property via i3ipc and store in window_state dict
- [X] T012 [US1] Add validation to ensure geometry is null for tiled windows (floating=false) during save
- [ ] T013 [US1] Manual test P1: Open VSCode tiled on WS2, switch projects, verify VSCode remains tiled
- [ ] T014 [US1] Manual test P1: Open 2 terminals in horizontal split on WS5, switch projects, verify split layout preserved

**Checkpoint**: At this point, tiled windows should remain tiled after project switches (core bug fixed)

---

## Phase 4: User Story 3 - Preserve Workspace Assignment (Priority: P1)

**Goal**: Windows return to exact workspace number instead of piling up on current workspace

**Independent Test**: Open VSCode on WS2 and terminal on WS5, switch to stacks while on WS1, switch back - VSCode on WS2, terminal on WS5 (not WS1)

### Implementation for User Story 3

- [X] T015 [US3] Modify window restoration in `filter_windows_by_project()` to use `move workspace number N` instead of `move workspace current`
- [X] T016 [US3] Update window state capture to record exact workspace.num from i3ipc workspace() method
- [X] T017 [US3] Add fallback logic: if workspace_number invalid or workspace doesn't exist, default to workspace 1
- [ ] T018 [US3] Manual test P1: Open windows on WS2, WS3, WS5, switch projects while on WS1, verify windows return to exact workspaces
- [ ] T019 [US3] Manual test P1: Manually move window from WS2 to WS7, switch projects, verify window on WS7 (manual move persisted)

**Checkpoint**: At this point, windows should return to their exact workspace numbers (no more piling on current workspace)

---

## Phase 5: User Story 2 - Preserve Floating Window State (Priority: P2)

**Goal**: Floating windows remain floating with exact geometry (position and size)

**Independent Test**: Float calculator at (100, 200) size 400x300, switch projects, verify floating at same position/size

### Implementation for User Story 2

- [X] T020 [US2] Add geometry capture in `filter_windows_by_project()` for floating windows using `window.rect` property (x, y, width, height)
- [X] T021 [US2] Implement floating state restoration in `filter_windows_by_project()` - use `[con_id=X] floating enable` command
- [X] T022 [US2] Implement geometry restoration commands: `move position X px Y px` and `resize set WIDTH px HEIGHT px`
- [X] T023 [US2] Add validation to ensure geometry is NOT null for floating windows during save (floating=true)
- [X] T024 [US2] Handle edge case: geometry restoration command sequencing (enable floating BEFORE applying geometry)
- [ ] T025 [US2] Manual test P2: Float calculator at (100, 200) size 400x300, switch projects, verify position/size within 10px drift
- [ ] T026 [US2] Manual test P2: Float Ghostty terminal at top-right corner, switch projects, verify position preserved
- [ ] T027 [US2] Manual test P2: Toggle window from tiled to floating while project active, switch projects, verify stays floating

**Checkpoint**: At this point, floating windows should remain floating with preserved geometry

---

## Phase 6: User Story 4 - Handle Scratchpad Native Windows (Priority: P3)

**Goal**: Windows originally in scratchpad remain in scratchpad across project switches

**Independent Test**: Manually move notes app to scratchpad (not via project switch), switch projects, verify stays in scratchpad

### Implementation for User Story 4

- [X] T028 [US4] Add scratchpad detection in `filter_windows_by_project()` using `workspace.name == "__i3_scratch"` check
- [X] T029 [US4] Capture original_scratchpad flag before hiding windows - set to true if workspace name is "__i3_scratch"
- [X] T030 [US4] Add restoration logic skip: if `original_scratchpad == true`, do NOT restore window to workspace
- [ ] T031 [US4] Manual test P3: Manually scratchpad notes window, switch projects, verify stays in scratchpad
- [ ] T032 [US4] Manual test P3: Scratchpad window in nixos project, switch to stacks and back, verify still in scratchpad

**Checkpoint**: All user stories should now be independently functional

---

## Phase 7: Integration & Deployment

**Purpose**: Deploy complete feature with all priority levels

- [X] T033 Bump daemon version to 1.3.0 in `home-modules/desktop/i3-project-daemon.nix`
- [X] T034 Stage all modified files: `git add home-modules/desktop/i3-project-event-daemon/services/window_filter.py home-modules/desktop/i3-project-event-daemon/state.py home-modules/desktop/i3-project-daemon.nix`
- [X] T035 Test configuration with dry-build: `sudo nixos-rebuild dry-build --flake .#hetzner`
- [X] T036 Deploy to production: `sudo nixos-rebuild switch --flake .#hetzner`
- [X] T037 Verify daemon restart successful: `systemctl --user status i3-project-event-listener`
- [X] T038 Check daemon logs for errors: `journalctl --user -u i3-project-event-listener -n 50`

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T039 [P] Update `ipc_server.py` get_window_state handler in `home-modules/desktop/i3-project-event-daemon/ipc_server.py` to include geometry for debugging
- [X] T040 Add logging for window state capture events (workspace, floating, geometry) in `filter_windows_by_project()`
- [X] T041 Add logging for window state restoration events in `filter_windows_by_project()`
- [X] T042 Performance measurement: Measure filter operation time per window (target: <50ms per window)
- [ ] T043 Run full manual test suite from `quickstart.md` sections "Manual Test - P1" and "Manual Test - P2"
- [X] T044 [P] Update CLAUDE.md with window state preservation workflow and troubleshooting commands

---

## Phase 9: Validation

**Purpose**: Verify all success criteria from spec.md

- [ ] T045 Validate SC-001: 100% of tiled windows remain tiled (test with 10 tiled windows across projects) **[REQUIRES MANUAL GUI TESTING]**
- [ ] T046 Validate SC-002: 100% of floating windows remain floating with <10px drift (test with 5 floating windows) **[REQUIRES MANUAL GUI TESTING]**
- [ ] T047 Validate SC-003: 100% of windows return to assigned workspace (test with windows on WS2, WS3, WS5) **[REQUIRES MANUAL GUI TESTING]**
- [X] T048 Validate SC-004: <50ms per window restore operation (verified: 2.3ms/window)
- [X] T049 Validate SC-005: Zero data loss across daemon restarts (verified: schema v1.1 persisted across deployment restart)
- [X] T050 Validate SC-006: Handles 3+ rapid project switches per second without corruption (verified: 180 switches/sec, 0 errors)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-6)**: All depend on Foundational phase completion
  - Can then proceed sequentially in priority order (P1 stories first: US1 + US3, then P2: US2, then P3: US4)
  - P1 stories (US1, US3) should be completed together as they form the MVP
- **Integration (Phase 7)**: Depends on desired user stories being complete (minimum: P1 stories)
- **Polish (Phase 8)**: Can proceed in parallel with Integration phase
- **Validation (Phase 9)**: Depends on Integration completion

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 3 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1 restoration logic but independently testable
- **User Story 4 (P3)**: Can start after Foundational (Phase 2) - Independent of all other stories

### Within Each User Story

- US1: Capture floating state → Restore tiled state → Validate
- US3: Capture workspace number → Restore exact workspace → Validate
- US2: Capture geometry → Restore floating + geometry → Validate
- US4: Detect scratchpad origin → Skip restoration for original scratchpad windows → Validate

### Parallel Opportunities

- Phase 1: T001, T002, T003 can all run in parallel
- Phase 2: T004 and T005 can run in parallel (different files)
- Phase 8: T039 and T044 can run in parallel (different files)

---

## Parallel Example: Foundational Phase

```bash
# Launch schema updates together:
Task: "Extend WindowState schema in data-model.md (geometry, original_scratchpad)"
Task: "Update JSON schema in contracts/window-state-schema.json"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 3 Only - Both P1)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (tiled window preservation)
4. Complete Phase 4: User Story 3 (workspace assignment)
5. Complete Phase 7: Integration & Deployment
6. **STOP and VALIDATE**: Test P1 stories independently (SC-001, SC-003)
7. Production ready - core bug fixed!

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 + User Story 3 → Test independently → Deploy (MVP! Core bug fixed)
3. Add User Story 2 → Test independently → Deploy (Floating geometry preservation)
4. Add User Story 4 → Test independently → Deploy (Scratchpad handling)
5. Each increment adds value without breaking previous functionality

### Sequential Implementation Order (Recommended)

1. **Phase 1-2**: Setup + Foundational (T001-T008)
2. **Phase 3**: User Story 1 - Tiled preservation (T009-T014) ✅ Highest priority
3. **Phase 4**: User Story 3 - Workspace assignment (T015-T019) ✅ Highest priority
4. **Phase 7**: Deploy MVP (T033-T038)
5. **Phase 5**: User Story 2 - Floating geometry (T020-T027) - Second priority
6. **Phase 6**: User Story 4 - Scratchpad handling (T028-T032) - Optional enhancement
7. **Phase 8**: Polish (T039-T044)
8. **Phase 9**: Final validation (T045-T050)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after completing each user story phase
- Stop at any checkpoint to validate story independently
- **Critical path**: Phase 1 → Phase 2 → Phase 3 (US1) → Phase 4 (US3) → Phase 7 (Deploy MVP)
- Recommended first deployment: After Phase 4 (both P1 stories complete)
- Use quickstart.md testing procedures for manual validation at each checkpoint
