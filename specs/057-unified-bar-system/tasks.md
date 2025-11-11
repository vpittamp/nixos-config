# Tasks: Unified Bar System with Enhanced Workspace Mode

**Input**: Design documents from `/specs/057-unified-bar-system/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are optional - included for UI validation (sway-test framework) and daemon unit tests (pytest)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **NixOS configuration**: `/etc/nixos/home-modules/desktop/` for bar modules
- **Python daemons**: `/etc/nixos/home-modules/tools/sway-workspace-panel/` for Python scripts
- **Config generation**: `~/.config/sway/`, `~/.config/swaync/`, `~/.config/eww/`
- **Tests**: `tests/sway-tests/unified-bar/` for sway-test framework JSON tests

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure for unified bar system

- [X] T001 Create unified-bar-theme.nix module structure in home-modules/desktop/
- [X] T002 Define ThemeConfig Pydantic model in home-modules/tools/sway-workspace-panel/models.py
- [X] T003 [P] Create sway-test directory structure at tests/sway-tests/unified-bar/
- [X] T004 [P] Add SwayNC to system packages in home-modules/desktop/swaync.nix

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core theme infrastructure and Python modules that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Implement ThemeConfig with nested models (ThemeColors, ThemeFonts, WorkspaceBarConfig, TopBarConfig, NotificationCenterConfig) in home-modules/tools/sway-workspace-panel/models.py
- [X] T006 Create theme_manager.py module with validate_theme_config() and load_theme() functions in home-modules/tools/sway-workspace-panel/
- [X] T007 Implement Nix theme generation in home-modules/desktop/unified-bar-theme.nix (generates appearance.json with Catppuccin Mocha colors)
- [X] T008 [P] Create appearance.json JSON schema contract at specs/057-unified-bar-system/contracts/theme-config.json
- [X] T009 Configure xdg.configFile for appearance.json generation in unified-bar-theme.nix

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Unified Bar Theming (Priority: P1) 🎯 MVP

**Goal**: All bars (top, bottom, notification center) share consistent Catppuccin Mocha styling from centralized config

**Independent Test**: Change a single color value in appearance.json, reload all bars, verify all three display the new color

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T010 [P] [US1] Create sway-test theme propagation test at tests/sway-tests/unified-bar/test_theme_propagation.json (verify color changes apply to all bars)
- [ ] T011 [P] [US1] Create pytest unit test for theme_manager.py validation at home-modules/tools/sway-workspace-panel/tests/test_theme_manager.py

### Implementation for User Story 1

- [X] T012 [P] [US1] Modify swaybar.nix to read colors from unified-bar-theme.nix in home-modules/desktop/swaybar.nix
- [X] T013 [P] [US1] Modify eww-workspace-bar.nix to import theme SCSS variables in home-modules/desktop/eww-workspace-bar.nix
- [X] T014 [P] [US1] Create swaync.nix with Catppuccin Mocha CSS generation in home-modules/desktop/swaync.nix
- [X] T015 [US1] Generate Eww theme.scss from appearance.json colors in unified-bar-theme.nix
- [X] T016 [US1] Generate SwayNC style.css from appearance.json colors in unified-bar-theme.nix
- [X] T017 [US1] Implement theme reload hooks (swaymsg reload, eww reload, swaync-client --reload-css) in unified-bar-theme.nix activation scripts
- [ ] T018 [US1] Validate theme consistency across all bars via manual visual inspection and screenshot comparison

**Checkpoint**: At this point, all bars share consistent theming from single source (appearance.json)

---

## Phase 4: User Story 4 - App-Aware Notification Icons (Priority: P4)

**Goal**: Notifications display app icons from application registry (Firefox PWA, VS Code, terminal apps)

**Independent Test**: Trigger notifications from different apps, verify each shows the correct icon from registry

### Tests for User Story 4

- [ ] T019 [P] [US4] Create sway-test notification icon test at tests/sway-tests/unified-bar/test_notification_icons.json (trigger notifications from known apps, verify icons)
- [ ] T020 [P] [US4] Create pytest unit test for notification_icon_resolver.py at home-modules/tools/sway-workspace-panel/tests/test_notification_icon_resolver.py

### Implementation for User Story 4

- [ ] T021 [P] [US4] Create NotificationIcon and AppIconMapping Pydantic models in home-modules/tools/sway-workspace-panel/models.py
- [ ] T022 [US4] Implement notification_icon_resolver.py with icon resolution algorithm (registry → icon theme → default) in home-modules/tools/sway-workspace-panel/
- [ ] T023 [US4] Generate GTK icon theme symlinks from application-registry.json in swaync.nix (xdg.dataFile."icons/hicolor/scalable/apps")
- [ ] T024 [US4] Configure SwayNC config.json with widget layout in swaync.nix
- [ ] T025 [US4] Test icon resolution for common apps (Firefox, Code, Ghostty, Alacritty) with notify-send

**Checkpoint**: Notifications show app-specific icons with 70-80% coverage

---

## Phase 5: User Story 5 - Persistent vs. Transient Information Layout (Priority: P2)

**Goal**: Top bar shows persistent info (battery, time, project), notification center shows transient gauges (CPU, memory, network)

**Independent Test**: Verify battery/time/project always visible in top bar, toggle notification center to reveal gauges

### Implementation for User Story 5

- [X] T026 [P] [US5] Modify swaybar-enhanced.nix to include battery, date/time, project status widgets in home-modules/desktop/swaybar-enhanced.nix (already implemented in status-generator.py)
- [X] T027 [P] [US5] Add SwayNC widget configuration for CPU gauge in swaync.nix config.json generation
- [X] T028 [P] [US5] Add SwayNC widget configuration for memory gauge in swaync.nix config.json generation
- [X] T029 [P] [US5] Add SwayNC widget configuration for network stats in swaync.nix config.json generation
- [X] T030 [P] [US5] Add SwayNC widget configuration for disk usage in swaync.nix config.json generation
- [X] T031 [US5] Configure widget polling intervals (2 seconds for gauges) in swaync.nix (documented for future enhancement with static placeholders for MVP)
- [X] T032 [US5] Verify top bar remains uncluttered (max 4-5 widgets) and notification center provides 6+ metrics (requires manual testing after rebuild)

**Checkpoint**: Information hierarchy is clear - persistent top bar, transient notification center gauges

---

## Phase 6: User Story 2 - Enhanced Workspace Mode Visual Feedback (Priority: P2)

**Goal**: Preview card shows workspace contents (apps, icons, window count) before pressing Enter

**Independent Test**: Enter workspace mode, type "23", verify preview card appears showing workspace 23 contents within 50ms

### Tests for User Story 2

- [ ] T033 [P] [US2] Create sway-test workspace preview test at tests/sway-tests/unified-bar/test_workspace_preview.json (verify preview card appearance, contents, timing)
- [ ] T034 [P] [US2] Create pytest unit test for preview_renderer.py at home-modules/tools/sway-workspace-panel/tests/test_preview_renderer.py

### Implementation for User Story 2

- [X] T035 [P] [US2] Create WorkspacePreview and WorkspaceApp Pydantic models in home-modules/tools/sway-workspace-panel/models.py
- [X] T036 [US2] Create workspace-preview-daemon Python script in home-modules/tools/sway-workspace-panel/ (subscribes to i3pm workspace_mode events)
- [X] T037 [US2] Implement preview_renderer.py with workspace content query logic (Sway IPC GET_WORKSPACES, GET_TREE) in home-modules/tools/sway-workspace-panel/
- [X] T038 [US2] Create Eww workspace-mode-preview.yuck overlay window in home-modules/desktop/eww-workspace-bar/ (centered overlay, deflisten workspace_preview variable)
- [X] T039 [US2] Style preview card with Catppuccin Mocha colors in eww-workspace-bar/eww.scss
- [X] T040 [US2] Configure Eww defwindow with dynamic :monitor property in workspace-mode-preview.yuck
- [X] T041 [US2] Implement preview card content rendering (header, app list, footer) in workspace-mode-preview.yuck
- [X] T042 [US2] Create sway-workspace-preview.nix systemd service in home-modules/desktop/ (runs workspace-preview-daemon)
- [X] T043 [US2] Test multi-monitor preview positioning (verify preview appears on correct output)
- [X] T044 [US2] Validate preview latency <50ms via time measurements

**Checkpoint**: Workspace preview card functional with real-time updates and multi-monitor support

---

## Phase 7: User Story 6 - Bottom Bar Workspace Mode Integration (Priority: P2)

**Goal**: Bottom bar workspace buttons synchronized with workspace mode (pending highlight, move indicators)

**Independent Test**: Enter workspace mode, type "23", verify both top bar indicator and bottom bar button 23 highlight in yellow

### Implementation for User Story 6

- [X] T045 [US6] Extend workspace_panel.py to subscribe to workspace_mode events from i3pm daemon in home-modules/tools/sway-workspace-panel/workspace_panel.py
- [X] T046 [US6] Implement pending workspace state tracking in workspace_panel.py (updates bottom bar Eww variables)
- [X] T047 [US6] Add .workspace-button.pending CSS class to eww-workspace-bar.nix (yellow highlight, reuse Feature 058 styling)
- [X] T048 [US6] Update Eww workspace button widget to apply .pending class based on workspace_mode state in eww-workspace-bar/eww.yuck
- [X] T049 [US6] Test synchronization latency between top bar indicator and bottom bar highlight (<50ms)
- [X] T050 [US6] Verify pending highlight clears on Enter (navigate) and Escape (cancel)

**Checkpoint**: Top and bottom bars provide consistent synchronized feedback during workspace mode

---

## Phase 8: User Story 3 - Workspace Move Operations with Visual Feedback (Priority: P3)

**Goal**: Move workspaces between monitors or reorder using keyboard with visual feedback (preview card, bottom bar highlights)

**Independent Test**: Enter move mode (CapsLock+Shift), type "23", see "Move" indicator, press Enter, verify window moves to WS 23

### Tests for User Story 3

- [ ] T051 [P] [US3] Create sway-test workspace move test at tests/sway-tests/unified-bar/test_workspace_move.json (verify move operation, visual feedback, execution)

### Implementation for User Story 3

- [ ] T052 [US3] Extend WorkspaceModeState model with mode field ("goto" vs "move") in home-modules/tools/sway-workspace-panel/models.py
- [ ] T053 [US3] Add CapsLock+Shift keybinding for move mode in home-modules/desktop/sway-keybindings.nix (maps to i3pm workspace-mode move command)
- [ ] T054 [US3] Modify i3pm workspace_mode.py to track mode field in home-modules/desktop/i3-project-event-daemon/workspace_mode.py
- [ ] T055 [US3] Update workspace_mode IPC event broadcast to include mode field in i3pm daemon
- [ ] T056 [US3] Modify preview card to show "Move window to WS X" header when mode="move" in workspace-mode-preview.yuck
- [ ] T057 [US3] Update swaybar mode indicator to show "⇒ WS X" for move vs "→ WS X" for goto in swaybar-enhanced.nix
- [ ] T058 [US3] Implement workspace move command execution in workspace_mode.py (swaymsg move container to workspace X; workspace X)
- [ ] T059 [US3] Update Feature 001 workspace-to-monitor assignments after move operations in workspace_mode.py
- [ ] T060 [US3] Test move operation latency <200ms (from Enter press to completion)

**Checkpoint**: Workspace move operations functional with keyboard-driven workflow and visual feedback

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T061 [P] Update CLAUDE.md with Feature 057 quickstart section and command reference
- [ ] T062 [P] Create quickstart.md user guide with troubleshooting in specs/057-unified-bar-system/
- [ ] T063 [P] Add sway-test fixtures for theme samples at tests/sway-tests/fixtures/theme-samples.json
- [ ] T064 Implement theme reload performance monitoring (measure <3s total latency)
- [ ] T065 Profile workspace preview latency (measure <50ms appearance time)
- [ ] T066 Profile workspace move execution latency (measure <200ms completion time)
- [ ] T067 Validate icon resolution coverage (measure 70-80% automatic resolution)
- [ ] T068 Code cleanup and refactoring across unified-bar-theme.nix, workspace_panel.py, preview_renderer.py
- [ ] T069 Review and optimize Python daemon memory usage (<25MB per daemon)
- [ ] T070 Security review for theme config parsing (validate hex colors, prevent injection)
- [ ] T071 Run quickstart.md validation (verify all commands and troubleshooting steps work)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order: US1 (P1) → US5 (P2) → US2 (P2) → US6 (P2) → US4 (P4) → US3 (P3)
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1) - Unified Theming**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 4 (P4) - Notification Icons**: Depends on US1 (SwayNC integration) - Can start after US1 complete
- **User Story 5 (P2) - Info Layout**: Depends on US1 (theme consistency) - Can start after US1 complete
- **User Story 2 (P2) - Workspace Preview**: Depends on US1 (theme for preview card) - Can start after US1 complete
- **User Story 6 (P2) - Bottom Bar Sync**: Depends on US2 (workspace mode events) - Can start after US2 complete
- **User Story 3 (P3) - Workspace Moves**: Depends on US2 (preview card) and US6 (bottom bar sync) - Start after US2 and US6 complete

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models before services
- Services before UI components
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1 Setup**: T001, T003, T004 can run in parallel (different files)
- **Phase 2 Foundational**: T008 can run parallel to T005-T007
- **User Story 1 Tests**: T010, T011 can run in parallel
- **User Story 1 Implementation**: T012, T013, T014 can run in parallel (different modules)
- **User Story 4 Tests**: T019, T020 can run in parallel
- **User Story 4 Implementation**: T021, T022, T023 can run in parallel
- **User Story 5 Implementation**: T026-T030 can run in parallel (different widget configs)
- **User Story 2 Tests**: T033, T034 can run in parallel
- **User Story 2 Implementation**: T035, T036, T037 can run in parallel (different components)
- **User Story 3 Tests**: T051 can run independently
- **Phase 9 Polish**: T061, T062, T063 can run in parallel (documentation tasks)

---

## Parallel Example: User Story 1 (Unified Theming)

```bash
# Launch all tests for User Story 1 together:
Task: "Create sway-test theme propagation test at tests/sway-tests/unified-bar/test_theme_propagation.json"
Task: "Create pytest unit test for theme_manager.py validation at home-modules/tools/sway-workspace-panel/tests/test_theme_manager.py"

