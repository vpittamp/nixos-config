# Tasks: Multi-Monitor Window Management Enhancements

**Input**: Design documents from `/specs/083-multi-monitor-window-management/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are NOT included in this task list (not explicitly requested in specification).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Paths use project structure from plan.md

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create test directory structure per plan at tests/083-multi-monitor-window-management/
- [x] T002 [P] Create Pydantic models file for data types at home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T003 [P] Add feature documentation to specs/083-multi-monitor-window-management/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Implement MonitorProfile Pydantic models in home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T005 [P] Implement ProfileEvent Pydantic models in home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T006 [P] Implement MonitorState and OutputDisplayState models in home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T007 Create EwwPublisher service skeleton in home-modules/desktop/i3-project-event-daemon/eww_publisher.py
- [x] T008 Create MonitorProfileService skeleton in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T009 Add profile event types to EventBuffer in home-modules/desktop/i3-project-event-daemon/daemon.py

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Real-Time Monitor State Feedback (Priority: P1) 🎯 MVP

**Goal**: Update top bar within 100ms of profile switch, replacing 2s polling with event-driven updates

**Independent Test**: Switch profiles via Mod4+Control+m and observe top bar updates within 100ms

### Implementation for User Story 1

- [x] T010 [US1] Implement Sway output event subscription in home-modules/desktop/i3-project-event-daemon/handlers.py
- [x] T011 [US1] Implement eww update command execution in home-modules/desktop/i3-project-event-daemon/eww_publisher.py
- [x] T012 [US1] Create monitor_state variable update function in home-modules/desktop/i3-project-event-daemon/eww_publisher.py
- [x] T013 [US1] Connect output event handler to EwwPublisher in home-modules/desktop/i3-project-event-daemon/daemon.py
- [x] T014 [P] [US1] Define monitor_state defvar in home-modules/desktop/eww-top-bar/eww.yuck
- [x] T015 [P] [US1] Create monitor status widget displaying H1/H2/H3 indicators in home-modules/desktop/eww-top-bar/eww.yuck
- [x] T016 [US1] Add monitor widget styling (active/inactive states) in home-modules/desktop/eww-top-bar/eww.scss
- [ ] T017 [US1] Remove polling-based active_outputs variable from Eww config in home-modules/desktop/eww-top-bar.nix
- [x] T018 [US1] Integrate EwwPublisher into daemon startup in home-modules/desktop/i3-project-event-daemon/daemon.py

**Checkpoint**: At this point, User Story 1 should be fully functional - top bar updates in <100ms

---

## Phase 4: User Story 2 - Monitor Profile Name Display (Priority: P2)

**Goal**: Display current profile name (single/dual/triple) in top bar alongside monitor indicators

**Independent Test**: Switch between profiles and verify profile name appears and updates in top bar

### Implementation for User Story 2

- [x] T019 [US2] Add profile_name field to MonitorState in home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T020 [US2] Read current profile from monitor-profile.current in MonitorProfileService at home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T021 [US2] Include profile name in Eww monitor_state updates in home-modules/desktop/i3-project-event-daemon/eww_publisher.py
- [x] T022 [P] [US2] Create profile name label widget in home-modules/desktop/eww-top-bar/eww.yuck
- [x] T023 [P] [US2] Style profile name label (font, color, position) in home-modules/desktop/eww-top-bar/eww.scss
- [x] T024 [US2] Watch monitor-profile.current for changes and update Eww in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - real-time indicators plus profile name

---

## Phase 5: User Story 3 - Atomic Profile Switching (Priority: P2)

**Goal**: Prevent race conditions and duplicate workspace reassignments during profile switches

**Independent Test**: Rapidly switch profiles and verify workspaces end up on correct monitors without duplicates

### Implementation for User Story 3

- [x] T025 [US3] Implement debounce task cancellation pattern in home-modules/desktop/i3-project-event-daemon/handlers.py
- [x] T026 [US3] Add profile_switch_in_progress guard to StateManager in home-modules/desktop/i3-project-event-daemon/state.py
- [x] T027 [US3] Implement atomic output state update in MonitorProfileService at home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T028 [US3] Batch workspace reassignment commands with asyncio.gather in home-modules/desktop/i3-project-event-daemon/handlers.py
- [x] T029 [US3] Emit structured ProfileEvents for each switch phase in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T030 [US3] Implement rollback on partial failure in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T031 [US3] Send notification on profile switch failure via notify-send in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py

**Checkpoint**: At this point, profile switches are atomic with zero duplicate reassignments

---

## Phase 6: User Story 4 - Daemon-Owned State Management (Priority: P3)

**Goal**: Consolidate state management so daemon owns output-states.json, eliminating shell script logic

**Independent Test**: Trigger profile switch and verify daemon writes output-states.json, not shell script

### Implementation for User Story 4

- [x] T032 [US4] Implement output-states.json writing in MonitorProfileService at home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T033 [US4] Add profile file watcher for monitor-profile.current changes in home-modules/desktop/i3-project-event-daemon/config.py
- [x] T034 [US4] Handle profile change notification from script in daemon at home-modules/desktop/i3-project-event-daemon/daemon.py
- [x] T035 [US4] Remove embedded Python for output-states.json from set-monitor-profile.sh at home-modules/desktop/scripts/set-monitor-profile.sh
- [x] T036 [US4] Simplify set-monitor-profile.sh to only write monitor-profile.current at home-modules/desktop/scripts/set-monitor-profile.sh
- [x] T037 [US4] Add daemon initialization to read current profile on startup in home-modules/desktop/i3-project-event-daemon/daemon.py
- [x] T038 [US4] Handle missing profile gracefully with fallback to default in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py

**Checkpoint**: Shell scripts only do Sway IPC; daemon owns all state files

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T039 [P] Update quickstart.md with final usage instructions at specs/083-multi-monitor-window-management/quickstart.md
- [x] T040 [P] Update CLAUDE.md with feature 083 documentation at CLAUDE.md
- [x] T041 Add i3pm diagnose events --type profile_switch command support in home-modules/tools/i3pm-cli/
- [x] T042 Run nixos-rebuild dry-build to validate configuration
- [ ] T043 Test full workflow: profile switch → top bar update → workspace assignment
- [ ] T044 Verify <100ms latency target with timing measurements
- [ ] T045 Document any edge cases discovered during testing

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can proceed in priority order (P1 → P2 → P3)
  - US1 and US2 have no dependencies on each other
  - US3 depends on US1 (needs event infrastructure)
  - US4 depends on US1 (needs Eww publisher)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational - Builds on US1's EwwPublisher but is independently testable
- **User Story 3 (P2)**: Depends on US1's event infrastructure - Must complete after US1
- **User Story 4 (P3)**: Depends on US1's EwwPublisher - Can start after US1

### Within Each User Story

- Models before services
- Services before Eww widgets
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- T014/T015 (Eww defvar and widget) can run in parallel
- T022/T023 (profile label widget and styling) can run in parallel
- All Polish tasks marked [P] can run in parallel

---

## Parallel Example: User Story 1

```bash
# After T013 completes (EwwPublisher connected), launch Eww tasks in parallel:
Task: "T014 [P] [US1] Define monitor_state defvar in home-modules/desktop/eww-top-bar/eww.yuck"
Task: "T015 [P] [US1] Create monitor status widget displaying H1/H2/H3 indicators in home-modules/desktop/eww-top-bar/eww.yuck"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test profile switch → top bar updates in <100ms
5. Deploy/demo if ready - this alone provides significant UX improvement

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test <100ms latency → Deploy (MVP!)
3. Add User Story 2 → Test profile name display → Deploy
4. Add User Story 3 → Test atomic switching → Deploy
5. Add User Story 4 → Test daemon state ownership → Deploy
6. Each story adds value without breaking previous stories

### Recommended Execution Order

For single developer, execute in this order:
1. T001-T003 (Setup)
2. T004-T009 (Foundational)
3. T010-T018 (User Story 1 - MVP)
4. **Validate MVP**: Test profile switching with timing
5. T019-T024 (User Story 2)
6. T025-T031 (User Story 3)
7. T032-T038 (User Story 4)
8. T039-T045 (Polish)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Performance target: <100ms for US1, <500ms end-to-end for US3
