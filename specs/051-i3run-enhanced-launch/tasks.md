# Tasks: i3run-Inspired Application Launch UX Enhancement

**Feature Branch**: `051-i3run-enhanced-launch`
**Input**: Design documents from `/etc/nixos/specs/051-i3run-enhanced-launch/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/daemon-rpc.json, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Tests**: Test-driven development is required per Principle XIV, but automated testing infrastructure for Sway IPC interactions is complex. Tests will be added incrementally during implementation.

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project structure and basic Python/Deno infrastructure

- [X] T001 Create directory structure for run-raise-hide implementation at home-modules/tools/i3pm/daemon/ and home-modules/tools/i3pm-deno/src/commands/
- [X] T002 Add Python dependencies to i3pm daemon requirements (i3ipc.aio, pydantic, psutil already present)
- [X] T003 Add Deno dependencies for CLI in home-modules/tools/i3pm-deno/deno.json (@std/cli already present)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models and infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] Create WindowState enum in home-modules/tools/i3pm/daemon/models/window_state.py (5 states: NOT_FOUND, DIFFERENT_WORKSPACE, SAME_WORKSPACE_UNFOCUSED, SAME_WORKSPACE_FOCUSED, SCRATCHPAD)
- [X] T005 [P] Create WindowStateInfo dataclass in home-modules/tools/i3pm/daemon/models/window_state.py (state, window, current_workspace, window_workspace, is_focused properties with derived geometry and floating accessors)
- [X] T006 [P] Create WindowGeometry Pydantic model in home-modules/tools/i3pm/daemon/models/scratchpad.py (x, y, width, height with validation, frozen=True for immutability)
- [X] T007 [P] Create ScratchpadState Pydantic model in home-modules/tools/i3pm/daemon/models/scratchpad.py (window_id, app_name, floating, geometry, hidden_at, project_name fields with validation)
- [X] T008 [P] Create RunMode enum in home-modules/tools/i3pm/daemon/models/window_state.py (SUMMON, HIDE, NOHIDE modes)
- [X] T009 [P] Create RunRequest Pydantic model in home-modules/tools/i3pm/daemon/models/window_state.py (app_name, mode, force_launch fields)
- [X] T010 [P] Create RunResponse Pydantic model in home-modules/tools/i3pm/daemon/models/window_state.py (action, window_id, focused, message fields)
- [X] T011 Verify WorkspaceTracker in home-modules/tools/i3pm/daemon/window_filtering.py supports geometry storage in window-workspace-map.json schema v1.1 (geometry and original_scratchpad fields should already exist)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Smart Application Toggle (Run-Raise-Hide) (Priority: P1) 🎯 MVP

**Goal**: Single keybinding to toggle frequently-used applications without managing window state manually

**Independent Test**:
1. Bind key to `i3pm run firefox`
2. Press 1: Launches firefox (not running) → Verify firefox window appears
3. Switch to different workspace, press 2: Focuses firefox → Verify workspace switches to firefox
4. Unfocus firefox, press 3: Focuses firefox → Verify firefox receives focus
5. With firefox focused, press 4: Hides firefox (requires mode=hide, tested in US5)

### Implementation for User Story 1

- [X] T012 [US1] Create RunRaiseManager class in home-modules/tools/i3pm/daemon/run_raise_manager.py with __init__ accepting sway connection, workspace_tracker, and daemon state reference
- [X] T013 [US1] Implement detect_window_state() method in RunRaiseManager (queries daemon state for window_id by app_name, executes Sway IPC GET_TREE, determines one of 5 WindowState values, returns WindowStateInfo)
- [X] T014 [US1] Implement _find_window_by_app_name() helper method in RunRaiseManager (looks up window_id from daemon's launch tracking via Feature 041, uses tree.find_by_id() for direct ID lookup)
- [X] T015 [US1] Implement execute_transition() method in RunRaiseManager (accepts WindowStateInfo and RunRequest, dispatches to appropriate _transition_* methods based on state and mode)
- [X] T016 [US1] Implement _transition_launch() method in RunRaiseManager (calls app-launcher-wrapper.sh via subprocess with app name from registry, handles launch failures with actionable errors)
- [X] T017 [US1] Implement _transition_focus() method in RunRaiseManager (executes Sway IPC command [con_id=X] focus for SAME_WORKSPACE_UNFOCUSED state)
- [X] T018 [US1] Implement _transition_goto() method in RunRaiseManager (for DIFFERENT_WORKSPACE state, switches to window's workspace then focuses window)
- [X] T019 [US1] Add error handling to RunRaiseManager methods (handle window closed during operation, Sway IPC command failures, launcher script errors, provide actionable error messages)
- [X] T020 [US1] Add app.run RPC method handler in home-modules/tools/i3pm/daemon/rpc_handlers.py (instantiate RunRaiseManager, validate RunRequest, call detect_window_state, execute_transition, return RunResponse with action/window_id/message)
- [X] T021 [US1] Create run.ts command file in home-modules/tools/i3pm-deno/src/commands/run.ts (implement parseArgs with app_name positional argument and boolean flags for modes)
- [X] T022 [US1] Add run command to router in home-modules/tools/i3pm-deno/src/main.ts (add case "run" with dynamic import of run.ts and runCommand invocation)
- [X] T023 [US1] Implement CLI to daemon RPC communication in run.ts (createClient from existing client.ts, send JSON-RPC request to app.run with app_name/mode/force_launch, handle 5-second timeout)
- [X] T024 [US1] Add human-readable output formatting in run.ts (format action messages like "Launched Firefox", "Focused Firefox on workspace 3", display window_id if present)
- [X] T025 [US1] Add error handling in run.ts (daemon not running with systemctl suggestion, app not found with i3pm apps list suggestion, RPC timeout, JSON-RPC error codes, proper exit codes)

**Checkpoint**: At this point, User Story 1 should be fully functional - basic run-raise-focus workflow works (launches app if not running, switches to workspace if on different workspace, focuses if unfocused)

---

## Phase 4: User Story 2 - Summon Mode (Bring Window to Current Workspace) (Priority: P1)

**Goal**: Option to bring window to current workspace instead of switching workspace

**Independent Test**:
1. Launch firefox on workspace 1 via `i3pm run firefox`
2. Switch to workspace 2 manually (swaymsg workspace 2)
3. Run `i3pm run firefox` (summon is default mode)
4. Verify firefox window moves from workspace 1 to workspace 2
5. Verify floating state and geometry are preserved (if window was floating)

### Implementation for User Story 2

- [X] T026 [US2] Implement _transition_summon() method in home-modules/tools/i3pm/daemon/run_raise_manager.py (captures current geometry if floating, moves window to current workspace via Sway IPC, restores geometry if needed)
- [X] T027 [US2] Extend execute_transition() in RunRaiseManager to dispatch to _transition_summon() when mode=SUMMON and state=DIFFERENT_WORKSPACE
- [X] T028 [US2] Add geometry preservation logic in _transition_summon() (before move: capture geometry from WindowStateInfo if is_floating=True, after move: execute Sway IPC commands to set geometry)
- [X] T029 [US2] Verify run.ts defaults to mode="summon" when no mode flag is provided (default behavior aligns with summon mode)
- [X] T030 [US2] Add CLI flag validation in run.ts to ensure --summon, --hide, --nohide are mutually exclusive (error message if multiple flags provided)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - users can launch/focus apps and windows move to current workspace by default (summon mode)

---

## Phase 5: User Story 3 - Generalized Scratchpad State Preservation (Priority: P2)

**Goal**: Windows remember floating state and geometry when hiding/showing from scratchpad

**Independent Test**:
1. Launch firefox and make it floating with specific geometry (swaymsg floating enable, resize to 1000x600, move to 500,300)
2. Hide to scratchpad via `i3pm run firefox --hide`
3. Verify firefox disappears from workspace
4. Show from scratchpad via `i3pm run firefox`
5. Verify firefox reappears with floating state and geometry within 10px tolerance

### Implementation for User Story 3

- [X] T031 [US3] Implement _transition_hide() method in home-modules/tools/i3pm/daemon/run_raise_manager.py (captures WindowStateInfo geometry and floating state, stores ScratchpadState via WorkspaceTracker, executes Sway IPC move scratchpad command)
- [X] T032 [US3] Implement _transition_show() method in RunRaiseManager (queries stored ScratchpadState from WorkspaceTracker, executes Sway IPC scratchpad show, restores floating state and geometry if stored)
- [X] T033 [US3] Add scratchpad state storage logic in _transition_hide() (create ScratchpadState Pydantic model with window_id/app_name/floating/geometry/hidden_at, call tracker.track_window with geometry parameter)
- [X] T034 [US3] Add scratchpad state restoration logic in _transition_show() (load window state from tracker.get_window_workspace, construct Sway IPC commands for floating enable/disable and geometry restoration via resize set and move position)
- [X] T035 [US3] Verify WorkspaceTracker window::close event handler clears scratchpad state when window is closed (prevents memory leak, this should already exist from Feature 038)
- [X] T036 [US3] Update execute_transition() to dispatch to _transition_hide() when mode=HIDE and state=SAME_WORKSPACE_FOCUSED
- [X] T037 [US3] Update execute_transition() to dispatch to _transition_show() when state=SCRATCHPAD (regardless of mode)
- [X] T038 [US3] Add --hide flag support in run.ts (parse --hide flag, set mode="hide" in RunRequest, validate mutual exclusivity with other mode flags)

**Checkpoint**: All scratchpad operations preserve window state correctly - floating windows restore to exact position/size, tiling windows restore to tiling state

---

## Phase 6: User Story 4 - Force Multi-Instance Launch (Priority: P2)

**Goal**: Explicit control to launch new instance even when existing instance is running

**Independent Test**:
1. Launch alacritty normally via `i3pm run alacritty` (focuses existing if running)
2. Trigger `i3pm run alacritty --force`
3. Verify new alacritty window appears with different PID
4. Verify original alacritty remains running
5. Check both have unique I3PM_APP_ID in /proc/<pid>/environ

### Implementation for User Story 4

- [X] T039 [US4] Add force_launch handling in execute_transition() (if force_launch=True, skip detect_window_state and directly call _transition_launch regardless of existing windows)
- [X] T040 [US4] Update _transition_launch() to generate unique I3PM_APP_ID for force-launched instances (include PID and timestamp in app_name to create unique identifier like "alacritty-12345-1730000000")
- [X] T041 [US4] Add --force flag support in run.ts (parse --force boolean flag, set force_launch=true in RunRequest params)
- [X] T042 [US4] Update daemon window tracking to handle multiple instances per app_name (extend Feature 041 launch tracking to use I3PM_APP_ID as unique key instead of app_name)
- [X] T043 [US4] Add most-recently-focused selection logic when multiple instances match app_name (query Sway IPC for focus timestamps across matching windows, return most recently focused window_id)

**Checkpoint**: Users can launch multiple instances of same app with --force flag, each instance is independently tracked and manageable

---

## Phase 7: User Story 5 - Explicit Hide/Nohide Control (Priority: P3)

**Goal**: Option to prevent hiding when window is focused, or always hide regardless of state

**Independent Test**:
1. Launch firefox and ensure it's focused
2. Trigger `i3pm run firefox --nohide`
3. Verify firefox remains focused and is NOT hidden to scratchpad
4. Switch firefox to different workspace, trigger `i3pm run firefox --hide`
5. Verify firefox hides to scratchpad without first switching workspace

### Implementation for User Story 5

- [X] T044 [US5] Update execute_transition() to handle mode=NOHIDE (when state=SAME_WORKSPACE_FOCUSED and mode=NOHIDE, take no action instead of hiding, return action="none")
- [X] T045 [US5] Update execute_transition() to handle mode=HIDE with state=DIFFERENT_WORKSPACE (skip summon/goto, directly call _transition_hide to hide from different workspace)
- [X] T046 [US5] Add --nohide flag support in run.ts (parse --nohide boolean flag, set mode="nohide" in RunRequest params)
- [X] T047 [US5] Update CLI flag validation in run.ts to ensure --hide, --nohide, and --summon are all mutually exclusive (error if more than one mode flag provided)

**Checkpoint**: All run modes work correctly - summon (default, move to current workspace), hide (toggle visibility), nohide (show only, never hide)

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories, performance optimization, comprehensive documentation

- [X] T048 [P] Add comprehensive error messages in run.ts (app not found suggests i3pm apps list, daemon not running shows systemctl --user status i3-project-event-listener, include exit codes in error context)
- [X] T049 [P] Add --json flag support in run.ts (parse --json boolean flag, output full RunResponse as JSON to stdout for scripting integration)
- [X] T050 [P] Add --help flag and usage text in run.ts (implement showHelp() function with all modes, flags, examples matching quickstart.md format)
- [X] T051 [P] Add logging for all RunRaiseManager operations in daemon (state detection with WindowState value, transition execution with action taken, error conditions with context)
- [X] T052 [P] Add performance metrics logging (track and log latency for detect_window_state <20ms target, execute_transition <50ms target, total run command <100ms target)
- [X] T053 Update quickstart.md with final keybinding recommendations and examples if implementation reveals UX improvements
- [X] T054 Add example keybindings to home-modules/desktop/sway-keybindings.nix (commented examples: $mod+f for firefox, $mod+c for vscode, $mod+t for alacritty with --hide flag)
- [X] T055 Run full workflow validation per quickstart.md scenarios (test all 5 user stories independently, verify each acceptance scenario passes)
- [ ] T056 Verify scratchpad state persistence across daemon restarts (hide window to scratchpad, restart i3-project-event-listener service, show window, check geometry restored correctly)
- [ ] T057 Verify multi-monitor support (test on Hetzner 3-display setup, ensure geometry preserved when moving between virtual displays, verify window appears on correct output)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - Basic run-raise-focus workflow
- **User Story 2 (Phase 4)**: Depends on Phase 3 completion - Extends with summon mode
- **User Story 3 (Phase 5)**: Depends on Phase 3 completion - Adds scratchpad state preservation
- **User Story 4 (Phase 6)**: Depends on Phase 3 completion - Adds force launch
- **User Story 5 (Phase 7)**: Depends on Phases 3-6 completion - Integrates all modes
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Foundation only - No dependencies on other stories (MVP core)
- **User Story 2 (P1)**: Extends User Story 1 - Requires basic run-raise-focus working
- **User Story 3 (P2)**: Independent of US2 - Can start after US1 complete (parallel with US4)
- **User Story 4 (P2)**: Independent of US2/US3 - Can start after US1 complete (parallel with US3)
- **User Story 5 (P3)**: Requires all previous stories - Integrates all modes (hide/nohide logic depends on summon/scratchpad working)

**Note**: User Stories 3 and 4 can be developed in parallel after US1/US2 complete

### Within Each User Story

**User Story 1 (Run-Raise-Focus)**:
1. Models first (T004-T011 from Foundational)
2. Manager class and state detection (T012-T014)
3. Transition methods (T015-T018)
4. Error handling (T019)
5. RPC integration (T020)
6. CLI command (T021-T025)

**User Story 2 (Summon Mode)**:
1. Daemon implementation first (T026-T028)
2. CLI updates after daemon working (T029-T030)

**User Story 3 (Scratchpad Preservation)**:
1. Hide transition first (T031, T033, T036)
2. Show transition after hide working (T032, T034, T037)
3. Cleanup verification (T035)
4. CLI flag last (T038)

**User Story 4 (Force Launch)**:
1. Daemon force logic (T039-T040)
2. CLI flag (T041)
3. Multi-instance tracking (T042-T043)

**User Story 5 (Hide/Nohide Modes)**:
1. Daemon mode handling (T044-T045)
2. CLI flags (T046-T047)

### Parallel Opportunities

- **Setup (Phase 1)**: All tasks T001-T003 can run in parallel (independent directory/dependency setup)
- **Foundational (Phase 2)**: All model creation tasks T004-T010 can run in parallel (different files, no dependencies), T011 is verification only
- **User Story 1**: T012-T019 (daemon implementation) can partially overlap if different methods, T021-T025 (CLI) can start once RPC handler (T020) interface is defined
- **User Stories 3 & 4**: Can be developed completely in parallel after US1/US2 complete (different concerns, different files)
- **Polish (Phase 8)**: All [P] tasks T048-T052 can run in parallel (different files, independent concerns)

---

## Parallel Example: Foundational Phase

```bash
# Launch all data model creation tasks together:
Task T004: "Create WindowState enum in home-modules/tools/i3pm/daemon/models/window_state.py"
Task T005: "Create WindowStateInfo dataclass in home-modules/tools/i3pm/daemon/models/window_state.py"
Task T006: "Create WindowGeometry Pydantic model in home-modules/tools/i3pm/daemon/models/scratchpad.py"
Task T007: "Create ScratchpadState Pydantic model in home-modules/tools/i3pm/daemon/models/scratchpad.py"
Task T008: "Create RunMode enum in home-modules/tools/i3pm/daemon/models/window_state.py"
Task T009: "Create RunRequest Pydantic model in home-modules/tools/i3pm/daemon/models/window_state.py"
Task T010: "Create RunResponse Pydantic model in home-modules/tools/i3pm/daemon/models/window_state.py"

