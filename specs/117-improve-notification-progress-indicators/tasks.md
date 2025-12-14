# Tasks: Improve Notification Progress Indicators

**Input**: Design documents from `/specs/117-improve-notification-progress-indicators/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/badge-state.md, quickstart.md

**Tests**: Not explicitly requested - test tasks omitted. Use quickstart.md manual tests to verify.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is a NixOS configuration project:
- **Hook scripts**: `scripts/claude-hooks/`
- **Nix modules**: `home-modules/`
- **Daemon code**: `home-modules/desktop/i3-project-event-daemon/`
- **Tests**: `tests/117-notification-indicators/` (new directory)

---

## Phase 1: Setup (Cleanup & Foundation)

**Purpose**: Remove legacy code and establish clean foundation per Constitution XII (Forward-Only Development)

- [x] T001 Remove `scripts/claude-hooks/badge-ipc-client.sh` entirely (per R1: File-Only decision)
- [x] T002 [P] Remove IPC calls from `scripts/claude-hooks/prompt-submit-notification.sh` (lines 79-84 per research.md)
- [x] T003 [P] Remove IPC calls from `scripts/claude-hooks/stop-notification.sh` (lines 93-98 per research.md)
- [x] T004 Remove focused-window fallback from `scripts/claude-hooks/prompt-submit-notification.sh` (per R2: Single detection)
- [x] T005 [P] Remove focused-window fallback from `scripts/claude-hooks/stop-notification.sh` (per R2: Single detection)

---

## Phase 2: Foundational (Badge Infrastructure)

**Purpose**: Core badge infrastructure required by ALL user stories

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T006 Create badge directory at `$XDG_RUNTIME_DIR/i3pm-badges/` in systemd service startup (if not exists)
- [x] T007 Add Pydantic Badge model to `home-modules/desktop/i3-project-event-daemon/badge_service.py` per data-model.md schema
- [x] T008 Add badge file read/write utilities to `badge_service.py` implementing contracts/badge-state.md operations
- [x] T009 Add constants BADGE_MIN_AGE_FOR_DISMISS=1.0, BADGE_MAX_AGE=300 to `badge_service.py`

**Checkpoint**: Badge infrastructure ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Real-Time Progress Visibility (Priority: P1) MVP

**Goal**: Badge shows working/stopped state synchronized with Claude Code within 600ms

**Independent Test**: Run Claude Code command, switch window, verify spinner appears within 600ms of prompt submit, bell appears within 600ms of completion

### Implementation for User Story 1

- [x] T010 [US1] Simplify `scripts/claude-hooks/prompt-submit-notification.sh` to file-only badge creation with working state
- [x] T011 [US1] Simplify `scripts/claude-hooks/stop-notification.sh` to file-only badge update to stopped state
- [x] T012 [US1] Ensure badge filename uses window_id from tmux PID detection (single method, fail if detection fails)
- [x] T013 [US1] Update `home-modules/desktop/eww-monitoring-panel.nix` to read badge state via inotify watch
- [x] T014 [US1] Add spinner animation (pulsating) for `state: "working"` in EWW widget
- [x] T015 [US1] Add bell icon with count for `state: "stopped"` in EWW widget
- [x] T016 [US1] Add dimmed spinner display when badge window is currently focused (reduced opacity)
- [x] T017 [US1] Add has_working_badge flag to monitoring data for global indicator

**Checkpoint**: User Story 1 complete - badges visually track Claude Code state in real-time

---

## Phase 4: User Story 2 - Focus-Aware Notification Dismissal (Priority: P1) MVP

**Goal**: Badges auto-clear when user focuses the window (after 1s minimum age)

**Independent Test**: Let Claude complete, see bell badge, focus terminal window, verify badge disappears within 500ms

### Implementation for User Story 2

- [x] T018 [US2] Add window focus event handler to `home-modules/desktop/i3-project-event-daemon/handlers.py`
- [x] T019 [US2] Implement badge age check (>1 second) before focus dismissal in handlers.py
- [x] T020 [US2] Implement badge file deletion on focus in handlers.py using badge_service utilities
- [x] T021 [US2] Add logging for focus-dismiss events in handlers.py

**Checkpoint**: User Story 2 complete - badges auto-clear on focus

---

## Phase 5: User Story 3 - Desktop Notification with Direct Navigation (Priority: P2)

**Goal**: Desktop notification with "Return to Window" action that focuses correct terminal

**Independent Test**: Run Claude task, switch workspaces, wait for notification, click action, verify correct terminal focused

### Implementation for User Story 3

- [x] T022 [US3] Ensure `scripts/claude-hooks/stop-notification.sh` sends desktop notification with action button
- [x] T023 [US3] Store window_id in notification hints/metadata for action callback
- [x] T024 [US3] Update `scripts/claude-hooks/swaync-action-callback.sh` to focus window using stored window_id
- [x] T025 [US3] Update `swaync-action-callback.sh` to clear badge file after focusing window
- [x] T026 [US3] Add error handling for "window already closed" case with brief error notification

**Checkpoint**: User Story 3 complete - notification action navigates to correct window

---

## Phase 6: User Story 4 - Concise Notification Content (Priority: P2)

**Goal**: Notifications show only "Claude Code Ready" + project name (or "Awaiting input")

**Independent Test**: Receive notification, verify message is 2 lines or less, shows project name clearly

### Implementation for User Story 4

- [x] T027 [US4] Simplify notification title to "Claude Code Ready" in `scripts/claude-hooks/stop-notification.sh`
- [x] T028 [US4] Simplify notification body to project name only (format: "project-name") in stop-notification.sh
- [x] T029 [US4] Handle no-project case with body "Awaiting input" in stop-notification.sh
- [x] T030 [US4] Remove verbose tmux session:window info from notification

**Checkpoint**: User Story 4 complete - notifications are concise and scannable

---

## Phase 7: User Story 5 - Stale Badge Cleanup (Priority: P3)

**Goal**: Orphaned badges automatically removed within 30 seconds

**Independent Test**: Close terminal with badge, verify badge removed from monitoring panel within 30 seconds

### Implementation for User Story 5

- [x] T031 [US5] Add `cleanup_orphaned_badges(valid_window_ids)` function to `monitoring_data.py`
- [x] T032 [US5] Integrate orphan cleanup into monitoring refresh cycle in monitoring_data.py
- [x] T033 [US5] Add `cleanup_stale_badges()` TTL-based cleanup function (5 min max age) to monitoring_data.py
- [x] T034 [US5] Add logging for cleanup operations (count removed, reason)
- [x] T035 [US5] Ensure badge directory is cleared on system startup (no stale badges persist across sessions)

**Checkpoint**: User Story 5 complete - orphaned badges auto-cleaned

---

## Phase 8: Polish & Integration

**Purpose**: Cross-cutting concerns and final integration

- [x] T036 Update `home-modules/ai-assistants/claude-code.nix` hook references if paths changed
- [x] T037 Add graceful degradation when daemon unavailable (badge hooks still create files)
- [x] T038 [P] Create test directory `tests/117-notification-indicators/` with README
- [x] T039 [P] Run quickstart.md manual tests to verify all success criteria
- [x] T040 Remove any remaining legacy code paths not covered by earlier tasks

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - starts immediately
- **Foundational (Phase 2)**: Depends on Phase 1 - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2
- **User Story 2 (Phase 4)**: Depends on Phase 2 (can run parallel with US1)
- **User Story 3 (Phase 5)**: Depends on Phase 2 (can run parallel with US1, US2)
- **User Story 4 (Phase 6)**: Depends on Phase 2 (can run parallel with others)
- **User Story 5 (Phase 7)**: Depends on Phase 2 (can run parallel with others)
- **Polish (Phase 8)**: Depends on all user stories complete

### User Story Dependencies

All user stories depend only on the Foundational phase (Phase 2):

- **US1**: Independent - no cross-story dependencies
- **US2**: Independent - uses badge_service from Phase 2
- **US3**: Slightly related to US1/US2 (assumes badge exists), but independently testable
- **US4**: Independent - only modifies notification content
- **US5**: Independent - cleanup operates on any badges

### Within Each Phase

- T001 must complete before T002-T005 (removes script that others reference)
- T006-T009 can run in parallel (different files)
- Within US phases: tasks are sequential (earlier tasks set up later ones)

### Parallel Opportunities

**Phase 1 (after T001)**:
```bash
# Run in parallel:
Task: T002 "Remove IPC from prompt-submit-notification.sh"
Task: T003 "Remove IPC from stop-notification.sh"
Task: T005 "Remove fallback from stop-notification.sh"
```

**Phase 2**:
```bash
# Run in parallel:
Task: T007 "Add Pydantic Badge model"
Task: T008 "Add badge file utilities"
Task: T009 "Add constants"
```

**After Phase 2 (all user stories can start)**:
```bash
# Different team members can work on:
Team A: Phase 3 (US1 - Progress visibility)
Team B: Phase 4 (US2 - Focus dismissal)
Team C: Phase 5-6 (US3-4 - Notifications)
Team D: Phase 7 (US5 - Cleanup)
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Cleanup legacy code
2. Complete Phase 2: Badge infrastructure
3. Complete Phase 3: US1 - Real-time badges
4. Complete Phase 4: US2 - Focus dismissal
5. **STOP and VALIDATE**: Test MVP per quickstart.md
6. Deploy if ready - core value delivered

### Incremental Delivery

1. Phase 1-2 → Foundation ready
2. Add US1 → Test → Deploy (badges work!)
3. Add US2 → Test → Deploy (auto-dismiss works!)
4. Add US3-4 → Test → Deploy (notifications improved!)
5. Add US5 → Test → Deploy (cleanup handles edge cases)

### Single Developer Strategy

1. Complete phases sequentially: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8
2. P1 user stories (US1, US2) deliver core value first
3. P2 (US3, US4) improve experience
4. P3 (US5) handles edge cases

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- US1 and US2 are both P1 priority - implement together for MVP
- Constitution XII: Remove legacy code first (Phase 1) before adding new
- File-only badges per R1 decision - no IPC anywhere
- Single window detection method per R2 - fail explicitly if detection fails
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