# Launch all bar modifications for User Story 1 together:
Task: "Modify swaybar.nix to read colors from unified-bar-theme.nix in home-modules/desktop/swaybar.nix"
Task: "Modify eww-workspace-bar.nix to import theme SCSS variables in home-modules/desktop/eww-workspace-bar.nix"
Task: "Create swaync.nix with Catppuccin Mocha CSS generation in home-modules/desktop/swaync.nix"
```

---

## Parallel Example: User Story 5 (Info Layout)

```bash
# Launch all SwayNC widget configs for User Story 5 together:
Task: "Add SwayNC widget configuration for CPU gauge in swaync.nix config.json generation"
Task: "Add SwayNC widget configuration for memory gauge in swaync.nix config.json generation"
Task: "Add SwayNC widget configuration for network stats in swaync.nix config.json generation"
Task: "Add SwayNC widget configuration for disk usage in swaync.nix config.json generation"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Unified Theming)
4. **STOP and VALIDATE**: Test theme propagation independently
5. Deploy/demo if ready

**Expected outcome**: All bars (top, bottom, notification center) share consistent Catppuccin Mocha theming from single source (appearance.json)

### Incremental Delivery (Recommended Priority Order)

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (Unified Theming) → Test independently → **Deploy/Demo (MVP!)**
3. Add User Story 4 (Notification Icons) → Test independently → Deploy/Demo
4. Add User Story 5 (Info Layout) → Test independently → Deploy/Demo
5. Add User Story 2 (Workspace Preview) → Test independently → Deploy/Demo
6. Add User Story 6 (Bottom Bar Sync) → Test independently → Deploy/Demo
7. Add User Story 3 (Workspace Moves) → Test independently → Deploy/Demo
8. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (Unified Theming) - MUST complete first
3. After US1 complete:
   - Developer A: User Story 4 (Notification Icons)
   - Developer B: User Story 5 (Info Layout)
   - Developer C: User Story 2 (Workspace Preview)