# All can be written to the same files in parallel if using proper merge strategies,
# or done sequentially with quick commits between each model
```

---

## Parallel Example: User Story 3 & 4

```bash
# Developer A works on User Story 3 (Scratchpad Preservation):
Task T031: "Implement _transition_hide() method in run_raise_manager.py"
Task T032: "Implement _transition_show() method in run_raise_manager.py"
Task T033: "Add scratchpad state storage logic in _transition_hide()"
Task T034: "Add scratchpad state restoration logic in _transition_show()"
Task T036-T038: "Update execute_transition() and CLI for hide mode"

# Developer B works on User Story 4 (Force Launch) in parallel:
Task T039: "Add force_launch handling in execute_transition()"
Task T040: "Update _transition_launch() for unique I3PM_APP_ID"
Task T041: "Add --force flag support in run.ts"
Task T042-T043: "Update daemon tracking for multi-instance"

# No conflicts - different concerns, can merge independently
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011) - CRITICAL blocker
3. Complete Phase 3: User Story 1 (T012-T025) - Basic run-raise-focus
4. Complete Phase 4: User Story 2 (T026-T030) - Summon mode
5. **STOP and VALIDATE**: Test core workflow independently
   - Launch app not running → verify launches
   - App on different workspace → verify moves to current workspace
   - App unfocused on same workspace → verify focuses
