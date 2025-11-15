# Tasks: Eww Top Bar Polish & Completion

**Input**: Design documents from `/etc/nixos/specs/061-eww-top-bar-polish/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Manual validation only (no automated test suite for this feature per spec)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Nix modules**: `home-modules/desktop/` for Eww configuration
- **Scripts**: `home-modules/desktop/eww-top-bar/scripts/` for monitoring scripts
- **Tests**: `tests/eww-top-bar/` for validation tests

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare project structure and dependencies

- [X] T001 Review existing eww-top-bar.nix module structure from Feature 060 in home-modules/desktop/eww-top-bar.nix
- [X] T002 Verify Eww version 0.6.0+ supports systray widget via nixpkgs
- [X] T003 [P] Verify NetworkManager and nmcli are available in system packages
- [X] T004 [P] Verify PipeWire (wpctl) or PulseAudio (pactl) is installed
- [X] T005 [P] Verify Nerd Fonts are installed for icon glyphs
- [X] T006 Create scripts directory structure in home-modules/desktop/eww-top-bar/scripts/ (wifi-status.sh, volume-status.sh, datetime-format.sh)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T007 Extract Catppuccin Mocha color definitions from Feature 057 for reuse in home-modules/desktop/eww-top-bar/eww.scss.nix
- [X] T008 Set up script template pattern with error handling and JSON output in home-modules/desktop/eww-top-bar/scripts/
- [ ] T009 Configure xdg.configFile entries in eww-top-bar.nix for script installation to ~/.config/eww/eww-top-bar/scripts/
- [ ] T010 Add script execution permissions via Nix module options

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 6 - Daemon Health Script Fix (Priority: P1) 🎯 MVP

**Goal**: Fix i3pm-health.sh to always exit with code 0 while returning correct JSON health status

**Independent Test**: Stop the i3pm daemon and verify the health widget shows "unhealthy" status in red without generating Eww warnings in the journal logs

### Implementation for User Story 6

- [X] T011 [US6] Update i3pm-health.sh to always exit with code 0 in home-modules/desktop/eww-top-bar/scripts/i3pm-health.sh
- [X] T012 [US6] Implement health status classification logic (healthy <100ms, slow 100-500ms, unhealthy >500ms)
- [X] T013 [US6] Add 1-second timeout to daemon socket query to prevent hanging
- [X] T014 [US6] Add graceful handling for missing socket file with error JSON response
- [X] T015 [US6] Update defpoll configuration in eww.yuck.nix to use fixed script
- [ ] T016 [US6] Test script manually with daemon running, stopped, and slow response scenarios
- [ ] T017 [US6] Verify no Eww warnings appear in systemd journal logs with: journalctl --user -u eww-top-bar -f

**Checkpoint**: At this point, daemon health widget should display all states correctly without log spam

---

## Phase 4: User Story 1 - System Tray Integration (Priority: P1) 🎯 MVP

**Goal**: Integrate Eww systray widget to display 1Password and other system tray applications

**Independent Test**: Launch 1Password and verify the system tray icon appears in the top bar. Click the icon and verify the 1Password menu opens with full functionality

### Implementation for User Story 1

- [X] T018 [US1] Add systray widget definition to eww.yuck.nix with properties: spacing 4, icon-size 16, orientation horizontal
- [X] T019 [US1] Implement multi-monitor conditional logic to show systray only on primary monitor (is_primary flag)
- [X] T020 [US1] Add systray CSS styling in eww.scss.nix with Catppuccin Mocha colors
- [X] T021 [US1] Configure systray positioning in top bar layout (right side after other widgets)
- [X] T022 [US1] Update defwindow definitions for all outputs (eDP-1, HDMI-A-1, HEADLESS-1/2/3) to pass is_primary parameter
- [ ] T023 [US1] Test systray with 1Password native package installation
- [ ] T024 [US1] Verify click interactions (left, middle, right-click) work correctly
- [ ] T025 [US1] Test icon appearance/disappearance when applications start/stop
- [ ] T026 [US1] Document 1Password installation requirements in quickstart.md

**Checkpoint**: At this point, system tray should be fully functional with 1Password and other SNI-compatible applications

---

## Phase 5: User Story 2 - WiFi Status & Control Widget (Priority: P1) 🎯 MVP

**Goal**: Display WiFi connection status with signal strength and network name, with click-to-configure functionality

**Independent Test**: Click the WiFi widget in the top bar and verify it shows current network name, signal strength, and opens NetworkManager connection editor

### Implementation for User Story 2

- [X] T027 [P] [US2] Create wifi-status.sh script in home-modules/desktop/eww-top-bar/scripts/wifi-status.sh
- [X] T028 [P] [US2] Implement nmcli query for active connection (SSID, signal strength)
- [X] T029 [US2] Add signal strength to color mapping logic (>70% green, 40-70% yellow, <40% orange, disconnected gray)
- [X] T030 [US2] Add JSON output format: {"connected": bool, "ssid": string, "signal": int, "color": string, "icon": string}
- [X] T031 [US2] Add error handling for NetworkManager not available
- [X] T032 [US2] Add defpoll definition in eww.yuck.nix with 2-second interval for wifi-status.sh
- [X] T033 [US2] Create wifi-widget definition in eww.yuck.nix with icon, SSID, and signal strength display
- [X] T034 [US2] Add click handler to open nm-connection-editor
- [X] T035 [US2] Add WiFi widget CSS styling in eww.scss.nix with color-coded signal strength classes
- [ ] T036 [US2] Test WiFi widget with connected, disconnected, and disabled states
- [ ] T037 [US2] Verify signal strength colors update correctly
- [ ] T038 [US2] Test click handler opens NetworkManager connection editor
- [ ] T039 [US2] Document WiFi widget usage and troubleshooting in quickstart.md

**Checkpoint**: At this point, WiFi widget should display connection status and allow quick network configuration

---

## Phase 6: User Story 3 - Enhanced Volume Control with Slider (Priority: P2)

**Goal**: Implement volume slider popup with real-time control, mute toggle, and visual feedback

**Independent Test**: Click the volume widget and verify a popup appears with a volume slider. Drag the slider and verify volume changes in real-time. Click the mute button and verify audio mutes

### Implementation for User Story 3

- [X] T040 [P] [US3] Create volume-status.sh script in home-modules/desktop/eww-top-bar/scripts/volume-status.sh
- [X] T041 [P] [US3] Implement audio system auto-detection (wpctl for PipeWire, pactl for PulseAudio)
- [X] T042 [US3] Add volume query logic for default audio sink
- [X] T043 [US3] Add mute state detection
- [X] T044 [US3] Add volume to icon mapping (>66% high, 34-66% medium, 1-33% low, 0 or muted = muted icon)
- [X] T045 [US3] Add JSON output format: {"volume": int, "muted": bool, "icon": string}
- [X] T046 [US3] Add defpoll definition in eww.yuck.nix with 2-second interval for volume-status.sh
- [X] T047 [US3] Create volume-widget definition in eww.yuck.nix displaying icon and percentage
- [X] T048 [US3] Create volume-popup window definition in eww.yuck.nix with revealer widget
- [X] T049 [US3] Add scale widget for volume slider (0-100 range, onchange event)
- [X] T050 [US3] Add mute toggle button to volume popup
- [X] T051 [US3] Configure popup positioning (anchor top right, below widget)
- [X] T052 [US3] Add click handler to toggle volume popup visibility
- [ ] T053 [US3] Add onlostfocus handler to close popup when clicking outside
- [X] T054 [US3] Add volume change command execution (wpctl set-volume or pactl set-sink-volume)
- [X] T055 [US3] Add mute toggle command execution (wpctl set-mute or pactl set-sink-mute)
- [ ] T056 [US3] Add volume widget CSS styling in eww.scss.nix
- [ ] T057 [US3] Add volume popup CSS styling with slider appearance
- [ ] T058 [US3] Test volume slider real-time updates (<100ms latency)
- [ ] T059 [US3] Test mute toggle functionality
- [ ] T060 [US3] Test popup open/close behavior
- [ ] T061 [US3] Test keyboard shortcut volume changes update widget display
- [ ] T062 [US3] Document volume control usage and troubleshooting in quickstart.md

**Checkpoint**: At this point, volume control should provide precise slider-based adjustment with mute toggle

---

## Phase 7: User Story 4 - Visual Polish & Animation Improvements (Priority: P2)

**Goal**: Add smooth hover effects, click animations, and transitions for professional UI polish

**Independent Test**: Hover over each widget in the top bar and verify smooth CSS transitions (<200ms). Click widgets and verify animations play smoothly without lag

### Implementation for User Story 4

- [ ] T063 [P] [US4] Add :hover CSS pseudo-class for all clickable widgets in eww.scss.nix
- [ ] T064 [P] [US4] Configure hover background color transition (Catppuccin Mocha surface1, 150ms ease-in-out)
- [ ] T065 [P] [US4] Add :active CSS pseudo-class for click feedback with darker background (100ms)
- [ ] T066 [P] [US4] Add CSS color transition for icon state changes (300ms ease-in-out)
- [ ] T067 [US4] Configure revealer widget slidedown animation for volume popup (200ms duration)
- [ ] T068 [US4] Add fade-in/fade-out transitions for widget value changes
- [ ] T069 [US4] Configure volume slider CSS with smooth highlight transitions
- [ ] T070 [US4] Test all hover effects for smooth 60 FPS transitions
- [ ] T071 [US4] Test popup animations for smooth slidedown effect
- [ ] T072 [US4] Test icon color transitions when state changes
- [ ] T073 [US4] Verify no visual stutter or lag during simultaneous animations

**Checkpoint**: At this point, all widgets should have polished hover states and smooth animations

---

## Phase 8: User Story 5 - Improved Date/Time Display & Calendar Popup (Priority: P3)

**Goal**: Enhance date/time widget with better formatting, timezone info, and calendar popup

**Independent Test**: Click the date/time widget and verify a popup calendar opens showing the current month. Verify date/time format is clear and includes timezone

### Implementation for User Story 5

- [ ] T074 [P] [US5] Create datetime-format.sh script in home-modules/desktop/eww-top-bar/scripts/datetime-format.sh
- [ ] T075 [P] [US5] Implement date format: "DDD MMM DD | HH:MM:SS" using date command
- [ ] T076 [US5] Update date/time widget definition in eww.yuck.nix with new format
- [ ] T077 [US5] Add calendar icon (nf-fa-calendar) to date/time widget
- [ ] T078 [US5] Create calendar-popup window definition in eww.yuck.nix
- [ ] T079 [US5] Add Eww calendar widget to popup (if available in Eww 0.6.0+)
- [ ] T080 [US5] Configure calendar popup positioning (anchor top center, below widget)
- [ ] T081 [US5] Add click handler to toggle calendar popup visibility
- [ ] T082 [US5] Add onlostfocus handler to close calendar when clicking outside
- [ ] T083 [US5] Add hover tooltip to date/time widget with full timezone information
- [ ] T084 [US5] Add calendar popup CSS styling in eww.scss.nix with current day highlighting (Catppuccin blue)
- [ ] T085 [US5] Test calendar popup open/close behavior
- [ ] T086 [US5] Test date/time format display
- [ ] T087 [US5] Verify timezone tooltip appears on hover
- [ ] T088 [US5] Document date/time widget usage in quickstart.md

**Checkpoint**: At this point, date/time widget should provide enhanced formatting and calendar reference

---

## Phase 9: User Story 7 - Multi-Monitor Testing & Validation (Priority: P2)

**Goal**: Validate top bar works correctly on M1 MacBook (2 displays) and Hetzner (3 virtual displays)

**Independent Test**: Connect an external monitor to the M1 MacBook and verify the top bar appears on both displays with correct positioning. SSH to Hetzner and verify all three virtual displays show the top bar

### Implementation for User Story 7

- [ ] T089 [US7] Review multi-monitor output configuration in eww-top-bar.nix (eDP-1, HDMI-A-1, HEADLESS-1/2/3)
- [ ] T090 [US7] Verify defwindow generation for all configured outputs
- [ ] T091 [US7] Verify is_primary flag is correctly set for primary monitor only
- [ ] T092 [US7] Test M1 MacBook with built-in display only (eDP-1)
- [ ] T093 [US7] Test M1 MacBook with external monitor connected (eDP-1 + HDMI-A-1)
- [ ] T094 [US7] Verify systray appears only on eDP-1 (primary) on M1
- [ ] T095 [US7] Verify all other widgets appear on both displays on M1
- [ ] T096 [US7] Test external monitor hotplug (connect/disconnect)
- [ ] T097 [US7] Verify top bar window closes gracefully when output removed
- [ ] T098 [US7] Test Hetzner headless system with all three virtual displays (HEADLESS-1/2/3)
- [ ] T099 [US7] Verify systray appears only on HEADLESS-1 (primary) on Hetzner
- [ ] T100 [US7] Verify all widgets appear on all three displays on Hetzner
- [ ] T101 [US7] Test window struts reservation with: swaymsg -t get_tree | jq '..|select(.type?=="con" and .name?=="eww")'
- [ ] T102 [US7] Verify maximized windows don't overlap top bar (36px reserved)
- [ ] T103 [US7] Test Sway reload (swaymsg reload) and verify top bar survives without restart
- [ ] T104 [US7] Document multi-monitor configuration in quickstart.md

**Checkpoint**: At this point, multi-monitor support should be validated on both target platforms

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, final validation, and project completion

- [ ] T105 [P] Update CLAUDE.md with new widget commands and debugging tips
- [ ] T106 [P] Update quickstart.md with complete usage examples for all widgets
- [ ] T107 [P] Add troubleshooting section to quickstart.md covering common issues
- [ ] T108 [P] Document system tray compatibility requirements (native packages, not Flatpak/Snap)
- [ ] T109 [P] Document WiFi widget NetworkManager dependency
- [ ] T110 [P] Document volume control audio system requirements (PipeWire/PulseAudio)
- [ ] T111 Validate all success criteria from spec.md (SC-001 through SC-010)
- [ ] T112 Test memory usage per Eww instance (<50MB target)
- [ ] T113 Test CPU usage across all top bar processes (<2% average)
- [ ] T114 Test widget click response time (<100ms)
- [ ] T115 Test animation frame rate (60 FPS target)
- [ ] T116 Verify zero Eww warnings in system journal logs
- [ ] T117 Run complete manual validation checklist per quickstart.md
- [ ] T118 Create deployment report documenting all tested scenarios

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-9)**: All depend on Foundational phase completion
  - US6 (Daemon Health Fix) should be completed first (critical bug fix)
  - US1, US2 are P1 MVP - should be completed next
  - US3, US4, US7 are P2 - can be done after MVP
  - US5 is P3 - lowest priority
- **Polish (Phase 10)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 6 (P1)**: Independent - can start after Foundational (critical bug fix)
- **User Story 1 (P1)**: Independent - can start after Foundational
- **User Story 2 (P1)**: Independent - can start after Foundational
- **User Story 3 (P2)**: Independent - can start after Foundational
- **User Story 4 (P2)**: Depends on US1, US2, US3 being complete (applies polish to existing widgets)
- **User Story 5 (P3)**: Independent - can start after Foundational
- **User Story 7 (P2)**: Depends on US1, US2, US3 being complete (validates all widgets on multi-monitor)

### Within Each User Story

- Script creation before defpoll configuration
- Widget definition before CSS styling
- Widget implementation before testing
- Core functionality before polish
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1 (Setup)**: T003, T004, T005 can run in parallel (different system checks)
- **Phase 2 (Foundational)**: All tasks are sequential (shared infrastructure setup)
- **Phase 3 (US6)**: All tasks are sequential (single script modification)
- **Phase 4 (US1)**: All tasks are sequential (widget integration)
- **Phase 5 (US2)**: T027, T028 can run in parallel (script creation vs nmcli testing)
- **Phase 6 (US3)**: T040-T045 can run in parallel (volume script components)
- **Phase 7 (US4)**: T063-T066 can run in parallel (different CSS rules)
- **Phase 8 (US5)**: T074, T075 can run in parallel (date script creation)
- **Phase 9 (US7)**: Testing tasks can be done in parallel if multiple test environments available
- **Phase 10 (Polish)**: T105-T110 can run in parallel (different documentation files)

---

## Parallel Example: User Story 2 (WiFi Widget)

```bash
# Launch script creation and testing in parallel:
Task T027: "Create wifi-status.sh script"
Task T028: "Implement nmcli query for active connection"

