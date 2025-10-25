# Tasks: Unified Application Launcher with Project Context

**Feature**: 034-create-a-feature
**Branch**: `034-create-a-feature`
**Generated**: 2025-10-24
**Input**: Design documents from `/etc/nixos/specs/034-create-a-feature/`

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US6)
- Exact file paths included in descriptions

## Path Conventions
- **Deno CLI**: `home-modules/tools/app-launcher/` (TypeScript source)
- **Nix modules**: `home-modules/desktop/`, `modules/services/`
- **Scripts**: `scripts/app-launcher-wrapper.sh`
- **Tests**: `home-modules/tools/app-launcher/tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 [P] Create Deno project structure in `home-modules/tools/app-launcher/` with src/, tests/ subdirectories
- [x] T002 [P] Create `home-modules/tools/app-launcher/deno.json` with tasks, imports, strict TypeScript config
- [x] T003 [P] Create `home-modules/tools/app-launcher/README.md` with project overview and development setup
- [x] T004 [P] Create placeholder registry definitions in `home-modules/desktop/app-registry.nix` with empty applications array
- [x] T005 [P] Create test configuration directory `home-modules/tools/app-launcher/tests/fixtures/` with sample registry JSON

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Registry Schema & Validation

- [x] T006 [P] Create JSON schema file `specs/034-create-a-feature/contracts/registry-schema.json` with complete application entry validation
- [x] T007 [P] Implement TypeScript types in `home-modules/tools/app-launcher/src/models.ts` for ApplicationRegistryEntry, VariableContext, LaunchCommand
- [x] T008 Implement registry loader in `home-modules/tools/app-launcher/src/registry.ts` with JSON parsing and validation
- [x] T009 [P] Add unit tests for registry loading in `tests/unit/registry_test.ts`

### Variable Substitution Engine

- [x] T010 [P] Implement variable substitution logic in `home-modules/tools/app-launcher/src/variables.ts` with security validation
- [x] T011 [P] Add unit tests for variable substitution in `tests/unit/variables_test.ts` covering all variables and edge cases
- [x] T012 Implement directory validation logic in `src/variables.ts` (absolute path, exists, no special chars)

### Daemon Integration

- [x] T013 [P] Create daemon client in `home-modules/tools/app-launcher/src/daemon-client.ts` with `getCurrentProject()` method
- [x] T014 [P] Add unit tests for daemon client in `tests/unit/daemon_client_test.ts` with mock responses

### Launcher Wrapper Script

- [x] T015 Create bash wrapper script at `scripts/app-launcher-wrapper.sh` with registry loading, daemon query, variable substitution, and execution logic
- [x] T016 Add error handling to wrapper script for missing registry, invalid JSON, daemon failures, command not found
- [x] T017 Add logging to wrapper script writing to `~/.local/state/app-launcher.log`
- [x] T018 Add DRY_RUN and DEBUG mode support to wrapper script

### Home-Manager Integration

- [x] T019 Create home-manager module `home-modules/tools/app-launcher.nix` that builds Deno CLI tool and installs wrapper script
- [x] T020 Add wrapper script installation to home-manager via `home.file.".local/bin/app-launcher-wrapper.sh"` with executable permissions

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Launch Project-Aware Application (Priority: P1) 🎯 MVP

**Goal**: Users can launch applications (VS Code, terminal) that automatically open in the active project directory

**Independent Test**: Activate "nixos" project, open launcher, select "VS Code", verify it opens in `/etc/nixos`

### Implementation for User Story 1

- [x] T021 [P] [US1] Define initial application entries in `home-modules/desktop/app-registry.nix`: vscode, ghostty, firefox (minimal set)
- [x] T022 [P] [US1] Implement wrapper script project context query using `i3pm project current --json` command
- [x] T023 [US1] Implement wrapper script variable substitution for $PROJECT_DIR in parameters field
- [x] T024 [US1] Implement wrapper script argument array building to prevent shell injection
- [x] T025 [US1] Implement wrapper script command execution using `exec` to replace process
- [x] T026 [US1] Add fallback behavior handling in wrapper script (skip/use_home/error) when no project active
- [x] T027 [US1] Test manual wrapper invocation: `app-launcher-wrapper.sh vscode` with nixos project active
- [x] T028 [US1] Test wrapper with no active project to verify fallback behavior works
- [ ] T029 [US1] Test wrapper with project containing spaces in directory path
- [x] T030 [US1] Verify all acceptance scenarios from spec.md work with wrapper script

**Checkpoint**: Manual wrapper script launching works with project context - ready for desktop file integration

---

## Phase 4: User Story 2 - Declarative Registry with Variables (Priority: P1)

**Goal**: Single registry file defines all applications with parameterized launch commands, enabling scaling without custom scripts

**Independent Test**: Add "yazi" file manager to registry with `$PROJECT_DIR`, rebuild, verify it appears in launcher and opens in active project

### Implementation for User Story 2

- [x] T031 [P] [US2] Expand application entries in `home-modules/desktop/app-registry.nix` to include 10-15 core apps (lazygit, yazi, thunar, etc.)
- [x] T032 [P] [US2] Implement all variable types in wrapper script: $PROJECT_NAME, $SESSION_NAME, $WORKSPACE, $HOME, $PROJECT_DISPLAY_NAME, $PROJECT_ICON
- [x] T033 [US2] Add Nix build-time validation for registry schema in `home-modules/desktop/app-registry.nix` (check required fields, unique names, valid workspace range)
- [x] T034 [US2] Add Nix validation to block shell metacharacters in parameters field (`;`, `|`, `&`, `` ` ``, `$()`)
- [x] T035 [US2] Generate JSON registry file via `xdg.configFile."i3/application-registry.json"` from Nix definitions
- [x] T036 [US2] Test adding new application to registry, rebuilding, and verifying it works without code changes
- [x] T037 [US2] Test all variable substitutions with different project contexts
- [ ] T038 [US2] Test parameter safety: verify blocked metacharacters cause build failure
- [x] T039 [US2] Verify all acceptance scenarios from spec.md work

