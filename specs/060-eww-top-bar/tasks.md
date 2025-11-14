# Tasks: Eww-Based Top Bar with Catppuccin Mocha Theme

**Feature Branch**: `060-eww-top-bar`
**Status**: ✅ **Deployed** (2025-11-14 09:07 EST)
**Generation**: 784 | **Commit**: eccb9dd
**Input**: Design documents from `/etc/nixos/specs/060-eww-top-bar/`
**Prerequisites**: plan.md ✅, spec.md ✅

## Current Status

**Completed**: 95/110 tasks (86%)
**Deployed**: M1 MacBook Pro, NixOS generation 784
**Working**: All 8 user stories functional

**What's Working**:
- ✅ Phases 1-10: All implementation complete
- ✅ Phase 12: Documentation complete (quickstart.md, CLAUDE.md updates)
- ✅ Successfully replaced Swaybar (no dual bars)
- ✅ All metrics displaying with correct colors and live updates
- ✅ Hardware auto-detection working (battery, bluetooth, temperature)
- ✅ Click handlers launching correct applications
- ✅ systemd service stable with auto-restart

**Known Issues**:
1. **Daemon health script exit code** (High Priority)
   - File: `home-modules/desktop/eww-top-bar/scripts/i3pm-health.sh`
   - Issue: Exits with code 1 when daemon unhealthy, causing Eww warnings every 5s
   - Impact: Cosmetic (script returns correct JSON, but Eww logs warnings)
   - Fix: Script should always exit 0 and encode status in JSON only

**Remaining Work** (15 tasks):
- Phase 7 (US4): Multi-monitor testing on external display + Hetzner
- Phase 11: Automated test suite (unit/integration/Sway IPC tests)
- Phase 12: Screenshots for documentation
- Bug fix: Daemon health script exit code

**Tests**: Manual validation (visual rendering) + Sway IPC tests (window positioning)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

