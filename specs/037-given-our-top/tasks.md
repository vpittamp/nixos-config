# Tasks: Unified Project-Scoped Window Management

**Input**: Design documents from `/specs/037-given-our-top/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are NOT requested in this specification - implementation-focused approach

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5)
- Include exact file paths in descriptions

## Path Conventions
- NixOS configuration root: `/etc/nixos/`
- Home modules: `home-modules/desktop/` and `home-modules/tools/i3pm/`
- Configuration files: `~/.config/i3/`
- State files: `~/.local/state/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [ ] T001 Stage and commit all design documents (spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md) to git
- [ ] T002 Create backup of existing `home-modules/desktop/i3-project-daemon.py` daemon implementation
- [ ] T003 [P] Add WindowState and ProjectWindows data models to `home-modules/tools/i3pm/models.py`
- [ ] T004 [P] Create display module for hidden windows at `home-modules/tools/i3pm/displays/hidden_windows.py`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Implement workspace tracking state file manager in `home-modules/desktop/i3-project-daemon.py` with load/save functions for `~/.config/i3/window-workspace-map.json`
- [X] T006 [P] Add /proc environment variable reading utility function to daemon: `get_window_i3pm_env(window_id) -> Dict[str, str]`
- [X] T007 [P] Add i3 IPC scratchpad query utility function to daemon: `get_scratchpad_windows() -> List[Window]`
- [X] T008 Implement workspace validation function using GET_WORKSPACES IPC: `validate_workspace_exists(workspace_num) -> bool`
- [X] T009 [P] Add batch i3 command builder utility: `build_batch_move_command(commands: List[str]) -> str`
- [X] T010 Implement garbage collection on daemon start to clean stale entries from window-workspace-map.json

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Automatic Window Filtering on Project Switch (Priority: P1) 🎯 MVP

**Goal**: When switching projects, automatically hide scoped windows from the previous project and show only windows relevant to the new project plus global applications

**Independent Test**: Launch VS Code and terminal in "nixos" project. Switch to "stacks" project. Verify VS Code and terminal disappear (hidden in scratchpad). Global apps like Firefox remain visible. Switch back to "nixos" and verify windows reappear on their original workspaces.

### Implementation for User Story 1

- [X] T011 [US1] Implement `project.hideWindows` JSON-RPC method in daemon at `home-modules/desktop/i3-project-daemon.py` that:
  - Queries i3 tree for all visible windows
  - Reads I3PM_PROJECT_NAME from /proc for each window
  - Filters windows matching target project with I3PM_SCOPE=scoped
  - Saves current workspace positions to window-workspace-map.json
  - Executes batch scratchpad move command
  - Returns WindowFilterResult with hidden count and errors
- [X] T012 [US1] Implement `project.restoreWindows` JSON-RPC method in daemon that:
  - Queries i3 tree for scratchpad windows
  - Reads I3PM_PROJECT_NAME from /proc for each scratchpad window
  - Filters windows matching target project
  - Loads workspace assignments from window-workspace-map.json
  - Validates workspaces exist (fallback to WS 1 if invalid)
  - Executes batch workspace restore command
  - Updates window-workspace-map.json with restored positions
  - Returns list of restorations with fallback indicators
- [X] T013 [US1] Implement `project.switchWithFiltering` JSON-RPC method in daemon that combines hide + restore operations with single i3 tree query for performance
- [X] T014 [US1] Modify daemon's `handle_tick()` event handler to detect project switch tick events and automatically call `project.switchWithFiltering`
- [X] T015 [US1] Add error handling for partial failures (continue processing remaining windows when individual window operations fail)
- [X] T016 [US1] Implement request queue in daemon to handle rapid project switches sequentially using asyncio.Queue
- [X] T017 [US1] Extend daemon client in `home-modules/tools/i3pm/daemon_client.py` with new JSON-RPC methods: hideWindows, restoreWindows, switchWithFiltering
- [ ] T018 [US1] Modify `i3pm project switch` command in `home-modules/tools/i3pm/__main__.py` to display filtering results (hidden count, restored count, duration) after switch completes
  **Note**: Filtering is automatic and logged. CLI display enhancement deferred in favor of Phase 4 (higher priority)