**Checkpoint**: Declarative registry with full variable support is functional - ready for desktop file generation

---

## Phase 5: User Story 3 - Desktop File Generation (Priority: P2)

**Goal**: System automatically generates .desktop files from registry for rofi integration with correct names, icons, and commands

**Independent Test**: Define 3 apps (scoped, global, terminal) in registry, rebuild, verify all 3 appear in rofi with correct metadata

### Implementation for User Story 3

- [x] T040 [P] [US3] Implement desktop file generation in `home-modules/desktop/app-registry.nix` using `xdg.desktopEntries`
- [x] T041 [US3] Configure desktop file Exec line to invoke wrapper script: `app-launcher-wrapper.sh <app-name>`
- [x] T042 [US3] Set desktop file Name field from registry display_name
- [x] T043 [US3] Set desktop file Icon field from registry icon
- [x] T044 [US3] Set desktop file StartupWMClass from registry expected_class
- [x] T045 [US3] Add custom X-Project-Scope and X-Preferred-Workspace fields to desktop files
- [x] T046 [US3] Generate Categories field based on scope (Development;Scoped vs Application;Global)
- [x] T047 [US3] Verify desktop files are created in `~/.local/share/applications/` after rebuild
- [ ] T048 [US3] Test orphaned desktop file removal when application removed from registry
- [x] T049 [US3] Verify desktop files appear in rofi `-show drun` with correct icons
- [x] T050 [US3] Verify all acceptance scenarios from spec.md work

**Checkpoint**: Desktop files auto-generate from registry and appear in rofi - ready for launcher interface

---

## Phase 6: User Story 4 - Unified Launcher Interface (Priority: P2)

**Goal**: Consistent rofi launcher shows all apps, scoped vs global status, and launches with project context

**Independent Test**: Open launcher, see all 20 apps with visual indicators, select scoped app, verify context-aware launch

### Implementation for User Story 4

- [x] T051 [P] [US4] Create i3 launcher configuration in `home-modules/desktop/i3-launcher.nix`
- [x] T052 [US4] Configure rofi drun mode with icons enabled: `-show drun -show-icons`
- [x] T053 [US4] Apply Catppuccin theme to rofi for consistent visual design
- [x] T054 [US4] Add rofi keybinding to i3 config (Win+D or custom)
- [x] T055 [US4] Test rofi launcher displays all registered applications with icons
- [x] T056 [US4] Test fuzzy search in rofi matches display_name and name fields
- [x] T057 [US4] Test launcher closes automatically after application selection
- [x] T058 [US4] Test visual distinction between scoped and global apps via Categories
- [x] T059 [US4] Verify all acceptance scenarios from spec.md work

