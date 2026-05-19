# Tasks: Unified Eww Device Control Panel

**Input**: Design documents from `/specs/116-use-eww-device/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No automated tests requested - manual verification on ThinkPad and Ryzen per spec.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md project structure:
- **Module**: `home-modules/desktop/eww-device-controls.nix`
- **Widgets**: `home-modules/desktop/eww-device-controls/eww.yuck.nix`
- **Styles**: `home-modules/desktop/eww-device-controls/eww.scss.nix`
- **Scripts**: `home-modules/desktop/eww-device-controls/scripts/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and module structure creation

- [X] T001 Create module directory structure at home-modules/desktop/eww-device-controls/
- [X] T002 Create main module skeleton in home-modules/desktop/eww-device-controls.nix with enable option and imports
- [X] T003 [P] Create empty eww.yuck.nix with widget stubs in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T004 [P] Create eww.scss.nix with Catppuccin Mocha base styles in home-modules/desktop/eww-device-controls/eww.scss.nix
- [X] T005 Create scripts directory structure at home-modules/desktop/eww-device-controls/scripts/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core backend infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Implement HardwareCapabilities detection in device-backend.py at home-modules/desktop/eww-device-controls/scripts/device-backend.py (detect battery, brightness, bluetooth, wifi, thermal sensors per data-model.md)
- [X] T007 [P] Implement VolumeState query using wpctl in device-backend.py at home-modules/desktop/eww-device-controls/scripts/device-backend.py (volume percentage, muted status, icon mapping, device list per data-model.md)
- [X] T008 [P] Implement BluetoothState query using bluetoothctl in device-backend.py at home-modules/desktop/eww-device-controls/scripts/device-backend.py (enabled status, device list with connection status per data-model.md)
- [X] T009 [P] Create volume-control.sh wrapper script at home-modules/desktop/eww-device-controls/scripts/volume-control.sh (get/set/up/down/mute/device actions per contracts/device-backend.md)
- [X] T010 [P] Create bluetooth-control.sh wrapper script at home-modules/desktop/eww-device-controls/scripts/bluetooth-control.sh (get/power/connect/disconnect/scan actions per contracts/device-backend.md)
- [X] T011 Add --mode flag support to device-backend.py for selective queries (full/volume/brightness/bluetooth/battery/thermal/network per contracts/device-backend.md)
- [X] T012 Add --listen flag support to device-backend.py for deflisten streaming mode per contracts/device-backend.md
- [X] T013 Implement error handling and JSON error output format in all scripts per contracts/device-backend.md error codes

**Checkpoint**: Foundation ready - backend scripts functional, user story implementation can now begin

---

## Phase 3: User Story 1 - Quick Device Access from Top Bar (Priority: P1) 🎯 MVP

**Goal**: Volume, Bluetooth, battery controls accessible via expandable top bar panels with <2 second interaction time

**Independent Test**: Click volume icon in top bar → expanded panel appears → drag slider → volume changes in real-time

### Implementation for User Story 1

- [X] T014 [P] [US1] Create defpoll for volume_state with 1s interval in home-modules/desktop/eww-device-controls/eww.yuck.nix using device-backend.py --mode volume
- [X] T015 [P] [US1] Create defpoll for bluetooth_state with 3s interval in home-modules/desktop/eww-device-controls/eww.yuck.nix using device-backend.py --mode bluetooth
- [X] T016 [US1] Create volume-indicator widget with expandable panel in home-modules/desktop/eww-device-controls/eww.yuck.nix (icon, click-to-expand, slider, mute toggle, device list)
- [X] T017 [US1] Create bluetooth-indicator widget with expandable panel in home-modules/desktop/eww-device-controls/eww.yuck.nix (icon with connection status color, toggle switch, paired device list)
- [X] T018 [US1] Implement click-outside-to-close behavior for expanded panels using eventbox in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T019 [US1] Add onscroll handlers to top bar indicators for quick volume/brightness adjustment in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T020 [US1] Style volume panel with Catppuccin Mocha colors (slider, mute icon states) in home-modules/desktop/eww-device-controls/eww.scss.nix
- [X] T021 [US1] Style bluetooth panel with Catppuccin Mocha colors (toggle switch, device list, connection status) in home-modules/desktop/eww-device-controls/eww.scss.nix
- [~] T022 [US1] DEFERRED: Integrate device indicators into existing eww-top-bar - eww-top-bar already has working volume/battery/bluetooth widgets with its own scripts. Device-controls provides value via Devices tab (Alt+7) instead. Refactoring top bar would be high-risk for minimal gain.
- [X] T023 [US1] Add Nix package dependencies (wpctl, bluetoothctl) to home-modules/desktop/eww-device-controls.nix