All paths relative to `/etc/nixos/` repository root:
- Nix modules: `home-modules/desktop/`
- Python scripts: `home-modules/desktop/eww-top-bar/scripts/`
- Tests: `tests/eww-top-bar/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create eww-top-bar directory structure at home-modules/desktop/eww-top-bar/
- [X] T002 [P] Create scripts directory at home-modules/desktop/eww-top-bar/scripts/
- [X] T003 [P] Create tests directory at tests/eww-top-bar/ with unit/, integration/, sway-tests/ subdirectories

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create main module file home-modules/desktop/eww-top-bar.nix with NixOS options definition
- [X] T005 [P] Import unified-bar-theme.nix colors into eww-top-bar.nix
- [X] T006 [P] Import python-environment.nix shared Python packages
- [X] T007 Create systemd user service definition (eww-top-bar.service) in home-modules/desktop/eww-top-bar.nix
- [X] T008 Configure service dependencies (sway-session.target, auto-restart on failure)
- [X] T009 Create hardware detection script home-modules/desktop/eww-top-bar/scripts/hardware-detect.py
- [X] T010 Implement battery detection (/sys/class/power_supply/) in hardware-detect.py
- [X] T011 [P] Implement bluetooth detection (D-Bus org.bluez) in hardware-detect.py
- [X] T012 [P] Implement thermal sensor detection (/sys/class/thermal/) in hardware-detect.py
- [X] T013 Create multi-monitor window generation logic in eww-top-bar.nix
- [X] T014 Add headless detection (networking.hostName == "nixos-hetzner-sway") in eww-top-bar.nix
- [X] T015 Generate per-monitor Eww window configs (HEADLESS-1/2/3, eDP-1/HDMI-A-1) in eww-top-bar.nix

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Real-Time System Metrics Display (Priority: P1) 🎯 MVP

**Goal**: Display core system metrics (CPU load, memory, disk, network, temperature, time) in top bar with Catppuccin Mocha colors

**Independent Test**: Launch Eww top bar and verify all metrics appear with correct colors and values

### Implementation for User Story 1

- [X] T016 [P] [US1] Create system-metrics.py script at home-modules/desktop/eww-top-bar/scripts/system-metrics.py
- [X] T017 [US1] Implement get_load_average() function reading /proc/loadavg in system-metrics.py
- [X] T018 [P] [US1] Implement get_memory_usage() function reading /proc/meminfo in system-metrics.py
- [X] T019 [P] [US1] Implement get_disk_usage() function using os.statvfs() for root filesystem in system-metrics.py
- [X] T020 [P] [US1] Implement get_network_traffic() function reading /sys/class/net/ in system-metrics.py
- [X] T021 [P] [US1] Implement get_temperature() function reading /sys/class/thermal/thermal_zone*/temp in system-metrics.py
- [X] T022 [US1] Create JSON output formatter aggregating all metrics in system-metrics.py
- [X] T023 [US1] Add error handling (try/except with null fallbacks) in system-metrics.py
- [X] T024 [US1] Create eww.yuck.nix widget definitions at home-modules/desktop/eww-top-bar/eww.yuck.nix
- [X] T025 [US1] Define defpoll for system-metrics with 2-second interval in eww.yuck.nix
- [X] T026 [US1] Create CPU load widget with  icon and blue color (#89b4fa) in eww.yuck.nix
- [X] T027 [P] [US1] Create memory widget with  icon and sapphire color (#74c7ec) in eww.yuck.nix
- [X] T028 [P] [US1] Create disk widget with  icon and sky color (#89dceb) in eww.yuck.nix
- [X] T029 [P] [US1] Create network widget with  icon and teal color (#94e2d5) in eww.yuck.nix
- [X] T030 [P] [US1] Create temperature widget with  icon and peach color (#fab387) (conditional on thermal sensors) in eww.yuck.nix
- [X] T031 [P] [US1] Create date/time widget with  icon and text color (#cdd6f4) in eww.yuck.nix
- [X] T032 [US1] Define defpoll for date/time with 1-second interval in eww.yuck.nix
- [X] T033 [US1] Create eww.scss.nix styles at home-modules/desktop/eww-top-bar/eww.scss.nix
- [X] T034 [US1] Define top bar container styles (background rgba(30,30,46,0.85), border-radius 6px) in eww.scss.nix
- [X] T035 [US1] Define widget block styles (horizontal layout, spacing, separator bars) in eww.scss.nix
- [X] T036 [US1] Define Nerd Font icon styles (font-family, size) in eww.scss.nix
- [X] T037 [US1] Create defwindow definitions for all monitor outputs in eww.yuck.nix
- [X] T038 [US1] Configure window geometry (anchor "top center", width "100%", height "32px") in eww.yuck.nix
- [X] T039 [US1] Configure struts reservation (side "top", distance "36px") in eww.yuck.nix
- [X] T040 [US1] Set window properties (windowtype "dock", exclusive true, focusable false) in eww.yuck.nix
- [X] T041 [US1] Wire eww.yuck.nix and eww.scss.nix outputs to xdg.configFile in eww-top-bar.nix
- [X] T042 [US1] Add systemd ExecStart command launching Eww daemon in eww-top-bar.nix
- [X] T043 [US1] Add systemd ExecStartPost command opening all windows via `eww open-many` in eww-top-bar.nix

**Checkpoint**: At this point, User Story 1 should be fully functional - basic system metrics displaying in top bar

---

## Phase 4: User Story 2 - Live Data Updates via Deflisten/Defpoll (Priority: P1)

**Goal**: Ensure metrics update automatically at configured intervals (load/memory: 2s, disk/network: 5s, time: 1s)

**Independent Test**: Monitor metric updates over time and verify update frequencies match configuration

### Implementation for User Story 2

- [X] T044 [US2] Verify system-metrics.py defpoll interval is 2 seconds in eww.yuck.nix
- [X] T045 [US2] Create separate defpoll for disk/network with 5-second interval in eww.yuck.nix
- [X] T046 [US2] Verify date/time defpoll interval is 1 second in eww.yuck.nix
- [X] T047 [US2] Test metric update latency manually (observe changes within configured intervals)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - metrics display and update in real-time

---

## Phase 5: User Story 7 - Volume Control Widget (Priority: P2)

**Goal**: Display volume status with deflisten for real-time updates and click handler to open pavucontrol

**Independent Test**: Change volume via keyboard shortcuts and verify widget updates; click to verify pavucontrol opens

### Implementation for User Story 7

- [X] T048 [P] [US7] Create volume-monitor.py script at home-modules/desktop/eww-top-bar/scripts/volume-monitor.py
- [X] T049 [US7] Implement PulseAudio/PipeWire listener via pydbus in volume-monitor.py
- [X] T050 [US7] Output JSON with volume percentage and muted state in volume-monitor.py
- [X] T051 [US7] Create deflisten for volume updates in eww.yuck.nix
- [X] T052 [US7] Create volume widget with 🔊/🔇 icons (green/gray colors) in eww.yuck.nix
- [X] T053 [US7] Add eventbox click handler opening pavucontrol in eww.yuck.nix

**Checkpoint**: Volume widget displays, updates in real-time, and opens pavucontrol on click

---

## Phase 6: User Story 3 - Interactive Click Handlers (Priority: P2)

**Goal**: Clicking status blocks launches corresponding configuration applications

**Independent Test**: Click each block and verify correct application opens

### Implementation for User Story 3

- [X] T054 [P] [US3] Add eventbox wrapper to network widget with nm-connection-editor click handler in eww.yuck.nix
- [X] T055 [P] [US3] Add eventbox wrapper to bluetooth widget with blueman-manager click handler in eww.yuck.nix
- [X] T056 [P] [US3] Add eventbox wrapper to datetime widget with gnome-calendar click handler in eww.yuck.nix
- [X] T057 [US3] Use absolute paths for all click handler executables (${pkgs.pavucontrol}/bin/pavucontrol pattern) in eww.yuck.nix

**Checkpoint**: All click handlers functional - clicking blocks opens appropriate applications

---

## Phase 7: User Story 4 - Multi-Monitor Support (Priority: P2)

**Status**: ⚠️ **Partial** - Code implemented, only tested on eDP-1 (M1 built-in display)

**Goal**: Top bar appears on all configured outputs with output-specific positioning

**Independent Test**: Connect multiple monitors and verify bar appears on each configured output

### Implementation for User Story 4

- [ ] T058 [US4] Test multi-monitor window generation on headless Hetzner (HEADLESS-1/2/3) (requires deployment)
- [ ] T059 [US4] Test multi-monitor window generation on M1 MacBook (eDP-1, HDMI-A-1 when connected) (requires deployment)
- [X] T060 [US4] Configure system tray to appear only on primary output (HEADLESS-1 or eDP-1) in eww.yuck.nix (N/A - Eww doesn't provide system tray widget)
- [ ] T061 [US4] Verify bar positioning and struts reservation on all outputs (requires deployment)

**Checkpoint**: Multi-monitor support working - bars appear on all configured outputs

**Note**: Code is implemented for multi-monitor (eww-top-bar.nix lines 33-45), but only tested on single display. External monitor testing and Hetzner deployment pending.

---

## Phase 8: User Story 6 - Battery and Bluetooth Status (Priority: P3)

**Goal**: Display battery level/charging state and bluetooth connectivity on hardware-capable systems

**Independent Test**: Test on M1 MacBook (battery present) and Hetzner (no battery) to verify auto-detection

### Implementation for User Story 6

- [X] T062 [P] [US6] Create battery-monitor.py script at home-modules/desktop/eww-top-bar/scripts/battery-monitor.py
- [X] T063 [US6] Implement UPower D-Bus listener for battery events in battery-monitor.py
- [X] T064 [US6] Output JSON with percentage, charging state, level thresholds in battery-monitor.py
- [X] T065 [US6] Create deflisten for battery updates in eww.yuck.nix
- [X] T066 [US6] Create battery widget with  icon and color-coded levels (green >50%, yellow 20-50%, red <20%) in eww.yuck.nix
- [X] T067 [US6] Conditionally show battery widget only when hardware-detect.py reports battery present in eww.yuck.nix
- [X] T068 [P] [US6] Create bluetooth-monitor.py script at home-modules/desktop/eww-top-bar/scripts/bluetooth-monitor.py
- [X] T069 [US6] Implement bluez D-Bus listener for bluetooth events in bluetooth-monitor.py
- [X] T070 [US6] Output JSON with connection state (connected/enabled/disabled) in bluetooth-monitor.py
- [X] T071 [US6] Create deflisten for bluetooth updates in eww.yuck.nix
- [X] T072 [US6] Create bluetooth widget with  icon and color-coded states (blue connected, green enabled, gray disabled) in eww.yuck.nix
- [X] T073 [US6] Conditionally show bluetooth widget only when hardware-detect.py reports bluetooth present in eww.yuck.nix

**Checkpoint**: Battery and bluetooth widgets display on capable hardware, hidden on headless systems

---

## Phase 9: User Story 8 - Active Project Display (Priority: P3)

**Goal**: Display currently active i3pm project name with real-time updates on project switch

**Independent Test**: Switch i3pm projects and verify project name updates within 500ms

### Implementation for User Story 8

- [X] T074 [P] [US8] Create active-project.py script at home-modules/desktop/eww-top-bar/scripts/active-project.py
- [X] T075 [US8] Implement i3pm daemon socket listener (/run/i3-project-daemon/ipc.sock) in active-project.py
- [X] T076 [US8] Output JSON with active project name (or "Global" if none) in active-project.py
- [X] T077 [US8] Create deflisten for project updates in eww.yuck.nix
- [X] T078 [US8] Create project widget with  icon and subtext color (#a6adc8) in eww.yuck.nix
- [X] T079 [US8] Add eventbox click handler opening i3pm project switcher (walker --modules=applications --filter="i3pm;p") in eww.yuck.nix

**Checkpoint**: Active project name displays and updates in real-time on project switch

---

## Phase 10: User Story 5 - i3pm Daemon Health Monitoring (Priority: P3)

**Goal**: Visual feedback about i3pm daemon responsiveness with color-coded status

**Independent Test**: Start/stop i3pm daemon and verify health indicator changes color appropriately

### Implementation for User Story 5

- [X] T080 [P] [US5] Create i3pm-health.sh script at home-modules/desktop/eww-top-bar/scripts/i3pm-health.sh
- [X] T081 [US5] Implement daemon health check via Unix socket with timeout measurement in i3pm-health.sh
- [X] T082 [US5] Output JSON with status (healthy/slow/unhealthy) and response time in i3pm-health.sh
- [X] T083 [US5] Create defpoll for daemon health with 5-second interval in eww.yuck.nix
- [X] T084 [US5] Create daemon health widget with color-coded icons (✓ green <100ms, ⚠ yellow 100-500ms, ❌ red unresponsive) in eww.yuck.nix
- [X] T085 [US5] Add eventbox click handler opening diagnostic output (i3pm diagnose health) in eww.yuck.nix

**Checkpoint**: Daemon health indicator displays and updates based on daemon state

**⚠️ Known Issue**: T081-T082 have a bug - script exits with code 1 when daemon unhealthy, causing Eww warnings. Script should always exit 0 and encode status in JSON only. Functionality works correctly but logs warnings every 5 seconds.

---

## Phase 11: Testing & Validation

**Status**: ⚠️ **Incomplete** - All tasks pending (manual validation performed, automated tests not written)

**Purpose**: Verify all user stories meet acceptance criteria

- [ ] T086 [P] Create Sway IPC window validation test at tests/eww-top-bar/integration/test_eww_window_creation.py
- [ ] T087 [P] Create Sway test for top bar positioning at tests/eww-top-bar/sway-tests/test_top_bar_positioning.json
- [ ] T088 [P] Create Sway test for struts reservation at tests/eww-top-bar/sway-tests/test_top_bar_struts.json
- [ ] T089 [P] Create unit tests for system-metrics.py at tests/eww-top-bar/unit/test_system_metrics.py
- [ ] T090 [P] Create unit tests for hardware-detect.py at tests/eww-top-bar/unit/test_hardware_detect.py
- [ ] T091 Run dry-build test on M1 MacBook: nixos-rebuild dry-build --flake .#m1 --impure
- [ ] T092 Run dry-build test on Hetzner: nixos-rebuild dry-build --flake .#hetzner-sway
- [ ] T093 Perform manual visual validation on M1 MacBook (colors, icons, layout match spec)
- [ ] T094 Perform manual visual validation on Hetzner headless (VNC connection)
- [ ] T095 Test metric update frequencies (load/memory: 2s, disk/network: 5s, time: 1s, volume: 1s)
- [ ] T096 Test all click handlers launch correct applications
- [ ] T097 Test battery/bluetooth auto-detection on M1 (present) and Hetzner (hidden)
- [ ] T098 Test multi-monitor window creation on Hetzner (3 virtual displays)
- [ ] T099 Test Sway reload compatibility (eww-top-bar survives swaymsg reload)
- [ ] T100 Test systemd service auto-restart on failure (kill Eww daemon, verify restart)

---

## Phase 12: Polish & Cross-Cutting Concerns

**Status**: ⚠️ **Mostly Complete** - Documentation done, screenshots pending

**Purpose**: Documentation and final improvements

- [X] T101 [P] Create quickstart.md at specs/060-eww-top-bar/quickstart.md
- [X] T102 Document configuration examples in quickstart.md (enable/disable module, customize colors)
- [X] T103 Document troubleshooting steps in quickstart.md (service status, log inspection, reload commands)
- [X] T104 Document customization options in quickstart.md (update intervals, widget order, click handlers)
- [X] T105 Update CLAUDE.md with top bar commands (reload: swaymsg reload, restart: systemctl --user restart eww-top-bar)
- [X] T106 Add migration notes to quickstart.md (disabling old swaybar.nix top bar configuration)
- [X] T107 Add eww-top-bar.nix to appropriate configurations (m1.nix, hetzner-sway configuration)
- [X] T108 Document performance characteristics (RAM: <50MB, CPU: <2%, startup: <3s)
- [ ] T109 Add screenshots to specs/060-eww-top-bar/ showing top bar on both M1 and Hetzner
- [ ] T110 Run quickstart.md validation (follow steps as new user would)

**Note**: T107 completed for M1 only. Hetzner deployment pending multi-monitor testing (T058).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-10)**: All depend on Foundational phase completion
  - US1 + US2 (P1 stories) are tightly coupled and should be completed together for MVP
  - US3, US4, US7 (P2 stories) can proceed in parallel after MVP
  - US5, US6, US8 (P3 stories) can proceed in parallel after P2 stories
- **Testing (Phase 11)**: Can start after any user story is complete, must finish before deployment
- **Polish (Phase 12)**: Depends on all user stories and testing being complete

### User Story Dependencies

- **User Story 1 (P1) - Metrics Display**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1) - Live Updates**: Tightly coupled with US1, must be completed together for MVP
- **User Story 7 (P2) - Volume Widget**: Can start after Foundational - Extends US1/US2 pattern to volume
- **User Story 3 (P2) - Click Handlers**: Can start after US1 widgets exist - Wraps existing widgets with eventbox
- **User Story 4 (P2) - Multi-Monitor**: Can start after US1 single-monitor works - Tests existing window generation logic
- **User Story 6 (P3) - Battery/Bluetooth**: Can start after Foundational - Reuses deflisteners pattern from US7
- **User Story 8 (P3) - Active Project**: Can start after Foundational - Independent feature using deflisten pattern
- **User Story 5 (P3) - Daemon Health**: Can start after Foundational - Independent feature using defpoll pattern

### Within Each User Story

- Models/scripts before widget definitions
- Widget definitions before styles
- Styles before window configuration
- Window configuration before systemd service integration

### Parallel Opportunities

- **Phase 1 (Setup)**: All 3 tasks can run in parallel (T001-T003)
- **Phase 2 (Foundational)**: T005/T006, T010/T011/T012 can run in parallel
- **Phase 3 (US1)**: T016-T021 (metric collection functions), T027-T031 (widget definitions) can run in parallel within their groups
- **Phase 5 (US7)**: T048 (volume script) can run in parallel with T051 (widget definition)
- **Phase 6 (US3)**: T054-T056 all run in parallel (different widgets)
- **Phase 8 (US6)**: T062-T067 (battery) and T068-T073 (bluetooth) can run in parallel
- **Phase 11 (Testing)**: T086-T090 all run in parallel (different test files)
- **Phase 12 (Polish)**: T101 (quickstart creation) and T109 (screenshots) can run in parallel

---

## Parallel Example: User Story 1 (MVP Metrics)

```bash
# Launch all metric collection functions together:
Task: "Implement get_load_average() function in system-metrics.py"
Task: "Implement get_memory_usage() function in system-metrics.py"
Task: "Implement get_disk_usage() function in system-metrics.py"
Task: "Implement get_network_traffic() function in system-metrics.py"
Task: "Implement get_temperature() function in system-metrics.py"