**Checkpoint**: rofi launcher provides unified application launching interface - ready for CLI integration

---

## Phase 7: User Story 5 - i3pm CLI Integration (Priority: P2)

**Goal**: Manage registry through CLI with `i3pm apps` commands for terminal-focused workflows and automation

**Independent Test**: Run `i3pm apps list`, `i3pm apps launch vscode`, verify identical behavior to GUI launcher

### Implementation for User Story 5

#### CLI Command Infrastructure

- [x] T060 [P] [US5] Add apps command to i3pm CLI in `home-modules/tools/i3pm-deno/main.ts`
- [x] T061 [P] [US5] Create apps command module in `home-modules/tools/i3pm-deno/src/commands/apps.ts`

#### List Command

- [x] T062 [P] [US5] Implement `i3pm apps list` with table and JSON output formats
- [x] T063 [US5] Add filtering options to list command: --scope, --workspace flags
- [x] T064 [P] [US5] Add unit tests for list command in `tests/unit/apps_test.ts`

#### Launch Command

- [x] T065 [P] [US5] Implement `i3pm apps launch` with wrapper script invocation
- [x] T066 [US5] Add --dry-run flag to launch command showing resolved command without execution
- [x] T067 [US5] Add --project override flag to launch command for testing
- [x] T068 [P] [US5] Add unit tests for launch command in `tests/unit/apps_test.ts`

#### Info Command

- [x] T069 [P] [US5] Implement `i3pm apps info` showing application details
- [x] T070 [US5] Add --resolve flag to info command showing current project context and resolved command
- [x] T071 [P] [US5] Add unit tests for info command in `tests/unit/apps_test.ts`

#### Edit & Validate Commands

- [x] T072 [P] [US5] Implement `i3pm apps edit` opening registry in $EDITOR
- [x] T073 [P] [US5] Implement `i3pm apps validate` with schema checks and validation
- [ ] T074 [US5] Add --fix flag to validate command for auto-fixing common issues
- [x] T075 [P] [US5] Add unit tests for validate command in `tests/unit/apps_test.ts`

#### Add & Remove Commands

- [x] T076 [P] [US5] Implement `i3pm apps add` in `src/commands/apps.ts` with interactive prompts and --non-interactive mode
- [x] T077 [P] [US5] Implement `i3pm apps remove` in `src/commands/apps.ts` with confirmation prompt and --force flag

#### Integration & Testing

- [x] T078 [US5] Wire up all subcommands in main.ts CLI router
- [ ] T079 [US5] Add CLI logging to `~/.local/state/i3pm-apps.log`
- [ ] T080 [US5] Test all CLI commands against live registry
- [ ] T081 [US5] Test CLI command JSON output is parseable
- [ ] T082 [US5] Verify all acceptance scenarios from spec.md work

**Checkpoint**: Full CLI interface for application management is functional - ready for window rules integration

---

## Phase 8: User Story 6 - Window Rules Integration (Priority: P3)

**Goal**: Window rules automatically align with registry for correct classification, workspace assignment, and project scoping

**Independent Test**: Add scoped app with preferred_workspace=5 to registry, launch it, verify window appears on WS5 and hides on project switch

### Implementation for User Story 6

#### Window Rules Generation

- [ ] T083 [P] [US6] Create window rules generation logic in `home-modules/desktop/app-registry.nix` mapping registry entries to rules
- [ ] T084 [US6] Generate window-rules-generated.json from registry with pattern, scope, priority, workspace fields
- [ ] T085 [US6] Set priority levels: 240 for scoped apps, 200 for PWAs, 180 for global apps
- [ ] T086 [US6] Handle both expected_class and expected_title_contains patterns in rule generation
- [ ] T087 [US6] Configure generated rules file with `force = true` for automatic updates

#### Manual Rules Preservation

- [ ] T088 [P] [US6] Create manual rules file at `~/.config/i3/window-rules-manual.json` with `force = false` to preserve user customizations
- [ ] T089 [US6] Document manual override priority (250+) above generated rules in quickstart.md

