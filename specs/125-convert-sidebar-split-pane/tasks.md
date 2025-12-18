# Tasks: Monitoring Panel Click-Through Fix and Docking Mode

**Input**: Design documents from `/specs/125-convert-sidebar-split-pane/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/scripts.md

**Tests**: Not explicitly requested in feature specification - tests are omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions (This Feature)

- **Nix modules**: `home-modules/desktop/`
- **Generated config**: `~/.config/eww-monitoring-panel/`
- **State files**: `~/.local/state/eww-monitoring-panel/`
- **Spec docs**: `specs/125-convert-sidebar-split-pane/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare state directories and remove deprecated code

- [X] T001 Create state directory structure at `$XDG_STATE_HOME/eww-monitoring-panel/` in home-modules/desktop/eww-monitoring-panel.nix
- [X] T002 [P] Remove `toggle-panel-focus` script from home-modules/desktop/eww-monitoring-panel.nix
- [X] T003 [P] Remove `exit-monitor-mode` script from home-modules/desktop/eww-monitoring-panel.nix
- [X] T004 [P] Remove Sway mode "📊 Panel" from home-modules/desktop/sway.nix

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core window definitions and eww variables that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Add `panel_dock_mode` boolean variable (default: false) to eww.yuck in home-modules/desktop/eww-monitoring-panel.nix
- [X] T006 Define `monitoring-panel-overlay` defwindow with `:exclusive false` in home-modules/desktop/eww-monitoring-panel.nix
- [X] T007 Define `monitoring-panel-docked` defwindow with `:exclusive true` and `:reserve (struts :side "right" :distance "554px")` in home-modules/desktop/eww-monitoring-panel.nix
- [X] T008 Extract shared `monitoring-panel-content` widget from existing defwindow in home-modules/desktop/eww-monitoring-panel.nix
- [X] T009 Update systemd service to read dock-mode state file on startup and open correct window in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: Foundation ready - two window definitions exist, eww variables defined, service knows initial mode

---

## Phase 3: User Story 1 - Click-Through When Panel Hidden (Priority: P1) 🎯 MVP

**Goal**: When the monitoring panel is hidden, mouse clicks pass through to underlying windows

**Independent Test**: Hide panel (`Mod+M`), click on window in right 550px region - click should be received by that window

### Implementation for User Story 1

- [X] T010 [US1] Update `toggle-monitoring-panel` script to use `eww close`/`eww open` instead of revealer-only for overlay mode in home-modules/desktop/eww-monitoring-panel.nix
- [X] T011 [US1] Ensure `panel_visible` eww variable syncs with window open/close state in home-modules/desktop/eww-monitoring-panel.nix
- [X] T012 [US1] Verify debounce lockfile mechanism (1-second) is preserved in toggle-monitoring-panel script
- [ ] T013 [US1] Test click-through by hiding panel and clicking on windows in panel region

**Checkpoint**: US1 complete - hiding panel enables click-through to underlying windows

---

## Phase 4: User Story 2 - Docked Panel Mode with Reserved Space (Priority: P2)

**Goal**: Panel can reserve screen space via Sway exclusive zone, causing tiled windows to resize

**Independent Test**: Enable dock mode, tile windows - windows should use (monitor_width - panel_width) horizontal space

### Implementation for User Story 2

- [X] T014 [US2] Create `toggle-panel-dock-mode` script per contracts/scripts.md in home-modules/desktop/eww-monitoring-panel.nix
- [X] T015 [US2] Implement state file read/write at `$XDG_STATE_HOME/eww-monitoring-panel/dock-mode` in toggle-panel-dock-mode script
- [X] T016 [US2] Add screen width validation: refuse dock if (monitor_width - panel_width) < 400px in toggle-panel-dock-mode script
- [X] T017 [US2] Add swaync notification when dock refused due to narrow screen in toggle-panel-dock-mode script
- [X] T018 [US2] Implement window swap logic: close current mode window, open other mode window in toggle-panel-dock-mode script
- [ ] T019 [US2] Test docked mode: tile windows and verify they resize to fit remaining space

**Checkpoint**: US2 complete - dock mode reserves space, windows resize accordingly

---

## Phase 5: User Story 3 - Toggle Between Overlay and Docked Modes (Priority: P2)

**Goal**: `Mod+Shift+M` cycles between overlay mode and docked mode

**Independent Test**: Press `Mod+Shift+M` - observe mode indicator change and window geometry change within 500ms

### Implementation for User Story 3

