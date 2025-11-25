# Implementation Tasks: Visual Notification Badges in Monitoring Panel

**Feature**: 095-visual-notification-badges | **Date**: 2025-11-24
**Branch**: `095-visual-notification-badges`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Overview

This feature implements visual notification badges in the Eww monitoring panel to provide persistent indicators when terminal windows require attention. Badges appear as bell icons with counts, clearing automatically on focus.

**MVP Scope**: User Story 1 (P1) - Visual Badge on Window Awaiting Input

**Total Tasks**: 31 tasks
**Parallelizable Tasks**: 18 tasks (58%)
**User Stories**: 4 (P1, P2, P3, P4)

---

## Phase 1: Setup & Prerequisites

**Goal**: Prepare project structure and verify existing dependencies

**Tasks**:

- [ ] T001 Verify Python 3.11+ available and i3pm daemon dependencies installed (i3ipc.aio, Pydantic, pytest-asyncio)
- [ ] T002 Create test directory structure: tests/095-visual-notification-badges/{unit,integration,sway-tests}
- [ ] T003 Verify Eww monitoring panel (Feature 085) is functional and monitoring_panel_publisher.py exists
- [ ] T004 Verify Feature 090 Claude Code hooks exist in scripts/claude-hooks/stop-notification.sh
- [ ] T005 Create badge-ipc-client.sh helper script skeleton in scripts/claude-hooks/badge-ipc-client.sh

---

## Phase 2: Foundational Components

**Goal**: Implement core badge data models and service (blocking prerequisites for all user stories)

**Tasks**:

- [ ] T006 [P] Create WindowBadge Pydantic model in home-modules/desktop/i3-project-event-daemon/badge_service.py
- [ ] T007 [P] Create BadgeState Pydantic model with dict[int, WindowBadge] in badge_service.py
- [ ] T008 [P] Implement WindowBadge.increment() method with 9999 cap in badge_service.py
- [ ] T009 [P] Implement WindowBadge.display_count() method ("9+" for >9) in badge_service.py
- [ ] T010 [P] Implement BadgeState.create_badge(window_id, source) method in badge_service.py
- [ ] T011 [P] Implement BadgeState.clear_badge(window_id) method in badge_service.py
- [ ] T012 [P] Implement BadgeState.has_badge(window_id) method in badge_service.py
- [ ] T013 [P] Implement BadgeState.get_badge(window_id) method in badge_service.py
- [ ] T014 [P] Implement BadgeState.to_eww_format() serialization method in badge_service.py
- [ ] T015 Integrate BadgeState as instance variable in i3pm daemon (home-modules/desktop/i3-project-event-daemon/daemon.py)
- [ ] T016 [P] Write unit tests for WindowBadge model in tests/095-visual-notification-badges/unit/test_badge_models.py
- [ ] T017 [P] Write unit tests for BadgeState operations in tests/095-visual-notification-badges/unit/test_badge_service.py
- [ ] T018 Run unit tests and verify all badge service operations pass (pytest tests/095-visual-notification-badges/unit/)

---

## Phase 3: User Story 1 (P1) - Visual Badge on Window Awaiting Input

**Priority**: P1 (MVP - Core Feature)

**Goal**: Badge appears on window item when notification fires, clears on focus

**Independent Test Criteria**:
- Trigger Claude Code stop hook → Badge appears on correct window item in monitoring panel
- Click badged window item → Terminal focused, badge clears
- Focus badged window via Alt+Tab → Badge clears immediately
- Close badged window → Badge state cleaned up without errors

**Tasks**:

### IPC Interface

- [ ] T019 [P] [US1] Add create_badge JSON-RPC method to IPC server in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [ ] T020 [P] [US1] Add clear_badge JSON-RPC method to IPC server in ipc_server.py
- [ ] T021 [P] [US1] Add get_badge_state JSON-RPC method to IPC server in ipc_server.py
- [ ] T022 [P] [US1] Implement window ID validation (GET_TREE query) in create_badge handler in ipc_server.py
- [ ] T023 [P] [US1] Write integration tests for badge IPC endpoints in tests/095-visual-notification-badges/integration/test_badge_ipc.py

### Event Handling

- [ ] T024 [US1] Add window::focus event subscription in home-modules/desktop/i3-project-event-daemon/handlers.py
- [ ] T025 [US1] Implement on_window_focus handler to clear badges in handlers.py
- [ ] T026 [US1] Add window::close event handler to clean up orphaned badges in handlers.py
- [ ] T027 [P] [US1] Write integration tests for focus-triggered badge clearing in tests/095-visual-notification-badges/integration/test_badge_focus_clearing.py

### Monitoring Panel Integration