#### Daemon Integration

- [ ] T090 [US6] Update daemon configuration to load both window-rules-generated.json and window-rules-manual.json
- [ ] T091 [US6] Verify daemon merges rules and sorts by priority (highest first)
- [ ] T092 [US6] Verify daemon file watcher detects changes to generated rules after rebuild

#### Testing & Validation

- [ ] T093 [US6] Test window rule generation: add app to registry, rebuild, verify rule appears in window-rules-generated.json
- [ ] T094 [US6] Test workspace assignment: launch app, verify window moves to preferred_workspace
- [ ] T095 [US6] Test scoped app hiding: launch scoped app, switch projects, verify window moves to scratchpad
- [ ] T096 [US6] Test global app visibility: launch global app, switch projects, verify window stays visible
- [ ] T097 [US6] Test manual override: add manual rule with higher priority, verify it overrides generated rule
- [ ] T098 [US6] Verify all acceptance scenarios from spec.md work

**Checkpoint**: Window rules fully integrated with registry - automatic classification and workspace assignment working

---

## Phase 9: Legacy Code Removal & Migration (Constitution XII - Forward-Only Development)

**Purpose**: Complete removal of old launch mechanisms in single commit per spec FR-031 to FR-034

**⚠️ CRITICAL**: This phase implements Constitution XII - no backwards compatibility, immediate complete migration

### Legacy Script Removal

- [ ] T099 [P] [Legacy] Remove all legacy launch scripts from filesystem: `~/.local/bin/launch-code.sh`, `launch-ghostty.sh`, etc.
- [ ] T100 [P] [Legacy] Remove legacy launch script references from `home-modules/desktop/i3.nix` keybindings
- [ ] T101 [P] [Legacy] Search for and remove any orphaned launch scripts in `~/scripts/` directory
- [ ] T102 [Legacy] Update all i3 keybindings in `home-modules/desktop/i3.nix` to use new launcher (rofi or CLI)

### Application Migration

- [ ] T103 [Legacy] Migrate VS Code launch (Win+C) from launch-code.sh to `i3pm apps launch vscode`
- [ ] T104 [Legacy] Migrate Ghostty terminal (Win+Return) from launch-ghostty.sh to `i3pm apps launch ghostty`
- [ ] T105 [Legacy] Migrate Lazygit (Win+G) from custom script to `i3pm apps launch lazygit`
- [ ] T106 [Legacy] Migrate Yazi (Win+Y) from custom script to `i3pm apps launch yazi`
- [ ] T107 [Legacy] Update application launcher keybinding (Win+D) to use rofi drun mode

### Registry Population

- [ ] T108 [Legacy] Define complete application registry in `home-modules/desktop/app-registry.nix` with all migrated applications
- [ ] T109 [Legacy] Add PWA applications to registry (YouTube, Claude, Google AI) with FFPWA IDs
- [ ] T110 [Legacy] Add system tools to registry (k9s, htop, etc.) as global applications

### Verification & Cleanup

- [ ] T111 [Legacy] Verify no launch-*.sh files exist anywhere in repository or home directory
- [ ] T112 [Legacy] Verify no old keybinding patterns remain in i3 config
- [ ] T113 [Legacy] Test all migrated keybindings work with new launcher
- [ ] T114 [Legacy] Document all removed legacy code in commit message for FR-034

**Checkpoint**: Legacy code completely removed, all launches use new unified system - no backwards compatibility

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories, documentation, and final validation

### Documentation

- [ ] T115 [P] [Polish] Update CLAUDE.md with launcher commands, keybindings, and workflows
- [ ] T116 [P] [Polish] Update quickstart.md with final application list and real-world examples
- [ ] T117 [P] [Polish] Create launcher troubleshooting guide in quickstart.md
- [ ] T118 [P] [Polish] Add inline code documentation to all TypeScript modules
- [ ] T119 [P] [Polish] Create example registry configurations for common use cases

### Testing & Validation

- [ ] T120 [P] [Polish] Run through all quickstart.md scenarios and verify they work
- [ ] T121 [P] [Polish] Validate all success criteria from spec.md are met (SC-001 through SC-009)
- [ ] T122 [Polish] Test launcher with 70+ applications to verify performance goals (<500ms launch)
- [ ] T123 [Polish] Test edge cases from spec.md (variable not available, app already running, etc.)
- [ ] T124 [Polish] Test special characters in project paths (spaces, dollar signs, etc.)

