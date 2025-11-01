# Tasks: Event-Driven Workspace Mode Navigation

**Feature Branch**: `042-event-driven-workspace-mode`
**Generated**: 2025-10-31
**Input**: Design documents from `/etc/nixos/specs/042-event-driven-workspace-mode/`

**Constitution Principle XII - Forward-Only Development**: This implementation replaces all bash script-based workspace mode navigation. No backward compatibility with legacy bash scripts. Focus on the best solution moving forward and discard code that is no longer useful or relevant.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `- [ ] [ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create foundational code structure and Pydantic models used across all user stories

- [X] T001 Create Pydantic models for workspace mode in home-modules/tools/i3pm/models/workspace_mode.py (WorkspaceModeState, WorkspaceSwitch, WorkspaceModeEvent)
- [X] T002 [P] Create CLI command structure in home-modules/tools/i3pm/cli/workspace_mode.py (argument parsing, command dispatch)
- [X] T003 [P] Create status bar block script skeleton in home-modules/desktop/i3bar/workspace_mode_block.py (event subscription, i3bar protocol)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core daemon infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete. All subsequent user stories depend on this daemon infrastructure.

- [X] T004 Create WorkspaceModeManager class in home-modules/tools/i3pm/daemon/workspace_mode.py (state management, output cache, history tracking)
- [X] T005 Register IPC methods in home-modules/tools/i3pm/daemon/main.py (workspace_mode.digit, workspace_mode.execute, workspace_mode.cancel, workspace_mode.state, workspace_mode.history)
- [X] T006 Add mode event handler in home-modules/tools/i3pm/daemon/main.py (on_mode subscription, mode entry/exit detection)
- [X] T007 Implement output cache refresh logic in home-modules/tools/i3pm/daemon/workspace_mode.py (_refresh_output_cache method with 1/2/3 monitor support)
- [X] T008 Implement event broadcasting for workspace_mode events in home-modules/tools/i3pm/daemon/workspace_mode.py (broadcast on digit, execute, cancel)

**Checkpoint**: Daemon infrastructure ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Fast Digit-Based Workspace Navigation (Priority: P1) 🎯 MVP

**Goal**: Enable users to quickly navigate to any workspace (1-70) by typing digits with <20ms latency

**Independent Test**: Press CapsLock (M1) or Ctrl+0 (Hetzner), type "23", press Enter, verify workspace 23 is focused with correct output

**Why P1**: Core value proposition - replaces slow bash scripts (70ms) with fast daemon-based processing (15ms)

### Implementation for User Story 1

- [X] T009 [P] [US1] Implement digit accumulation logic in home-modules/tools/i3pm/daemon/workspace_mode.py (add_digit method with leading zero handling)
- [X] T010 [P] [US1] Implement workspace switch execution in home-modules/tools/i3pm/daemon/workspace_mode.py (execute method with i3 IPC commands)
- [X] T011 [US1] Implement workspace_mode.digit IPC handler in home-modules/tools/i3pm/daemon/main.py (validate digit, call add_digit, broadcast event)
- [X] T012 [US1] Implement workspace_mode.execute IPC handler in home-modules/tools/i3pm/daemon/main.py (call execute, handle empty digits, broadcast event)
- [X] T013 [US1] Implement CLI digit command in home-modules/tools/i3pm/cli/workspace_mode.py (i3pm workspace-mode digit <N>)
- [X] T014 [US1] Implement CLI execute command in home-modules/tools/i3pm/cli/workspace_mode.py (i3pm workspace-mode execute)
- [X] T015 [US1] Create Sway goto_workspace mode definition in home-modules/desktop/sway-config-manager.nix modesConfContents (digit bindings 0-9, Enter, Escape calling i3pm CLI)
- [X] T016 [US1] Add M1 mode entry keybindings in home-modules/desktop/sway.nix extraConfig (bindcode 66 for CapsLock with xkb_options caps:none)
- [X] T017 [US1] Add Hetzner mode entry keybindings in home-modules/desktop/sway.nix extraConfig (bindsym Control+0)

**Checkpoint**: User Story 1 complete - workspace navigation via digit input fully functional and independently testable

---

## Phase 4: User Story 2 - Move Windows to Workspaces (Priority: P1)

**Goal**: Enable users to quickly move focused window to any workspace by typing digits

**Independent Test**: Focus window, press Shift+CapsLock, type "7", press Enter, verify window moved to workspace 7 and user followed

**Why P1**: Equal importance to goto mode - users need both navigation and window management with same performance improvement

### Implementation for User Story 2

- [X] T018 [US2] Add mode_type detection in home-modules/tools/i3pm/daemon/workspace_mode.py (enter_mode method with "goto" vs "move" parameter)
- [X] T019 [US2] Modify execute method to handle move mode in home-modules/tools/i3pm/daemon/workspace_mode.py (move container + follow for move mode)
- [X] T020 [US2] Create Sway move_workspace mode definition in home-modules/desktop/sway-config-manager.nix modesConfContents (identical digit bindings to goto mode)
- [X] T021 [US2] Add M1 move mode entry keybindings in home-modules/desktop/sway.nix extraConfig (bindcode Shift+66)
- [X] T022 [US2] Add Hetzner move mode entry keybindings in home-modules/desktop/sway.nix extraConfig (bindsym Control+Shift+0)

**Checkpoint**: User Stories 1 AND 2 both work independently - complete navigation and window management

---

## Phase 5: User Story 5 - Smart Output Focusing (Priority: P1)

**Goal**: Automatically focus correct monitor when switching workspaces in multi-monitor setups

**Independent Test**: On Hetzner (3 monitors), switch to workspace 1 (PRIMARY), workspace 4 (SECONDARY), workspace 7 (TERTIARY), verify correct output focused each time

**Why P1**: Critical for multi-monitor workflows - already working in bash version, must be preserved

### Implementation for User Story 5

- [X] T023 [US5] Implement _get_output_for_workspace logic in home-modules/tools/i3pm/daemon/workspace_mode.py (1-2→PRIMARY, 3-5→SECONDARY, 6+→TERTIARY)
- [X] T024 [US5] Add output focusing in execute method in home-modules/tools/i3pm/daemon/workspace_mode.py (focus output via i3 IPC after workspace switch)
- [X] T025 [US5] Add output event subscription in home-modules/desktop/i3-project-event-daemon/daemon.py (on_output handler already subscribed, now passes workspace_mode_manager)
- [X] T026 [US5] Implement output cache refresh on monitor changes in home-modules/desktop/i3-project-event-daemon/handlers.py (on_output calls workspace_mode_manager._refresh_output_cache)
- [X] T027 [US5] Add single-monitor fallback logic in home-modules/desktop/i3-project-event-daemon/workspace_mode.py (_refresh_output_cache handles 1-3 monitors adaptively)

**Checkpoint**: All P1 user stories complete - core navigation with full multi-monitor support

---

## Phase 6: User Story 3 - Real-Time Visual Feedback (Priority: P2)

**Goal**: Display accumulated digits in status bar with <10ms latency for immediate user confirmation

**Independent Test**: Enter workspace mode, type "1", "2", observe status bar shows "WS: 12" before pressing Enter

**Why P2**: Improves usability significantly but not blocking - can use fallback (notify-send or binding_mode_indicator) temporarily

### Implementation for User Story 3

- [X] T028 [P] [US3] Implement workspace mode status block in home-modules/desktop/i3bar/status-event-driven.sh (build_workspace_mode_block function queries daemon state)
- [X] T029 [P] [US3] Implement state querying in build_workspace_mode_block (i3pm workspace-mode state --json parses active/mode_type/accumulated_digits)
- [X] T030 [US3] Implement i3bar protocol output in build_workspace_mode_block (full_text with mode symbol, color, separator)
- [X] T031 [US3] Register workspace_mode block in build_status_line (add to status line array after project block)
- [X] T032 [US3] Add Catppuccin color scheme for workspace mode block (COLOR_GREEN #a6e3a1 for active mode, → for goto, ⇒ for move)

**Checkpoint**: User Story 3 complete - real-time status bar feedback independently functional

---

## Phase 7: User Story 6 - Native Sway Mode Indicator (Priority: P2)

**Goal**: Use Sway's native binding_mode_indicator for integrated UI feel

**Independent Test**: Configure swaybar with binding_mode_indicator, enter workspace mode, verify mode name appears with styling

**Why P2**: Nice visual improvement but not blocking - status bar from US3 provides functionality

### Implementation for User Story 6

- [X] T033 [US6] Enable binding_mode_indicator in home-modules/desktop/sway/bar.conf (binding_mode_indicator yes)
- [X] T034 [US6] Configure mode indicator colors in home-modules/desktop/sway/bar.conf (Catppuccin surface0 background, green border)
- [X] T035 [US6] Add Pango markup for mode names in home-modules/desktop/sway/modes.conf (→ WS for goto, ⇒ WS for move)

**Checkpoint**: User Story 6 complete - native Sway mode indicator integrated

---

## Phase 8: User Story 4 - Workspace Navigation History (Priority: P3)

**Goal**: Track last 100 workspace switches with timestamps for future analytics and "recent workspace" shortcuts

**Independent Test**: Perform 5 workspace switches, query `i3pm workspace-mode history`, verify all 5 switches recorded with timestamps and outputs

**Why P3**: Nice-to-have for future enhancements, not required for core functionality

### Implementation for User Story 4

- [X] T036 [P] [US4] Implement history recording in home-modules/desktop/i3-project-event-daemon/workspace_mode.py (_record_switch method called after successful execute)
- [X] T037 [P] [US4] Implement circular buffer logic in home-modules/desktop/i3-project-event-daemon/workspace_mode.py (maintain max 100 entries with pop(0) for oldest)
- [X] T038 [US4] Implement workspace_mode.history IPC handler in home-modules/desktop/i3-project-event-daemon/ipc_server.py (query with optional limit parameter)
- [X] T039 [US4] Implement CLI history command in home-modules/tools/i3pm/cli/workspace_mode.py (cmd_history with --limit and --json flags)
- [X] T040 [US4] Implement history table formatting in home-modules/tools/i3pm/cli/workspace_mode.py (Rich table with workspace, output, time, mode columns)

**Checkpoint**: User Story 4 complete - navigation history tracking functional

---

## Phase 9: Cleanup & Legacy Elimination

**Purpose**: Remove old bash-based workspace mode implementation per Constitution Principle XII (Forward-Only Development)

- [X] T041 Remove legacy bash workspace mode handler script from home-modules/desktop/sway-config-manager.nix (removed workspaceModeHandlerScript variable and xdg.configFile entry)
- [X] T042 Legacy keybindings already removed (modesConfContents now calls i3pm CLI instead of bash script)
- [X] T043 Update CLAUDE.md with new workspace mode documentation (Feature 042 section with usage examples)
- [X] T044 Verify no remaining references to workspace-mode-handler.sh in codebase (only comments remain referencing legacy removal)

**Checkpoint**: Legacy code eliminated - clean forward-only implementation

---

## Phase 10: Polish & Documentation

**Purpose**: Final improvements and documentation updates

- [X] T045 [P] Update quickstart.md with CLI examples and troubleshooting steps (already comprehensive with full CLI examples, troubleshooting section, advanced usage, and architecture notes)
- [X] T046 [P] Add performance logging for digit accumulation (added millisecond timing to add_digit method)
- [X] T047 [P] Add performance logging for workspace switch execution (added detailed timing for IPC commands, output focusing, and total execution)
- [X] T048 Implement workspace_mode.cancel IPC handler in home-modules/desktop/i3-project-event-daemon/ipc_server.py (calls manager.cancel, broadcasts event)
- [X] T049 Implement CLI cancel command in home-modules/tools/i3pm/cli/workspace_mode.py (cmd_cancel with IPC call)
- [X] T050 Implement workspace_mode.state IPC handler in home-modules/desktop/i3-project-event-daemon/ipc_server.py (returns current state dict)
- [X] T051 Implement CLI state command in home-modules/tools/i3pm/cli/workspace_mode.py (cmd_state with --json flag and Rich formatting)
- [X] T052 [P] Add error handling for i3 IPC failures in workspace_mode.py (try/except with logging, state preserved on error for retry)
- [ ] T053 Run quickstart.md validation scenarios manually on M1 and Hetzner platforms (manual testing after rebuild required)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-8)**: All depend on Foundational phase completion
  - User Story 1 (P1): Independent after Phase 2
  - User Story 2 (P1): Builds on US1 mode infrastructure
  - User Story 5 (P1): Extends US1 execute method with output focusing
  - User Story 3 (P2): Independent after Phase 2 (status bar)
  - User Story 6 (P2): Independent after Phase 2 (mode indicator)
  - User Story 4 (P3): Extends US1 execute method with history recording
- **Cleanup (Phase 9)**: Can start after any P1 user stories complete
- **Polish (Phase 10)**: Depends on desired user stories being complete

### User Story Dependencies

- **US1 (Digit Navigation)**: Foundation for all other stories
- **US2 (Move Windows)**: Reuses US1 digit accumulation, adds move mode type
- **US5 (Smart Output)**: Extends US1 execute method with output focusing
- **US3 (Status Bar)**: Independent - subscribes to events from US1
- **US6 (Mode Indicator)**: Independent - pure Sway configuration
- **US4 (History)**: Extends US1 execute method with history recording

### Parallel Opportunities

**After Phase 2 completes:**
- US1 (T009-T017) can proceed
- US3 (T028-T032) can proceed in parallel (different subsystem)
- US6 (T033-T035) can proceed in parallel (pure config)

**After US1 completes:**
- US2 (T018-T022) can proceed (extends US1)
- US5 (T023-T027) can proceed (extends US1)
- US4 (T036-T040) can proceed (extends US1)

**Within Phases:**
- Phase 1: T002 and T003 can run in parallel with T001
- Phase 6 (US3): T028 and T029 can run in parallel
- Phase 8 (US4): T036 and T037 can run in parallel
- Phase 10: T045, T046, T047, T052 can all run in parallel

---

## Implementation Strategy

### MVP First (P1 User Stories Only)

**Goal**: Fastest path to functional workspace navigation

1. **Phase 1**: Setup (T001-T003) - ~30 minutes
2. **Phase 2**: Foundational (T004-T008) - ~2 hours
3. **Phase 3**: User Story 1 (T009-T017) - ~2 hours
4. **Phase 4**: User Story 2 (T018-T022) - ~1 hour
5. **Phase 5**: User Story 5 (T023-T027) - ~1 hour

**STOP and VALIDATE**: Test complete navigation workflow on M1 and Hetzner
- CapsLock/Ctrl+0 → type digits → Enter → workspace switches with correct output focus
- Shift+CapsLock/Ctrl+Shift+0 → type digits → Enter → window moves and follows

**Estimated MVP Time**: 6-7 hours total

### Incremental Delivery (Add P2/P3 Stories)

**After MVP validation:**

6. **Phase 6**: User Story 3 (T028-T032) - ~1 hour - Status bar feedback
7. **Phase 7**: User Story 6 (T033-T035) - ~30 minutes - Native mode indicator
8. **Phase 8**: User Story 4 (T036-T040) - ~1 hour - History tracking

**Test each story independently before proceeding to next**

### Legacy Cleanup & Polish

**After all desired stories complete:**

9. **Phase 9**: Cleanup (T041-T044) - ~1 hour - Remove bash scripts per Principle XII
10. **Phase 10**: Polish (T045-T053) - ~2 hours - Documentation and final touches

**Total Estimated Time**: 11-13 hours for complete feature

---

## Parallel Execution Example: MVP

**Maximize efficiency with concurrent work:**

```bash
# Phase 1 - Launch in parallel:
Task T001: Create Pydantic models (foundation for everything)
# Then immediately after T001:
Task T002 (parallel): Create CLI structure
Task T003 (parallel): Create status bar skeleton