- [ ] T028 [US1] Modify monitoring_panel_publisher.py to include badge state in panel_state JSON (home-modules/desktop/i3-project-event-daemon/monitoring_panel_publisher.py)
- [ ] T029 [US1] Add badge data to transform_monitoring_data() function in monitoring_panel_publisher.py
- [ ] T030 [US1] Trigger panel state push after badge create/clear operations in monitoring_panel_publisher.py

### Eww Widget UI

- [ ] T031 [US1] Add badge widget overlay to window-item in home-modules/desktop/eww-monitoring-panel.nix (Yuck syntax: defwidget window-badge)
- [ ] T032 [US1] Implement get_badge_count() Eww helper function to extract badge count from panel_state.badges in eww-monitoring-panel.nix
- [ ] T033 [US1] Add window-badge CSS styling (Catppuccin Mocha Mauve, bell icon, positioning) in eww-monitoring-panel.nix
- [ ] T034 [US1] Add conditional :visible to badge widget (only show when count > 0) in eww-monitoring-panel.nix

### Badge IPC Client Script

- [ ] T035 [P] [US1] Implement badge-ipc create command in scripts/claude-hooks/badge-ipc-client.sh
- [ ] T036 [P] [US1] Implement badge-ipc clear command in scripts/claude-hooks/badge-ipc-client.sh
- [ ] T037 [P] [US1] Implement badge-ipc get-state command in scripts/claude-hooks/badge-ipc-client.sh
- [ ] T038 [US1] Add badge IPC call to scripts/claude-hooks/stop-notification.sh after notify-send

### UI Testing

- [ ] T039 [P] [US1] Create sway-test for badge appearance (tests/095-visual-notification-badges/sway-tests/test_badge_appearance.json - partial mode)
- [ ] T040 [P] [US1] Create sway-test for badge clearing on focus (tests/095-visual-notification-badges/sway-tests/test_badge_clearing.json - action + state validation)
- [ ] T041 [US1] Run all User Story 1 tests and verify acceptance scenarios pass

**User Story 1 Complete**: Badge system functional for basic notification workflow (create → display → clear)

---

## Phase 4: User Story 2 (P2) - Badge Persistence Across Panel Toggles

**Priority**: P2

**Goal**: Badges persist across panel hide/show cycles

**Independent Test Criteria**:
- Create badge → Close panel (Mod+M) → Reopen panel → Badge still visible
- Badge state survives 100% of panel toggles during 30-minute session

**Tasks**:

- [ ] T042 [P] [US2] Write integration test for badge persistence across panel toggles in tests/095-visual-notification-badges/integration/test_badge_persistence.py
- [ ] T043 [P] [US2] Verify badge state remains in daemon memory when panel closes (no cleanup on panel hide)
- [ ] T044 [US2] Test badge restoration after panel reopen (read from daemon state, repopulate UI)
- [ ] T045 [US2] Document badge loss on daemon restart (acceptable degradation) in quickstart.md troubleshooting section

**User Story 2 Complete**: Badge state reliably persists across UI state changes

---

## Phase 5: User Story 3 (P3) - Badge Integration with Project Switching

**Priority**: P3

**Goal**: Project-level badge aggregation in Projects tab

**Independent Test Criteria**:
- Project A has 2 badged windows → Projects tab shows "2" aggregate count
- Click project entry → System switches to project, focuses first badged window

**Tasks**:

- [ ] T046 [P] [US3] Implement BadgeState.get_project_badge_count(project_name) in badge_service.py
- [ ] T047 [P] [US3] Query i3pm daemon for project window IDs in badge_service.py
- [ ] T048 [P] [US3] Sum badge counts for all windows in project in badge_service.py
- [ ] T049 [US3] Add project-level badge counts to monitoring panel Projects tab in eww-monitoring-panel.nix
- [ ] T050 [US3] Implement click handler to switch project and focus first badged window in eww-monitoring-panel.nix
- [ ] T051 [P] [US3] Create sway-test for project-level badge aggregation (tests/095-visual-notification-badges/sway-tests/test_badge_project_aggregation.json)
- [ ] T052 [US3] Run User Story 3 tests and verify project badge aggregation works

**User Story 3 Complete**: Project-level badge visibility enables cross-project task discovery

---

## Phase 6: User Story 4 (P4) - Multi-Notification Badge Count

**Priority**: P4

**Goal**: Badge count increments for multiple notifications on same window

**Independent Test Criteria**:
- Trigger 2 notifications on same window → Badge shows "2"
- Focus window → Badge clears completely (all notifications addressed)
- Badge count > 9 → Display shows "9+"

**Tasks**:

- [ ] T053 [P] [US4] Write unit test for badge count increment behavior in tests/095-visual-notification-badges/unit/test_badge_service.py
- [ ] T054 [P] [US4] Write unit test for display_count() "9+" overflow in tests/095-visual-notification-badges/unit/test_badge_models.py
- [ ] T055 [US4] Verify badge increment in IPC create_badge (second call → increment, not replace)
- [ ] T056 [US4] Test badge clearing resets count to 0 (not decrement by 1)
- [ ] T057 [US4] Run User Story 4 tests and verify multi-notification counting works

**User Story 4 Complete**: Badge count provides context about notification volume (Note: Already supported by Phase 2 implementation, Phase 6 adds comprehensive testing)

---

## Phase 7: Polish & Cross-Cutting Concerns

**Goal**: Notification abstraction, documentation, error handling

**Tasks**:

### Notification Abstraction

- [ ] T058 [P] Verify badge service has zero notification library dependencies (no SwayNC/Ghostty imports) in badge_service.py
- [ ] T059 [P] Document notification-agnostic architecture in quickstart.md (SwayNC, Ghostty, tmux examples)
- [ ] T060 [P] Create example integration for Ghostty notifications in quickstart.md
- [ ] T061 [P] Create example integration for tmux alerts in quickstart.md

### Error Handling & Edge Cases