- [X] T020 [US3] Update `Mod+Shift+M` keybinding to exec `toggle-panel-dock-mode` in home-modules/desktop/sway-keybindings.nix
- [X] T021 [US3] Add mode indicator widget to panel header (📌 docked, 🔳 overlay) in home-modules/desktop/eww-monitoring-panel.nix
- [X] T022 [US3] Add CSS classes `.mode-indicator.docked` and `.mode-indicator.overlay` in home-modules/desktop/eww-monitoring-panel.nix
- [X] T023 [US3] Implement docked-but-hidden behavior: revealer hides content but window stays open (per FR-011) in toggle-monitoring-panel script
- [ ] T024 [US3] Test mode persistence: toggle mode, restart session, verify mode restored

**Checkpoint**: US3 complete - mode toggle works via keybinding, persists across sessions

---

## Phase 6: User Story 4 - Preserve CPU Optimizations (Priority: P1)

**Goal**: Panel maintains <7% CPU contribution regardless of mode

**Independent Test**: Monitor CPU usage with panel visible in each mode over 60 seconds

### Implementation for User Story 4

- [X] T025 [US4] Verify `deflisten` pattern preserved for monitoring_data in both window definitions
- [X] T026 [US4] Verify `:run-while false` preserved for disabled tabs (tabs 2-6) in monitoring-panel-content widget
- [X] T027 [US4] Verify 30-second polling interval preserved for build_health_data defpoll
- [ ] T028 [US4] Test CPU usage: measure over 60s in overlay mode, docked mode, and during transitions
- [ ] T029 [US4] Verify no memory leaks during repeated mode toggles (10 cycles, check memory)

**Checkpoint**: US4 complete - CPU optimizations preserved, no performance regression

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, screenshots, and documentation

- [ ] T030 [P] Take "after" screenshots with grim: overlay visible, overlay hidden, docked visible, docked hidden
- [ ] T031 [P] Update quickstart.md with troubleshooting for any new edge cases discovered
- [X] T032 Run `nixos-rebuild dry-build --flake .#hetzner-sway` to verify build succeeds
- [ ] T033 Deploy to hetzner-sway and run full acceptance scenario validation per spec.md
- [X] T034 Update CLAUDE.md keybindings section with new `Mod+Shift+M` behavior

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - US1 and US4 are P1 priority - complete first
  - US2 and US3 are P2 priority - can proceed in parallel after US1
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational - Uses window definitions from Foundation
- **User Story 3 (P2)**: Depends on US2 (dock mode script must exist before keybinding can call it)
- **User Story 4 (P1)**: Can start after Foundational - Verification only, no code changes

### Within Each User Story

- Script implementation before keybinding updates
- Widget changes before CSS styling
- Implementation before testing tasks

### Parallel Opportunities

- T002, T003, T004 in Setup can run in parallel (removing deprecated code)
- T030, T031 in Polish can run in parallel (documentation tasks)
- US1 and US4 can run in parallel after Foundation (different files, verification vs implementation)

---

## Parallel Example: Phase 1 Setup

```bash
# Launch all deprecated code removal tasks together:
Task: "Remove toggle-panel-focus script from home-modules/desktop/eww-monitoring-panel.nix"
Task: "Remove exit-monitor-mode script from home-modules/desktop/eww-monitoring-panel.nix"
Task: "Remove Sway mode '📊 Panel' from home-modules/desktop/sway.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (remove deprecated code)
2. Complete Phase 2: Foundational (window definitions)
3. Complete Phase 3: User Story 1 (click-through fix)
4. **STOP and VALIDATE**: Test click-through behavior
5. This alone delivers significant value (fixes usability blocker)

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Test → Deploy (fixes click-through blocker!)
3. Add User Story 4 → Test → Verify no CPU regression
4. Add User Story 2 → Test → Deploy (adds dock mode)
5. Add User Story 3 → Test → Deploy (adds keybinding toggle)
6. Polish → Final screenshots and documentation

### Recommended Execution Order

1. **T001-T004**: Setup (parallel where marked)
2. **T005-T009**: Foundational (sequential, builds on each other)
3. **T010-T013**: US1 Click-Through (sequential)
4. **T025-T029**: US4 CPU Verification (can parallel with US1 testing)
5. **T014-T019**: US2 Dock Mode (sequential)
6. **T020-T024**: US3 Mode Toggle (sequential, depends on US2)
7. **T030-T034**: Polish (parallel where marked)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All code changes are in Nix files - rebuild required to test
- Use `nixos-rebuild dry-build` before `switch` for safety
- Take screenshots with `grim -o <output> <filename>` for comparison
- State file format: "overlay" or "docked" (no newline, case-sensitive)
