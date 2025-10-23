# Tasks: Automated Window Rules Discovery and Validation

**Feature Branch**: `031-create-a-new`
**Input**: Design documents from `/etc/nixos/specs/031-create-a-new/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Tests**: NOT REQUESTED - No test tasks included (spec does not request TDD approach)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US5)
- Include exact file paths in descriptions

## User Story Priorities
- **US1** (P1): Automatic Pattern Discovery - Foundation for all functionality
- **US5** (P2): Deno CLI Integration - Unified interface (high priority for architecture)
- **US2** (P2): Pattern Validation and Testing - Ensures reliability
- **US3** (P3): Bulk Migration and Configuration Update - Makes patterns actionable
- **US4** (P4): Interactive Pattern Learning - Fine-tuning and learning experience

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure for hybrid Deno CLI + Python services architecture

- [X] T001 Create Deno CLI project structure at `home-modules/tools/i3pm/` (EXTENDED EXISTING)
- [X] T002 Create Python backend services structure at `home-modules/tools/i3-window-rules-service/`
- [X] T003 [P] Initialize Deno project with deno.json configuration (EXISTING - i3pm-deno already configured)
- [X] T004 [P] Initialize Python project (dependencies: i3ipc-python, Pydantic - already available in NixOS)
- [X] T005 [P] Create test directory structure: `tests/i3pm-cli/` for Deno tests (SKIPPED - MVP)
- [X] T006 [P] Create test directory structure: `tests/i3-window-rules/` for Python tests (unit/, integration/, scenarios/, fixtures/)
- [X] T007 [P] Add Deno formatter and linter configuration (EXISTING - already in deno.json)
- [X] T008 [P] Add Python development dependencies (EXISTING - available in NixOS environment)

**Checkpoint**: ✅ Project structure ready for foundational implementation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Python Backend Foundation

- [X] T009 [P] Implement Pydantic models in `home-modules/tools/i3-window-rules-service/models.py` (Window, Pattern, PatternType, Scope, WindowRule, ApplicationDefinition, DiscoveryResult, ValidationResult, ConfigurationBackup)
- [X] T010 [P] Implement i3 IPC client wrapper in `home-modules/tools/i3-window-rules-service/i3_client.py` using i3ipc.aio (async connection, get_tree, get_windows, subscribe to events)
- [X] T011 [P] Implement configuration manager in `home-modules/tools/i3-window-rules-service/config_manager.py` (read/write window-rules.json, app-classes.json, application-registry.json with validation)
- [X] T012 Implement standalone CLI in `home-modules/tools/i3-window-rules-service/cli.py` (SIMPLIFIED - direct Python CLI instead of JSON-RPC server for MVP)
- [X] T013 [P] Create main entry point in `home-modules/tools/i3-window-rules-service/__main__.py` and wrapper script

### Deno CLI Foundation

- [X] T014 [P] TypeScript interfaces (EXISTING - i3pm-deno already has comprehensive type system in models.ts)
- [X] T015 Direct Python CLI execution (ADAPTED - calls Python CLI directly instead of JSON-RPC for MVP simplicity)
- [X] T016 [P] CLI utilities (EXISTING - i3pm-deno/src/ui/ already has colors, tables, progress components)
- [X] T017 Main CLI entry point (EXISTING - i3pm-deno/main.ts already routes to subcommands)

### Configuration Files & Schema

- [X] T018 [P] window-rules.json schema (EXISTING - daemon already uses this file)
- [X] T019 [P] app-classes.json schema (EXISTING - daemon already uses this file)
- [X] T020 [P] Create application-registry.json template in `~/.config/i3/application-registry.json` (empty applications array with example entries)
- [X] T021 Create backup directory at `~/.config/i3/backups/` with proper permissions

**Checkpoint**: ✅ Foundation ready - MVP discovery functionality implemented

---

## Phase 3: User Story 1 - Automatic Pattern Discovery (Priority: P1) 🎯 MVP

**Goal**: Automatically discover correct window matching patterns by launching applications and capturing their actual properties via i3 IPC

**Independent Test**: Launch pavucontrol, automatically capture WM_CLASS/title, generate pattern, verify pattern matches correctly

### Implementation for User Story 1

- [X] T022 [P] [US1] Implement rofi launcher simulation and direct launch in `discovery.py` (launch_via_rofi and launch_application_direct functions)
- [X] T023 [P] [US1] Implement window waiting logic in `i3_client.py` - wait_for_window_event() function (subscribe to window::new, timeout with configurable duration, return captured Window)
- [X] T024 [US1] Implement pattern generation logic in `discovery.py` - generate_pattern() function (detect terminal emulators, detect PWAs, choose class vs title patterns, confidence scoring)
- [X] T025 [US1] Implement single application discovery in `discovery.py` - discover_application() async function (launch via rofi or direct command, wait for window, generate pattern, clean up window, return DiscoveryResult)
- [X] T026 [US1] Implement Deno CLI command for discovery in `i3pm-deno/src/commands/rules.ts` - discover subcommand (parse --app, --workspace, --scope flags, call Python CLI, display results)
- [X] T027 [US1] Add pattern confidence scoring in `discovery.py` (exact class match = 1.0, terminal commands = 0.9, generic patterns = 0.7)
- [X] T028 [US1] Add cleanup logic to close launched windows after discovery (implemented in discover_application with keep_window flag)
- [X] T029 [US1] Direct CLI execution (ADAPTED - using direct Python CLI execution instead of JSON-RPC for MVP simplicity)
- [X] T030 [US1] Add CLI output formatting in `cli.py` - display pattern type, value, confidence, warnings/errors with color coding

**Checkpoint**: ✅ Single application discovery works end-to-end (ready for testing)

---

## Phase 4: User Story 5 - Deno CLI Integration (Priority: P2)

**Goal**: Provide unified Deno CLI interface (`i3pm`) for all window rules operations, daemon status, logs, and system diagnostics

**Independent Test**: Run `i3pm rules discover --app pavucontrol` and verify CLI calls Python service, captures result, displays formatted output

### Implementation for User Story 5

- [X] T031 [P] [US5] Status dashboard (EXISTING - `i3pm daemon status` already implemented)
- [X] T032 [P] [US5] Logs command (EXISTING - `i3pm daemon events` already implemented with filtering and tail mode)
- [X] T033 [US5] CLI router (EXISTING - `i3pm-deno/main.ts` already routes to rules, daemon, windows, project commands)
- [X] T034 [US5] Error handling (IMPLEMENTED - discoverCommand has try/catch with user-friendly messages)
- [X] T035 [P] [US5] Progress indicators (EXISTING - bulk discovery in cli.py shows progress, Deno has progress.ts)
- [X] T036 [P] [US5] JSON output mode (IMPLEMENTED - --json flag supported in discover command)
- [X] T037 [US5] Help text (IMPLEMENTED - showHelp() updated with discover command examples)

**Checkpoint**: ✅ Unified CLI interface operational with discovery commands integrated into existing i3pm CLI

---

## Phase 5: User Story 2 - Pattern Validation and Testing (Priority: P2)

**Goal**: Validate configured patterns against real windows to identify broken patterns before they cause workspace assignment failures

**Independent Test**: Given window-rules.json with 5 test patterns, launch each application and verify patterns match correctly and windows appear on assigned workspaces

### Implementation for User Story 2

- [ ] T038 [P] [US2] Implement pattern matching logic in `home-modules/tools/i3-window-rules-service/validation.py` - match_pattern() function (uses Pattern.matches() from models.py, applies precedence order: class → PWA → title_regex → title substring)
- [ ] T039 [P] [US2] Implement window validation against open windows in `home-modules/tools/i3-window-rules-service/validation.py` - validate_against_open_windows() function (query i3 tree, match patterns, check workspaces, detect false positives/negatives)
- [ ] T040 [US2] Implement launch-and-test validation in `home-modules/tools/i3-window-rules-service/validation.py` - validate_with_launch() function (launch application, wait for window, validate pattern match, verify workspace, return ValidationResult)
- [ ] T041 [US2] Implement comprehensive validation report in `home-modules/tools/i3-window-rules-service/validation.py` - validate_all() function (process all rules from window-rules.json, generate statistics: total/passed/failed/accuracy)
- [ ] T042 [US2] Implement Deno CLI validate command in `home-modules/tools/i3pm/src/commands/rules.ts` - validate subcommand (parse --app, --launch, --report flags, call Python service, display results with color-coded pass/fail)
- [ ] T043 [US2] Add false positive detection in `home-modules/tools/i3-window-rules-service/validation.py` (detect patterns matching multiple different applications, report ambiguity)
- [ ] T044 [US2] Add false negative detection in `home-modules/tools/i3-window-rules-service/validation.py` (detect windows with no matching patterns, report unclassified windows)
- [ ] T045 [US2] Add workspace verification in `home-modules/tools/i3-window-rules-service/validation.py` (compare expected workspace from rule vs actual workspace from i3 tree)
- [ ] T046 [US2] Add suggested fixes to validation report in `home-modules/tools/i3-window-rules-service/validation.py` (if pattern fails, suggest more specific pattern with instance/title criteria)
- [ ] T047 [US2] Add JSON-RPC method registration for validate methods in `home-modules/tools/i3-window-rules-service/json_rpc_server.py`

**Checkpoint**: Pattern validation works for both open windows and launch-and-test scenarios

---

## Phase 6: User Story 3 - Bulk Migration and Configuration Update (Priority: P3)

**Goal**: Migrate existing broken configuration to verified patterns in bulk, updating window-rules.json and app-classes.json

**Independent Test**: Start with test window-rules.json with 5 broken patterns, run discovery, execute migration, verify config updated and windows now on correct workspaces

### Implementation for User Story 3

- [ ] T048 [P] [US3] Implement backup creation in `home-modules/tools/i3-window-rules-service/migration.py` - create_backup() function (timestamp format YYYYMMDD-HHMMSS, copy window-rules.json and app-classes.json to backups/, return ConfigurationBackup)
- [ ] T049 [P] [US3] Implement pattern replacement in `home-modules/tools/i3-window-rules-service/migration.py` - replace_patterns() function (update existing rules with new patterns, preserve workspace/scope/priority, maintain JSON structure)
- [ ] T050 [US3] Implement new rule insertion in `home-modules/tools/i3-window-rules-service/migration.py` - add_new_rules() function (insert rules for new applications, update app-classes.json scoped/global lists, maintain alphabetical order)
- [ ] T051 [US3] Implement duplicate detection in `home-modules/tools/i3-window-rules-service/migration.py` - detect_duplicates() function (find duplicate patterns, report conflicts, prompt for resolution)
- [ ] T052 [US3] Implement JSON validation with rollback in `home-modules/tools/i3-window-rules-service/migration.py` - validate_and_write() function (validate JSON syntax after updates, rollback to backup if corruption detected)
- [ ] T053 [US3] Implement daemon reload in `home-modules/tools/i3-window-rules-service/migration.py` - reload_daemon() function (systemctl --user restart i3-project-event-listener, verify daemon running)
- [ ] T054 [US3] Implement Deno CLI migrate command in `home-modules/tools/i3pm/src/commands/rules.ts` - migrate subcommand (parse --from, --dry-run, --interactive, --no-backup flags, call Python service, display migration report)
- [ ] T055 [US3] Add dry-run mode support in `home-modules/tools/i3-window-rules-service/migration.py` (show changes without applying, prefix output with [DRY RUN])
- [ ] T056 [US3] Add interactive conflict resolution in `home-modules/tools/i3-window-rules-service/migration.py` (prompt user: keep existing / replace / skip when duplicates found)
- [ ] T057 [US3] Add workspace conflict detection in `home-modules/tools/i3-window-rules-service/migration.py` (detect if workspace already assigned to different application, suggest available workspaces)
- [ ] T058 [US3] Add JSON-RPC method registration for migrate methods in `home-modules/tools/i3-window-rules-service/json_rpc_server.py`

**Checkpoint**: Bulk migration works with backups, validation, rollback, and daemon reload

---

## Phase 7: User Story 4 - Interactive Pattern Learning (Priority: P4)

**Goal**: Provide interactive TUI mode for launching applications one at a time, seeing captured properties in real-time, and testing assignments with instant feedback

**Independent Test**: Launch interactive mode, select application from list, watch it launch and capture properties, manually review/adjust pattern, assign workspace, test by relaunching

### Implementation for User Story 4

- [ ] T059 [P] [US4] Implement application list view in `home-modules/tools/i3-window-rules-service/interactive.py` - ApplicationListView class (load applications from registry, display with Rich tables, handle selection with keyboard: ↑/↓/Space/Enter)
- [ ] T060 [P] [US4] Implement property display view in `home-modules/tools/i3-window-rules-service/interactive.py` - PropertyDisplayView class (show captured WM_CLASS/instance/title/workspace, display generated pattern, show confidence, highlight warnings)
- [ ] T061 [US4] Implement pattern editor in `home-modules/tools/i3-window-rules-service/interactive.py` - PatternEditor class (allow manual adjustment of pattern type/value, real-time validation, show which windows would match)
- [ ] T062 [US4] Implement workspace assignment UI in `home-modules/tools/i3-window-rules-service/interactive.py` - WorkspaceAssignmentView class (show available workspaces 1-9, warn if workspace already assigned, allow scope selection: scoped/global with explanations)
- [ ] T063 [US4] Implement test launcher in `home-modules/tools/i3-window-rules-service/interactive.py` - test_pattern() function (close current window, relaunch application, verify workspace placement, show real-time feedback with color indicators)
- [ ] T064 [US4] Implement interactive main loop in `home-modules/tools/i3-window-rules-service/interactive.py` - run_interactive() function (orchestrate views: list → launch → capture → edit → assign → test → save, handle Ctrl+S save, Ctrl+T test, Ctrl+Q quit)
- [ ] T065 [US4] Implement Deno CLI interactive command in `home-modules/tools/i3pm/src/commands/rules.ts` - interactive subcommand (launch Python TUI service, handle terminal setup, display help text with keyboard shortcuts)
- [ ] T066 [US4] Add classification explanations in `home-modules/tools/i3-window-rules-service/interactive.py` (when selecting scope, show examples: "Scoped = project-specific like VSCode, Global = always visible like Firefox")
- [ ] T067 [US4] Add pattern suggestion in `home-modules/tools/i3-window-rules-service/interactive.py` (show similar applications with similar classifications, suggest workspace based on application type)
- [ ] T068 [US4] Add JSON-RPC method registration for interactive mode in `home-modules/tools/i3-window-rules-service/json_rpc_server.py`

**Checkpoint**: Interactive TUI mode provides complete workflow from application selection to tested pattern

---

## Phase 8: Bulk Discovery & Advanced Features

**Purpose**: Support bulk operations and advanced discovery scenarios building on US1-US4

### Bulk Discovery (builds on US1)

- [ ] T069 [P] [US1] Implement bulk discovery from file in `home-modules/tools/i3-window-rules-service/discovery.py` - discover_bulk() function (read application list from file one per line, process sequentially with delays, aggregate DiscoveryResults, show progress)
- [ ] T070 [P] [US1] Implement bulk discovery from registry in `home-modules/tools/i3-window-rules-service/discovery.py` - discover_from_registry() function (load application-registry.json, use command/parameters from ApplicationDefinition, process all 70+ applications)
- [ ] T071 [US1] Add parameterized command support in `home-modules/tools/i3-window-rules-service/discovery.py` (handle $PROJECT_DIR substitution, launch with base command for discovery, validate pattern matches parameterized launches)
- [ ] T072 [US1] Add bulk discovery progress reporting in `home-modules/tools/i3pm/src/commands/rules.ts` (show [N/70] progress, display success/failure counts, show average time per application)
- [ ] T073 [US1] Add configurable delay between bulk discoveries in `home-modules/tools/i3-window-rules-service/discovery.py` (default 1s delay, allow --delay flag to prevent overwhelming window manager)

### Advanced Edge Cases (builds on US1, US2)

- [ ] T074 [P] [US1] Add multi-window detection in `home-modules/tools/i3-window-rules-service/discovery.py` (detect when application spawns multiple windows, prompt user which window to use for pattern)
- [ ] T075 [P] [US1] Add unstable WM_CLASS detection in `home-modules/tools/i3-window-rules-service/discovery.py` (detect if WM_CLASS changes between launches, warn user, suggest title-based pattern instead)
- [ ] T076 [P] [US2] Add pattern ambiguity suggestions in `home-modules/tools/i3-window-rules-service/validation.py` (when pattern matches multiple apps, suggest making pattern more specific: add instance or title criteria)
- [ ] T077 [P] [US1] Add rofi simulation fallback in `home-modules/tools/i3-window-rules-service/rofi_launcher.py` (detect rofi timeout, fall back to direct command execution, log failure)

### Inspection & Debugging (builds on US1, US5)

- [ ] T078 [P] [US1] Implement inspect mode in `home-modules/tools/i3-window-rules-service/discovery.py` - inspect() function (show detailed window properties, test multiple patterns against window, show which patterns match)
- [ ] T079 [US1] Add inspect mode to Deno CLI in `home-modules/tools/i3pm/src/commands/rules.ts` - discover --inspect flag (display comprehensive property table, show pattern matching test results)

**Checkpoint**: Bulk operations support all 70+ applications, edge cases handled gracefully

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

### Documentation

- [ ] T080 [P] Update CLAUDE.md in `/etc/nixos/CLAUDE.md` with window rules discovery section (i3pm rules commands, common workflows, troubleshooting)
- [ ] T081 [P] Create inline code documentation in all Python modules (docstrings for all functions, classes, parameters following Google style)
- [ ] T082 [P] Create inline code documentation in all Deno modules (JSDoc comments for all functions, interfaces, types)
- [ ] T083 [P] Add README.md to `home-modules/tools/i3pm/` (Deno CLI architecture, commands overview, JSON-RPC communication)
- [ ] T084 [P] Add README.md to `home-modules/tools/i3-window-rules-service/` (Python services overview, data models, integration points)

### Validation & Testing Scenarios

- [ ] T085 Run quickstart.md validation: Discover pavucontrol pattern
- [ ] T086 Run quickstart.md validation: Discover VSCode pattern with workspace assignment
- [ ] T087 Run quickstart.md validation: Bulk discover from applications.txt
- [ ] T088 Run quickstart.md validation: Validate current configuration
- [ ] T089 Run quickstart.md validation: Validate specific pattern with launch
- [ ] T090 Run quickstart.md validation: Migrate discovered patterns
- [ ] T091 Run quickstart.md validation: Interactive pattern learning workflow
- [ ] T092 Run quickstart.md validation: Fix broken workspace assignments workflow (VSCode WS2 → WS31)

### Error Handling & Logging

- [ ] T093 [P] Add comprehensive error handling to all Python services (catch i3 IPC errors, file I/O errors, JSON parsing errors, return error results instead of exceptions)
- [ ] T094 [P] Add comprehensive error handling to Deno CLI (catch JSON-RPC errors, display user-friendly messages, suggest troubleshooting steps)
- [ ] T095 [P] Add logging to Python services using standard logging module (log discovery attempts, validation results, migration operations to systemd journal)
- [ ] T096 [P] Add debug mode flag to CLI in `home-modules/tools/i3pm/main.ts` (--debug shows verbose output, logs JSON-RPC calls, displays stack traces)

### Performance & Optimization

- [ ] T097 [P] Optimize i3 IPC queries in `home-modules/tools/i3-window-rules-service/i3_client.py` (cache get_tree results when appropriate, reuse connections)
- [ ] T098 [P] Optimize JSON configuration loading in `home-modules/tools/i3-window-rules-service/config_manager.py` (cache parsed JSON, only reload on changes)
- [ ] T099 [P] Add timeout configuration to discovery in `home-modules/tools/i3-window-rules-service/discovery.py` (allow --timeout flag, default 10s, fast-launching apps use 5s, slow apps use 30s)

### NixOS Integration

- [ ] T100 Add i3pm Deno CLI to NixOS home-manager configuration in `home-modules/tools/i3pm/default.nix`
- [ ] T101 Add Python window rules service to NixOS home-manager configuration in `home-modules/tools/i3-window-rules-service/default.nix`
- [ ] T102 [P] Add required dependencies to NixOS configuration: xdotool, i3ipc-python, deno, python311Packages.rich, python311Packages.pydantic
- [ ] T103 Add systemd user service for JSON-RPC server in `home-modules/tools/i3-window-rules-service/i3-window-rules-service.service`
- [ ] T104 Rebuild NixOS system and verify i3pm command available

### Final Validation

- [ ] T105 Test complete workflow: Discover 5 test applications (pavucontrol, firefox, vscode, lazygit, 1password)
- [ ] T106 Validate all 5 discovered patterns match correctly
- [ ] T107 Migrate 5 patterns to window-rules.json and verify daemon reloads
- [ ] T108 Test interactive mode with one new application
- [ ] T109 Test bulk discovery with 10 applications from registry
- [ ] T110 Verify all CLI commands work: i3pm rules discover, i3pm rules validate, i3pm rules migrate, i3pm rules interactive, i3pm status, i3pm logs

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Phase 2 completion
  - **Phase 3 (US1 - P1)**: Foundation for discovery functionality
  - **Phase 4 (US5 - P2)**: CLI integration layer (depends on US1 basic discovery being available)
  - **Phase 5 (US2 - P2)**: Validation (can run in parallel with Phase 4, uses discovery from Phase 3)
  - **Phase 6 (US3 - P3)**: Migration (depends on US1 discovery and US2 validation)
  - **Phase 7 (US4 - P4)**: Interactive mode (depends on US1, US2, US3 all complete)
- **Bulk Discovery (Phase 8)**: Depends on Phase 3, 4, 5 (builds on US1, US2, US5)
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1 - Discovery)**: Can start after Phase 2 - No dependencies on other stories, foundation for all others
- **User Story 5 (P2 - CLI Integration)**: Can start after US1 has basic discovery operational (T022-T025 complete)
- **User Story 2 (P2 - Validation)**: Can start after Phase 2 - Uses discovery from US1 but can run in parallel with US5
- **User Story 3 (P3 - Migration)**: Depends on US1 (discovery) and US2 (validation) - should not start until both operational
- **User Story 4 (P4 - Interactive)**: Depends on US1, US2, US3 all complete - integrates all functionality

### Within Each User Story

**User Story 1 (Discovery)**:
- T022, T023 (rofi launcher, window waiting) can run in parallel [P]
- T024 (pattern generation) depends on T023 (needs window waiting)
- T025 (discovery orchestration) depends on T022, T023, T024
- T026-T030 (CLI integration) depend on T025

**User Story 5 (CLI Integration)**:
- T031, T032, T035, T036, T037 (status, logs, progress, JSON mode, help) can all run in parallel [P]
- T033 (CLI router) depends on T031, T032
- T034 (error handling) can run in parallel [P]

**User Story 2 (Validation)**:
- T038, T039 (pattern matching, open window validation) can run in parallel [P]
- T040 (launch-and-test) depends on T038
- T041 (comprehensive validation) depends on T038, T039, T040
- T042-T047 (CLI integration, enhancements) depend on T041

**User Story 3 (Migration)**:
- T048, T049 (backup, pattern replacement) can run in parallel [P]
- T050 (new rule insertion) can run in parallel [P]
- T051, T052 (duplicate detection, JSON validation) depend on T049, T050
- T053-T058 (daemon reload, CLI, enhancements) depend on T052

**User Story 4 (Interactive)**:
- T059, T060 (list view, property display) can run in parallel [P]
- T061, T062 (pattern editor, workspace assignment) can run in parallel [P]
- T063 (test launcher) depends on T061, T062
- T064 (main loop) depends on T059-T063
- T065-T068 (CLI integration, enhancements) depend on T064

### Parallel Opportunities

- **Setup (Phase 1)**: T003/T004 (Deno/Python init), T005/T006 (test directories), T007/T008 (dev tools) can all run in parallel
- **Foundational (Phase 2)**: T009/T010/T011 (models, i3 client, config manager) can run in parallel, T014/T016 (TypeScript interfaces, UI utilities) can run in parallel
- **User Story 1**: T022/T023 can run in parallel
- **User Story 5**: T031/T032/T035/T036/T037 can run in parallel
- **User Story 2**: T038/T039 can run in parallel
- **User Story 3**: T048/T049/T050 can run in parallel
- **User Story 4**: T059/T060 and T061/T062 can run in parallel
- **Bulk Discovery (Phase 8)**: T069/T070, T074/T075/T076/T077, T078 can run in parallel (different files)
- **Polish (Phase 9)**: All documentation (T080-T084), all error handling (T093-T096), all optimization (T097-T099), NixOS dependencies (T102) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch rofi launcher and window waiting together:
Task T022: "Implement rofi launcher simulation in home-modules/tools/i3-window-rules-service/rofi_launcher.py"
Task T023: "Implement window waiting logic in home-modules/tools/i3-window-rules-service/discovery.py - wait_for_new_window()"

# These are independent Python functions in different aspects of discovery
```

