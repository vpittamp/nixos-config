# Tasks: i3 Project Workspace Management System

**Feature Branch**: `010-i3-project-workspace`
**Input**: Design documents from `/etc/nixos/specs/010-i3-project-workspace/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓

**Tests**: NOT included (not requested in feature specification)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- NixOS module structure:
  - System module: `modules/desktop/i3-project-workspace.nix`
  - Home-manager module: `home-modules/desktop/i3-projects.nix`
  - Documentation: `docs/I3_PROJECT_WORKSPACE.md`
  - Scripts embedded in modules via `pkgs.writeShellScriptBin`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic NixOS module structure

- [X] T001 [P] Create system module structure at `modules/desktop/i3-project-workspace.nix` with basic options and module scaffold
- [X] T002 [P] Create home-manager module structure at `home-modules/desktop/i3-projects.nix` with basic options for project definitions
- [X] T003 [P] Create shared library script template at `modules/desktop/i3-project-workspace.nix` (embedded as `i3-project-lib.sh` via pkgs.writeShellScript)

**Checkpoint**: Module structure ready for implementation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Define Nix types for Project entity in `home-modules/desktop/i3-projects.nix` (displayName, workspaces, primaryWorkspace, workingDirectory, enabled, autostart)
- [ ] T005 Define Nix types for WorkspaceConfig entity in `home-modules/desktop/i3-projects.nix` (number, output, outputs, applications, layout, layoutMode)
- [ ] T006 Define Nix types for ApplicationConfig entity in `home-modules/desktop/i3-projects.nix` (package, command, wmClass, wmInstance, workingDirectory, args, instanceBehavior, launchDelay, floating, position, size)
- [ ] T007 Implement project configuration validation in `home-modules/desktop/i3-projects.nix` (assertions for unique names, valid workspace references, existing packages)
- [ ] T008 Implement JSON configuration generation in `home-modules/desktop/i3-projects.nix` to create `~/.config/i3-projects/projects.json` from Nix definitions
- [ ] T009 Create shared library functions in embedded `i3-project-lib.sh`: i3_workspace_switch, i3_get_workspaces, i3_get_outputs, check_package_installed
- [ ] T010 [P] Add required packages to system module in `modules/desktop/i3-project-workspace.nix`: i3, i3-save-tree, xdotool, xprop, jq, wmctrl
- [ ] T011 [P] Implement conditional module activation based on i3wm presence in both system and home-manager modules

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Quick Project Environment Switch (Priority: P1) 🎯 MVP

**Goal**: Enable instant switching between complete project environments with all applications launching in correct positions

**Independent Test**: Define a project with 2-3 applications, activate it, verify all applications launch in correct workspace positions, switch away, switch back to verify state persistence

### Implementation for User Story 1

- [ ] T012 [US1] Implement core project activation logic in `i3-project` CLI (embedded in `modules/desktop/i3-project-workspace.nix` via pkgs.writeShellScriptBin): load config, validate project exists
- [ ] T013 [US1] Implement workspace switching logic in `i3-project` CLI: iterate workspaces, switch to each using i3-msg
- [ ] T014 [US1] Implement application launching logic in `i3-project` CLI: launch applications with configured delays, handle working directory context
- [ ] T015 [US1] Implement primary workspace focus in `i3-project` CLI: focus project's primary workspace after all applications launch
- [ ] T016 [US1] Implement project state tracking in `i3-project` CLI: write project state to `/tmp/i3-projects/<name>.state` with PIDs, timestamps, workspace list
- [ ] T017 [US1] Implement `i3-project list` command in `i3-project` CLI: read projects from JSON config, show status (active/inactive), display workspace and application counts
- [ ] T018 [US1] Implement `i3-project status` command in `i3-project` CLI: read state files, show running applications, workspace assignments, resource usage
- [ ] T019 [US1] Implement `i3-project switch` command in `i3-project` CLI: check if project active, focus primary workspace, error if not active
- [ ] T020 [US1] Implement project close logic in `i3-project close` command: read state file, send SIGTERM to PIDs, wait for graceful termination, optional SIGKILL with --force
- [ ] T021 [US1] Add error handling and user feedback to all commands: project not found, i3 communication errors, application launch failures
- [ ] T022 [US1] Implement --dry-run flag for `activate` command: show what would be done without executing
- [ ] T023 [US1] Implement --verbose flag for detailed activation progress across all commands

**Checkpoint**: At this point, User Story 1 should be fully functional - users can define projects in Nix, activate them, list them, close them, and switch between them

---

## Phase 4: User Story 2 - Declarative Project Configuration via NixOS (Priority: P1)

**Goal**: Enable users to define all project environments in NixOS configuration files with version control and cross-machine reproducibility

**Independent Test**: Add a project definition to home-manager config, rebuild system, verify project is available and functional without manual setup

### Implementation for User Story 2

- [ ] T024 [US2] Implement project definition example in `home-modules/desktop/i3-projects.nix` module comments: complete working example with all options documented
- [ ] T025 [US2] Implement configuration reload mechanism in `i3-project reload` command: re-read JSON, validate, update internal state
- [ ] T026 [US2] Add parameterized working directory support in `i3-project activate`: --dir flag to override workingDirectory for all applications
- [ ] T027 [US2] Implement application command construction with working directory in shared library: build command with --working-directory flags for terminals
- [ ] T028 [US2] Add support for application args in configuration: concatenate args list to command, quote properly for shell execution
- [ ] T029 [US2] Implement project templates helper function in `home-modules/desktop/i3-projects.nix` module comments: example of makeProjectTemplate pattern for reusable configurations
- [ ] T030 [US2] Add validation for working directory existence in home-manager module: check paths exist or can be created, generate warnings
- [ ] T031 [US2] Implement configuration update detection: warn users when config changed but not rebuilt

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - users can fully manage projects via declarative Nix configuration

---

## Phase 5: User Story 3 - Multi-Monitor Workspace Management (Priority: P2)

**Goal**: Enable project environments spanning multiple displays with graceful single-monitor fallback

**Independent Test**: Define project with applications across 3 workspaces on 3 monitors, verify correct monitor placement, test same config on single-monitor to ensure graceful degradation

### Implementation for User Story 3

- [ ] T032 [P] [US3] Implement monitor detection in shared library `i3-project-lib.sh`: query xrandr for connected outputs, parse output names
- [ ] T033 [P] [US3] Implement workspace output assignment in `i3-project activate`: generate i3 config for workspace-to-output mapping using outputs fallback list
- [ ] T034 [US3] Add monitor configuration validation in home-manager module: check output names are valid, warn if outputs not currently connected
- [ ] T035 [US3] Implement single-monitor fallback logic in `i3-project activate`: detect available monitors, consolidate workspaces if outputs missing
- [ ] T036 [US3] Add workspace redistribution on monitor change (optional enhancement): detect when monitors reconnect, offer to redistribute workspaces
- [ ] T037 [US3] Update `i3-project status` to show monitor assignments: display which monitor each workspace is on, indicate if fallback active

**Checkpoint**: All multi-monitor features working - projects adapt to monitor configuration changes gracefully

---

## Phase 6: User Story 4 - Ad-Hoc Project Creation from Running State (Priority: P2)

**Goal**: Capture current workspace layouts and save them as declarative project configurations

**Independent Test**: Manually arrange 3-4 applications, execute capture command, clear workspace, re-activate captured project to verify layout matches

### Implementation for User Story 4

- [ ] T038 [US4] Implement `i3-project-capture` CLI tool skeleton in `modules/desktop/i3-project-workspace.nix` via pkgs.writeShellScriptBin: argument parsing, options handling
- [ ] T039 [US4] Implement workspace scanning in `i3-project-capture`: query i3 for all workspaces, filter non-empty (or include empty with --include-empty)
- [ ] T040 [US4] Implement layout capture per workspace: call i3-save-tree for each workspace, save to `~/.config/i3-projects/captured/layouts/<name>-ws-<N>.json`
- [ ] T041 [US4] Implement layout post-processing: uncomment swallows criteria using sed, remove unnecessary comments
- [ ] T042 [US4] Implement window information extraction: query i3 tree, extract WM_CLASS, instance, geometry, floating status, PID
- [ ] T043 [US4] Implement working directory detection for terminals: read /proc/<pid>/cwd for terminal PIDs, add to configuration
- [ ] T044 [US4] Implement command detection: read /proc/<pid>/cmdline, extract executable and args, map to nixpkgs package names
- [ ] T045 [US4] Implement instance behavior detection: use heuristics to classify apps as multi/single/shared based on known patterns
- [ ] T046 [US4] Implement Nix configuration generation: build complete project definition from captured data, include TODO comments for manual review
- [ ] T047 [US4] Implement JSON snapshot generation: create machine-readable snapshot with all captured metadata
- [ ] T048 [US4] Add --workspace flag support: capture only specific workspace instead of all workspaces
- [ ] T049 [US4] Add --no-layouts flag support: skip layout file generation, only capture application definitions
- [ ] T050 [US4] Implement capture summary output: show what was captured, file paths, next steps for user integration
- [ ] T051 [US4] Add warnings for problematic windows: no WM_CLASS, command detection failed, empty workspaces included

**Checkpoint**: Layout capture fully functional - users can capture workspace arrangements and convert them to declarative configurations

---

## Phase 7: User Story 5 - Shorthand Project Activation (Priority: P3)

**Goal**: Enable power users to quickly compose workspace configurations via compact command-line syntax

**Independent Test**: Execute shorthand command like "i3-project compose vsc:1 ff:2 term:3", verify applications launch on specified workspaces

### Implementation for User Story 5

- [ ] T052 [P] [US5] Define ApplicationAlias type in `home-modules/desktop/i3-projects.nix`: alias name, package, command, wmClass, defaultArgs, instanceBehavior
- [ ] T053 [P] [US5] Implement alias configuration in home-manager module: programs.i3Projects.aliases attribute set
- [ ] T054 [US5] Implement shorthand syntax parser in new `i3-project compose` command: parse "alias:workspace" syntax, validate aliases exist
- [ ] T055 [US5] Implement ad-hoc project creation from shorthand: build temporary project structure from parsed aliases
- [ ] T056 [US5] Implement temporary project activation: launch without writing permanent config, use /tmp state
- [ ] T057 [US5] Add alias expansion in project definitions: allow referencing aliases in full project configs
- [ ] T058 [US5] Implement common alias defaults in module: provide built-in aliases for common apps (ff, vsc, term, etc.)
- [ ] T059 [US5] Add project overlay support in `i3-project activate`: --add flag to launch additional apps beyond project definition

**Checkpoint**: Shorthand syntax working - power users can compose temporary workspaces without editing config files

---

## Phase 8: User Story 6 - Git Repository Integration (Priority: P3)

**Goal**: Automatically associate project environments with repository directories for context-aware application launching

**Independent Test**: Define project linked to git repo path, activate project, verify terminals open in repo root and editors open repo workspace

### Implementation for User Story 6

- [ ] T060 [P] [US6] Add repository path detection in project activation: check if workingDirectory is a git repository
- [ ] T061 [P] [US6] Implement git repository context propagation: ensure all terminals launch with repo root as CWD
- [ ] T062 [US6] Add editor workspace opening: pass repository path as argument to code/editor commands
- [ ] T063 [US6] Implement project templates with repository parameterization: example patterns for makeRepoProject helpers
- [ ] T064 [US6] Add automatic working directory override: if activated from within git repo, use current repo as context
- [ ] T065 [US6] Implement monorepo subdirectory support: allow projects to specify subdirectory within larger repository
- [ ] T066 [US6] Add project context switching: update application working directories when switching between related projects

**Checkpoint**: Git integration complete - projects seamlessly integrate with repository contexts

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, optimization, and enhancements that affect multiple user stories

- [ ] T067 [P] Create comprehensive documentation at `docs/I3_PROJECT_WORKSPACE.md`: user guide, examples, troubleshooting, integration patterns
- [ ] T068 [P] Update `CLAUDE.md` with project workspace commands: add to Common Tasks section with quick reference
- [ ] T069 [P] Add rofi integration script `i3-project-menu`: interactive project launcher using rofi, embed in system module
- [ ] T070 [P] Implement i3wsr integration: update i3wsr config to show project names in workspace labels
- [ ] T071 [P] Add shell completions for bash: generate completion scripts for i3-project commands
- [ ] T072 Create example project configurations in module comments: showcase common patterns (web dev, API dev, ML research)
- [ ] T073 Implement logging and debugging support: add DEBUG mode with verbose i3 IPC logging, configurable via environment variable
- [ ] T074 Add application instance detection improvements: expand known single-instance app list, improve detection heuristics
- [ ] T075 Optimize application launch timing: implement xdotool-based waiting as alternative to sleep-based delays
- [ ] T076 Add project activation hooks (optional): pre-activation and post-activation script support in project definitions
- [ ] T077 Implement workspace cleanup on close: remove empty workspaces after project close unless --keep-workspaces
- [ ] T078 Add JSON output support: --json flag for list, status, and other commands for scripting integration
- [ ] T079 Create man pages for CLI tools: i3-project(1), i3-project-capture(1) man page documentation
- [ ] T080 Run quickstart.md validation: manually test all examples from quickstart guide to ensure accuracy

**Checkpoint**: Feature complete, documented, and production-ready

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - User Story 1 (P1): Core functionality - no dependencies on other stories ✓ MVP
  - User Story 2 (P1): Builds on US1 configuration - can run in parallel with US1
  - User Story 3 (P2): Independent - only needs US1 for basic activation
  - User Story 4 (P2): Independent - captures existing layouts, generates configs for US1/US2
  - User Story 5 (P3): Depends on US2 (aliases concept) - enhances US1/US2
  - User Story 6 (P3): Independent - adds repository context to US1/US2 projects
- **Polish (Phase 9)**: Depends on desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1) - Quick Switch**: Foundation only → Can start immediately after Phase 2
- **User Story 2 (P1) - Declarative Config**: Foundation only → Can run in parallel with US1
- **User Story 3 (P2) - Multi-Monitor**: Requires US1 activation logic → Can start after T012-T023
- **User Story 4 (P2) - Layout Capture**: Independent → Can start after Phase 2
- **User Story 5 (P3) - Shorthand**: Requires US2 alias concept → Can start after T053
- **User Story 6 (P3) - Git Integration**: Requires US1 activation → Can start after T014

### Within Each User Story

- Phase 3 (US1): T012 → T013 → T014 → T015 (sequential); T016-T023 can follow in any order
- Phase 4 (US2): All tasks independent except T031 depends on T025
- Phase 5 (US3): T032-T033 can run in parallel; T034-T037 sequential
- Phase 6 (US4): T038 → T039 → T040 → T041; then T042-T047 sequential; T048-T051 enhancements
- Phase 7 (US5): T052-T053 parallel; T054 → T055 → T056 sequential; T057-T059 enhancements
- Phase 8 (US6): T060-T061 parallel; T062-T066 can follow in any order

### Parallel Opportunities

**Within Setup (Phase 1)**:
- All three module structure tasks (T001, T002, T003) can run in parallel

**Within Foundational (Phase 2)**:
- T004-T006 (type definitions) can run in parallel
- T010-T011 (packages and conditional activation) can run in parallel

**Across User Stories** (once Phase 2 complete):
- US1 + US2 + US4 can all start in parallel
- US3 can start once US1 reaches T014
- US5 can start once US2 reaches T053
- US6 can start once US1 reaches T014

**Within Phase 9 (Polish)**:
- T067, T068, T069, T070, T071 (documentation and integrations) all parallel
- T073-T080 can run in any order

---

## Parallel Example: Maximum Parallelism After Foundation

```bash
# After Phase 2 completes, launch multiple user stories in parallel:

