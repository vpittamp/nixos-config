# Tasks: Unified Notification System with Eww Integration

**Input**: Design documents from `/specs/110-improve-notifications-system/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in specification - using manual verification via `notify-send` and visual inspection.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
```text
home-modules/desktop/eww-top-bar/
├── eww.yuck.nix          # Widget definitions
├── eww.scss.nix          # CSS styling
└── scripts/
    └── notification-monitor.py  # NEW: Streaming backend
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the notification monitor streaming backend

- [x] T001 Create notification-monitor.py streaming script in home-modules/desktop/eww-top-bar/scripts/notification-monitor.py
- [x] T002 Add Python script to Nix derivation and ensure it's copied to ~/.config/eww/eww-top-bar/scripts/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before user story UI work

**⚠️ CRITICAL**: Python streaming backend must work before Eww integration

- [x] T003 Implement SwayNC subscribe process spawning in notification-monitor.py with subprocess.Popen
- [x] T004 Add JSON parsing and transformation for SwayNC events (add has_unread, display_count computed fields)
- [x] T005 Add graceful error handling for SwayNC daemon unavailability with automatic reconnection
- [x] T006 [P] Test notification-monitor.py manually: run script, send `notify-send "Test" "message"`, verify JSON output

**Checkpoint**: Python streaming backend outputs valid JSON on stdout when notifications change

---

## Phase 3: User Story 1 - View Unread Notification Count (Priority: P1) 🎯 MVP

**Goal**: Display badge with unread count (0-9, "9+") in top bar that updates in real-time

**Independent Test**: Send notifications via `notify-send`, verify badge count updates within 100ms

### Implementation for User Story 1

- [x] T007 [US1] Add `deflisten notification_data` variable in home-modules/desktop/eww-top-bar/eww.yuck.nix with JSON initial value
- [x] T008 [US1] Create `notification-badge` widget showing display_count from notification_data in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T009 [US1] Add badge CSS classes (.notification-badge, .notification-badge-hidden, .notification-badge-count) in home-modules/desktop/eww-top-bar/eww.scss.nix
- [x] T010 [US1] Integrate notification-badge widget into main-bar right section replacing existing notification-center-toggle in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T011 [US1] Add pulsing glow animation for unread notifications (pulse-unread keyframes) in home-modules/desktop/eww-top-bar/eww.scss.nix

**Checkpoint**: Badge displays count and pulses when notifications exist

---

## Phase 4: User Story 2 - Toggle Notification Center from Top Bar (Priority: P1)

**Goal**: Click notification icon to open/close SwayNC control center

**Independent Test**: Click widget, verify SwayNC panel toggles; verify icon state updates

### Implementation for User Story 2

- [x] T012 [US2] Add onclick handler to notification-badge widget calling `toggle-swaync` in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T013 [US2] Update widget class binding to reflect center_open (visible) state from notification_data in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T014 [US2] Remove separate notification_center_visible defpoll (use notification_data.visible instead) in home-modules/desktop/eww-top-bar/eww.yuck.nix

**Checkpoint**: Clicking widget toggles SwayNC panel; icon reflects open/closed state

---

## Phase 5: User Story 3 - Visual Distinction for Notification States (Priority: P2)

**Goal**: Different icons for no notifications (󰂜), has unread (󰂚), DND enabled (󰂛)

**Independent Test**: Transition through states, verify icon changes correctly

### Implementation for User Story 3

- [x] T015 [US3] Update notification-badge widget icon to use conditional rendering based on dnd and has_unread in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T016 [US3] Add CSS classes for icon states (.notification-icon-empty, .notification-icon-active, .notification-icon-dnd) in home-modules/desktop/eww-top-bar/eww.scss.nix
- [x] T017 [US3] Style DND icon with muted color (gray/red slash indicator) in home-modules/desktop/eww-top-bar/eww.scss.nix

**Checkpoint**: Icon visually distinguishes between no notifications, has unread, and DND

---

## Phase 6: User Story 4 - Consistent Theme Integration (Priority: P2)

**Goal**: Badge colors match Catppuccin Mocha palette (red/peach gradient)

**Independent Test**: Visual comparison against other top bar widgets for color consistency

### Implementation for User Story 4

