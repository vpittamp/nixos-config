# Tasks: Project-Scoped Scratchpad Terminal

**Input**: Design documents from `/specs/062-project-scratchpad-terminal/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/scratchpad-rpc.json, quickstart.md

**Feature**: Toggle floating project-scoped terminal via keybinding (Mod+Shift+Return) with independent state per project

**Tests**: Test tasks are included per TDD requirements (Principle XIV). Write tests FIRST, ensure they FAIL before implementation.

**Organization**: Tasks grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and test framework setup

- [X] T001 Create Python module structure for scratchpad in home-modules/tools/i3pm/models/scratchpad.py
- [X] T002 Create TypeScript module structure for scratchpad CLI in home-modules/tools/i3pm/src/commands/scratchpad.ts (ALREADY EXISTED)
- [X] T003 [P] Setup pytest test structure in home-modules/tools/i3pm/tests/062-project-scratchpad-terminal/unit/test_scratchpad_manager.py
- [X] T004 [P] Setup integration test structure in home-modules/tools/i3pm/tests/062-project-scratchpad-terminal/integration/test_terminal_lifecycle.py
- [X] T005 [P] Setup E2E test structure in home-modules/tools/i3pm/tests/062-project-scratchpad-terminal/scenarios/test_user_workflows.py

---

## Phase 2: Foundational (Blocking Prerequisites) ✅ COMPLETE

**Purpose**: Core data models, unified launcher integration, and terminal selection logic that MUST be complete before ANY user story

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Implement ScratchpadTerminal Pydantic model in home-modules/tools/i3pm/models/scratchpad.py (fields: project_name, pid, window_id, mark, working_dir, created_at, last_shown_at)
- [X] T007 Add Pydantic field validators for project_name (alphanumeric + hyphens) and working_dir (absolute path) in home-modules/tools/i3pm/models/scratchpad.py
- [X] T008 Implement ScratchpadTerminal.is_process_running() method using psutil in home-modules/tools/i3pm/models/scratchpad.py
- [X] T009 Implement ScratchpadTerminal.create_mark() class method for Sway mark generation in home-modules/tools/i3pm/models/scratchpad.py
- [X] T010 Implement ScratchpadTerminal.to_dict() for JSON serialization in home-modules/tools/i3pm/models/scratchpad.py
- [X] T011 Implement terminal emulator selection function (Ghostty primary, Alacritty fallback) in home-modules/tools/i3pm/daemon/terminal_launcher.py
- [X] T012 Implement unified launcher integration helper in home-modules/tools/i3pm/daemon/terminal_launcher.py (constructs app-launcher-wrapper.sh invocation with parameters)
- [X] T013 Implement launch notification payload builder in home-modules/tools/i3pm/daemon/terminal_launcher.py (Feature 041 integration: app_name, project_name, expected_class, timestamp)
- [X] T014 [P] Add scratchpad-terminal entry to app-registry-data.nix - ALREADY EXISTED (line 277, Alacritty-based)
- [X] T015 [P] Update TypeScript models in home-modules/tools/i3pm/src/models.ts (add ScratchpadTerminal interface matching Python model) (ALREADY EXISTED)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Quick Terminal Access (Priority: P1) 🎯 MVP

**Goal**: Enable users to instantly access a project-scoped terminal via Mod+Shift+Return keybinding, with automatic working directory setup in project root

**Independent Test**: Switch to a project, press Mod+Shift+Return, verify Ghostty terminal opens floating and centered in project root directory (falls back to Alacritty if Ghostty unavailable). Press keybinding again to hide terminal to scratchpad (process keeps running). Press again to restore terminal with command history intact.

**Acceptance Scenarios**:
1. First press in project "nixos" → Ghostty terminal opens floating, centered, working directory=/etc/nixos (Alacritty fallback if Ghostty unavailable)
2. Terminal visible → press keybinding → terminal hides to scratchpad, process continues running
3. Terminal hidden → press keybinding → same terminal appears in same position with command history intact

### Tests for User Story 1 (TDD - Write FIRST)

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T016 [P] [US1] Unit test for ScratchpadTerminal model validation (project_name, working_dir, mark format) in home-modules/tools/i3pm/tests/unit/test_scratchpad_manager.py
- [ ] T017 [P] [US1] Unit test for terminal emulator selection (Ghostty primary, Alacritty fallback) in home-modules/tools/i3pm/tests/unit/test_scratchpad_manager.py
- [ ] T018 [P] [US1] Unit test for launch notification payload generation in home-modules/tools/i3pm/tests/unit/test_scratchpad_manager.py
- [ ] T019 [US1] Integration test for terminal launch via unified launcher (mocked app-launcher-wrapper.sh) in home-modules/tools/i3pm/tests/integration/test_terminal_lifecycle.py
- [ ] T020 [US1] Integration test for window correlation via launch notification (Feature 041) in home-modules/tools/i3pm/tests/integration/test_terminal_lifecycle.py
- [ ] T021 [US1] Integration test for window marking with scratchpad:PROJECT_NAME pattern in home-modules/tools/i3pm/tests/integration/test_terminal_lifecycle.py
- [ ] T022 [US1] E2E test for first-time terminal launch (keybinding → Ghostty opens → floating + centered + correct working dir) in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py
- [ ] T023 [US1] E2E test for terminal toggle hide (keybinding → terminal moves to scratchpad __i3_scratch workspace) in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py
- [ ] T024 [US1] E2E test for terminal toggle show (keybinding → same terminal restored with same PID) in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py

### Implementation for User Story 1

- [X] T025 [US1] Implement ScratchpadManager.__init__() with terminals dict and Sway IPC connection in home-modules/tools/i3pm/daemon/scratchpad_manager.py
- [X] T026 [US1] Implement ScratchpadManager.launch_terminal() method in home-modules/tools/i3pm/daemon/scratchpad_manager.py (unified launcher invocation, pre-launch notification, window event wait with 2s timeout, window correlation via launch notification or /proc fallback)
- [ ] T027 [US1] Implement window event handler for new terminal windows in home-modules/tools/i3pm/daemon/event_handlers.py (filter by I3PM_SCRATCHPAD=true env var, mark window with scratchpad:PROJECT_NAME, set floating + dimensions 1200x700, center on display) - NOTE: Window handling integrated into launch_terminal()
- [X] T028 [US1] Implement ScratchpadManager.validate_terminal() method in home-modules/tools/i3pm/daemon/scratchpad_manager.py (check process running via psutil, verify window exists in Sway tree via GET_TREE, re-apply mark if missing)
- [X] T029 [US1] Implement ScratchpadManager.get_terminal_state() method in home-modules/tools/i3pm/daemon/scratchpad_manager.py (query Sway tree, check if window in __i3_scratch workspace → "hidden", else → "visible")
- [X] T030 [US1] Implement ScratchpadManager.toggle_terminal() method in home-modules/tools/i3pm/daemon/scratchpad_manager.py (validate terminal exists, get current state, issue Sway IPC command: move scratchpad if visible, scratchpad show if hidden, update last_shown_at timestamp)
- [X] T031 [US1] Implement JSON-RPC handler for scratchpad.toggle in daemon RPC router - ALREADY EXISTED in ipc_server.py
- [X] T032 [US1] Implement Deno CLI command `i3pm scratchpad toggle` in home-modules/tools/i3pm/src/commands/scratchpad.ts (ALREADY EXISTED)
- [X] T033 [US1] Update Deno main.ts to register scratchpad subcommand in home-modules/tools/i3pm/src/main.ts (ALREADY EXISTED)
- [X] T034 [US1] Add Sway keybinding for scratchpad terminal in home-modules/desktop/sway-default-keybindings.toml (Mod+Shift+Return exec i3pm scratchpad toggle)
- [X] T035 [US1] Add error handling for daemon unavailable in home-modules/tools/i3pm/src/commands/scratchpad.ts (ALREADY EXISTED)
- [X] T036 [US1] Add error handling for launch timeout - ALREADY EXISTED in daemon services/scratchpad_manager.py
- [X] T037 [US1] Add logging for terminal lifecycle events - ALREADY EXISTED in daemon services/scratchpad_manager.py

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently. Users can toggle a project-scoped terminal via keybinding with show/hide/launch behavior.

---

## Phase 4: User Story 2 - Multi-Project Terminal Isolation (Priority: P2)

**Goal**: Enable users to maintain independent scratchpad terminals per project, each with separate command history, running processes, and working directories

**Independent Test**: Create scratchpad terminals in two different projects (nixos and dotfiles), run different commands in each, switch between projects, verify each terminal maintains independent state (different PIDs, command history, working directories)

**Acceptance Scenarios**:
1. Terminal in project "nixos" runs `git status` → switch to "dotfiles" → open terminal → shows empty history, different working directory, different PID
2. Terminals exist for both "nixos" and "dotfiles" → switch from nixos to dotfiles → nixos terminal auto-hides, dotfiles terminal remains hidden until explicitly shown
3. Multiple regular Alacritty windows open in project → press scratchpad keybinding → only designated scratchpad terminal toggles, other terminals unaffected

### Tests for User Story 2 (TDD - Write FIRST)

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T038 [P] [US2] Unit test for ScratchpadManager.get_terminal() retrieval by project_name in home-modules/tools/i3pm/tests/unit/test_scratchpad_manager.py
- [ ] T039 [P] [US2] Unit test for ScratchpadManager state isolation (multiple projects tracked independently) in home-modules/tools/i3pm/tests/unit/test_scratchpad_manager.py
- [ ] T040 [US2] Integration test for multiple terminal launches (different projects → different PIDs + window IDs + marks) in home-modules/tools/i3pm/tests/integration/test_terminal_lifecycle.py
- [ ] T041 [US2] Integration test for project switch with scratchpad terminals (old project terminal auto-hides) in home-modules/tools/i3pm/tests/integration/test_terminal_lifecycle.py
- [ ] T042 [US2] E2E test for multi-project terminal isolation (create terminals in nixos + dotfiles, verify different PIDs, command history, working directories) in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py
- [ ] T043 [US2] E2E test for project switch behavior (switch project A → B, terminal A auto-hides, terminal B remains hidden until toggled) in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py

### Implementation for User Story 2

- [ ] T044 [US2] Implement ScratchpadManager.get_terminal() method in home-modules/tools/i3pm/src/daemon/scratchpad_manager.py (retrieve terminal by project_name from terminals dict)
- [ ] T045 [US2] Implement ScratchpadManager.list_terminals() method in home-modules/tools/i3pm/src/daemon/scratchpad_manager.py (return list of all ScratchpadTerminal instances)
- [ ] T046 [US2] Implement project switch event handler in home-modules/tools/i3pm/src/daemon/event_handlers.py (on project_switch event, auto-hide old project's visible scratchpad terminal to scratchpad via Sway IPC move scratchpad command per FR-010)
- [ ] T047 [US2] Implement window identification logic to distinguish scratchpad terminals from regular terminals in home-modules/tools/i3pm/src/daemon/event_handlers.py (check for I3PM_SCRATCHPAD=true env var via /proc/<pid>/environ reading per FR-006)
- [ ] T048 [US2] Implement JSON-RPC handler for scratchpad.status in home-modules/tools/i3pm/src/daemon/rpc_handlers.py (accepts optional project_name param, returns terminal status with state, process_running, window_exists, timestamps; if no param, returns all terminals)
- [ ] T049 [US2] Implement Deno CLI command `i3pm scratchpad status` in home-modules/tools/i3pm-deno/src/commands/scratchpad.ts (call scratchpad.status RPC method, display formatted output with project, PID, state, working dir, timestamps; support --all flag for all terminals)
- [ ] T050 [US2] Add state persistence for ScratchpadManager.terminals dict in daemon in home-modules/tools/i3pm/src/daemon/state.py (add scratchpad_terminals field to DaemonState)
- [ ] T051 [US2] Add window close event handler for scratchpad terminals in home-modules/tools/i3pm/src/daemon/event_handlers.py (detect window close via mark prefix scratchpad:, remove from terminals dict, log INFO event)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently. Each project maintains its own terminal with isolation, and switching projects auto-hides terminals.

---

## Phase 5: User Story 3 - Terminal State Persistence (Priority: P3)

**Goal**: Ensure scratchpad terminals maintain command history and running processes across hide/show operations and extended periods

**Independent Test**: Start long-running command (tail -f logfile.txt) in scratchpad terminal, hide terminal, wait 30 minutes, show terminal again, verify tail command still running and showing updates

**Acceptance Scenarios**:
1. Terminal hidden for 4 hours → show terminal → command history and session state intact
2. Started `tail -f logfile.txt` then hid terminal → show 30 minutes later → tail still running and showing new log entries
3. Terminal visible when switching projects → switch back to original project → show terminal → appears in same state as when project was left

### Tests for User Story 3 (TDD - Write FIRST)

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T052 [P] [US3] Unit test for ScratchpadTerminal.is_process_running() with long-running process in home-modules/tools/i3pm/tests/unit/test_scratchpad_manager.py
- [ ] T053 [P] [US3] Unit test for last_shown_at timestamp updates in home-modules/tools/i3pm/tests/unit/test_scratchpad_manager.py
- [ ] T054 [US3] Integration test for terminal state validation after extended hide period (mock time.sleep) in home-modules/tools/i3pm/tests/integration/test_terminal_lifecycle.py
- [ ] T055 [US3] Integration test for process persistence (launch terminal, start bg process, hide, validate process still running) in home-modules/tools/i3pm/tests/integration/test_terminal_lifecycle.py
- [ ] T056 [US3] E2E test for long-running command persistence (start tail -f, hide terminal, wait, show, verify tail still running) in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py
- [ ] T057 [US3] E2E test for terminal state restoration (hide terminal, switch projects multiple times, return and show, verify same state) in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py

### Implementation for User Story 3

- [ ] T058 [US3] Implement ScratchpadTerminal.mark_shown() method to update last_shown_at timestamp in home-modules/tools/i3pm/src/models/scratchpad.py
- [ ] T059 [US3] Update ScratchpadManager.toggle_terminal() to call mark_shown() on show operations in home-modules/tools/i3pm/src/daemon/scratchpad_manager.py
- [ ] T060 [US3] Implement periodic validation task to clean up dead terminals in home-modules/tools/i3pm/src/daemon/scratchpad_manager.py (run every 5 minutes, call cleanup_invalid_terminals())
- [ ] T061 [US3] Implement ScratchpadManager.cleanup_invalid_terminals() method in home-modules/tools/i3pm/src/daemon/scratchpad_manager.py (validate all terminals via validate_terminal(), remove invalid entries, return count cleaned + projects list)
- [ ] T062 [US3] Implement JSON-RPC handler for scratchpad.cleanup in home-modules/tools/i3pm/src/daemon/rpc_handlers.py (call cleanup_invalid_terminals(), return cleaned_up count, remaining count, projects_cleaned list)
- [ ] T063 [US3] Implement Deno CLI command `i3pm scratchpad cleanup` in home-modules/tools/i3pm-deno/src/commands/scratchpad.ts (call scratchpad.cleanup RPC method, display summary of cleaned terminals)
- [ ] T064 [US3] Add automatic cleanup on daemon startup in home-modules/tools/i3pm/src/daemon/__init__.py (call scratchpad_manager.cleanup_invalid_terminals() on daemon initialization)
- [ ] T065 [US3] Add performance measurement for toggle operations in home-modules/tools/i3pm/src/daemon/scratchpad_manager.py (timestamp at RPC entry, timestamp after Sway IPC command, log latency per TR-007, target <500ms for existing terminals)

**Checkpoint**: All user stories should now be independently functional. Terminals persist state across hide/show and extended periods.

---

## Phase 6: Global Mode & Additional Operations (Priority: P3)

**Goal**: Support global scratchpad terminal (no active project) and explicit launch/close operations

**Acceptance Scenarios**:
1. No active project (global mode) → press scratchpad keybinding → terminal opens in home directory (~)
2. Global terminal persists across all project switches → toggle global terminal independent of project terminals
3. User can explicitly close scratchpad terminal → next toggle launches new terminal

### Tests for Global Mode (TDD - Write FIRST)

- [ ] T066 [P] Unit test for global terminal creation (project_name="global") in home-modules/tools/i3pm/tests/unit/test_scratchpad_manager.py
- [ ] T067 [P] Integration test for global terminal working directory (should be home directory) in home-modules/tools/i3pm/tests/integration/test_terminal_lifecycle.py
- [ ] T068 [P] E2E test for global terminal persistence across project switches in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py

### Implementation for Global Mode

- [ ] T069 Implement global terminal detection in JSON-RPC toggle handler in home-modules/tools/i3pm/src/daemon/rpc_handlers.py (if no current_project, use project_name="global", working_dir=home directory per FR-012)
- [ ] T070 Implement JSON-RPC handler for scratchpad.launch in home-modules/tools/i3pm/src/daemon/rpc_handlers.py (explicit launch, fail if terminal already exists, accept optional project_name and working_dir params per contract)
- [ ] T071 Implement JSON-RPC handler for scratchpad.close in home-modules/tools/i3pm/src/daemon/rpc_handlers.py (close terminal window via Sway IPC kill command, remove from terminals dict, return project_name and message per contract)
- [ ] T072 Implement Deno CLI command `i3pm scratchpad launch` in home-modules/tools/i3pm-deno/src/commands/scratchpad.ts (call scratchpad.launch RPC method, support --project and --working-dir flags)
- [ ] T073 Implement Deno CLI command `i3pm scratchpad close` in home-modules/tools/i3pm-deno/src/commands/scratchpad.ts (call scratchpad.close RPC method, support --project flag)
- [ ] T074 Add support for toggle global terminal via CLI in home-modules/tools/i3pm-deno/src/commands/scratchpad.ts (i3pm scratchpad toggle global)

---

## Phase 7: Migration & Configuration Updates (Priority: P2)

**Goal**: Migrate from legacy shell script to daemon-based approach, update Sway configuration

**Migration Steps** (from spec.md MIG-001 through MIG-004):

- [ ] T075 Remove legacy shell script from version control in ~/.config/sway/scripts/scratchpad-terminal-toggle.sh (delete file)
- [ ] T076 Remove shell script generation from sway-config-manager.nix template in home-modules/desktop/sway-config-manager.nix (remove scratchpad-terminal-toggle.sh template)
- [ ] T077 Update for_window rules to use I3PM_APP_NAME environment variable matching in home-modules/desktop/window-rules.json (replace app_id regex with I3PM_APP_NAME="scratchpad-terminal" pattern per MIG-002)
- [ ] T078 Update window-rules.json template with Ghostty-based criteria in home-modules/desktop/sway-config-manager.nix (add Ghostty app_id matching + environment variable validation per MIG-004)
- [ ] T079 Add deprecation notice to CLAUDE.md documenting replacement of shell script with daemon approach in CLAUDE.md (scratchpad terminal section per MIG-001)
- [ ] T080 Update CLAUDE.md with scratchpad terminal usage documentation in CLAUDE.md (add to i3pm section: keybindings, CLI commands, troubleshooting)

---

## Phase 8: Diagnostic Integration (Priority: P3)

**Goal**: Integrate scratchpad terminal status into i3pm diagnose command for troubleshooting

- [ ] T081 Implement scratchpad status in `i3pm diagnose health` command in home-modules/tools/i3pm-deno/src/commands/diagnose.ts (query daemon for scratchpad.status, include terminal count, PID validity, window existence in health report per FR-023)
- [ ] T082 Implement scratchpad window validation in `i3pm diagnose window` command in home-modules/tools/i3pm-deno/src/commands/diagnose.ts (for scratchpad terminals, show I3PM_SCRATCHPAD env var, mark, state, validation status)
- [ ] T083 Add scratchpad event tracing to `i3pm diagnose events` command in home-modules/tools/i3pm-deno/src/commands/diagnose.ts (filter for scratchpad-related window events, show launch/toggle/close events with timing)

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, performance validation, and final integration

- [ ] T084 [P] Update quickstart.md with actual CLI examples and keybindings in specs/062-project-scratchpad-terminal/quickstart.md (verify all workflows work as documented)
- [ ] T085 [P] Validate all E2E test scenarios match quickstart.md workflows in home-modules/tools/i3pm/tests/scenarios/test_user_workflows.py
- [ ] T086 [P] Performance validation: measure toggle latency (target <500ms for existing terminals, <2s for launch per TR-007) via automated tests
- [ ] T087 [P] Performance validation: measure daemon event processing (target <100ms per event per plan.md performance goals) via automated tests
- [ ] T088 Code cleanup and refactoring (remove dead code, consolidate error handling, improve logging consistency)
- [ ] T089 Security review: validate environment variable reading from /proc doesn't leak sensitive data
- [ ] T090 Final integration test: run complete quickstart.md test scenarios (US1-US3 workflows)
- [ ] T091 NixOS dry-build test for hetzner-sway configuration (sudo nixos-rebuild dry-build --flake .#hetzner-sway)
- [ ] T092 NixOS dry-build test for m1 configuration (sudo nixos-rebuild dry-build --flake .#m1 --impure)
- [ ] T093 Apply NixOS configuration updates (sudo nixos-rebuild switch --flake .#<target>)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Migration (Phase 7)**: Can run in parallel with user stories (different files)
- **Diagnostic Integration (Phase 8)**: Depends on User Story 1-2 completion (needs scratchpad.status RPC)
- **Polish (Phase 9)**: Depends on all phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1 but independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Builds on US1 but independently testable
- **Global Mode (Phase 6)**: Can start after US1 completion - Uses same toggle infrastructure

### Within Each User Story

1. **Tests FIRST** (TDD requirement per Principle XIV):
   - Unit tests before models/services
   - Integration tests before RPC handlers
   - E2E tests before CLI commands
   - Verify all tests FAIL before implementing
2. **Models before services**: ScratchpadTerminal model before ScratchpadManager
3. **Services before RPC handlers**: ScratchpadManager before scratchpad.toggle handler
4. **RPC handlers before CLI**: Daemon methods before Deno CLI commands
5. **Core implementation before integration**: Basic toggle before project switch integration

### Parallel Opportunities

**Setup (Phase 1)**: T003, T004, T005 (test structure creation - different directories)

**Foundational (Phase 2)**: T014, T015 (Nix registry + TypeScript models - different files)

**User Story 1 Tests**: T016, T017, T018 (unit tests - different test cases in same file, can run together)

**User Story 1 Implementation**: None (sequential due to dependencies)

**User Story 2 Tests**: T038, T039 (unit tests - different test cases)

**User Story 3 Tests**: T052, T053 (unit tests - different test cases)

**Global Mode Tests**: T066, T067, T068 (independent test cases)

**Migration (Phase 7)**: All tasks T075-T080 can run in parallel (different files)

**Diagnostic Integration (Phase 8)**: All tasks T081-T083 can run in parallel (different diagnose subcommands)

**Polish (Phase 9)**: T084, T085, T086, T087 (documentation + performance tests - different concerns)

**Multiple User Stories in Parallel**:
- Once Foundational (Phase 2) is complete:
  - Developer A: User Story 1 (Phase 3)
  - Developer B: User Story 2 (Phase 4)
  - Developer C: Migration (Phase 7)
- Stories complete and integrate independently

---

## Parallel Example: User Story 1

```bash
# Launch all unit tests for User Story 1 together (different test cases):
Task T016: "Unit test for ScratchpadTerminal model validation"
Task T017: "Unit test for terminal emulator selection"
Task T018: "Unit test for launch notification payload generation"