# Then continue with sequential tasks:
Task T029: "Add signal strength to color mapping logic"
Task T030: "Add JSON output format"
```

---

## Parallel Example: User Story 4 (Visual Polish)

```bash
# Launch all CSS styling tasks in parallel (different CSS rules):
Task T063: "Add :hover CSS pseudo-class for all clickable widgets"
Task T064: "Configure hover background color transition"
Task T065: "Add :active CSS pseudo-class for click feedback"
Task T066: "Add CSS color transition for icon state changes"
```

---

## Implementation Strategy

### MVP First (User Stories 6, 1, 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 6 (Daemon Health Fix - critical bug)
4. Complete Phase 4: User Story 1 (System Tray - essential feature)
5. Complete Phase 5: User Story 2 (WiFi Widget - essential feature)
6. **STOP and VALIDATE**: Test all three stories independently
7. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 6 → Test independently → Deploy/Demo (bug fix)
3. Add User Story 1 → Test independently → Deploy/Demo (system tray)
4. Add User Story 2 → Test independently → Deploy/Demo (WiFi widget) - **MVP COMPLETE**
5. Add User Story 3 → Test independently → Deploy/Demo (volume slider)
6. Add User Story 4 → Test independently → Deploy/Demo (visual polish)
7. Add User Story 5 → Test independently → Deploy/Demo (calendar)
8. Add User Story 7 → Test independently → Deploy/Demo (multi-monitor validation)
9. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 6 (quick bug fix)
   - Developer B: User Story 1 (system tray)
   - Developer C: User Story 2 (WiFi widget)
3. Then:
   - Developer A: User Story 3 (volume slider)
   - Developer B: User Story 5 (calendar)
4. Finally:
   - Developer A: User Story 4 (visual polish - depends on US1, US2, US3)
   - Developer B: User Story 7 (multi-monitor testing - depends on all widgets)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Manual validation required (no automated test suite for this feature)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- MVP scope: US6 (bug fix) + US1 (system tray) + US2 (WiFi widget)
- All scripts must exit with code 0 to prevent Eww warnings
- Multi-monitor testing requires actual hardware (M1 + external display) or VNC access (Hetzner)
- System tray only appears on primary monitor to prevent icon duplication
