# Tasks: Enhanced Swaybar Status

**Input**: Design documents from `/specs/052-enhanced-swaybar-status/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are OPTIONAL - this feature does not explicitly request TDD approach, but test tasks are included for validation purposes.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US4)
- Include exact file paths in descriptions

## Path Conventions

Following NixOS home-manager module patterns:
- **NixOS Module**: `home-modules/desktop/swaybar-enhanced.nix`
- **Status Generator**: `home-modules/desktop/swaybar/status-generator.py`
- **Status Blocks**: `home-modules/desktop/swaybar/blocks/*.py`
- **Tests**: `tests/swaybar/`
- **Configuration**: Generated via `xdg.configFile` in home-manager

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create directory structure for swaybar components in home-modules/desktop/swaybar/
- [X] T002 Create test directory structure in tests/swaybar/ (unit/, integration/, fixtures/)
- [X] T003 [P] Create NixOS module skeleton in home-modules/desktop/swaybar-enhanced.nix with basic options structure
- [X] T004 [P] Create Python package structure with __init__.py in home-modules/desktop/swaybar/blocks/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Implement StatusBlock dataclass in home-modules/desktop/swaybar/blocks/models.py with to_json() method
- [X] T006 [P] Implement Config dataclass in home-modules/desktop/swaybar/blocks/config.py with theme, intervals, and click handlers
- [X] T007 [P] Implement ColorTheme dataclass hierarchy in home-modules/desktop/swaybar/blocks/config.py (VolumeColors, BatteryColors, NetworkColors, BluetoothColors)
- [X] T008 Create i3bar protocol handler skeleton in home-modules/desktop/swaybar/status-generator.py (header output, main loop structure)
- [X] T009 Implement ClickEvent dataclass in home-modules/desktop/swaybar/blocks/models.py with from_json() parser
- [X] T010 Create click handler infrastructure in home-modules/desktop/swaybar/blocks/click_handler.py with subprocess launching
- [X] T011 Setup NixOS module options structure in home-modules/desktop/swaybar-enhanced.nix (enable, icons, theme, intervals, clickHandlers, hardware detection)
- [X] T012 Create xdg.configFile generation for status-generator.py installation in home-modules/desktop/swaybar-enhanced.nix
- [X] T013 Add pytest configuration in tests/swaybar/conftest.py with fixtures for mock D-Bus responses

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Visual System Status Monitoring (Priority: P1) 🎯 MVP

**Goal**: Display system status (volume, battery, network, bluetooth) at a glance with clear visual indicators and icons

**Independent Test**: Launch enhanced status bar and verify all system status indicators (volume, battery, WiFi, Bluetooth) are visible with appropriate Nerd Font icons and current values

### Implementation for User Story 1

**Volume Status Block**:
- [X] T014 [P] [US1] Implement VolumeState dataclass in home-modules/desktop/swaybar/blocks/volume.py with get_icon(), get_color(), to_status_block()
- [X] T015 [P] [US1] Implement volume query via pactl subprocess in home-modules/desktop/swaybar/blocks/volume.py (get_volume_state function)
- [X] T016 [US1] Add volume status block integration to main loop in home-modules/desktop/swaybar/status-generator.py

**Battery Status Block**:
- [X] T017 [P] [US1] Implement BatteryState dataclass in home-modules/desktop/swaybar/blocks/battery.py with get_icon(), get_color(), get_tooltip(), to_status_block()
- [X] T018 [P] [US1] Implement UPower D-Bus query in home-modules/desktop/swaybar/blocks/battery.py using pydbus (get_battery_state function)
- [X] T019 [US1] Add battery status block integration to main loop with hardware detection in home-modules/desktop/swaybar/status-generator.py

**Network Status Block**:
- [X] T020 [P] [US1] Implement NetworkState dataclass in home-modules/desktop/swaybar/blocks/network.py with get_icon(), get_color(), get_tooltip(), to_status_block()
- [X] T021 [P] [US1] Implement NetworkManager D-Bus query in home-modules/desktop/swaybar/blocks/network.py using pydbus (get_network_state function)
- [X] T022 [US1] Add network status block integration to main loop in home-modules/desktop/swaybar/status-generator.py

**Bluetooth Status Block**:
- [X] T023 [P] [US1] Implement BluetoothState dataclass in home-modules/desktop/swaybar/blocks/bluetooth.py with get_icon(), get_color(), get_tooltip(), to_status_block()
- [X] T024 [P] [US1] Implement BlueZ D-Bus query in home-modules/desktop/swaybar/blocks/bluetooth.py using pydbus (get_bluetooth_state function, get_connected_devices)
- [X] T025 [US1] Add bluetooth status block integration to main loop with hardware detection in home-modules/desktop/swaybar/status-generator.py

**Status Generator Main Loop**:
- [X] T026 [US1] Implement periodic update loop in home-modules/desktop/swaybar/status-generator.py with interval-based polling (battery: 30s, volume: 1s, network: 5s, bluetooth: 10s)
- [X] T027 [US1] Add JSON array formatting and stdout printing in home-modules/desktop/swaybar/status-generator.py following i3bar protocol
- [X] T028 [US1] Add error handling for missing hardware (no battery, no bluetooth adapter) with graceful degradation

**NixOS Integration**:
- [X] T029 [US1] Configure Nerd Fonts dependency in home-modules/desktop/swaybar-enhanced.nix
- [X] T030 [US1] Add pydbus and Python 3.11+ dependencies to NixOS module
- [X] T031 [US1] Create default Catppuccin Mocha theme configuration in home-modules/desktop/swaybar-enhanced.nix
- [X] T032 [US1] Setup status_command in swaybar config to launch status-generator.py
- [X] T033 [US1] Add module to hetzner-sway configuration for testing

**Checkpoint**: At this point, User Story 1 should be fully functional - all status indicators visible with icons and values

---

## Phase 4: User Story 4 - Native Sway Integration Preservation (Priority: P1)

**Goal**: Retain all native Sway status bar functionality (workspace indicators, binding mode, system tray) alongside enhanced status

**Independent Test**: Verify all native Sway status bar features (workspaces, binding modes, system tray) continue to function as expected with enhanced status elements present

### Implementation for User Story 4

- [X] T034 [P] [US4] Verify swaybar config preserves workspace indicators in home-modules/desktop/swaybar-enhanced.nix
- [X] T035 [P] [US4] Verify swaybar config preserves binding_mode display in generated swaybar config
- [X] T036 [P] [US4] Verify swaybar config supports system tray (tray_output) in generated swaybar config
- [X] T037 [US4] Test workspace switching updates workspace indicators correctly with enhanced status present
- [X] T038 [US4] Test binding mode entry (workspace mode) displays correctly alongside status blocks
- [X] T039 [US4] Add documentation for native Sway feature compatibility in quickstart.md

**Checkpoint**: At this point, User Stories 1 AND 4 should both work - enhanced status does not break native Sway features

---

## Phase 5: User Story 2 - Interactive Status Controls (Priority: P2)

**Goal**: Interact with status bar elements through clicks to quickly adjust settings or access controls

**Independent Test**: Click on each status element (volume, network, bluetooth, battery) and verify appropriate controls or menus appear

### Implementation for User Story 2

**Click Event Infrastructure**:
- [X] T040 [US2] Implement stdin click event listener thread in home-modules/desktop/swaybar/status-generator.py
- [X] T041 [US2] Add click event parsing and ClickEvent deserialization in status-generator.py main loop

**Volume Click Handlers**:
- [X] T042 [P] [US2] Implement left click handler for volume (launch pavucontrol) in home-modules/desktop/swaybar/blocks/click_handler.py
- [X] T043 [P] [US2] Implement scroll up handler for volume (+5% via pactl) in home-modules/desktop/swaybar/blocks/click_handler.py
- [X] T044 [P] [US2] Implement scroll down handler for volume (-5% via pactl) in home-modules/desktop/swaybar/blocks/click_handler.py

**Network Click Handlers**:
- [X] T045 [P] [US2] Implement left click handler for network (launch nm-connection-editor) in home-modules/desktop/swaybar/blocks/click_handler.py

**Bluetooth Click Handlers**:
- [X] T046 [P] [US2] Implement left click handler for bluetooth (launch blueman-manager) in home-modules/desktop/swaybar/blocks/click_handler.py

**Battery Click Handlers**:
- [X] T047 [P] [US2] Implement left click handler for battery (show detailed power stats via notify-send or rofi) in home-modules/desktop/swaybar/blocks/click_handler.py

**Configuration**:
- [X] T048 [US2] Add click handler configuration options to NixOS module (clickHandlers.volume, network, bluetooth, battery)
- [X] T049 [US2] Add required packages to NixOS module (pavucontrol, networkmanagerapplet, blueman) in home-modules/desktop/swaybar-enhanced.nix
- [X] T050 [US2] Wire click event dispatcher in status-generator.py to call appropriate handlers based on block name

**Checkpoint**: At this point, User Stories 1, 2, and 4 should all work - users can click status elements to access controls

---

## Phase 6: User Story 3 - Enhanced Visual Feedback (Priority: P3)

**Goal**: See visual feedback when hovering over status bar elements with tooltips showing additional context

**Independent Test**: Hover over each status element and verify visual feedback (tooltip with detailed information) appears

### Implementation for User Story 3

**Note**: Swaybar does not natively support hover tooltips via i3bar protocol. This requires either:
1. External tooltip daemon (e.g., using layer-shell overlay)
2. Pango markup with extended information in status blocks
3. Alternative approach using rofi/wofi on hover simulation

**Simplified Approach (Pango Markup)**:
- [X] T051 [P] [US3] Enhance battery status block to include tooltip text in full_text via pango markup in home-modules/desktop/swaybar/blocks/battery.py (e.g., battery percentage + time remaining)
- [X] T052 [P] [US3] Enhance network status block to include signal strength in full_text in home-modules/desktop/swaybar/blocks/network.py
- [X] T053 [P] [US3] Enhance bluetooth status block to show connected device count in full_text in home-modules/desktop/swaybar/blocks/bluetooth.py
- [X] T054 [US3] Add visual state indicators via color changes (urgent flag for low battery) in status block generation

**Alternative Approach (Future Enhancement)**:
- [X] T055 [US3] Research tooltip daemon options for Wayland (wl-tooltip, mako notification on hover) - document in research.md for future implementation

**Checkpoint**: At this point, all user stories (1, 2, 3, 4) should work - enhanced visual feedback via markup and colors

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

**Testing & Validation**:
- [X] T056 [P] Create unit tests for VolumeState in tests/swaybar/unit/test_volume.py (test get_icon, get_color, to_status_block)
- [X] T057 [P] Create unit tests for BatteryState in tests/swaybar/unit/test_battery.py (test get_icon, get_color, get_tooltip, to_status_block)
- [ ] T058 [P] Create unit tests for NetworkState in tests/swaybar/unit/test_network.py (test get_icon, get_color, get_tooltip, to_status_block)
- [ ] T059 [P] Create unit tests for BluetoothState in tests/swaybar/unit/test_bluetooth.py (test get_icon, get_color, get_tooltip, to_status_block)
- [ ] T060 [P] Create integration test for status-generator.py in tests/swaybar/integration/test_status_generator.py (test full update cycle, JSON output)
- [ ] T061 [P] Create click handler integration tests in tests/swaybar/integration/test_click_handler.py (test subprocess launching)

**Documentation**:
- [X] T062 [P] Update quickstart.md with installation instructions and configuration examples
- [X] T063 [P] Add troubleshooting section to quickstart.md (status bar not updating, icons not displaying, click handlers not working)
- [X] T064 [P] Add performance benchmarking section to quickstart.md (CPU/memory usage monitoring)
- [ ] T065 [P] Update CLAUDE.md with swaybar enhanced status documentation and keybindings reference

**Code Quality**:
- [X] T066 [P] Add type hints to all functions in status-generator.py and block modules
- [X] T067 [P] Add error handling for D-Bus service unavailable scenarios with fallback to CLI tools
- [X] T068 [P] Add logging infrastructure with configurable log levels (DEBUG, INFO, WARNING) in status-generator.py
- [X] T069 Code cleanup and refactoring - extract common patterns into utility functions

**Performance & Optimization**:
- [ ] T070 [P] Implement D-Bus signal subscription for battery changes (replace polling) in home-modules/desktop/swaybar/blocks/battery.py
- [ ] T071 [P] Implement D-Bus signal subscription for network changes (replace polling) in home-modules/desktop/swaybar/blocks/network.py
- [ ] T072 [P] Implement D-Bus signal subscription for bluetooth changes (replace polling) in home-modules/desktop/swaybar/blocks/bluetooth.py
- [ ] T073 Optimize JSON serialization to reduce CPU overhead in main loop
- [ ] T074 Add performance monitoring (measure update latency <16ms target)

**Security & Hardening**:
- [X] T075 [P] Validate D-Bus responses to prevent injection attacks (sanitize SSID, device names)
- [X] T076 [P] Add subprocess timeout for click handlers to prevent hanging processes
- [X] T077 Implement graceful shutdown on SIGTERM/SIGINT signals

**Deployment & Configuration**:
- [ ] T078 Test on M1 MacBook Pro configuration (verify single display, hardware detection)
- [ ] T079 Test on hetzner-sway configuration (verify headless displays, VNC access)
- [ ] T080 Validate quickstart.md instructions end-to-end on fresh NixOS install
- [ ] T081 Create example configurations for different color themes (catppuccin, dracula, nord)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational phase completion - MVP story
- **User Story 4 (Phase 4)**: Depends on Foundational phase completion - Can run in parallel with US1
- **User Story 2 (Phase 5)**: Depends on US1 completion (needs status blocks to exist)
- **User Story 3 (Phase 6)**: Depends on US1 completion (enhances existing blocks)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1) - Visual Status Monitoring**: Can start after Foundational (Phase 2) - MVP story, no dependencies on other stories
- **User Story 4 (P1) - Native Sway Integration**: Can start after Foundational (Phase 2) - Independent of US1 but validates compatibility
- **User Story 2 (P2) - Interactive Controls**: Depends on US1 (needs status blocks to click) - Can run in parallel with US3 and US4
- **User Story 3 (P3) - Visual Feedback**: Depends on US1 (enhances existing blocks) - Can run in parallel with US2 and US4

### Within Each User Story

**User Story 1 (Visual Status)**:
1. Implement all state dataclasses in parallel (VolumeState, BatteryState, NetworkState, BluetoothState) → T014, T017, T020, T023
2. Implement all D-Bus query functions in parallel (volume via pactl, battery via UPower, network via NetworkManager, bluetooth via BlueZ) → T015, T018, T021, T024
3. Integrate blocks into main loop sequentially → T016, T019, T022, T025
4. Implement main loop and JSON output → T026, T027, T028
5. NixOS integration tasks can run in parallel → T029-T033

**User Story 2 (Interactive Controls)**:
1. Click event infrastructure first → T040, T041
2. All click handlers can run in parallel → T042-T047
3. Configuration and wiring → T048-T050

**User Story 3 (Visual Feedback)**:
- All markup enhancement tasks can run in parallel → T051-T054

### Parallel Opportunities

- All Setup tasks (T001-T004) can run in parallel
- All Foundational dataclass tasks (T005-T007, T009) can run in parallel
- US1 state dataclasses (T014, T017, T020, T023) can run in parallel
- US1 D-Bus query implementations (T015, T018, T021, T024) can run in parallel
- US1 NixOS integration tasks (T029-T033) can run in parallel
- US2 click handler implementations (T042-T047) can run in parallel
- US3 markup enhancement tasks (T051-T054) can run in parallel
- All test tasks (T056-T061) can run in parallel
- All documentation tasks (T062-T065) can run in parallel
- All code quality tasks (T066-T069) can run in parallel
- All performance optimization tasks (T070-T074) can run in parallel
- All security tasks (T075-T077) can run in parallel

---

## Parallel Example: User Story 1 (Visual Status Monitoring)

```bash
# Launch all state dataclass implementations together:
Task T014: "Implement VolumeState dataclass in home-modules/desktop/swaybar/blocks/volume.py"
Task T017: "Implement BatteryState dataclass in home-modules/desktop/swaybar/blocks/battery.py"
Task T020: "Implement NetworkState dataclass in home-modules/desktop/swaybar/blocks/network.py"
Task T023: "Implement BluetoothState dataclass in home-modules/desktop/swaybar/blocks/bluetooth.py"

# Then launch all D-Bus query implementations together:
Task T015: "Implement volume query via pactl in home-modules/desktop/swaybar/blocks/volume.py"
Task T018: "Implement UPower D-Bus query in home-modules/desktop/swaybar/blocks/battery.py"
Task T021: "Implement NetworkManager D-Bus query in home-modules/desktop/swaybar/blocks/network.py"
Task T024: "Implement BlueZ D-Bus query in home-modules/desktop/swaybar/blocks/bluetooth.py"

# NixOS integration tasks can all run in parallel:
Task T029: "Configure Nerd Fonts dependency"
Task T030: "Add pydbus and Python 3.11+ dependencies"
Task T031: "Create default Catppuccin Mocha theme"
Task T032: "Setup status_command in swaybar config"
Task T033: "Add module to hetzner-sway configuration"
```

---

## Parallel Example: User Story 2 (Interactive Controls)

```bash
# Launch all click handler implementations together:
Task T042: "Implement left click handler for volume (pavucontrol)"
Task T043: "Implement scroll up handler for volume (+5%)"
Task T044: "Implement scroll down handler for volume (-5%)"
Task T045: "Implement left click handler for network (nm-connection-editor)"
Task T046: "Implement left click handler for bluetooth (blueman-manager)"
Task T047: "Implement left click handler for battery (power stats)"
```

---

## Implementation Strategy

### MVP First (User Story 1 + 4 Only)

1. Complete Phase 1: Setup → Directory structure ready
2. Complete Phase 2: Foundational → Core dataclasses and i3bar protocol handler ready (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 → Visual status monitoring functional
4. Complete Phase 4: User Story 4 → Verify native Sway features preserved
5. **STOP and VALIDATE**: Test status bar shows all indicators with Nerd Font icons, native Sway features work
6. Deploy to hetzner-sway for testing

**MVP delivers**: All system status visible at a glance with icons, no native Sway features broken

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (T001-T013)
2. Add User Story 1 → Test independently → **MVP deployed** (visual status monitoring)
3. Add User Story 4 → Test independently → Validate compatibility (native Sway features preserved)
4. Add User Story 2 → Test independently → Deploy/Demo (interactive controls added)
5. Add User Story 3 → Test independently → Deploy/Demo (visual feedback enhanced)
6. Add Polish → Final testing → Production-ready

Each story adds value without breaking previous stories:
- **After US1**: Users see system status with icons
- **After US1+US4**: Confirmed no native features broken
- **After US1+US2+US4**: Users can click to access controls
- **After US1+US2+US3+US4**: Enhanced visual feedback with tooltips

### Parallel Team Strategy

With multiple developers:

1. **Team completes Setup + Foundational together** (T001-T013)
2. **Once Foundational is done, split work**:
   - **Developer A**: User Story 1 - Visual Status (T014-T033)
   - **Developer B**: User Story 4 - Native Sway Integration (T034-T039)
3. **After US1 complete, add interactivity**:
   - **Developer A**: User Story 2 - Interactive Controls (T040-T050)
   - **Developer B**: User Story 3 - Visual Feedback (T051-T055)
4. **Final polish in parallel**:
   - **Developer A**: Tests (T056-T061)
   - **Developer B**: Documentation (T062-T065)
   - **Developer C**: Performance & Security (T066-T077)

---

## Notes

- **[P] tasks** = different files, no dependencies, can run in parallel
- **[Story] label** maps task to specific user story (US1, US2, US3, US4) for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group of tasks
- Stop at any checkpoint to validate story independently
- **Performance targets**: <2% CPU usage, <50MB memory, <16ms render time per update
- **Hardware detection**: Battery and Bluetooth blocks auto-hide if hardware not present
- **Icon font**: Nerd Fonts required (already deployed on hetzner-sway)
- **D-Bus dependencies**: pydbus for Python, system services (UPower, NetworkManager, BlueZ)
- **Click handlers**: External tools (pavucontrol, nm-connection-editor, blueman-manager) required

---

## Total Task Count: 81 tasks

### Tasks per User Story:
- **Setup (Phase 1)**: 4 tasks
- **Foundational (Phase 2)**: 9 tasks (BLOCKING)
- **User Story 1 (P1 - Visual Status)**: 20 tasks (MVP)
- **User Story 4 (P1 - Native Integration)**: 6 tasks (MVP validation)
- **User Story 2 (P2 - Interactive Controls)**: 11 tasks
- **User Story 3 (P3 - Visual Feedback)**: 5 tasks
- **Polish (Final Phase)**: 26 tasks (testing, docs, optimization, security)

### Suggested MVP Scope:
- **Phases 1-4** (Setup + Foundational + US1 + US4) = **39 tasks**
- Delivers fully functional visual status bar with native Sway compatibility
- Estimated effort: 2-3 days for experienced developer

### Parallel Opportunities Identified:
- **14 parallel groups** across all phases (40+ tasks can run concurrently with proper team distribution)
- Highest parallelism in US1 implementation (8+ tasks), Polish phase (15+ tasks), and Foundational setup (4+ tasks)
