---
description: "Task list for Dynamic Sway Configuration Management Architecture"
---

# Tasks: Dynamic Sway Configuration Management Architecture

**Feature**: 047-create-a-new
**Input**: Design documents from `/specs/047-create-a-new/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in specification - tasks focus on implementation

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- Python daemon: `home-modules/desktop/i3-project-event-daemon/`
- Deno CLI: `home-modules/tools/i3pm/src/commands/`
- Runtime config: `~/.config/sway/`
- Nix config: `home-modules/desktop/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure for configuration management subsystem

- [X] T001 Create configuration subsystem directory structure in `home-modules/desktop/sway-config-manager/config/` with `__init__.py`, `loader.py`, `validator.py`, `merger.py`, `rollback.py`
- [X] T002 Create rules engine directory structure in `home-modules/desktop/sway-config-manager/rules/` with `__init__.py`, `keybinding_manager.py`, `window_rule_engine.py`, `workspace_assignments.py`
- [X] T003 [P] Add configuration management dependencies to daemon requirements (jsonschema, tomllib, watchdog)
- [X] T004 [P] Create runtime config directory structure in home-manager Nix module to generate `~/.config/sway/` with subdirectories (projects/, schemas/)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Define Pydantic data models for configuration entities in `home-modules/desktop/sway-config-manager/models.py` (KeybindingConfig, WindowRule, WorkspaceAssignment, ProjectWindowRuleOverride, ConfigurationVersion, ConfigurationSourceAttribution)
- [X] T006 Generate JSON schemas from Pydantic models for validation in `config/schema_generator.py`
- [X] T007 Implement base configuration loader in `config/loader.py` with methods: load_keybindings_toml(), load_window_rules_json(), load_workspace_assignments_json(), load_project_overrides()
- [X] T008 Implement configuration validator in `config/validator.py` with structural validation (JSON Schema) and semantic validation (Sway IPC queries for workspaces/outputs)
- [X] T009 Implement configuration merger in `config/merger.py` to merge Nix base config + runtime overrides + project overrides with precedence rules (Nix=1, runtime=2, project=3)
- [X] T010 Extend daemon IPC server in `ipc_server.py` to add JSON-RPC endpoints: config_reload, config_validate, config_rollback, config_get_versions, config_show, config_get_conflicts, config_watch_start, config_watch_stop
- [X] T011 Implement git-based rollback manager in `config/rollback.py` with methods: list_versions(), rollback_to_commit(), commit_config_changes(), get_active_version()
- [X] T012 Add configuration state tracking to daemon state in `state.py` (active_config_version, config_load_timestamp, validation_errors)

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Hot-Reloadable Configuration Changes (Priority: P1) 🎯 MVP

**Goal**: Enable users to modify keybindings, window rules, and workspace assignments and reload them within 2-5 seconds without NixOS rebuild or Sway restart

**Independent Test**: Modify keybinding in `~/.config/sway/keybindings.toml`, run `swayconfig reload`, verify new keybinding active immediately without rebuild

### Implementation for User Story 1

- [X] T013 [P] [US1] Implement keybinding manager in `rules/keybinding_manager.py` to parse Sway keybinding format and apply via Sway IPC `bindsym` commands
- [X] T014 [P] [US1] Implement window rule engine in `rules/window_rule_engine.py` to match window criteria (app_id, window_class, title) and apply actions (floating, resize, workspace assignment) via Sway IPC
- [X] T015 [P] [US1] Implement workspace assignment handler in `rules/workspace_assignments.py` to reassign workspaces to outputs via Sway IPC `move workspace to output` commands
- [X] T016 [US1] Implement configuration reload orchestrator in `config/reload_manager.py` with two-phase commit (validate → apply) and automatic rollback on failure
- [X] T017 [US1] Integrate configuration reload into daemon main loop in `daemon.py` to handle config_reload IPC requests and emit config_reloaded/config_validation_failed events
- [X] T018 [US1] Implement file watcher using watchdog library in `config/file_watcher.py` to detect changes in `~/.config/sway/*.toml` and `*.json` files with 500ms debounce
- [X] T019 [US1] Create CLI client in `cli.py` to call daemon IPC endpoints with commands (reload, validate, rollback, versions, show, conflicts, ping)
- [X] T020 [US1] Generate default configuration files via home-manager in `sway-config-manager.nix` to populate `~/.config/sway/keybindings.toml`, `window-rules.json`, `workspace-assignments.json` on first run
- [X] T021 [US1] Add configuration reload validation to ensure no user input disruption (check for active keyboard/mouse grabs before applying changes)
- [X] T022 [US1] Implement atomic configuration application to prevent partial state (use transaction context manager, rollback all changes if any step fails)
- [X] T023 [US1] Add configuration reload logging in `daemon.py` to record timestamp, changed settings, reload duration, success/failure status