- [X] T019 [US1] Add logging for all window filtering operations with debug details (window IDs, projects, workspaces)

**Checkpoint**: At this point, User Story 1 should be fully functional - project switches automatically hide/restore windows

---

## Phase 4: User Story 2 - Workspace Persistence Across Switches (Priority: P1) 🎯 MVP

**Goal**: Windows return to their exact workspace locations when returning to a previously active project, preserving user's workspace organization

**Independent Test**: In "nixos" project, move VS Code from WS2 to WS5. Switch to "stacks". Switch back to "nixos". Verify VS Code returns to WS5 (not default WS2).

### Implementation for User Story 2

- [X] T020 [US2] Implement daemon event handler for `window::move` events in `home-modules/desktop/i3-project-daemon.py` that updates window-workspace-map.json when user manually moves windows
- [X] T021 [US2] Extend workspace tracking to capture floating state in window-workspace-map.json (floating: true/false)
  **Note**: Already implemented in Phase 2 (T005-T010)
- [X] T022 [US2] Modify `project.restoreWindows` to restore floating state using i3 command: `[con_id="X"] move to workspace N, floating enable|disable`
  **Note**: Already implemented in Phase 2 (T005-T010)
- [X] T023 [US2] Add validation in restoration logic to preserve custom workspace assignments over registry defaults (user overrides take precedence)
  **Note**: Already implemented in Phase 2 (T005-T010)
- [X] T024 [US2] Implement atomic write pattern for window-workspace-map.json (write to temp file + rename) to prevent corruption
  **Note**: Already implemented in Phase 2 (T005-T010)
- [X] T025 [US2] Add last_seen timestamp to tracking entries for debugging and potential cleanup
  **Note**: Already implemented in Phase 2 (T005-T010)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - windows persist their positions across switches

---

## Phase 5: User Story 3 - Guaranteed Workspace Assignment on Launch (Priority: P2)

**Goal**: Applications launched via Walker/Elephant open on their configured workspace regardless of which workspace is currently focused

**Independent Test**: Be on workspace 5. Launch VS Code via Walker (configured for WS2). Verify VS Code opens on WS2, not WS5.

### Implementation for User Story 3

- [X] T026 [US3] Modify daemon's `handle_window_new()` event handler in `home-modules/desktop/i3-project-daemon.py` to:
  - Extract window PID and read I3PM_* environment variables
  - Look up preferred_workspace from application registry
  - Move window to preferred_workspace if current workspace differs
  - Update window-workspace-map.json with initial assignment
- [X] T027 [US3] Add registry query helper function to daemon: `get_app_preferred_workspace(app_name: str) -> int`
  **Note**: Implemented as load_application_registry() in config.py
- [X] T028 [US3] Implement workspace assignment with i3 IPC COMMAND: `[con_id="X"] move to workspace number N`
- [X] T029 [US3] Add logging when windows are moved to preferred workspace on launch

**Checkpoint**: Applications now open on correct workspaces automatically

---

## Phase 6: User Story 4 - Automatic Monitor-Workspace Redistribution (Priority: P2)

**Goal**: Workspaces automatically redistribute across monitors when monitor configuration changes (connect/disconnect)

**Independent Test**: Configure 2-monitor layout (WS1-2 on primary, WS3-9 on secondary). Disconnect secondary monitor. Verify all workspaces move to primary. Reconnect. Verify WS3-9 move back to secondary.

### Implementation for User Story 4

- [ ] T030 [US4] Add daemon event subscription for `output` events in `home-modules/desktop/i3-project-daemon.py` to detect monitor connect/disconnect
- [ ] T031 [US4] Implement `handle_output()` event handler that triggers workspace redistribution on monitor changes
- [ ] T032 [US4] Add integration with Feature 033's `i3pm monitors reassign` command - daemon should call this command on output events
- [ ] T033 [US4] Implement debouncing for rapid monitor events (300ms delay before triggering reassignment to handle multiple quick changes)
- [ ] T034 [US4] Add configuration option in daemon to enable/disable auto-reassignment (respect enable_auto_reassign from Feature 033)
- [ ] T035 [US4] Update window-workspace-map.json after monitor redistribution to reflect new workspace assignments