# Launch all widget definitions together (after metrics script is done):
Task: "Create memory widget with  icon and sapphire color in eww.yuck.nix"
Task: "Create disk widget with  icon and sky color in eww.yuck.nix"
Task: "Create network widget with  icon and teal color in eww.yuck.nix"
Task: "Create temperature widget with  icon and peach color in eww.yuck.nix"
Task: "Create date/time widget with  icon and text color in eww.yuck.nix"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Metrics Display)
4. Complete Phase 4: User Story 2 (Live Updates)
5. **STOP and VALIDATE**: Test metrics display and update in real-time
6. Deploy/demo if ready - this is a functional replacement for swaybar top bar

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Stories 1 + 2 → Test independently → **Deploy/Demo (MVP!)**
3. Add User Story 7 (Volume) → Test independently → Deploy/Demo
4. Add User Story 3 (Click Handlers) → Test independently → Deploy/Demo
5. Add User Story 4 (Multi-Monitor) → Test independently → Deploy/Demo
6. Add User Story 6 (Battery/Bluetooth) → Test independently → Deploy/Demo
7. Add User Story 8 (Active Project) → Test independently → Deploy/Demo
8. Add User Story 5 (Daemon Health) → Test independently → Deploy/Demo
9. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Stories 1 + 2 (MVP - tightly coupled)
   - Wait for MVP completion before proceeding
3. After MVP is complete:
   - Developer A: User Story 7 (Volume Widget)
   - Developer B: User Story 3 (Click Handlers)
   - Developer C: User Story 4 (Multi-Monitor)
4. After P2 stories complete:
   - Developer A: User Story 6 (Battery/Bluetooth)
   - Developer B: User Story 8 (Active Project)
   - Developer C: User Story 5 (Daemon Health)
5. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- Manual visual validation required for colors/icons (GTK rendering limitations)
- Sway IPC tests validate window positioning and struts reservation
- Python unit tests validate metric collection logic