### Code Quality

- [ ] T125 [P] [Polish] Run Deno formatter on all TypeScript files: `deno fmt`
- [ ] T126 [P] [Polish] Run Deno linter: `deno lint`
- [ ] T127 [P] [Polish] Optimize wrapper script for performance (minimize jq calls, cache socket path)
- [ ] T128 [Polish] Add comprehensive error messages to all failure paths in wrapper script
- [ ] T129 [Polish] Review and cleanup temporary/debug code

### Security Hardening

- [ ] T130 [P] [Polish] Audit variable substitution for command injection risks
- [ ] T131 [P] [Polish] Review parameter validation to ensure metacharacter blocking works
- [ ] T132 [Polish] Test wrapper script with malicious inputs (command injection attempts)
- [ ] T133 [Polish] Verify all execution uses argument arrays, not string concatenation

### Performance Optimization

- [ ] T134 [Polish] Benchmark launcher overhead: registry load, daemon query, variable substitution
- [ ] T135 [Polish] Optimize registry JSON size (remove unnecessary fields)
- [ ] T136 [Polish] Profile CLI commands for bottlenecks
- [ ] T137 [Polish] Verify all performance goals from plan.md are met

### Final Validation

- [ ] T138 [Polish] Rebuild NixOS system on Hetzner with complete feature
- [ ] T139 [Polish] Test on M1 Mac (Wayland) to verify cross-platform compatibility
- [ ] T140 [Polish] Test on WSL2 (limited GUI) to verify CLI-only workflows work
- [ ] T141 [Polish] Run through all 6 user stories end-to-end
- [ ] T142 [Polish] Verify all functional requirements (FR-001 through FR-034) are implemented

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Stories (Phases 3-8)**: All depend on Foundational completion
  - US1, US2 can proceed in parallel (different focuses)
  - US3 depends on US2 (needs registry definitions)
  - US4 depends on US3 (needs desktop files)
  - US5 can proceed in parallel with US3/US4 (different interface)
  - US6 depends on US2 (needs registry for rule generation)
- **Legacy Removal (Phase 9)**: Depends on US1-US5 complete (new system must work first)
- **Polish (Phase 10)**: Depends on all previous phases

### User Story Dependencies

```
Foundational (Phase 2)
  ├─→ US1 (Phase 3): Project-aware launching - MVP foundation
  ├─→ US2 (Phase 4): Declarative registry - extends US1
  ├─→ US3 (Phase 5): Desktop files - depends on US2
  ├─→ US4 (Phase 6): Launcher UI - depends on US3
  ├─→ US5 (Phase 7): CLI - can parallel with US3/US4
  └─→ US6 (Phase 8): Window rules - depends on US2
```

### Within Each User Story

- US1: Project context → Variable substitution → Fallback → Execution
- US2: Registry expansion → All variables → Validation → JSON generation
- US3: Desktop file generation → Icon/Name/Exec → rofi integration
- US4: rofi config → Keybinding → Testing
- US5: List → Launch → Info → Edit → Validate → Add/Remove
- US6: Rule generation → Manual preservation → Daemon integration

### Parallel Opportunities

**Phase 1 (Setup)**: All tasks (T001-T005) can run in parallel

**Phase 2 (Foundational)**:
- T006, T007 (schema & types) in parallel
- T010, T011 (variables) in parallel with T013, T014 (daemon)
- T009 (tests) after T008 (registry loader)

**Phase 3 (US1)**:
- T021, T022 in parallel (registry defs, wrapper context query)

**Phase 4 (US2)**:
- T031, T032 in parallel (registry expansion, variable types)

**Phase 5 (US3)**:
- T040-T046 all desktop file config changes can be done together

**Phase 7 (US5)**:
- T062, T065, T069, T072, T073, T076, T077 (all command files) in parallel
- T064, T068, T071, T075 (all test files) in parallel

**Phase 9 (Legacy Removal)**:
- T099, T100, T101 (script removals) in parallel
- T103-T107 (migrations) can be done together