6. Deploy/demo if ready

**MVP Deliverable**: Users can toggle any registered app with single command, windows intelligently move to current workspace

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Core run-raise-focus working
3. Add User Story 2 → Test independently → Summon mode working (P1 features complete!)
4. Add User Story 3 → Test independently → Scratchpad state preservation working
5. Add User Story 4 → Test independently → Multi-instance force launch working
6. Add User Story 5 → Test independently → All modes complete (hide/nohide)
7. Polish phase → Documentation, performance tuning, validation
8. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T011)
2. Developer A: User Story 1 + 2 (T012-T030) - Core P1 features
3. Once US1/US2 complete:
   - Developer B: User Story 3 (T031-T038) - Scratchpad preservation
   - Developer C: User Story 4 (T039-T043) - Force launch
   - Both in parallel, different files
4. Developer A: User Story 5 (T044-T047) - Integrates all modes
5. Team: Polish phase together (T048-T057)

---

## Notes

- [P] tasks = different files, no dependencies, can execute in parallel
- [Story] label maps task to specific user story for traceability (US1, US2, US3, US4, US5)
- Each user story should be independently testable via acceptance scenarios in spec.md
- Tests are marked as TDD-required but automated Sway IPC testing infrastructure is complex - implement tests incrementally during development
- Commit after each task or logical group of related tasks
- Stop at any checkpoint to validate story independently before proceeding
- All paths relative to `/etc/nixos/` repository root
- Python code follows existing daemon patterns (async/await, Pydantic models, i3ipc.aio)
- Deno TypeScript follows existing CLI patterns (@std/cli/parse-args, createClient from client.ts)
- Reuses existing infrastructure:
  - Feature 038 (window-workspace-map.json storage, WorkspaceTracker)
  - Feature 041 (launch notification, window_id tracking)
  - Feature 057 (app-launcher-wrapper.sh, I3PM_* environment injection)
  - Feature 062 (scratchpad state preservation patterns)