**Checkpoint**: User Story 1 complete - keybindings, window rules, and workspace assignments can be hot-reloaded within 2-5 seconds

---

## Phase 4: User Story 2 - Clear Configuration Responsibility Boundaries (Priority: P1)

**Goal**: Establish and document clear separation between Nix-managed static settings and Python-managed dynamic runtime behavior

**Independent Test**: Review configuration documentation and verify each setting category has unambiguous ownership (Nix vs Python) with no overlap

### Implementation for User Story 2

- [X] T024 [US2] Document configuration precedence architecture in `/etc/nixos/docs/SWAY_CONFIG_ARCHITECTURE.md` with decision tree for "where should this setting go" (keybindings → TOML, system packages → Nix, window rules → JSON, project logic → Python daemon)
- [X] T025 [US2] Implement configuration source attribution tracker in `config/source_tracker.py` to record which settings came from Nix vs runtime vs project overrides (setting_path, source_system, precedence_level, last_modified, file_path)
- [X] T026 [US2] Add conflict detection to configuration merger in `config/merger.py` to identify duplicate settings across precedence levels and log warnings with resolution (higher precedence wins)
- [X] T027 [US2] Create Deno CLI command in `home-modules/tools/i3pm/src/commands/config_show.ts` to display active configuration with source attribution (--category=keybindings|window-rules|workspaces|all, --sources, --project <name>, --json)
- [X] T028 [US2] Create Deno CLI command in `home-modules/tools/i3pm/src/commands/config_conflicts.ts` to show configuration conflicts across precedence levels with resolution explanations
- [X] T029 [US2] Update quickstart.md documentation with configuration precedence examples and troubleshooting section for common conflicts
- [X] T030 [US2] Add Nix module option documentation in `home-modules/desktop/sway.nix` using `lib.mkOption` descriptions to clarify which settings are Nix-managed vs runtime-managed
- [X] T031 [US2] Implement diagnostic command integration in daemon to respond to config_show IPC requests with full configuration state and source attribution

**Checkpoint**: Configuration boundaries documented and enforced - users can easily determine where to make changes

---

## Phase 5: User Story 3 - Project-Aware Dynamic Window Rules (Priority: P1)

**Goal**: Enable project-specific window rules that override global rules based on active project context

**Independent Test**: Define project-specific window rule (e.g., float calculator for "nixos" project), switch to project, launch application, verify rule applies correctly

### Implementation for User Story 3

- [X] T032 [US3] Extend project JSON schema in `config/models.py` to include window_rule_overrides array (base_rule_id, override_properties, enabled) and keybinding_overrides dictionary
- [X] T033 [US3] Implement project-aware window rule resolution in `rules/window_rule_engine.py` to check active project, load project overrides, and apply with precedence (project > global)
- [X] T034 [US3] Integrate project context into window::new event handler in `daemon.py` to query active project and apply project-specific rules dynamically
- [ ] T035 [US3] Update project configuration files in `~/.config/sway/projects/<name>.json` to include window_rule_overrides and keybinding_overrides sections
- [ ] T036 [US3] Implement project override validation in `config/validator.py` to check that base_rule_id references exist and override_properties are valid WindowRule fields
- [ ] T037 [US3] Add project-scoped keybinding override support in `rules/keybinding_manager.py` to replace/augment global keybindings when project is active
- [ ] T038 [US3] Update configuration reload logic in `config/reload_manager.py` to reload project overrides when active project changes
- [ ] T039 [US3] Add diagnostic output to config_show command to display project-specific overrides when --project flag is used

**Checkpoint**: Project-specific window rules working - different window behavior based on active project context

---

## Phase 6: User Story 4 - Version-Controlled Configuration with Rollback (Priority: P2)

**Goal**: Enable version-controlled configuration with instant rollback to previous versions (within 3 seconds)

**Independent Test**: Make configuration changes, commit to git, make breaking changes, execute rollback command, verify previous state restored within 3 seconds

### Implementation for User Story 4