**Phase 10 (Polish)**:
- T115-T119 (docs) in parallel
- T120-T124 (testing) in parallel
- T125-T129 (code quality) in parallel
- T130-T133 (security) in parallel

---

## Parallel Example: User Story 5 (CLI)

```bash
# Launch all command implementations together:
Task: "Implement i3pm apps list in src/commands/list.ts"
Task: "Implement i3pm apps launch in src/commands/launch.ts"
Task: "Implement i3pm apps info in src/commands/info.ts"
Task: "Implement i3pm apps edit in src/commands/edit.ts"
Task: "Implement i3pm apps validate in src/commands/validate.ts"
Task: "Implement i3pm apps add in src/commands/add.ts"
Task: "Implement i3pm apps remove in src/commands/remove.ts"

# Then launch all test files together:
Task: "Add unit tests for list command in tests/unit/list_test.ts"
Task: "Add unit tests for launch command in tests/unit/launch_test.ts"
Task: "Add unit tests for info command in tests/unit/info_test.ts"
Task: "Add unit tests for validate command in tests/unit/validate_test.ts"
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only)

1. ✅ Complete Phase 1: Setup
2. ✅ Complete Phase 2: Foundational (registry, variables, daemon, wrapper)
3. ✅ Complete Phase 3: US1 (project-aware launching works)
4. ✅ Complete Phase 4: US2 (declarative registry works)
5. **STOP and VALIDATE**: Test manual launcher works with 10-15 apps
6. Optional: Skip to Phase 9 to remove legacy code early
7. **Result**: Core functionality working - can launch apps with project context

### Incremental Delivery

1. Foundation (Phases 1-2) → Core infrastructure ready
2. US1 + US2 (Phases 3-4) → Manual launching works → **First milestone**
3. US3 + US4 (Phases 5-6) → rofi integration → **Second milestone** (GUI users happy)
4. US5 (Phase 7) → CLI integration → **Third milestone** (terminal users happy)
5. US6 (Phase 8) → Window rules → **Fourth milestone** (full automation)
6. Legacy removal (Phase 9) → Clean system → **Fifth milestone**
7. Polish (Phase 10) → Production ready → **Final delivery**

### Parallel Team Strategy

With 2-3 developers:

1. **Together**: Complete Setup + Foundational (Phases 1-2)
2. **Split after Foundational**:
   - Developer A: US1 + US2 (Phases 3-4) - Core launcher
   - Developer B: US3 + US4 (Phases 5-6) - rofi integration
   - Developer C: US5 (Phase 7) - CLI tools
3. **Converge**: US6 (Phase 8) + Legacy removal (Phase 9) together
4. **Together**: Polish (Phase 10)

---

## Success Metrics

Track progress against spec.md success criteria:

- [ ] **SC-001**: New app in registry → launcher in <2 minutes
- [ ] **SC-002**: Launch to window appearance in <3 seconds
- [ ] **SC-003**: All apps appear with correct display names/icons/scope
- [ ] **SC-004**: All variable substitutions resolve correctly
- [ ] **SC-005**: Zero custom launch scripts remain (4+ → 0)
- [ ] **SC-006**: Window rules align with registry automatically
- [ ] **SC-007**: CLI commands execute in <500ms
- [ ] **SC-008**: No config drift (registry = behavior)
- [ ] **SC-009**: All legacy code removed (verified by absence of launch-*.sh)

---

## Notes

- **[P]** tasks run in parallel (different files, no conflicts)
- **[Story]** labels map tasks to user stories for traceability
- Each user story is independently testable
- Stop at any checkpoint to validate story works
- **No tests included** - spec.md did not request TDD approach
- All paths are absolute from repository root
- Wrapper script is core - invest in making it robust and well-tested
- Legacy removal (Phase 9) is NON-NEGOTIABLE per Constitution XII

---

**Generated Task Count**: 142 tasks
**User Story Count**: 6 stories
**Estimated MVP Scope**: Phases 1-4 (Tasks T001-T039, ~39 tasks)
**Parallel Opportunities**: 40+ tasks marked [P]
**Critical Path**: Setup → Foundational → US1 → US2 → US3 → US4 → Legacy Removal

**Next Step**: Begin Phase 1 (Setup) tasks T001-T005