# Team Member A: User Story 1 (Core functionality)
Task: T012 - T023 (Project activation, list, status, switch, close)

# Team Member B: User Story 2 (Declarative config)
Task: T024 - T031 (Configuration examples, reload, parameterization)

# Team Member C: User Story 4 (Layout capture)
Task: T038 - T051 (Workspace scanning, layout capture, config generation)

# All three can proceed independently until they need integration points
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011) - CRITICAL BLOCKER
3. Complete Phase 3: User Story 1 (T012-T023) - Core activation
4. Complete Phase 4: User Story 2 (T024-T031) - Declarative config
5. **STOP and VALIDATE**: Test project definition → activation → switching → closing cycle
6. Add minimal documentation (T067-T068)
7. **Deploy/demo MVP**: Users can define and activate projects declaratively

### Incremental Delivery Sequence

1. **Foundation** (Setup + Foundational) → Module structure ready
2. **MVP Release** (US1 + US2) → Core functionality: define projects, activate, close, switch
3. **Multi-Monitor Release** (US3) → Enhanced workspace management across displays
4. **Capture Release** (US4) → Capture existing layouts, generate configs
5. **Power User Release** (US5 + US6) → Shorthand syntax and git integration
6. **Polish Release** (Phase 9) → Full documentation, optimizations, integrations