**Checkpoint**: User Story 1 complete - volume and Bluetooth controls work from top bar on both ThinkPad and Ryzen

---

## Phase 4: User Story 2 - Hardware-Adaptive Device Detection (Priority: P2)

**Goal**: Only show controls for available hardware - no brightness on Ryzen, no battery on desktop

**Independent Test**: Deploy same config to ThinkPad and Ryzen, verify each shows only applicable controls

### Implementation for User Story 2

- [X] T024 [P] [US2] Implement BrightnessState query using brightnessctl in device-backend.py at home-modules/desktop/eww-device-controls/scripts/device-backend.py (display and keyboard brightness per data-model.md)
- [X] T025 [P] [US2] Implement BatteryState query using upower in device-backend.py at home-modules/desktop/eww-device-controls/scripts/device-backend.py (percentage, state, time remaining, icon mapping per data-model.md)
- [X] T026 [P] [US2] Create brightness-control.sh wrapper script at home-modules/desktop/eww-device-controls/scripts/brightness-control.sh (get/set/up/down with --device flag per contracts/device-backend.md)
- [X] T027 [US2] Add hardware capability flags to JSON output in device-backend.py (has_battery, has_brightness, has_keyboard_backlight, has_bluetooth, etc. per data-model.md)
- [X] T028 [US2] Create conditional widget rendering using hardware flags in home-modules/desktop/eww-device-controls/eww.yuck.nix (show brightness only if has_brightness, battery only if has_battery)
- [X] T029 [P] [US2] Create brightness-indicator widget with expandable panel in home-modules/desktop/eww-device-controls/eww.yuck.nix (display slider, keyboard slider if available)
- [X] T030 [P] [US2] Create battery-indicator widget in home-modules/desktop/eww-device-controls/eww.yuck.nix (icon based on level/charging state, click to expand for time remaining)
- [X] T031 [US2] Style brightness and battery panels with Catppuccin Mocha colors in home-modules/desktop/eww-device-controls/eww.scss.nix
- [X] T032 [US2] Add defpoll for brightness_state (2s interval, only when has_brightness) in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T033 [US2] Add defpoll for battery_state (5s interval, only when has_battery) in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T034 [US2] Implement "Not Available" graceful fallback state display for disabled/missing hardware in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T035 [US2] Add Nix package dependencies (brightnessctl, upower) to home-modules/desktop/eww-device-controls.nix

**Checkpoint**: User Story 2 complete - ThinkPad shows all controls, Ryzen shows only applicable ones

---

## Phase 5: User Story 3 - Comprehensive Device Dashboard in Monitoring Panel (Priority: P3)

**Goal**: Full device overview in monitoring panel Devices tab (index 6, Alt+7) with all metrics and keyboard navigation

**Independent Test**: Press Mod+M → Alt+7 → see comprehensive device info organized by category, navigate with j/k/Enter

### Implementation for User Story 3