# Sequential implementation (dependencies):
Task T025: "ScratchpadManager.__init__()" (depends on T006-T010 models)
  ↓
Task T026: "ScratchpadManager.launch_terminal()" (depends on T025, T011-T013 launcher)
  ↓
Task T027: "Window event handler for new terminals" (depends on T026)
  ↓
Task T031: "JSON-RPC handler for scratchpad.toggle" (depends on T025-T030)
  ↓
Task T032: "Deno CLI command i3pm scratchpad toggle" (depends on T031)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. **Complete Phase 1**: Setup (T001-T005) → Test infrastructure ready
2. **Complete Phase 2**: Foundational (T006-T015) → CRITICAL - blocks all stories
3. **Complete Phase 3**: User Story 1 (T016-T037)
   - Write tests FIRST (T016-T024), verify they FAIL
   - Implement ScratchpadTerminal model (T025)
   - Implement ScratchpadManager (T026-T030)
   - Implement RPC handler + CLI (T031-T033)
   - Add keybinding + error handling (T034-T037)
4. **STOP and VALIDATE**: Run all User Story 1 tests, verify they PASS
5. **Test manually**: Follow quickstart.md Workflow 1 (Basic Toggle)
6. Deploy/demo if ready

**At this checkpoint, users can toggle a project-scoped terminal via Mod+Shift+Return. This is the MVP.**

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP! Quick terminal access works)
3. Add User Story 2 → Test independently → Deploy/Demo (Multi-project isolation works)
4. Add User Story 3 → Test independently → Deploy/Demo (State persistence works)
5. Add Global Mode (Phase 6) → Test independently → Deploy/Demo (Global terminal works)
6. Add Migration (Phase 7) + Diagnostic Integration (Phase 8) → Deploy final version
7. Polish (Phase 9) → Validate performance + documentation

