# Tasks: Declarative Workspace-to-Monitor Mapping Configuration

**Input**: Design documents from `/specs/033-declarative-workspace-to/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/jsonrpc-api.md ✅

**Tests**: Tests are NOT explicitly requested in the specification. This implementation focuses on the feature functionality without TDD.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- **Python daemon**: `home-modules/tools/i3pm-daemon/`
- **Deno CLI**: `home-modules/tools/i3pm-cli/`
- **i3 scripts**: `home-modules/desktop/i3/scripts/` (for deletion)
- **NixOS config**: `home-modules/` for home-manager integration

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 [P] Create Python daemon directory structure at `home-modules/tools/i3pm-daemon/` with `models.py`, `monitor_config_manager.py`, `config_schema.json`
- [X] T002 [P] Create Deno CLI directory structure at `home-modules/tools/i3pm-cli/` with subdirectories `src/commands/`, `src/ui/`, and `deno.json`
- [X] T003 [P] Add Pydantic dependency to Python daemon requirements (update `home-modules/tools/i3pm-daemon/requirements.txt` or inline in NixOS config)
- [X] T004 [P] Configure Deno dependencies in `home-modules/tools/i3pm-cli/deno.json` (import maps for @std/cli, @std/fs, @std/json, zod)
- [X] T005 Generate default configuration file template at `home-modules/tools/i3pm-daemon/default-config.json` matching spec defaults

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 [P] Implement Pydantic configuration models in `home-modules/tools/i3pm-daemon/models.py`: `MonitorRole`, `MonitorDistribution`, `DistributionRules`, `WorkspaceMonitorConfig`
- [X] T007 [P] Implement i3 state models in `home-modules/tools/i3pm-daemon/models.py`: `OutputRect`, `MonitorConfig`, `WorkspaceAssignment`, `MonitorSystemState`
- [X] T008 [P] Implement validation models in `home-modules/tools/i3pm-daemon/models.py`: `ValidationIssue`, `ConfigValidationResult`
- [X] T009 Create JSON schema file at `home-modules/tools/i3pm-daemon/config_schema.json` for configuration validation
- [X] T010 [P] Implement TypeScript/Zod models in `home-modules/tools/i3pm-cli/src/models.ts`: All schemas from data-model.md
- [X] T011 Implement `MonitorConfigManager` class in `home-modules/tools/i3pm-daemon/monitor_config_manager.py` with methods: `load_config()`, `validate_config_file()`, `_validate_distribution_logic()`, `_validate_workspace_preferences()`
- [X] T012 Add NixOS home-manager configuration in `home-modules/tools/i3pm-daemon/default.nix` to generate default config file at `~/.config/i3/workspace-monitor-mapping.json` using `xdg.configFile`
- [X] T013 [P] Implement JSON-RPC daemon client in `home-modules/tools/i3pm-cli/src/daemon_client.ts`: `DaemonClient` class with `request()`, `connect()`, `close()` methods
- [X] T014 [P] Implement JSON-RPC error handling in `home-modules/tools/i3pm-cli/src/daemon_client.ts`: `parseDaemonConnectionError()`, `validateResponse()` functions

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Declarative Workspace Distribution Configuration (Priority: P1) 🎯 MVP

**Goal**: Define workspace-to-monitor distribution rules in a JSON configuration file, read and apply them via daemon

**Independent Test**: Create a JSON config file with custom distribution (workspaces 1-5 primary, 6-10 secondary), verify daemon reads config and applies assignments correctly when `i3pm monitors reassign` is called

### Implementation for User Story 1

- [X] T015 [US1] Refactor `workspace_manager.py` to replace hardcoded distribution logic (lines 186-221) with call to `MonitorConfigManager.load_config()`
- [X] T016 [US1] Implement `get_workspace_distribution()` method in `monitor_config_manager.py` that returns distribution rules based on active monitor count (1/2/3 monitors)
- [X] T017 [US1] Implement `resolve_workspace_target_role()` method in `monitor_config_manager.py` that resolves workspace number to role (primary/secondary/tertiary) considering workspace_preferences overrides
- [X] T018 [US1] Implement `assign_monitor_roles()` method in `monitor_config_manager.py` that assigns roles to active monitors based on primary flag and output_preferences
- [X] T019 [US1] Update `assign_workspaces_to_monitors()` function in `workspace_manager.py` to use config-driven logic instead of hardcoded rules
- [X] T020 [US1] Implement `reassign_workspaces` JSON-RPC method in daemon IPC server (`home-modules/desktop/i3-project-event-daemon/ipc_server.py`) calling workspace manager
- [X] T021 [US1] Implement `get_config` JSON-RPC method in daemon IPC server to return current loaded configuration
- [X] T022 [US1] Implement `validate_config` JSON-RPC method in daemon IPC server calling `MonitorConfigManager.validate_config_file()`
- [X] T023 [US1] Implement `reload_config` JSON-RPC method in daemon IPC server that reloads config and returns change summary
- [X] T024 [US1] Implement CLI command `i3pm monitors config show` in `home-modules/tools/i3pm-cli/src/commands/monitors_config.ts` (show subcommand)
- [X] T025 [US1] Implement CLI command `i3pm monitors config edit` in `home-modules/tools/i3pm-cli/src/commands/monitors_config.ts` (edit subcommand with $EDITOR)
- [X] T026 [US1] Implement CLI command `i3pm monitors config init` in `home-modules/tools/i3pm-cli/src/commands/monitors_config.ts` (init subcommand to generate default)
- [X] T027 [US1] Implement CLI command `i3pm monitors config validate` in `home-modules/tools/i3pm-cli/src/commands/monitors_config.ts` (validate subcommand)
- [X] T028 [US1] Implement CLI command `i3pm monitors config reload` in `home-modules/tools/i3pm-cli/src/commands/monitors_config.ts` (reload subcommand)
- [X] T029 [US1] Implement CLI command `i3pm monitors reassign` in `home-modules/tools/i3pm-cli/src/commands/monitors_reassign.ts` with `--dry-run` flag support
- [X] T030 [US1] Delete `home-modules/desktop/i3/scripts/detect-monitors.sh` bash script (forward-only development)
- [X] T031 [US1] Remove i3 config startup exec line for `detect-monitors.sh` from i3 configuration file

**Checkpoint**: At this point, User Story 1 should be fully functional - users can create config files, validate them, and apply workspace distribution via CLI

---

## Phase 4: User Story 2 - Multi-Monitor Adaptation (Priority: P1)

**Goal**: Automatically adjust workspace distribution based on the number of active monitors (1, 2, or 3) via event-driven daemon

**Independent Test**: Start with 1 monitor (all workspaces on primary), connect a second monitor (workspaces redistribute according to config), disconnect secondary (workspaces return to primary), verify all workspaces remain accessible

### Implementation for User Story 2

- [X] T032 [US2] Implement `get_monitors` JSON-RPC method in daemon IPC server to query i3 IPC GET_OUTPUTS and return `List[MonitorConfig]`
- [X] T033 [US2] Implement `get_workspaces` JSON-RPC method in daemon IPC server to query i3 IPC GET_WORKSPACES and return `List[WorkspaceAssignment]` with target roles
- [X] T034 [US2] Implement `get_system_state` JSON-RPC method in daemon IPC server combining monitors + workspaces into `MonitorSystemState`
- [X] T035 [US2] Add i3 IPC OUTPUT event subscription to daemon's event loop (in `home-modules/desktop/i3-project-event-daemon/main.py` or equivalent)
- [X] T036 [US2] Implement `on_output_change` event handler in daemon that debounces for `debounce_ms` milliseconds before triggering reassignment
- [X] T037 [US2] Implement automatic workspace reassignment in `on_output_change` handler (only if `enable_auto_reassign` is true)
- [X] T038 [US2] Add monitor change event logging to daemon event history (for `get_monitor_history` method later)
- [X] T039 [US2] Implement CLI command `i3pm monitors status` in `home-modules/tools/i3pm-cli/src/commands/monitors_status.ts` showing monitor table with role, resolution, workspaces
- [X] T040 [US2] Implement CLI command `i3pm monitors workspaces` in `home-modules/tools/i3pm-cli/src/commands/monitors_workspaces.ts` showing workspace-to-output mapping table
- [X] T041 [US2] Implement table formatter utility in `home-modules/tools/i3pm-cli/src/ui/table_formatter.ts` using Cliffy Table component
- [X] T042 [US2] Update daemon to handle monitor count changes: detect when monitors go from 2→1, 1→2, 2→3, 3→2 and apply correct distribution rules

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - config-driven distribution + automatic adaptation to monitor changes

---

## Phase 5: User Story 3 - Comprehensive CLI/TUI Interface (Priority: P1)

**Goal**: Provide complete CLI and TUI interface for viewing, managing, editing, and troubleshooting workspace-to-monitor system

**Independent Test**: Run various CLI commands (`status`, `move`, `diagnose`, `watch`, `tui`) and verify all operations complete with clear output. Test TUI interactivity (move workspace, edit config, reload).

### Implementation for User Story 3

#### Status and Display Commands

- [ ] T043 [P] [US3] Implement `move_workspace` JSON-RPC method in daemon IPC server accepting `workspace_num` and `target_role` or `target_output`
- [ ] T044 [P] [US3] Implement `get_monitor_history` JSON-RPC method in daemon IPC server returning recent output/workspace events
- [ ] T045 [P] [US3] Implement `get_diagnostics` JSON-RPC method in daemon IPC server analyzing orphaned workspaces, inactive outputs, config issues
- [ ] T046 [US3] Implement CLI command `i3pm monitors move` in `home-modules/tools/i3pm-cli/src/commands/monitors_move.ts` with `--to <role|output>` flag
- [ ] T047 [US3] Implement CLI command `i3pm monitors history` in `home-modules/tools/i3pm-cli/src/commands/monitors_history.ts` displaying recent events
- [ ] T048 [US3] Implement CLI command `i3pm monitors diagnose` in `home-modules/tools/i3pm-cli/src/commands/monitors_diagnose.ts` showing diagnostic report with suggested fixes
- [ ] T049 [US3] Implement CLI command `i3pm monitors debug` in `home-modules/tools/i3pm-cli/src/commands/monitors_debug.ts` with verbose daemon state output

#### Live Monitoring (TUI)

- [ ] T050 [US3] Add deno_tui dependency to `home-modules/tools/i3pm-cli/deno.json` import map
- [ ] T051 [US3] Implement CLI command `i3pm monitors watch` in `home-modules/tools/i3pm-cli/src/commands/monitors_watch.ts` with auto-refresh every 2 seconds using deno_tui
- [ ] T052 [US3] Implement base TUI components in `home-modules/tools/i3pm-cli/src/ui/tui_components.ts`: `MonitorTable`, `WorkspaceTable`, `StatusPanel`
- [ ] T053 [US3] Implement CLI command `i3pm monitors tui` in `home-modules/tools/i3pm-cli/src/commands/monitors_tui.ts` with full interactive TUI
- [ ] T054 [US3] Add TUI keybindings in `monitors_tui.ts`: Tab (switch views), m (move workspace), e (edit config), r (reload config), h (toggle hidden), q (quit)
- [ ] T055 [US3] Implement real-time TUI updates by polling `get_system_state` every 100-250ms in TUI event loop
- [ ] T056 [US3] Add workspace selection and move dialog to TUI (prompt for target role/output when 'm' pressed)

#### JSON Output and Help

- [ ] T057 [P] [US3] Add `--json` flag support to all CLI commands for scripting (output raw JSON-RPC response)
- [ ] T058 [P] [US3] Add `--help` documentation to all CLI commands with usage examples
- [ ] T059 [US3] Implement main CLI router in `home-modules/tools/i3pm-cli/main.ts` to dispatch `monitors` subcommand to appropriate handler

**Checkpoint**: All user stories (US1, US2, US3) should now be independently functional with complete CLI/TUI interface

---

## Phase 6: User Story 4 - Intelligent Workspace State Preservation (Priority: P2)

**Goal**: Remember workspace states when disconnecting monitors and restore them intelligently when reconnecting

**Independent Test**: With 2 monitors, open windows on workspaces 1-8. Disconnect secondary monitor (workspaces collapse to primary). Reconnect secondary monitor. Verify workspaces 3-8 return to secondary monitor automatically.

### Implementation for User Story 4

- [ ] T060 [US4] Add workspace state persistence to daemon: track which workspaces had windows before monitor disconnect (store in memory or state file)
- [ ] T061 [US4] Implement `save_workspace_state()` method in `monitor_config_manager.py` or workspace_manager that records workspace-to-role mapping before monitor change
- [ ] T062 [US4] Implement `restore_workspace_state()` method that restores workspaces to their previous roles when monitor reconnects
- [ ] T063 [US4] Update `on_output_change` handler to call `save_workspace_state()` on disconnect and `restore_workspace_state()` on connect
- [ ] T064 [US4] Add logic to distinguish "monitor reconnect" from "initial connect" (restore only on reconnect, not fresh setup)
- [ ] T065 [US4] Implement `restore` CLI command in `home-modules/tools/i3pm-cli/src/commands/monitors_restore.ts` for manual workspace state restoration
- [ ] T066 [US4] Add "last known good state" tracking for each monitor count configuration (1/2/3 monitors)
- [ ] T067 [US4] Handle edge case: workspace preferences changed since disconnect (prefer current config over saved state)
- [ ] T068 [US4] Add state restoration events to monitor history for debugging

**Checkpoint**: All user stories (US1-US4) complete - full declarative configuration with intelligent state preservation

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T069 [P] Update CLAUDE.md with new CLI commands (`i3pm monitors` subcommands) and configuration file location
- [X] T070 [P] Create NixOS module wrapper in `home-modules/tools/i3pm-cli/default.nix` to compile Deno CLI to executable and install to PATH
- [X] T071 [P] Update existing `home-modules/tools/i3pm-daemon/default.nix` to include new Python modules and dependencies
- [ ] T072 Add error handling for common edge cases: config file missing, daemon not running, invalid output names, workspace on inactive output
- [ ] T073 Add user-friendly error messages for daemon connection failures (suggest systemctl commands)
- [ ] T074 Verify quickstart.md examples work end-to-end (run each command example and validate output)
- [ ] T075 [P] Add logging throughout daemon monitor config manager (config load, validation, reassignment operations)
- [ ] T076 Test configuration reload without daemon restart (verify new config takes effect immediately)
- [ ] T077 Test workspace reassignment with windows open (verify windows move with workspaces)
- [ ] T078 Test multi-monitor rapid connect/disconnect (verify debouncing works correctly)
- [ ] T079 Validate JSON schema generation and schema-based validation in config manager
- [ ] T080 Run full smoke test: create custom config, validate, reload, reassign, move workspace, check diagnostics, verify TUI updates

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - US1 (P1): Can start after Foundational - No dependencies on other stories
  - US2 (P1): Can start after Foundational - No dependencies on other stories (can run parallel to US1)
  - US3 (P1): Depends on US1 (T020-T023 JSON-RPC methods) and US2 (T032-T034 JSON-RPC methods)
  - US4 (P2): Depends on US2 (event handling) - Can be deferred if needed
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1 - Config)**: Foundation only → Can start immediately after Phase 2
- **User Story 2 (P1 - Auto-adapt)**: Foundation only → Can start in parallel with US1
- **User Story 3 (P1 - CLI/TUI)**: Needs US1 (T020-T023) and US2 (T032-T034) for JSON-RPC methods → Start after US1 and US2 complete their daemon methods
- **User Story 4 (P2 - State preservation)**: Needs US2 event handling → Start after US2 complete

### Within Each User Story

- US1: Config models → Config manager → Daemon RPC methods → CLI commands → Delete old bash script
- US2: State query RPC methods → Event subscription → Event handler → CLI display commands
- US3: Daemon diagnostic/move methods → CLI commands → TUI components → Interactive TUI
- US4: State tracking → Save/restore logic → Event integration → CLI restore command

### Parallel Opportunities

- **Phase 1 (Setup)**: All 5 tasks can run in parallel
- **Phase 2 (Foundational)**: T006-T008 (models) parallel, T010 parallel, T013-T014 parallel
- **Phase 3 (US1)**: T024-T028 (CLI commands) can run parallel after daemon methods complete
- **Phase 4 (US2)**: T032-T034 (RPC methods) parallel, T039-T040 (CLI commands) parallel
- **Phase 5 (US3)**: T043-T045 (RPC methods) parallel, T046-T049 (CLI commands) parallel, T057-T058 (flags) parallel
- **Phase 7 (Polish)**: T069-T071 (docs/nix) parallel, most testing can run parallel

---

## Parallel Example: User Story 1 (Config)

```bash
# After daemon methods (T020-T023) complete, launch CLI commands in parallel:
Task T024: "Implement CLI command `i3pm monitors config show`"
Task T025: "Implement CLI command `i3pm monitors config edit`"
Task T026: "Implement CLI command `i3pm monitors config init`"
Task T027: "Implement CLI command `i3pm monitors config validate`"
Task T028: "Implement CLI command `i3pm monitors config reload`"
# All work on different files in src/commands/monitors_config.ts subcommands
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (T001-T005)
2. Complete Phase 2: Foundational (T006-T014) - CRITICAL
3. Complete Phase 3: User Story 1 (T015-T031) - Config-driven distribution
4. Complete Phase 4: User Story 2 (T032-T042) - Auto-adaptation
5. **STOP and VALIDATE**: Test US1+US2 independently (create config, test auto-reassign on monitor change)
6. Deploy/demo if ready

