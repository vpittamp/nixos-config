# Tasks: Complete i3pm Deno CLI with Extensible Architecture

**Feature**: Complete i3pm Deno CLI with Extensible Architecture
**Branch**: `027-update-the-spec`
**Input**: Design documents from `/etc/nixos/specs/027-update-the-spec/`

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Tests**: No tests requested in spec - test tasks omitted per template guidance.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure) ✅ COMPLETE

**Purpose**: Project initialization and basic structure

- [X] T001 Create project directory structure at `/etc/nixos/home-modules/tools/i3pm-deno/` with subdirectories: `src/`, `src/commands/`, `src/ui/`, `src/utils/`, `tests/unit/`, `tests/integration/`, `tests/fixtures/`
- [X] T002 Initialize Deno project with `deno.json` configuration including tasks (dev, compile, test), imports map, compiler options (strict: true, lib: ["deno.window"])
- [X] T003 [P] Create README.md in `/etc/nixos/home-modules/tools/i3pm-deno/README.md` with module documentation, compilation instructions, and quick start guide

---

## Phase 2: Foundational (Blocking Prerequisites) ✅ COMPLETE

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create TypeScript type definitions in `src/models.ts` for all core entities: WindowState, WindowGeometry, Workspace, Output, OutputGeometry, Project, EventNotification, EventType, DaemonStatus, WindowRule, ApplicationClass
- [X] T005 [P] Create Zod validation schemas in `src/validation.ts` for all entities from models.ts: WindowStateSchema, WorkspaceSchema, OutputSchema, ProjectSchema, EventNotificationSchema, DaemonStatusSchema, WindowRuleSchema, ApplicationClassSchema
- [X] T006 [P] Create JSON-RPC protocol types in `src/models.ts`: JsonRpcRequest, JsonRpcResponse, JsonRpcNotification, JsonRpcError, JsonRpcErrorCode enum, request/response param types (GetWindowsParams, SwitchProjectParams, GetEventsParams, EventNotificationParams)
- [X] T007 Implement JSON-RPC 2.0 client in `src/client.ts` with DaemonClient class: socket connection management, request() method with timeout, subscribe() method for events, line-delimited JSON parsing, error handling, connection retry logic
- [X] T008 [P] Implement Unix socket utilities in `src/utils/socket.ts`: socket path discovery from XDG_RUNTIME_DIR, connection timeout handling, reconnection with exponential backoff
- [X] T009 [P] Implement error handling utilities in `src/utils/errors.ts`: user-friendly error messages for daemon unavailable, socket not found, permission denied, timeout, connection refused
- [X] T010 [P] Implement signal handling utilities in `src/utils/signals.ts`: SIGINT (Ctrl+C) handler with cleanup, SIGWINCH (terminal resize) handler, double Ctrl+C detection for immediate exit
- [X] T011 [P] Create ANSI formatting utilities in `src/ui/ansi.ts`: cursor control (hide/show, move up/down), screen management (clear, alternate buffer), color codes, TextEncoder/TextDecoder wrappers
- [X] T012 Create main CLI entry point in `main.ts` with parseArgs() routing: global options parsing (help, version, verbose, debug), parent command routing (project, windows, daemon, rules, monitor, app-classes), help text generation, version display

**Checkpoint**: ✅ Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Project Context Switching (Priority: P1) 🎯 MVP ✅ COMPLETE

**Goal**: Enable instant project context switching with window visibility management

**Independent Test**: Run `i3pm project switch nixos` and verify only nixos-scoped windows become visible and i3bar indicator updates to show "nixos"

### Implementation for User Story 1

- [X] T013 [US1] Implement `i3pm project switch` command in `src/commands/project.ts`: call daemon's switch_project RPC method, parse response with windows_hidden/windows_shown counts, display success message with window counts, handle project-not-found errors
- [X] T014 [US1] Implement `i3pm project clear` command in `src/commands/project.ts`: call daemon's clear_project RPC method, display previous project and windows shown count, handle errors gracefully
- [X] T015 [US1] Implement `i3pm project current` command in `src/commands/project.ts`: call daemon's get_current_project RPC method, display active project name or "Global" if null, format output for terminal display
- [X] T016 [US1] Implement `i3pm project list` command in `src/commands/project.ts`: call daemon's list_projects RPC method, validate response with Zod ProjectSchema array, format output showing project names, display names, directories, and icons