Each story adds value without breaking previous stories.

### Parallel Team Strategy

With multiple developers:

1. **Team completes Setup + Foundational together** (T001-T015)
2. **Once Foundational is done**:
   - Developer A: User Story 1 (Phase 3, T016-T037)
   - Developer B: User Story 2 (Phase 4, T038-T051) - can start tests, but implementation waits for A's ScratchpadManager
   - Developer C: Migration (Phase 7, T075-T080) - independent of user stories
3. **After US1 complete**:
   - Developer A: User Story 3 (Phase 5, T052-T065)
   - Developer B: Continues US2 implementation using A's ScratchpadManager
   - Developer C: Diagnostic Integration (Phase 8, T081-T083) - depends on scratchpad.status from US2
4. **Stories complete and integrate independently**

---

## Task Count Summary

- **Total Tasks**: 93
- **Phase 1 (Setup)**: 5 tasks
- **Phase 2 (Foundational)**: 10 tasks (BLOCKING)
- **Phase 3 (User Story 1 - MVP)**: 22 tasks (9 tests + 13 implementation)
- **Phase 4 (User Story 2)**: 14 tasks (6 tests + 8 implementation)
- **Phase 5 (User Story 3)**: 13 tasks (6 tests + 7 implementation)
- **Phase 6 (Global Mode)**: 9 tasks (3 tests + 6 implementation)
- **Phase 7 (Migration)**: 6 tasks
- **Phase 8 (Diagnostic Integration)**: 3 tasks
- **Phase 9 (Polish)**: 10 tasks

**Test Coverage**: 24 test tasks (26% of total) - comprehensive unit/integration/E2E coverage per TDD requirements

**Parallel Opportunities**: 15 tasks marked [P] across all phases

**MVP Scope**: Phases 1-3 (37 tasks) delivers User Story 1 - Quick Terminal Access

---

## Notes

- **[P] tasks** = different files, no dependencies, can run in parallel
- **[Story] label** maps task to specific user story for traceability
- **Each user story** is independently completable and testable
- **TDD requirement**: Write tests FIRST (Principle XIV), verify they FAIL before implementing
- **Sway IPC is authoritative** (Principle XI): Always validate against Sway tree, not just daemon state
- **Unified launcher integration** (Features 041/057): MUST use app-launcher-wrapper.sh, NOT direct subprocess launch
- **Performance targets** (TR-007): <500ms toggle for existing terminals, <2s for initial launch
- **Ghostty primary, Alacritty fallback** (FR-016, FR-017): Runtime terminal selection via `command -v ghostty`
- **Commit after each task** or logical group
- **Stop at any checkpoint** to validate story independently
- **Avoid**: vague tasks, same file conflicts, cross-story dependencies that break independence