# Phase 2 - Sequential (daemon core):
Task T004: WorkspaceModeManager class
Task T005: Register IPC methods
Task T006: Mode event handler
Task T007: Output cache logic
Task T008: Event broadcasting

# Phase 3 (US1) + Phase 6 (US3) + Phase 7 (US6) - Parallel:
# Team member A works on US1 core navigation
Tasks T009-T017 (sequential within US1)

# Team member B works on US3 status bar (can start immediately after Phase 2)
Tasks T028-T032 (T028-T029 parallel, then T030-T032)

# Team member C works on US6 mode indicator (can start immediately after Phase 2)
Tasks T033-T035 (all parallel - pure config)
```

**Result**: MVP ready in ~4-5 hours with 3 team members vs ~7 hours solo

---

## Notes

- **Forward-Only Development**: All legacy bash workspace mode scripts will be REMOVED (Principle XII)
- **Tests**: Not included per spec.md (manual validation sufficient for this daemon extension)
- **Platform Support**: M1 (CapsLock via keyd), Hetzner (Ctrl+0 via VNC), both tested independently
- **Performance**: Target <10ms digit accumulation, <20ms workspace switch, <100ms total navigation
- **Event-Driven**: All state managed in daemon memory, real-time event broadcasting to status bar
- **Multi-Monitor**: Smart output focusing (1-2→PRIMARY, 3-5→SECONDARY, 6+→TERTIARY) with dynamic cache refresh

**Key Insight**: This is a daemon extension following Feature 015 patterns, not a new standalone system. Leverages existing i3pm daemon infrastructure for IPC, event broadcasting, and state management.