**Checkpoint**: ✅ User Story 1 (project switching workflow) is fully functional and testable independently

---

## Phase 4: User Story 2 - Real-time Window State Visualization (Priority: P2)

**Goal**: Provide multiple visualization formats for window state with real-time updates

**Independent Test**: Run `i3pm windows --live` and verify real-time display updates when opening/closing windows

### Implementation for User Story 2

- [ ] T017 [P] [US2] Implement tree view formatter in `src/ui/tree.ts`: hierarchical rendering (outputs → workspaces → windows), visual indicators (● focus, 🔸 scoped, 🔒 hidden, ⬜ floating), project tags ([nixos], [stacks]), Unicode box-drawing characters for tree structure
- [ ] T018 [P] [US2] Implement table view formatter in `src/ui/table.ts`: column definitions (ID, Class, Title, WS, Output, Project, Status), unicodeWidth() for column alignment, header rendering with separators, row formatting with padding, status icon concatenation
- [ ] T019 [US2] Implement `i3pm windows` command (tree mode) in `src/commands/windows.ts`: call daemon's get_windows RPC method, validate response with Zod OutputSchema array, filter hidden windows by default, render tree view using tree.ts formatter, handle empty state (no windows)
- [ ] T020 [US2] Add `--table` flag support in `src/commands/windows.ts`: same get_windows call, render table view using table.ts formatter, handle empty state with message
- [ ] T021 [US2] Add `--json` flag support in `src/commands/windows.ts`: same get_windows call, output raw JSON with JSON.stringify(result, null, 2), no validation errors to stdout
- [ ] T022 [US2] Implement live TUI in `src/ui/live.ts`: LiveTUI class with run() method, alternate screen buffer management (enter: \x1b[?1049h, exit: \x1b[?1049l), cursor hiding/showing, raw mode for keyboard input, event subscription via daemon client, refresh() method calling get_windows, keyboard handler (Tab: switch view, H: toggle hidden, Q: quit, Ctrl+C: exit), terminal resize handler (SIGWINCH), cleanup/exit with terminal restoration
- [ ] T023 [US2] Add `--live` flag support in `src/commands/windows.ts`: instantiate LiveTUI class, pass daemon client, call run() method, handle exit gracefully, ensure terminal restoration on errors

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently (project switching + window visualization)

---

## Phase 5: User Story 3 - Project Configuration Management (Priority: P3) ✅ COMPLETE

**Goal**: Enable declarative project configuration management through CLI

**Independent Test**: Run `i3pm project create --name test --dir /tmp/test` and verify new project appears in `i3pm project list`

### Implementation for User Story 3

- [X] T024 [US3] Implement `i3pm project create` command in `src/commands/project.ts`: parse flags (--name, --dir, --icon, --display-name) using parseArgs(), validate name format (lowercase alphanumeric with hyphens), validate directory path (absolute path starting with /), call daemon's create_project RPC method, display success message with project details
- [X] T025 [US3] Implement `i3pm project show` command in `src/commands/project.ts`: parse project name argument, call daemon's get_project RPC method, validate response with Zod ProjectSchema, format multi-line output (name, display name, icon, directory, scoped classes, created timestamp, last used timestamp), handle project-not-found error
- [X] T026 [US3] Implement `i3pm project validate` command in `src/commands/project.ts`: call daemon's list_projects RPC method, iterate projects and validate each with Zod ProjectSchema, check directory existence (optional - warn if missing), display validation results (projects checked count, errors if any), exit with code 1 if validation fails
- [X] T027 [US3] Implement `i3pm project delete` command in `src/commands/project.ts`: parse project name argument, call daemon's delete_project RPC method, display confirmation message, handle project-not-found error

**Checkpoint**: ✅ All project management commands (switch, clear, current, list, create, show, validate, delete) are fully functional

---

## Phase 6: User Story 4 - Daemon Status and Event Monitoring (Priority: P4)

**Goal**: Provide visibility into daemon health and event history for troubleshooting

**Independent Test**: Run `i3pm daemon status` and verify output shows daemon uptime, connected state, event counts, and active project

### Implementation for User Story 4

- [ ] T028 [US4] Implement `i3pm daemon status` command in `src/commands/daemon.ts`: call daemon's get_status RPC method, validate response with Zod DaemonStatusSchema, format multi-line output (status, connected, uptime in human-readable format, active project, window/workspace/event counts, version, socket path), handle daemon unavailable error with actionable systemctl command
- [ ] T029 [US4] Implement `i3pm daemon events` command in `src/commands/daemon.ts`: parse flags (--limit, --type, --since-id) using parseArgs(), call daemon's get_events RPC method with params, validate response with Zod EventNotificationSchema array, format output in reverse chronological order (newest first) with event_id, timestamp (human-readable), event_type:change, container info (window class/title or workspace name), handle empty event history, display total events and ID range

**Checkpoint**: Daemon monitoring commands (status, events) should now be functional for troubleshooting

---

## Phase 7: User Story 5 - Window Classification and Rule Management (Priority: P5)

**Goal**: Enable management and testing of window classification rules

**Independent Test**: Run `i3pm rules list` and verify output shows current window classification rules with scoping information

### Implementation for User Story 5

- [ ] T030 [P] [US5] Implement `i3pm rules list` command in `src/commands/rules.ts`: call daemon's list_rules RPC method, validate response with Zod WindowRuleSchema array, format output showing rule number, class pattern, scope (scoped/global), priority, enabled state
- [ ] T031 [P] [US5] Implement `i3pm rules classify` command in `src/commands/rules.ts`: parse flags (--class, --instance) using parseArgs(), call daemon's classify_window RPC method, format output showing classification result (class, instance, scope, matched rule with ID and priority), handle no matching rule case
- [ ] T032 [P] [US5] Implement `i3pm rules validate` command in `src/commands/rules.ts`: call daemon's list_rules RPC method, validate each rule's regex patterns (class_pattern, instance_pattern), check for rule conflicts (same pattern with different scopes at same priority), display validation results, exit with code 1 if validation fails
- [ ] T033 [P] [US5] Implement `i3pm rules test` command in `src/commands/rules.ts`: parse --class flag, call daemon's classify_window RPC method, display all matching rules (not just final winner), show evaluation order by priority, display final classification result
- [ ] T034 [US5] Implement `i3pm app-classes` command in `src/commands/app-classes.ts`: call daemon's get_app_classes RPC method, validate response with Zod ApplicationClassSchema arrays (scoped, global), format output in two sections (Scoped Applications, Global Applications), display class name, display name, icon, description for each

**Checkpoint**: All window classification commands (list, classify, validate, test, app-classes) should now be functional

---

## Phase 8: User Story 6 - Interactive Monitor Dashboard (Priority: P6)

**Goal**: Provide holistic real-time monitoring dashboard for system debugging

**Independent Test**: Run `i3pm monitor` and verify multi-pane TUI launches showing live daemon status, event stream, and window state

### Implementation for User Story 6

- [ ] T035 [US6] Implement monitor dashboard in `src/ui/monitor-dashboard.ts`: MonitorDashboard class with multi-pane layout (daemon status pane, event stream pane, window state pane), alternate screen buffer management, cursor hiding, raw mode keyboard input, pane rendering methods (renderStatusPane(), renderEventsPane(), renderWindowsPane()), refresh rate limiting (<250ms between refreshes), event subscription for real-time updates, keyboard handler (Tab: switch pane focus, Q: quit, Ctrl+C: exit), terminal resize handler, cleanup/exit with terminal restoration
- [ ] T036 [US6] Implement `i3pm monitor` command in `src/commands/monitor.ts`: instantiate MonitorDashboard class, pass daemon client, call run() method, handle exit gracefully, ensure terminal restoration on errors

**Checkpoint**: Interactive monitor dashboard should now be functional for holistic debugging sessions

---

## Phase 9: NixOS Integration & Compilation ✅ COMPLETE

**Purpose**: Package CLI as compiled binary and integrate into NixOS/home-manager

- [X] T037 Create NixOS derivation in `/etc/nixos/home-modules/tools/i3pm-deno.nix`: stdenv.mkDerivation with pname "i3pm", version "2.0.0", src pointing to i3pm-deno directory, nativeBuildInputs with pkgs.deno, buildPhase with deno compile command (--allow-net, --allow-read=/run/user,/home, --allow-env=XDG_RUNTIME_DIR,HOME,USER, --output=i3pm, main.ts), installPhase copying binary to $out/bin/, meta with description and platforms
- [X] T038 Add i3pm package to home-manager configuration: import i3pm-deno.nix module in appropriate home-modules file, ensure binary is in home.packages
- [ ] T039 Test compiled binary: rebuild NixOS/home-manager, verify `i3pm --version` shows version 2.0.0, verify `i3pm --help` shows usage information, test all commands against running daemon (pending system rebuild)

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T040 [P] Add comprehensive help text for all commands: implement --help flag handler in main.ts, add help text for each parent command (project, windows, daemon, rules, monitor, app-classes), add help text for each subcommand with usage examples, format help output with proper indentation and examples
- [ ] T041 [P] Implement --verbose flag support: add verbose logging to daemon client connection, log all RPC requests/responses when --verbose is enabled, log event notifications in live modes
- [ ] T042 [P] Implement --debug flag support: add debug logging for socket connection details, log Zod validation details, log terminal state changes (raw mode, alternate screen), log signal handling events
- [ ] T043 Handle all edge cases from spec.md: daemon not running error message with systemctl command, socket connection timeout with retry notification, terminal resize during live TUI (trigger redraw), malformed JSON-RPC responses (validation error message), empty window state (friendly "No windows open" message), long window titles (truncation with ellipsis at column boundary), keyboard interrupt (Ctrl+C) with cleanup and exit code 130, concurrent project switch requests (show queue/blocking message), non-existent project directory (warning but allow switch), project directory not accessible (warning with permission hint)
- [ ] T044 [P] Validate against quickstart.md workflows: test "Workflow 1: Start Working on a Project" (list → switch → current → windows), verify completion time <5 seconds per SC-001, test "Workflow 2: Debug Window Visibility Issue" (current → windows --live with H toggle → rules classify → daemon events), test "Workflow 3: Create New Project" (create → show → switch → windows), verify completion time <30 seconds, test "Workflow 4: Monitor System in Real-Time" (windows --live, daemon events, monitor), verify all three modes work as expected
- [ ] T045 Performance validation: measure CLI startup time (should be <300ms per SC-003), measure project switch time (should be <2s per SC-001), measure window state query time (should be <500ms), measure live TUI update latency (should be <100ms per FR-030, SC-004), verify binary size (should be <20MB per SC-002), measure memory usage during extended live monitoring session (should be <50MB after 1 hour per SC-005)
- [ ] T046 [P] Documentation updates: update quickstart.md with actual binary installation path, update README.md with compilation and testing instructions, add troubleshooting section to README.md for common errors, document all environment variables used (XDG_RUNTIME_DIR, HOME, USER), document daemon protocol version compatibility requirements

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3 → P4 → P5 → P6)
- **NixOS Integration (Phase 9)**: Depends on at least US1 (MVP) being complete, ideally all user stories
- **Polish (Phase 10)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independent (uses same daemon client from Phase 2)
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Independent (extends project.ts from US1 but separate commands)
- **User Story 4 (P4)**: Can start after Foundational (Phase 2) - Independent (new command file daemon.ts)
- **User Story 5 (P5)**: Can start after Foundational (Phase 2) - Independent (new command files rules.ts, app-classes.ts)
- **User Story 6 (P6)**: Can start after Foundational (Phase 2) - Independent (new files monitor-dashboard.ts, monitor.ts)

### Within Each User Story

- Models/types before services (Phase 2 handles this globally)
- Services/client before commands (Phase 2 handles client)
- Commands can be implemented in any order within a story
- UI components before commands that use them

### Parallel Opportunities

- **Phase 1 (Setup)**: All tasks marked [P] can run in parallel (T003)
- **Phase 2 (Foundational)**: T005-T011 all marked [P] can run in parallel after T004 completes
- **Phase 3 (US1)**: All tasks sequential (same file src/commands/project.ts)
- **Phase 4 (US2)**: T017, T018 can run in parallel (different UI formatter files)
- **Phase 5 (US3)**: All tasks sequential (same file src/commands/project.ts)
- **Phase 6 (US4)**: T028, T029 sequential (same file src/commands/daemon.ts)
- **Phase 7 (US5)**: T030-T033 can run in parallel (different commands in rules.ts), T034 parallel (different file app-classes.ts)
- **Phase 8 (US6)**: T035, T036 sequential (dashboard before command)
- **Phase 10 (Polish)**: T040, T041, T042, T044, T046 all marked [P] can run in parallel

**Once Foundational phase completes, all user stories (Phase 3-8) can start in parallel if team capacity allows**

---

## Parallel Example: User Story 2 (Window Visualization)

```bash
# After Foundational phase (Phase 2) completes, launch parallel UI formatter tasks:
Task: "Implement tree view formatter in src/ui/tree.ts" (T017)
Task: "Implement table view formatter in src/ui/table.ts" (T018)

# These work on different files and have no dependencies on each other
# Once both complete, T019-T023 can proceed sequentially
```

---

## Parallel Example: User Story 5 (Rules Management)

```bash
# After Foundational phase completes, launch parallel rules commands:
Task: "Implement i3pm rules list command in src/commands/rules.ts" (T030)
Task: "Implement i3pm rules classify command in src/commands/rules.ts" (T031)
Task: "Implement i3pm rules validate command in src/commands/rules.ts" (T032)
Task: "Implement i3pm rules test command in src/commands/rules.ts" (T033)
Task: "Implement i3pm app-classes command in src/commands/app-classes.ts" (T034)

# NOTE: T030-T033 are in same file but separate command functions - can be parallelized
# T034 is in different file - definitely parallel
```

---

## Implementation Strategy

### MVP First (User Story 1 Only - Project Switching)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T012) - CRITICAL foundation
3. Complete Phase 3: User Story 1 (T013-T016) - Project context switching
4. **STOP and VALIDATE**: Test User Story 1 independently
   - `i3pm project list`
   - `i3pm project switch nixos`
   - `i3pm project current` (should show "nixos")
   - `i3pm project clear`
   - `i3pm project current` (should show "Global")
5. Optionally complete Phase 9 (T037-T039) to compile and deploy MVP
6. Gather feedback on core project switching workflow

**MVP Deliverable**: Fully functional project context switching CLI with 4 commands (switch, clear, current, list)

### Incremental Delivery (Add User Stories Sequentially)

1. Complete Setup + Foundational (Phases 1-2) → Foundation ready
2. Add User Story 1 (Phase 3) → Test independently → **Deploy/Demo MVP!**
3. Add User Story 2 (Phase 4) → Test independently → Deploy/Demo (MVP + Window Visualization)
4. Add User Story 3 (Phase 5) → Test independently → Deploy/Demo (+ Configuration Management)
5. Add User Story 4 (Phase 6) → Test independently → Deploy/Demo (+ Daemon Monitoring)
6. Add User Story 5 (Phase 7) → Test independently → Deploy/Demo (+ Rules Management)
7. Add User Story 6 (Phase 8) → Test independently → Deploy/Demo (+ Monitor Dashboard)
8. Complete NixOS Integration (Phase 9) → Compiled binary in home-manager
9. Complete Polish (Phase 10) → Production-ready CLI

**Each story adds value without breaking previous stories**

### Parallel Team Strategy

With multiple developers:

1. **Week 1**: Team completes Setup + Foundational together (Phases 1-2)
2. **Week 2+**: Once Foundational is done, parallelize:
   - Developer A: User Story 1 (Phase 3) - Project switching
   - Developer B: User Story 2 (Phase 4) - Window visualization
   - Developer C: User Story 4 (Phase 6) - Daemon monitoring
3. **Week 3**: Continue parallelizing:
   - Developer A: User Story 3 (Phase 5) - Configuration management
   - Developer B: User Story 5 (Phase 7) - Rules management
   - Developer C: User Story 6 (Phase 8) - Monitor dashboard
4. **Week 4**: Integration
   - All developers: NixOS Integration (Phase 9)
   - All developers: Polish (Phase 10) - can split parallel tasks

Stories complete and integrate independently, enabling maximum parallelization.

---

## Total Task Count: 46 tasks

### By Phase:
- Phase 1 (Setup): 3 tasks
- Phase 2 (Foundational): 9 tasks
- Phase 3 (US1 - Project Switching): 4 tasks
- Phase 4 (US2 - Window Visualization): 7 tasks
- Phase 5 (US3 - Configuration Management): 4 tasks
- Phase 6 (US4 - Daemon Monitoring): 2 tasks
- Phase 7 (US5 - Rules Management): 5 tasks
- Phase 8 (US6 - Monitor Dashboard): 2 tasks
- Phase 9 (NixOS Integration): 3 tasks
- Phase 10 (Polish): 7 tasks

### By User Story:
- US1 (P1): 4 tasks - Project context switching (MVP core)
- US2 (P2): 7 tasks - Window visualization (high value)
- US3 (P3): 4 tasks - Configuration management
- US4 (P4): 2 tasks - Daemon monitoring
- US5 (P5): 5 tasks - Rules management
- US6 (P6): 2 tasks - Monitor dashboard
- Infrastructure: 22 tasks (Setup + Foundational + NixOS + Polish)

### Parallel Opportunities Identified:
- Phase 2: 7 tasks can run in parallel (T005-T011)
- Phase 4 (US2): 2 tasks can run in parallel (T017, T018)
- Phase 7 (US5): 5 tasks can run in parallel (T030-T034)
- Phase 10: 5 tasks can run in parallel (T040, T041, T042, T044, T046)
- **Cross-story parallelization**: After Phase 2, all 6 user stories can be worked on simultaneously

### Independent Test Criteria per Story:
- **US1**: Run `i3pm project switch nixos` → only nixos windows visible + i3bar shows "nixos"
- **US2**: Run `i3pm windows --live` → real-time updates when opening/closing windows
- **US3**: Run `i3pm project create --name test --dir /tmp/test` → appears in `i3pm project list`
- **US4**: Run `i3pm daemon status` → shows uptime, connected state, event counts, active project
- **US5**: Run `i3pm rules list` → shows classification rules with scoping information
- **US6**: Run `i3pm monitor` → multi-pane TUI with live daemon status, events, windows

### Suggested MVP Scope:
**Minimum**: Phase 1 + Phase 2 + Phase 3 (User Story 1 only) = 16 tasks
**Deliverable**: Core project switching functionality (switch, clear, current, list)
**Time Estimate**: 2-3 days for single developer

**Recommended MVP**: Add Phase 4 (US2) = 23 tasks total
**Deliverable**: Project switching + window visualization (tree, table, live, JSON)
**Time Estimate**: 4-5 days for single developer

---

## Notes

- [P] tasks = different files or independent code sections, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group (e.g., T013-T016 for US1)
- Stop at any checkpoint to validate story independently before proceeding
- All file paths use TypeScript/Deno conventions in `/etc/nixos/home-modules/tools/i3pm-deno/`
- No test tasks included as tests were not requested in feature specification
- Daemon remains unchanged - all tasks are CLI-side only
- Compilation happens in Phase 9 - can defer until multiple user stories are complete