### Full Feature (All User Stories)

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Validate
3. Add User Story 2 → Test independently → Validate (MVP: US1+US2!)
4. Add User Story 3 → Test independently → Validate (Full CLI/TUI)
5. Add User Story 4 → Test independently → Validate (State preservation)
6. Complete Polish phase → Final validation
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (Config system)
   - Developer B: User Story 2 (Auto-adaptation) - can run parallel to US1
   - Developer C: Wait for US1+US2 daemon methods, then start User Story 3 (CLI/TUI)
3. User Story 4 starts after US2 complete (state preservation)
4. Stories complete and integrate independently

---

## Notes

- **Forward-only development**: T030-T031 DELETE old bash script, no compatibility mode
- **No tests requested**: Specification does not explicitly request test tasks, focusing on feature implementation
- **[P] tasks**: Different files or independent modules, no dependencies within phase
- **[Story] labels**: Map task to specific user story for traceability
- **Config file location**: `~/.config/i3/workspace-monitor-mapping.json`
- **Daemon socket**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
- Each user story should be independently testable via quickstart.md scenarios
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Priority: US1 + US2 = MVP, US3 = Full CLI/TUI, US4 = Advanced (P2)

---

## Total Task Count

- **Phase 1 (Setup)**: 5 tasks
- **Phase 2 (Foundational)**: 9 tasks (14 total)
- **Phase 3 (US1 - Config)**: 17 tasks (31 total)
- **Phase 4 (US2 - Auto-adapt)**: 11 tasks (42 total)
- **Phase 5 (US3 - CLI/TUI)**: 17 tasks (59 total)
- **Phase 6 (US4 - State preservation)**: 9 tasks (68 total)
- **Phase 7 (Polish)**: 12 tasks (80 total)

**Total: 80 tasks**

**MVP Scope (US1 + US2)**: 42 tasks
**Full Feature (US1-US3)**: 59 tasks
**Complete (US1-US4 + Polish)**: 80 tasks