- [x] T018 [P] [US4] Style badge background with Catppuccin red/peach gradient (#f38ba8, #fab387) in home-modules/desktop/eww-top-bar/eww.scss.nix
- [x] T019 [P] [US4] Style badge text with high contrast (white or light cream) in home-modules/desktop/eww-top-bar/eww.scss.nix
- [x] T020 [US4] Add consistent hover transitions matching other Eww pills (120ms ease) in home-modules/desktop/eww-top-bar/eww.scss.nix

**Checkpoint**: Badge visually matches Catppuccin Mocha theme used in other widgets

---

## Phase 7: User Story 5 - Real-Time Badge Updates (Priority: P2)

**Goal**: Badge updates within 100ms of notification changes (event-driven, not polling)

**Independent Test**: Rapidly send/dismiss notifications, verify no perceptible lag

### Implementation for User Story 5

- [x] T021 [US5] Ensure notification-monitor.py flushes output immediately after each JSON line in home-modules/desktop/eww-top-bar/scripts/notification-monitor.py
- [x] T022 [US5] Add automatic reconnection with exponential backoff when SwayNC daemon restarts in home-modules/desktop/eww-top-bar/scripts/notification-monitor.py
- [x] T023 [US5] Verify deflisten receives updates without buffering (test with multiple rapid notifications)

**Checkpoint**: Badge updates reflect notification changes within 100ms

---

## Phase 8: User Story 6 - Keyboard Tooltip for Accessibility (Priority: P3)

**Goal**: Tooltip shows count and keyboard shortcut on hover

**Independent Test**: Hover over notification icon, verify tooltip displays correct info

### Implementation for User Story 6

- [x] T024 [US6] Add dynamic tooltip to notification-badge widget showing count and shortcut in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T025 [US6] Add tooltip text variations for DND state ("Do Not Disturb enabled") in home-modules/desktop/eww-top-bar/eww.yuck.nix
- [x] T026 [US6] Add tooltip text for zero notifications ("No notifications") in home-modules/desktop/eww-top-bar/eww.yuck.nix

**Checkpoint**: Tooltip displays contextual information on hover

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, error handling, and final validation

- [x] T027 [P] Handle SwayNC daemon not running - show muted icon state in notification-monitor.py
- [x] T028 [P] Verify badge recovers state within 2s after SwayNC daemon restart
- [x] T029 [P] Test with 50+ notifications to ensure no UI degradation
- [x] T030 [P] Test monitor profile switching - verify badge persists correctly
- [x] T031 Run quickstart.md validation (all troubleshooting commands work)
- [x] T032 Build and test with `sudo nixos-rebuild dry-build --flake .#hetzner-sway`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - US1 (P1): Can start after Foundational
  - US2 (P1): Can start after US1 (uses notification_data variable)
  - US3 (P2): Can start after US1 (builds on icon widget)
  - US4 (P2): Can run in parallel with US3 (CSS only, different selectors)
  - US5 (P2): Can start after US1 (backend improvements)
  - US6 (P3): Can start after US1 (widget enhancements)
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Blocking - creates notification_data variable and badge widget
- **User Story 2 (P1)**: Depends on US1 (uses same widget, adds click handler)
- **User Story 3 (P2)**: Depends on US1 (enhances icon rendering)
- **User Story 4 (P2)**: Independent of other stories (CSS-only changes)
- **User Story 5 (P2)**: Depends on US1 (backend performance)
- **User Story 6 (P3)**: Depends on US1 (adds tooltip to widget)

### Parallel Opportunities

- T018, T019 can run in parallel (different CSS properties)
- T027, T028, T029, T030 can run in parallel (independent validation tests)
- US3 and US4 can run in parallel after US1 (different concerns)
- US5 and US6 can run in parallel after US1 (different concerns)

---

## Parallel Example: User Story 4 (CSS Styling)

```bash
# Launch CSS tasks together:
Task: "Style badge background with Catppuccin red/peach gradient in eww.scss.nix"
Task: "Style badge text with high contrast in eww.scss.nix"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (notification-monitor.py)
2. Complete Phase 2: Foundational (streaming backend works)
3. Complete Phase 3: User Story 1 (badge displays count)
4. Complete Phase 4: User Story 2 (clicking toggles panel)
5. **STOP and VALIDATE**: Badge shows count, click toggles panel
6. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Backend streaming works
2. Add User Story 1 → Badge with count visible (MVP!)
3. Add User Story 2 → Click to toggle panel
4. Add User Story 3 → Icon state variations
5. Add User Story 4 → Theme polish
6. Add User Story 5 → Performance tuning
7. Add User Story 6 → Tooltip accessibility
8. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files or independent CSS selectors, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence

## Summary

- **Total tasks**: 32
- **Phase 1 (Setup)**: 2 tasks
- **Phase 2 (Foundational)**: 4 tasks
- **Phase 3 (US1 - MVP)**: 5 tasks
- **Phase 4 (US2)**: 3 tasks
- **Phase 5 (US3)**: 3 tasks
- **Phase 6 (US4)**: 3 tasks
- **Phase 7 (US5)**: 3 tasks
- **Phase 8 (US6)**: 3 tasks
- **Phase 9 (Polish)**: 6 tasks
- **Parallel opportunities**: 12 tasks marked [P]
- **MVP scope**: Phases 1-4 (14 tasks, delivers visible badge + toggle)