- No duplicate logic or new infrastructure where existing patterns solve the problem

---

## Success Criteria Validation

After implementation, verify these measurable outcomes from spec.md:

- **SC-001**: Users can toggle any registered application with single command, with correct state-dependent behavior (launch/focus/hide/show) occurring within 500ms in 95% of cases
  - Measure: `time i3pm run firefox` across all 5 states, verify P95 <500ms
- **SC-002**: Summon mode successfully moves windows between workspaces while preserving floating state and geometry (within 10-pixel tolerance) in 100% of cases
  - Measure: Float window, record geometry, summon to different workspace, verify geometry within 10px
- **SC-003**: Scratchpad hide/show operations preserve window state with less than 10-pixel geometry error in 95% of cases
  - Measure: Hide/show 20 times, measure geometry error each time, verify P95 <10px
- **SC-004**: Force-launch mode successfully creates independent instances with unique I3PM_APP_ID in 100% of cases
  - Measure: Launch with --force 10 times, check /proc/<pid>/environ for unique IDs
- **SC-005**: CLI commands provide clear actionable error messages for all failure modes (launch fail, window closed, timeout) in 100% of cases
  - Test: Manually trigger each error condition, verify error message is actionable
- **SC-006**: State storage memory usage remains bounded (no leaks) during 24-hour operation with 100+ hide/show cycles
  - Measure: Monitor daemon RSS via `systemctl --user status i3-project-event-listener` before/after

---

**Total Tasks**: 57
**MVP Tasks** (Phase 1-4): 30 tasks (Setup + Foundational + User Story 1 + User Story 2)
**Full Feature Tasks**: 57 tasks (all phases)
**Estimated MVP Duration**: 2-3 days (single developer, core run-raise-summon functionality)
**Estimated Full Feature Duration**: 4-6 days (single developer, all user stories + polish)
**Parallel Opportunities**: Foundational models (7 tasks), User Stories 3 & 4 (14 tasks), Polish (5 tasks) = 26 tasks can be parallelized