Each release adds value incrementally without breaking previous functionality.

### Parallel Team Strategy

With 3 developers after Foundation (Phase 2):

1. **Week 1**: All complete Setup + Foundational together (T001-T011)
2. **Week 2-3**:
   - Dev A: User Story 1 (T012-T023)
   - Dev B: User Story 2 (T024-T031)
   - Dev C: User Story 4 (T038-T051)
3. **Week 4**: Integration + MVP validation
4. **Week 5-6**:
   - Dev A: User Story 3 (T032-T037)
   - Dev B: User Story 5 (T052-T059)
   - Dev C: User Story 6 (T060-T066)
5. **Week 7**: Polish (T067-T080) - all hands

---

## Notes

- **[P] tasks**: Different files, no dependencies - safe to parallelize
- **[Story] label**: Maps task to specific user story for traceability
- **No tests included**: Feature spec did not request TDD approach
- **NixOS-specific**: All code embedded in modules via pkgs.writeShellScriptBin patterns
- **Each user story independently completable**: Can stop after any story for incremental delivery
- **Commit strategy**: Commit after each task or logical group (e.g., after each command implementation)
- **Checkpoints**: Stop at story completion to validate independently before moving forward
- **Avoid**: Cross-story dependencies that break independence (except where noted as enhancements)

---

## Total Task Count

- **Phase 1 (Setup)**: 3 tasks
- **Phase 2 (Foundational)**: 8 tasks (BLOCKING)
- **Phase 3 (US1 - P1 MVP)**: 12 tasks
- **Phase 4 (US2 - P1 MVP)**: 8 tasks
- **Phase 5 (US3 - P2)**: 6 tasks
- **Phase 6 (US4 - P2)**: 14 tasks
- **Phase 7 (US5 - P3)**: 8 tasks
- **Phase 8 (US6 - P3)**: 7 tasks
- **Phase 9 (Polish)**: 14 tasks

**Total**: 80 tasks across 9 phases

**MVP Scope** (Phases 1-4): 31 tasks
**Full Feature** (All phases): 80 tasks

---

**Generated**: 2025-10-17
**Template Version**: 1.0
**Next Step**: Execute `/speckit.implement` to begin task-by-task implementation