- [X] T036 [P] [US3] Implement ThermalState query using lm_sensors in device-backend.py at home-modules/desktop/eww-device-controls/scripts/device-backend.py (CPU temp, fan speed, thermal zones per data-model.md)
- [X] T037 [P] [US3] Implement NetworkState query using nmcli and tailscale in device-backend.py at home-modules/desktop/eww-device-controls/scripts/device-backend.py (WiFi SSID, signal strength, Tailscale status per data-model.md)
- [X] T038 [P] [US3] Implement PowerProfileState query using TLP or power-profiles-daemon in device-backend.py at home-modules/desktop/eww-device-controls/scripts/device-backend.py (current profile, available profiles per data-model.md)
- [X] T039 [P] [US3] Create power-profile-control.sh wrapper script at home-modules/desktop/eww-device-controls/scripts/power-profile-control.sh (get/set/cycle actions per contracts/device-backend.md)
- [X] T040 [US3] Create devices-tab widget definition in home-modules/desktop/eww-device-controls/eww.yuck.nix with sections: Audio, Display, Bluetooth, Power, Thermal, Network
- [X] T041 [US3] Create audio section widget with output device selector, volume slider, microphone status in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T042 [P] [US3] Create display section widget with brightness sliders (display + keyboard backlight) in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T043 [P] [US3] Create bluetooth section widget with adapter toggle and full paired device list in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T044 [US3] Create power section widget with battery details (health, cycles, power draw), charging status, power profile selector in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T045 [P] [US3] Create thermal section widget with CPU temperature, fan speed, thermal zone readings in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T046 [P] [US3] Create network section widget with WiFi status/SSID/signal and Tailscale connection status in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T047 [US3] Implement keyboard navigation (j/k/Enter/Escape) for devices-tab in focus mode in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T048 [US3] Style devices-tab sections with Catppuccin Mocha theme, consistent with existing monitoring panel tabs in home-modules/desktop/eww-device-controls/eww.scss.nix
- [X] T049 [US3] Add defpoll for full device_state (2s interval, run-while Devices tab visible) in home-modules/desktop/eww-device-controls/eww.yuck.nix
- [X] T050 [US3] Integrate Devices tab into eww-monitoring-panel at index 6 (Alt+7) by updating home-modules/desktop/eww-monitoring-panel.nix
- [X] T051 [US3] Add Nix package dependencies (lm_sensors, tailscale CLI) to home-modules/desktop/eww-device-controls.nix

**Checkpoint**: User Story 3 complete - Devices tab provides comprehensive dashboard with keyboard navigation

---

## Phase 6: User Story 4 - Remove Duplicate Controls and Consolidate (Priority: P4)

**Goal**: Deprecate eww-quick-panel, migrate all functionality to unified system, eliminate duplication

**Independent Test**: Verify eww-quick-panel is disabled, all its controls accessible via new system

### Implementation for User Story 4