- [ ] T040 [US4] Implement git integration in `config/rollback.py` with methods: get_git_history(), parse_commit_metadata(), checkout_commit(), get_changed_files()
- [ ] T041 [US4] Create automatic git commit on successful reload in `config/reload_manager.py` with auto-generated commit messages (timestamp, files changed, reload success)
- [ ] T042 [US4] Implement configuration version tracking in `config/version_manager.py` to maintain `.config-version` file with active commit hash, timestamp, message
- [ ] T043 [US4] Create Deno CLI command in `home-modules/tools/i3pm/src/commands/config_rollback.ts` to call daemon IPC config_rollback endpoint with commit hash and --no-reload flag
- [ ] T044 [US4] Create Deno CLI command in `home-modules/tools/i3pm/src/commands/config_list_versions.ts` to call daemon IPC config_get_versions endpoint with --limit and --since flags
- [ ] T045 [US4] Implement automatic rollback on apply failure in `config/reload_manager.py` to revert to previous commit if Sway reload fails
- [ ] T046 [US4] Add rollback logging to track which settings changed during rollback operation (before/after values, rollback duration, success status)
- [ ] T047 [US4] Update quickstart.md with rollback workflow examples and version history navigation

**Checkpoint**: Version control and rollback working - users can safely experiment with configuration changes

---

## Phase 7: User Story 5 - Integrated Configuration Validation (Priority: P2)

**Goal**: Provide automatic validation before configuration reload to catch syntax and semantic errors early

**Independent Test**: Create invalid configuration (malformed syntax, non-existent workspace), run validation, verify errors detected with helpful messages before reload

### Implementation for User Story 5

- [ ] T048 [US5] Implement JSON Schema structural validation in `config/validator.py` with detailed error messages (file_path, line_number, error_type, message, suggestion)
- [ ] T049 [US5] Implement semantic validation in `config/validator.py` to query Sway IPC for workspace numbers, output names, and validate references
- [ ] T050 [US5] Add keybinding syntax validation in `config/validator.py` to check key combo patterns match Sway syntax (e.g., `Mod+Return` not `Mod++Return`)
- [ ] T051 [US5] Implement regex validation for window rule criteria in `config/validator.py` to detect invalid patterns and provide fix suggestions
- [ ] T052 [US5] Create Deno CLI command in `home-modules/tools/i3pm/src/commands/config_validate.ts` to call daemon IPC config_validate endpoint with --files and --strict flags
- [ ] T053 [US5] Add auto-validation option to file watcher in `config/file_watcher.py` to run validation on file save and display results
- [ ] T054 [US5] Implement validation result formatting in CLI with color-coded output (✅ success, ❌ errors, ⚠️ warnings) and summary statistics
- [ ] T055 [US5] Create validation error test suite with common error scenarios (syntax errors, missing references, conflicts) to verify 100% syntax error detection target (SC-006)

**Checkpoint**: Configuration validation complete - users catch errors before applying changes

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and system-wide enhancements

- [ ] T056 [P] Create configuration editor integration in `home-modules/tools/i3pm/src/commands/config_edit.ts` to open config files in $EDITOR with automatic validation after close
- [ ] T057 [P] Add performance metrics tracking to configuration reload operations (load time, validation time, apply time) with logging
- [ ] T058 [P] Implement configuration backup on reload in `config/rollback.py` to create timestamped backup before applying changes
- [ ] T059 [P] Create systemd timer for periodic configuration validation (daily) in home-manager Nix module to detect config drift
- [ ] T060 Add comprehensive error handling to all IPC endpoints with structured error codes and recovery suggestions
- [ ] T061 Update daemon systemd service configuration in `home-modules/desktop/sway.nix` to add configuration file paths to watchdog monitoring
- [ ] T062 [P] Add configuration reload notifications via desktop notification system (notify-send) on success/failure
- [ ] T063 [P] Update quickstart.md with complete workflow examples, troubleshooting guide, and performance tips
- [ ] T064 [P] Create pre-commit hook example for configuration validation in docs/
- [ ] T065 Implement configuration migration tool to convert existing Nix-only config to dynamic config format
- [ ] T066 Run quickstart.md validation workflows to verify all documented commands work correctly
- [ ] T067 Performance optimization: Profile configuration reload operations and optimize to meet <2 second target (SC-001)
- [ ] T068 Add telemetry for configuration reload success rate to track 95% success target (SC-003)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 (Phase 3): Hot-reloadable config - MUST complete first (MVP foundation)
  - US2 (Phase 4): Configuration boundaries - can start after US1, no blocking dependencies
  - US3 (Phase 5): Project-aware rules - depends on US1 (needs reload mechanism)
  - US4 (Phase 6): Version control - depends on US1 (needs reload to trigger commits)
  - US5 (Phase 7): Validation - can start in parallel with US1, integrated into reload
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - MVP foundation, must complete first
- **User Story 2 (P1)**: Can start after US1 - needs reload mechanism to demonstrate boundaries
- **User Story 3 (P1)**: Depends on US1 (reload mechanism) - extends with project-specific rules
- **User Story 4 (P2)**: Depends on US1 (reload triggers commits) - adds version control layer
- **User Story 5 (P2)**: Can develop in parallel with US1, integrated into reload workflow