**Checkpoint**: Monitor configuration changes now trigger automatic workspace redistribution

---

## Phase 7: User Story 5 - Visual Status Indicators (Priority: P3)

**Goal**: Users can see which windows are hidden and which project each belongs to for transparency and debugging

**Independent Test**: Switch from "nixos" (3 windows) to "stacks". Use status command to list hidden windows. Verify it shows: "3 windows hidden for project 'nixos': VS Code (WS2), Terminal (WS1), Lazygit (WS7)".

### Implementation for User Story 5

- [ ] T036 [US5] Implement `windows.getHidden` JSON-RPC method in daemon that:
  - Queries i3 tree for all scratchpad windows
  - Reads I3PM_PROJECT_NAME for each scratchpad window
  - Loads workspace tracking from window-workspace-map.json
  - Groups windows by project name
  - Returns project-grouped data with window details
- [ ] T037 [US5] Implement `windows.getState` JSON-RPC method in daemon for inspecting individual window state (visibility, project, workspace, I3PM_* variables)
- [ ] T038 [US5] Create `i3pm windows hidden` CLI command in `home-modules/tools/i3pm/__main__.py` with options:
  - --project=<name> filter
  - --workspace=<num> filter
  - --app=<name> filter
  - --format=table|tree|json output formats
- [ ] T039 [US5] Implement table format display using Rich library in `home-modules/tools/i3pm/displays/hidden_windows.py` with project grouping and colored output
- [ ] T040 [US5] Implement tree format display with hierarchical project → windows structure
- [ ] T041 [US5] Create `i3pm windows restore` CLI command with options:
  - <project-name> argument (required)
  - --dry-run flag
  - --window-id=<id> to restore specific window
  - --workspace=<num> to override tracked workspace
- [ ] T042 [US5] Implement restore command logic that calls daemon's `project.restoreWindows` and displays results with checkmarks/warnings
- [ ] T043 [US5] Create `i3pm windows inspect` CLI command that takes window ID and displays comprehensive state (visibility, project, workspace, I3PM_* env vars, tracking info)
- [ ] T044 [US5] Modify `i3pm windows` command to add --show-hidden flag that includes scratchpad windows in tree/table view with 🔒 icon indicator
- [ ] T045 [US5] Extend daemon client in `home-modules/tools/i3pm/daemon_client.py` with getHidden and getState methods

**Checkpoint**: All user stories are now independently functional - users have full visibility into hidden windows

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T046 [P] Update quickstart.md with actual CLI command outputs from implementation
- [ ] T047 [P] Add shell aliases to `home-modules/shell/bash-config.nix`: phidden, prestore, pwinspect
- [ ] T048 Add suggested keybindings to i3 config in `home-modules/desktop/i3-config.nix` for showing hidden windows
- [ ] T049 Implement daemon event notifications (window.hidden, window.restored) for observability
- [ ] T050 Add performance monitoring to log switch duration, hide/restore counts, and error rates
- [ ] T051 [P] Review and optimize /proc reading with parallel async reads using asyncio.gather() for 30+ windows
- [ ] T052 [P] Optimize batch i3 command execution to combine hide + restore into single IPC call
- [ ] T053 Add comprehensive error messages with troubleshooting guidance to all CLI commands
- [ ] T054 Implement help text for all new CLI commands (--help flag)
- [ ] T055 Add daemon status diagnostics: switch queue length, recent filtering operations, error counts
- [ ] T056 Test and validate all quickstart.md scenarios manually
- [ ] T057 Update CLAUDE.md documentation with window filtering workflow and commands
- [ ] T058 Stage and commit all implementation changes with feature completion message

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - User Story 1 (P1): Can start after Foundational - Core filtering logic (MVP)
  - User Story 2 (P1): Depends on User Story 1 - Extends filtering with persistence (MVP)
  - User Story 3 (P2): Can start after Foundational - Independent launch behavior
  - User Story 4 (P2): Can start after Foundational - Independent monitor handling
  - User Story 5 (P3): Depends on User Story 1 & 2 - Visibility into filtering system
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Core MVP - Must complete first (automatic filtering)
- **User Story 2 (P1)**: Extends US1 - Adds workspace persistence (required for MVP)
- **User Story 3 (P2)**: Independent - Can run in parallel with US4, enhances launch behavior
- **User Story 4 (P2)**: Independent - Can run in parallel with US3, adds monitor adaptation
- **User Story 5 (P3)**: Depends on US1 & US2 - Provides visibility commands