- [ ] T062 [P] Implement orphaned badge cleanup on daemon startup in badge_service.py
- [ ] T063 [P] Handle invalid window ID gracefully in create_badge IPC handler (error response, don't crash)
- [ ] T064 [P] Handle race condition: badge created for window that closes 1ms later (badge persists until cleanup)
- [ ] T065 [P] Add logging for badge operations (create, clear, cleanup) with "Feature 095" prefix

### Performance Validation

- [ ] T066 Test badge appearance latency (<100ms from notification to UI update) via timestamp logging
- [ ] T067 Test badge clearing latency (<100ms from focus event to UI update) via focus event timestamp
- [ ] T068 Test concurrent badges scalability (20+ badges without UI degradation) via stress test
- [ ] T069 Measure memory footprint (50 badges ~12KB) via daemon memory profiling

### Documentation & Integration

- [ ] T070 Update CLAUDE.md with badge system usage (badge-ipc commands, troubleshooting)
- [ ] T071 [P] Add badge troubleshooting section to quickstart.md (daemon status, orphaned badges, count errors)
- [ ] T072 [P] Document badge creation examples for custom notification sources in quickstart.md
- [ ] T073 [P] Update monitoring panel documentation (Feature 085 quickstart) to mention badge indicators

---

## Dependencies & Execution Order

### Story Completion Dependencies

```
Phase 1 (Setup) → Phase 2 (Foundational)
                        ↓
        ┌───────────────┼───────────────┬────────────────┐
        ↓               ↓               ↓                ↓
    Phase 3 (US1)   Phase 4 (US2)   Phase 5 (US3)   Phase 6 (US4)
        ↓               ↓               ↓                ↓
        └───────────────┴───────────────┴────────────────┘
                        ↓
                Phase 7 (Polish)
```

**Story Independence**:
- **US1 (P1)**: Blocks US2 (requires badge display), blocks US3 (requires badge state), blocks US4 (requires badge count)
- **US2 (P2)**: Independent of US3/US4 (can be implemented in parallel after US1)
- **US3 (P3)**: Independent of US2/US4 (can be implemented in parallel after US1)
- **US4 (P4)**: Independent of US2/US3 (already supported by US1, Phase 6 adds testing)

### Critical Path

**Minimum MVP** (User Story 1 only):
```
T001-T005 (Setup) → T006-T018 (Foundational) → T019-T041 (US1 Implementation) = 41 tasks
```

**Estimated Time**:
- Setup: 1 hour (5 tasks)
- Foundational: 4 hours (13 tasks, mostly parallel)
- User Story 1: 8 hours (23 tasks, mixed parallel/sequential)
- **Total MVP**: ~13 hours

**Full Feature** (All User Stories):
- US2: +2 hours (4 tasks)
- US3: +3 hours (7 tasks)
- US4: +1 hour (5 tasks, mostly testing)
- Polish: +3 hours (16 tasks, mostly parallel)
- **Total Full Feature**: ~22 hours

---

## Parallel Execution Opportunities

### Phase 2 (Foundational) - 9 Parallel Tasks

Can execute T006-T014 in parallel (independent Pydantic models and methods):

```bash
# Terminal 1: WindowBadge model
# T006, T008, T009

# Terminal 2: BadgeState model
# T007, T010, T011, T012, T013, T014

# Terminal 3: Unit tests (after models complete)
# T016, T017
```

### Phase 3 (User Story 1) - 12 Parallel Tasks

After daemon integration (T015), can execute in parallel:

```bash
# Terminal 1: IPC Interface
# T019, T020, T021, T022, T023

# Terminal 2: Eww Widget UI
# T031, T032, T033, T034

# Terminal 3: Badge IPC Client
# T035, T036, T037

# Terminal 4: UI Tests (after widgets complete)
# T039, T040
```

**Sequential Dependencies**:
- T024-T027 (Event Handling): Must complete after T015 (daemon integration)
- T028-T030 (Monitoring Panel): Must complete after T014 (to_eww_format method)
- T038 (Hook Integration): Must complete after T035 (badge-ipc script)
- T041 (Run Tests): Must complete after all implementation tasks

### Phase 7 (Polish) - 14 Parallel Tasks

Documentation and validation tasks are highly parallelizable:

```bash
# Terminal 1: Notification abstraction docs
# T058, T059, T060, T061

# Terminal 2: Error handling
# T062, T063, T064, T065

# Terminal 3: Performance validation
# T066, T067, T068, T069

# Terminal 4: Documentation updates
# T070, T071, T072, T073
```

---

## Implementation Strategy

### Recommended Approach

1. **Start with MVP** (Phase 1-3, User Story 1):
   - Delivers core value: badges appear and clear on focus
   - Independently testable and deployable
   - Time to value: ~13 hours

2. **Add Reliability** (Phase 4, User Story 2):
   - Badge persistence across panel toggles
   - Builds trust in badge system
   - Time to value: +2 hours

3. **Enhance Discovery** (Phase 5, User Story 3):
   - Project-level badge aggregation
   - Useful for multi-project workflows
   - Time to value: +3 hours

4. **Comprehensive Testing** (Phase 6, User Story 4):
   - Multi-notification count validation
   - Already supported by foundational work
   - Time to value: +1 hour

5. **Polish & Document** (Phase 7):
   - Notification abstraction examples
   - Error handling and edge cases
   - Production-ready documentation
   - Time to value: +3 hours

### Testing Strategy

**Test-Driven Development** (Constitution Principle XIV):
- Write unit tests BEFORE implementing badge service methods (T016-T017 before T019-T030)
- Write integration tests BEFORE IPC handlers (T023 before T019-T022)
- Write sway-tests AFTER Eww widgets (T039-T040 after T031-T034)

**Test Coverage Goals**:
- Unit tests: 80%+ coverage for badge_service.py
- Integration tests: All IPC methods, focus event handling
- Sway tests: Badge appearance, clearing, project aggregation (declarative JSON)

### Risk Mitigation

**Highest Risk Tasks**:
1. **T028-T030 (Monitoring Panel Integration)**: Must not break existing Feature 085 panel updates
   - Mitigation: Test with existing panel workflows before adding badge field

2. **T024-T027 (Focus Event Handling)**: Race conditions between focus events and badge clearing
   - Mitigation: Async event handling with proper ordering, no blocking operations

3. **T031-T034 (Eww Widget UI)**: CSS/layout changes may break existing window-item styling
   - Mitigation: Use overlay positioning (absolute), test with multiple window states

**Validation Checkpoints**:
- After T018: All unit tests pass, badge service logic validated
- After T041: User Story 1 acceptance scenarios pass, MVP functional
- After T057: All user stories independently tested and validated
- After T073: Documentation complete, production-ready

---

## Task Summary

**Total Tasks**: 73
**Parallelizable Tasks**: 35 (48%)
**Sequential Tasks**: 38 (52%)

**By Phase**:
- Phase 1 (Setup): 5 tasks (7%)
- Phase 2 (Foundational): 13 tasks (18%)
- Phase 3 (US1): 23 tasks (32%)
- Phase 4 (US2): 4 tasks (5%)
- Phase 5 (US3): 7 tasks (10%)
- Phase 6 (US4): 5 tasks (7%)
- Phase 7 (Polish): 16 tasks (22%)

**By User Story**:
- User Story 1 (P1): 23 tasks (MVP)
- User Story 2 (P2): 4 tasks
- User Story 3 (P3): 7 tasks
- User Story 4 (P4): 5 tasks
- Infrastructure: 34 tasks (Setup + Foundational + Polish)

**MVP Deployment**: Phases 1-3 (41 tasks) = Fully functional badge system with core workflow

**Full Feature Deployment**: All phases (73 tasks) = Production-ready badge system with all user stories, error handling, and comprehensive documentation

---

**Ready for Implementation**: All tasks follow checklist format (checkbox, ID, optional [P]/[Story] labels, description with file paths). Each user story is independently testable. Parallel execution opportunities identified. Dependencies mapped.