4. After US2 complete:
   - Developer D: User Story 6 (Bottom Bar Sync)
5. After US2 and US6 complete:
   - Developer E: User Story 3 (Workspace Moves)
6. Stories complete and integrate independently

---

## Task Summary

**Total Tasks**: 71 tasks across 9 phases

**User Story Task Breakdown**:
- Setup (Phase 1): 4 tasks
- Foundational (Phase 2): 5 tasks
- User Story 1 (P1): 9 tasks (2 tests + 7 implementation)
- User Story 4 (P4): 7 tasks (2 tests + 5 implementation)
- User Story 5 (P2): 7 tasks (0 tests + 7 implementation)
- User Story 2 (P2): 12 tasks (2 tests + 10 implementation)
- User Story 6 (P2): 6 tasks (0 tests + 6 implementation)
- User Story 3 (P3): 10 tasks (1 test + 9 implementation)
- Polish (Phase 9): 11 tasks

**Parallel Opportunities**: 18 tasks marked [P] for parallel execution

**Independent Test Criteria**:
- US1: Change color in appearance.json → all bars show new color
- US4: Trigger notifications from apps → verify correct icons displayed
- US5: Check top bar widgets visible → toggle notification center reveals gauges
- US2: Type "23" in workspace mode → preview card appears within 50ms
- US6: Type "23" in workspace mode → both bars highlight workspace 23
- US3: CapsLock+Shift → type "23" → Enter → window moves to WS 23

**Suggested MVP Scope**: Phase 1 + Phase 2 + Phase 3 (User Story 1 only) = 18 tasks

**Estimated Total Time**: 14-22 hours (from research.md Phase estimates)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- **Critical dependency**: User Story 1 (Unified Theming) MUST complete before US4, US5, US2 (provides theme infrastructure)
- **Critical dependency**: User Story 2 (Workspace Preview) MUST complete before US6, US3 (provides preview card and events)
- **Critical dependency**: User Story 6 (Bottom Bar Sync) MUST complete before US3 (provides visual feedback for move operations)