### Within Each User Story

- Foundational utilities before story implementation
- JSON-RPC methods before CLI commands
- Daemon client extensions before CLI usage
- Core logic before display/formatting
- Error handling and logging after core implementation

### Parallel Opportunities

- Phase 1: T003 and T004 can run in parallel (different files)
- Phase 2: T006, T007, T009 can run in parallel (independent utilities)
- Phase 8: T046, T047, T051, T052 can run in parallel (different concerns)
- User Story 3 and User Story 4 can be implemented in parallel (independent features)

---

## Parallel Example: Foundational Phase

```bash
# Launch foundational utilities in parallel:
Task: "Add /proc environment variable reading utility" (T006)
Task: "Add i3 IPC scratchpad query utility" (T007)
Task: "Add batch i3 command builder utility" (T009)

# These are independent utility functions in the same file but different sections
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Automatic Filtering)
4. Complete Phase 4: User Story 2 (Workspace Persistence)
5. **STOP and VALIDATE**: Test both stories together
6. Deploy minimal viable feature

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 & 2 → Test together → Deploy/Demo (MVP - automatic filtering with persistence!)
3. Add User Story 3 → Test independently → Deploy/Demo (enhanced launch behavior)
4. Add User Story 4 → Test independently → Deploy/Demo (monitor adaptation)
5. Add User Story 5 → Test independently → Deploy/Demo (visibility commands)
6. Polish phase → Optimize and document

### Sequential Implementation (Recommended)

Since this is a single developer extending an existing daemon:

1. Phase 1: Setup (commit docs, create structure)
2. Phase 2: Foundational (build utilities)
3. Phase 3 & 4: User Stories 1 & 2 together (core MVP)
4. Validate MVP and commit
5. Phase 5: User Story 3 (workspace assignment)
6. Phase 6: User Story 4 (monitor redistribution)
7. Phase 7: User Story 5 (visibility commands)
8. Phase 8: Polish and optimize

---

## Notes

- [P] tasks = different files or independent sections, no dependencies
- [Story] label maps task to specific user story for traceability
- User Stories 1 & 2 form the MVP (automatic filtering + persistence)
- User Stories 3 & 4 are independent enhancements
- User Story 5 provides debugging/visibility
- Verify manual tests from quickstart.md after each story
- Commit after completing each user story
- Stop at any checkpoint to validate story independently
- All paths are relative to /etc/nixos/ repository root
- Must run `nixos-rebuild switch --flake .#hetzner` after completing implementation
- Must restart daemon after applying: `systemctl --user restart i3-project-event-listener`

## Summary Statistics

- **Total Tasks**: 58 tasks
- **Setup Phase**: 4 tasks
- **Foundational Phase**: 6 tasks (CRITICAL - blocks all stories)
- **User Story 1 (P1 MVP)**: 9 tasks (automatic filtering)
- **User Story 2 (P1 MVP)**: 6 tasks (workspace persistence)
- **User Story 3 (P2)**: 4 tasks (guaranteed workspace assignment)
- **User Story 4 (P2)**: 6 tasks (monitor redistribution)
- **User Story 5 (P3)**: 10 tasks (visibility commands)
- **Polish Phase**: 13 tasks (optimization and documentation)
- **MVP Scope**: User Stories 1 & 2 (15 tasks after foundational)
- **Parallel Opportunities**: 8 tasks can run in parallel at various phases
- **Critical Path**: Setup → Foundational → US1 → US2 → Validate MVP