- [X] T052 [US4] Audit existing eww-quick-panel module at home-modules/desktop/eww-quick-panel.nix to identify all controls that must be migrated
- [X] T053 [US4] Verify all eww-quick-panel controls are present in unified device controls (brightness, audio, etc.)
- [X] T054 [US4] Update eww-quick-panel.nix to set enable = mkDefault false (deprecate but don't remove)
- [X] T055 [US4] Add deprecation comment and migration guidance to eww-quick-panel.nix pointing to eww-device-controls
- [~] T056 [US4] DEFERRED: Top bar already uses its own volume-status.sh/volume-monitor.py scripts. Device-controls and top bar are intentionally separate Eww instances to avoid conflicts.
- [X] T057 [US4] Verify no duplicate defpoll or deflisten - VERIFIED: device-controls uses device-backend.py in separate Eww config (~/.config/eww/eww-device-controls/), top bar uses its own scripts (~/.config/eww/eww-top-bar/scripts/). No conflicts.
- [ ] T058 [US4] MANUAL: Test unified controls on ThinkPad - verify Devices tab (Alt+7) shows all sections
- [ ] T059 [US4] MANUAL: Test unified controls on Ryzen - verify Devices tab shows only applicable sections (no brightness/battery)

**Checkpoint**: User Story 4 complete - eww-quick-panel deprecated, all controls unified, no duplication

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, performance optimization, and final validation

- [X] T060 [P] Validate quickstart.md scenarios match actual implementation in specs/116-use-eww-device/quickstart.md
- [ ] T061 [P] MANUAL: Verify <100ms latency for volume/brightness updates using deflisten mode
- [ ] T062 MANUAL: Verify memory usage stays under 50MB additional overhead (SC-008)
- [ ] T063 MANUAL: Run full manual test on ThinkPad per acceptance scenarios in spec.md
- [ ] T064 MANUAL: Run full manual test on Ryzen per acceptance scenarios in spec.md
- [X] T065 Update CLAUDE.md with Devices tab keybindings (Alt+7) and new device control documentation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can then proceed in priority order (P1 → P2 → P3 → P4)
  - Some parallelization possible within stories
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - Core top bar controls (volume, bluetooth)
- **User Story 2 (P2)**: Can start after Foundational - Adds brightness, battery, hardware detection
- **User Story 3 (P3)**: Can start after US1/US2 - Adds monitoring panel Devices tab
- **User Story 4 (P4)**: Should start after US1/US2/US3 complete - Deprecation and consolidation

### Within Each User Story

- Backend scripts before widget implementation
- Widgets before styling
- Core functionality before integration with existing modules
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks T003-T004 can run in parallel
- Foundational tasks T007-T010 can run in parallel (different scripts)
- Within US1: T014-T015 (defpolls) in parallel, T020-T021 (styles) in parallel
- Within US2: T024-T026 (backend) in parallel, T029-T030 (widgets) in parallel
- Within US3: T036-T039 (backend) in parallel, T042-T046 (section widgets) in parallel

---

## Parallel Example: User Story 1

```bash
# Launch defpolls together:
Task: T014 "defpoll for volume_state"
Task: T015 "defpoll for bluetooth_state"

# Launch styles together (after widgets):
Task: T020 "Style volume panel"
Task: T021 "Style bluetooth panel"
```

---

## Parallel Example: User Story 3

```bash
# Launch all backend queries together:
Task: T036 "ThermalState query"
Task: T037 "NetworkState query"
Task: T038 "PowerProfileState query"
Task: T039 "power-profile-control.sh wrapper"

# Launch section widgets together (after main devices-tab structure):
Task: T042 "Display section widget"
Task: T043 "Bluetooth section widget"
Task: T045 "Thermal section widget"
Task: T046 "Network section widget"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - backend scripts)
3. Complete Phase 3: User Story 1 (volume + bluetooth top bar controls)
4. **STOP and VALIDATE**: Test on both ThinkPad and Ryzen
5. Deploy if ready - core device controls functional

### Incremental Delivery

1. Setup + Foundational → Backend ready
2. Add User Story 1 → Test → Deploy (MVP: volume + bluetooth)
3. Add User Story 2 → Test → Deploy (brightness + battery + hardware detection)
4. Add User Story 3 → Test → Deploy (Devices tab in monitoring panel)
5. Add User Story 4 → Test → Deploy (deprecate quick-panel, cleanup)
6. Polish → Final validation → Feature complete

### Key Files Summary

| Component | File Path |
|-----------|-----------|
| Main module | home-modules/desktop/eww-device-controls.nix |
| Widget definitions | home-modules/desktop/eww-device-controls/eww.yuck.nix |
| Widget styles | home-modules/desktop/eww-device-controls/eww.scss.nix |
| Backend script | home-modules/desktop/eww-device-controls/scripts/device-backend.py |
| Volume control | home-modules/desktop/eww-device-controls/scripts/volume-control.sh |
| Brightness control | home-modules/desktop/eww-device-controls/scripts/brightness-control.sh |
| Bluetooth control | home-modules/desktop/eww-device-controls/scripts/bluetooth-control.sh |
| Power profile control | home-modules/desktop/eww-device-controls/scripts/power-profile-control.sh |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Manual testing required on both ThinkPad and Ryzen per spec