### Within Each User Story

- **US1**: Loader/validator/merger → reload orchestrator → rule engines → CLI commands → file watcher
- **US2**: Source tracker → conflict detection → CLI commands → documentation
- **US3**: Extend models → window rule engine → project override validation → integration
- **US4**: Git integration → version manager → CLI commands → automatic rollback
- **US5**: Validation implementation → CLI commands → auto-validation integration

### Parallel Opportunities

- Within Setup (Phase 1): T003, T004 can run in parallel
- Within Foundational (Phase 2): T006 can run in parallel after T005 completes
- Within US1: T013, T014, T015 (rule engines) can run in parallel; T019, T020 can run in parallel after T017
- Within US2: T024, T025 can run in parallel; T027, T028, T029 can run in parallel
- Within US5: T048, T049, T050, T051 (validation logic) can run in parallel
- Within Polish (Phase 8): T056, T057, T058, T059, T062, T063, T064 can all run in parallel

---

## Parallel Example: User Story 1 (Hot-Reload)

```bash
# After Foundational phase completes, launch rule engines in parallel:
Task T013: "Implement keybinding manager in rules/keybinding_manager.py"
Task T014: "Implement window rule engine in rules/window_rule_engine.py"
Task T015: "Implement workspace assignment handler in rules/workspace_assignments.py"

# After T017 completes, launch CLI and config generation in parallel:
Task T019: "Create CLI command config_reload.ts"
Task T020: "Generate default config files via home-manager"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T012) - CRITICAL blocking phase
3. Complete Phase 3: User Story 1 (T013-T023) - Hot-reload capability
4. **STOP and VALIDATE**: Test hot-reload workflow end-to-end
5. Deploy/demo if ready

**Rationale**: User Story 1 delivers core value (eliminates rebuild friction). Once working, users can iterate on configuration changes in seconds instead of minutes. Other stories enhance this foundation.

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (T001-T012)
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!) (T013-T023)
3. Add User Story 2 → Test independently → Deploy/Demo (T024-T031)
4. Add User Story 3 → Test independently → Deploy/Demo (T032-T039)
5. Add User Story 4 → Test independently → Deploy/Demo (T040-T047)
6. Add User Story 5 → Test independently → Deploy/Demo (T048-T055)
7. Polish → Complete feature (T056-T068)

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T012)
2. Once Foundational is done:
   - Developer A: User Story 1 (hot-reload) - T013-T023
   - Developer B: User Story 5 (validation) - T048-T055 (can start early, integrates with US1)
3. After US1 complete:
   - Developer A: User Story 3 (project-aware) - T032-T039
   - Developer B: User Story 2 (boundaries) - T024-T031
   - Developer C: User Story 4 (version control) - T040-T047
4. All developers: Polish phase (T056-T068)

---

## Success Criteria Tracking

| Success Criteria | Related Tasks | Target |
|------------------|---------------|--------|
| SC-001: Reload keybindings <5s | T016, T017, T019, T067 | <2s reload component |
| SC-002: Reload window rules <3s | T014, T016, T017 | <3s total |
| SC-003: 95% reload success rate | T016, T022, T068 | 95% success |
| SC-006: 100% syntax error detection | T048, T050, T051, T055 | 100% syntax |
| SC-007: Rollback <3s | T040, T043, T045 | <3s total |
| SC-009: No input disruption | T021 | 100% cases |
| SC-010: Reduce test time 120s→10s | T016, T017, T018 | <10s total |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Configuration reload (US1) is MVP - all other stories build on this foundation
- Validation (US5) can develop in parallel with US1 for early error detection
- Version control (US4) provides safety net for experimentation