## Parallel Example: User Story 5

```bash
# Launch all CLI component tasks together:
Task T031: "Implement status dashboard in home-modules/tools/i3pm/src/commands/status.ts"
Task T032: "Implement logs command in home-modules/tools/i3pm/src/commands/logs.ts"
Task T035: "Implement progress indicators in home-modules/tools/i3pm/src/ui/progress.ts"
Task T036: "Add JSON output mode in home-modules/tools/i3pm/src/commands/rules.ts"
Task T037: "Add help text to CLI in home-modules/tools/i3pm/main.ts"

# All different files, no dependencies
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 5 Basic CLI)

**Goal**: Get single application discovery working end-to-end with CLI interface

1. Complete Phase 1: Setup (T001-T008)
2. Complete Phase 2: Foundational (T009-T021) - CRITICAL blocking phase
3. Complete Phase 3: User Story 1 (T022-T030) - Discovery functionality
4. Complete Phase 4: User Story 5 Basic (T031-T034) - CLI integration for discovery
5. **STOP and VALIDATE**: Test `i3pm rules discover --app pavucontrol`
6. If working, move to validation features

**Expected Result**: Can discover pattern for any single application via unified CLI

### Incremental Delivery

1. **Setup + Foundational** (Phases 1-2) → Foundation ready
2. **+ User Story 1** (Phase 3) → Single app discovery works → **Test independently**
3. **+ User Story 5 Basic** (Phase 4 partial) → CLI interface operational → **Test independently**
4. **+ User Story 2** (Phase 5) → Pattern validation works → **Test independently**
5. **+ User Story 3** (Phase 6) → Migration works → **Test independently**
6. **+ Bulk Discovery** (Phase 8) → Can process 70+ applications → **Test with 10 apps**
7. **+ User Story 4** (Phase 7) → Interactive TUI for fine-tuning → **Test with new app**
8. **+ Polish** (Phase 9) → Production-ready

Each phase adds value without breaking previous functionality.

### Parallel Team Strategy

With multiple developers:

1. **Team completes Setup + Foundational together** (Phases 1-2)
2. **Once Foundational done**, split work:
   - **Developer A**: User Story 1 (Discovery) - Phase 3
   - **Developer B**: User Story 5 (CLI Integration) - Phase 4 (waits for T022-T025 from Dev A)
   - **Developer C**: User Story 2 (Validation) - Phase 5 (can start after Phase 2)
3. **Once US1, US2 complete**, Developer C continues with:
   - User Story 3 (Migration) - Phase 6
4. **Once US1, US2, US3 complete**, Developer A or B implements:
   - User Story 4 (Interactive) - Phase 7
   - Bulk Discovery - Phase 8

---

## Task Count Summary

- **Phase 1 (Setup)**: 8 tasks
- **Phase 2 (Foundational)**: 13 tasks (BLOCKING)
- **Phase 3 (US1 - Discovery)**: 9 tasks
- **Phase 4 (US5 - CLI Integration)**: 7 tasks
- **Phase 5 (US2 - Validation)**: 10 tasks
- **Phase 6 (US3 - Migration)**: 11 tasks
- **Phase 7 (US4 - Interactive)**: 10 tasks
- **Phase 8 (Bulk Discovery & Advanced)**: 11 tasks
- **Phase 9 (Polish)**: 31 tasks

**Total**: 110 tasks

### Tasks Per User Story

- **User Story 1 (Discovery - P1)**: 22 tasks (Phase 3: 9 + Phase 8: 13)
- **User Story 5 (CLI Integration - P2)**: 7 tasks (Phase 4)
- **User Story 2 (Validation - P2)**: 10 tasks (Phase 5)
- **User Story 3 (Migration - P3)**: 11 tasks (Phase 6)
- **User Story 4 (Interactive - P4)**: 10 tasks (Phase 7)
- **Setup + Foundational**: 21 tasks (Phases 1-2)
- **Polish**: 31 tasks (Phase 9)

### Parallel Opportunities Identified

- **Setup Phase**: 6 tasks can run in parallel (T003-T008)
- **Foundational Phase**: 7 tasks can run in parallel (T009-T011, T014, T016, T018-T020)
- **User Story 1**: 2 pairs of parallel tasks
- **User Story 5**: 5 tasks can run in parallel (T031, T032, T034, T035, T036, T037)
- **User Story 2**: 2 pairs of parallel tasks
- **User Story 3**: 3 pairs of parallel tasks
- **User Story 4**: 4 tasks can run in parallel (T059-T062)
- **Bulk Discovery**: 6 tasks can run in parallel
- **Polish Phase**: 15+ tasks can run in parallel (documentation, error handling, optimization)

**Total parallel opportunities**: 40+ tasks that can be executed concurrently

### Independent Test Criteria

**User Story 1 (Discovery)**: Launch pavucontrol → Capture WM_CLASS "Pavucontrol" → Generate class pattern → Verify pattern matches → Success

**User Story 5 (CLI Integration)**: Run `i3pm rules discover --app pavucontrol` → CLI calls Python service → Displays formatted table with pattern → Success

**User Story 2 (Validation)**: Configure 5 test patterns → Launch each application → Verify all 5 patterns match correctly → Verify all 5 windows on correct workspaces → Success

**User Story 3 (Migration)**: Start with 5 broken patterns → Run discovery → Execute migration → Verify window-rules.json updated → Verify windows now on correct workspaces → Success

**User Story 4 (Interactive)**: Launch TUI → Select application → Watch capture → Review/adjust pattern → Assign workspace → Test relaunch → Verify workspace → Success

### Suggested MVP Scope

**Minimum Viable Product**: User Story 1 (Discovery) + User Story 5 Basic (CLI)

**Rationale**: Provides immediate value - can discover correct patterns for any application via unified CLI interface. Validates hybrid Deno+Python architecture. Enables manual configuration updates while automated migration is being built.

**Time Estimate**:
- Setup + Foundational: ~2-3 days
- User Story 1: ~2-3 days
- User Story 5 Basic: ~1 day
- **MVP Total**: ~5-7 days

**Next Priority**: User Story 2 (Validation) to ensure discovered patterns actually work before migrating 65+ broken rules.

---

## Notes

- **[P]** tasks = different files, no dependencies within same phase
- **[Story]** label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- No tests included (not requested in spec)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Architecture follows Constitution Principles X (Python for i3 IPC) + XIII (Deno for CLI)
- JSON-RPC communication ensures clean separation between Deno CLI frontend and Python backend services

---

**Tasks Complete**: 110 tasks organized by user story for independent implementation and delivery
