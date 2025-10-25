# Tasks: Registry-Centric Project & Workspace Management

**Input**: Design documents from `/specs/035-now-that-we/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are NOT explicitly requested in the feature specification, therefore NO test tasks are included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5)
- Include exact file paths in descriptions

## Path Conventions
- **Registry**: `home-modules/desktop/app-registry.nix` (source of truth)
- **Deno CLI**: `home-modules/tools/i3pm/` (TypeScript, Deno)
- **Daemon**: `home-modules/desktop/i3-project-event-daemon/` (Python, existing from Feature 015)
- **Launcher Wrapper**: `scripts/app-launcher-wrapper.sh` (Bash)
- **Configs**: `~/.config/i3/` (runtime user configuration)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Review existing codebase structure from Feature 034 (app-registry.nix) and Feature 015 (i3pm daemon)
- [X] T002 [P] Create project directory structure per plan.md in home-modules/tools/i3pm/src/
- [X] T003 [P] Update deno.json with new task definitions and dependencies in home-modules/tools/i3pm/deno.json

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Remove tags field from app-registry.nix schema in home-modules/desktop/app-registry.nix (no longer needed)
- [X] T005 [P] Create TypeScript interfaces for registry schema in home-modules/tools/i3pm/src/models/registry.ts (without tags)
- [X] T006 [P] Create TypeScript interfaces for project schema in home-modules/tools/i3pm/src/models/project.ts (without application_tags)
- [X] T007 [P] Create TypeScript interfaces for layout schema with app_instance_id in home-modules/tools/i3pm/src/models/layout.ts
- [X] T008 [P] Create TypeScript interfaces for process environment (I3PM_* variables) in home-modules/tools/i3pm/src/models/environment.ts
- [X] T009 Implement registry JSON loader/parser service in home-modules/tools/i3pm/src/services/registry.ts
- [X] T010 [P] Implement project CRUD service (load, save, validate) in home-modules/tools/i3pm/src/services/project-manager.ts
- [X] T011 [P] Implement JSON-RPC client wrapper for daemon communication in home-modules/tools/i3pm/src/services/daemon-client.ts
- [X] T012 Create Python window_filter.py service module in home-modules/desktop/i3-project-event-daemon/services/window_filter.py
- [X] T013 Implement read_process_environ() function in window_filter.py to read /proc/<pid>/environ
- [X] T014 Implement get_window_pid() function using xprop in window_filter.py (i3ipc doesn't expose reliably)
- [X] T015 Create registry_loader.py service to load and validate registry on daemon startup in home-modules/desktop/i3-project-event-daemon/services/registry_loader.py

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Launch Project Applications from Registry (Priority: P1) 🎯 MVP

**Goal**: Launch applications for the current project using the centralized registry with automatic workspace assignment and environment variable injection for project context

**Independent Test**: Switch to a project, launch any registered application (VS Code, terminal, file manager), verify it opens with correct project directory and lands on expected workspace. Verify I3PM_* environment variables are present in /proc/<pid>/environ.

**Why P1**: Foundational capability that replaces current ad-hoc launching. Without this, none of the other features work properly. Delivers immediate value by simplifying project-scoped app launches.

### Implementation for User Story 1

- [X] T016 [P] [US1] Update app-launcher-wrapper.sh to query daemon for active project via JSON-RPC in scripts/app-launcher-wrapper.sh
- [X] T017 [P] [US1] Implement generateAppInstanceId() function in wrapper script (format: ${app}-${project}-${pid}-${timestamp})
- [X] T018 [US1] Inject I3PM_* environment variables in app-launcher-wrapper.sh before exec:
  - I3PM_APP_ID (unique instance ID)
  - I3PM_APP_NAME (registry application name)
  - I3PM_PROJECT_NAME (active project name or empty)
  - I3PM_PROJECT_DIR (project directory or empty)
  - I3PM_SCOPE (scoped or global)
  - I3PM_ACTIVE (true if project active)
  - I3PM_LAUNCH_TIME (unix timestamp)
  - I3PM_LAUNCHER_PID (wrapper script PID)
- [X] T019 [US1] Implement variable substitution for $PROJECT_DIR in wrapper script (use I3PM_PROJECT_DIR)
- [X] T020 [US1] Implement fallback behavior (skip, use_home, error) when no project active in wrapper
- [X] T021 [P] [US1] Implement application launcher service using registry protocol in home-modules/tools/i3pm/src/services/launcher.ts
- [X] T022 [US1] Handle multi-instance applications in launcher (multiple windows per app allowed)
- [X] T023 [US1] Update daemon on_window_new handler to read /proc/<pid>/environ in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T024 [US1] Extract I3PM_APP_ID and I3PM_PROJECT_NAME from process environment in on_window_new
- [X] T025 [US1] Store window environment data in daemon state for filtering
- [X] T026 [US1] Implement workspace assignment logic in daemon based on registry preferred_workspace
- [X] T027 [US1] Add registry validation to ensure expected_class matches actual window classes

**Checkpoint**: At this point, User Story 1 should be fully functional - applications launch with environment variables injected, windows appear on correct workspaces

---

## Phase 4: User Story 3 - Deterministic Window Matching via Application IDs (Priority: P1)

**Goal**: Each application instance has a unique I3PM_APP_ID enabling exact window identification even with multiple instances running, eliminating ambiguity for layout restore

**Independent Test**: Launch multiple instances of the same application across different projects, use /proc/<pid>/environ to verify each window has a unique I3PM_APP_ID and correct project association. Switch projects and verify windows filter correctly.

**Why P1**: Eliminates ambiguity in window matching. Traditional window class matching fails with multiple instances (e.g., multiple VS Code windows all have class="Code"). Must work in parallel with US1.

**NOTE**: Implementing this BEFORE US2 because it's P1 and works in parallel with US1

### Implementation for User Story 3

- [X] T028 [P] [US3] Create i3-window-rules.nix module to auto-generate window rules from registry for GLOBAL apps only in home-modules/desktop/i3-window-rules.nix
- [X] T029 [US3] Implement Nix function to filter global apps and generate for_window rules
- [X] T030 [US3] Import auto-generated window rules into i3wm.nix module in modules/desktop/i3wm.nix
- [X] T031 [US3] Implement window instance ID matching in window_filter.py by comparing I3PM_APP_ID
- [X] T032 [US3] Handle PWA applications with FFPWA-* class patterns in window filter
- [X] T033 [US3] Add expected_title_contains fallback matching for apps without reliable window class
- [X] T034 [US3] Test deterministic matching for all 21 registry applications with multiple instances

**Checkpoint**: At this point, User Stories 1 AND 3 should both work - apps launch with unique IDs AND can be deterministically matched

---

## Phase 5: User Story 2 - Environment-Based Window Filtering (Priority: P2)

**Goal**: Windows automatically show/hide when switching projects based on I3PM_PROJECT_NAME read from /proc/<pid>/environ, eliminating need for tag configuration

**Independent Test**: Launch applications in one project, switch to another project, verify windows from first project are automatically hidden while windows from second project remain visible. Global applications remain visible across all projects.

**Why P2**: Builds on P1 by automatically filtering windows based on which project they were launched with. Uses process environment to determine window ownership.

### Implementation for User Story 2

- [X] T035 [P] [US2] Implement CLI command `i3pm apps list` in home-modules/tools/i3pm/src/commands/apps.ts
- [X] T036 [P] [US2] Add filtering by scope, workspace to apps list command (no tags)
- [X] T037 [P] [US2] Implement CLI command `i3pm apps show <name>` in home-modules/tools/i3pm/src/commands/apps.ts
- [X] T038 [P] [US2] Implement CLI command `i3pm project create` in home-modules/tools/i3pm/src/commands/project.ts
- [X] T039 [US2] Add interactive prompts for project creation (display name, directory, icon - NO TAGS)
- [X] T040 [US2] Validate project directory exists during creation
- [X] T041 [US2] Implement CLI command `i3pm project list` in home-modules/tools/i3pm/src/commands/project.ts
- [X] T042 [P] [US2] Implement CLI command `i3pm project show [name]` in home-modules/tools/i3pm/src/commands/project.ts
- [X] T043 [P] [US2] Implement CLI command `i3pm project current` (alias for show with no args)
- [X] T044 [P] [US2] Implement CLI command `i3pm project update <name>` in home-modules/tools/i3pm/src/commands/project.ts
- [X] T045 [P] [US2] Implement CLI command `i3pm project delete <name>` with confirmation prompt
- [X] T046 [US2] Implement CLI command `i3pm project switch <name>` in home-modules/tools/i3pm/src/commands/project.ts
- [X] T047 [US2] Update active-project.json on project switch
- [X] T048 [US2] Send i3 tick event to daemon when project switches (payload: "project:switch:<name>")
- [X] T049 [US2] Implement CLI command `i3pm project clear` to return to global mode
- [X] T050 [US2] Implement daemon handler for project switch tick event in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T051 [US2] Implement filter_windows_by_project() in window_filter.py:
  - Get all windows from i3 tree
  - For each window: get PID via xprop
  - Read /proc/<PID>/environ
  - Extract I3PM_PROJECT_NAME
  - If matches active project → keep visible
  - If no match → move to scratchpad (hide)
  - If no I3PM_PROJECT_NAME → global → keep visible
- [X] T052 [US2] Handle permission errors gracefully when reading /proc/<pid>/environ (assume global scope)
- [X] T053 [US2] Add performance optimization: cache PIDs on window::new to avoid xprop on every switch
- [X] T054 [US2] Update i3bar status with new project name on switch

**Checkpoint**: At this point, User Stories 1, 2, AND 3 should all work independently - projects can be switched with automatic window filtering by environment

---

## Phase 6: User Story 5 - CLI for Config Management and Monitoring (Priority: P2)

**Goal**: Command-line tools to view, update, and monitor registry configuration and projects for efficient terminal-based management

**Independent Test**: Run CLI commands to list applications, show project details, view workspace assignments, update project settings - all common tasks achievable via CLI

**Why P2**: Essential visibility and control over the registry-centric system. Users need to inspect config and troubleshoot without editing Nix files.

**NOTE**: Implementing this BEFORE US4 because it's P2 and provides debugging tools needed for layout restore

### Implementation for User Story 5

- [X] T055 [P] [US5] Add --json output flag support to all commands in home-modules/tools/i3pm/src/ui/formatters.ts
- [X] T056 [P] [US5] Implement table formatter for application list output
- [X] T057 [P] [US5] Implement table formatter for project list output
- [X] T058 [P] [US5] Extend `i3pm windows` command to show registry app names and I3PM_PROJECT_NAME
- [X] T059 [US5] Add --live mode to windows command with real-time monitoring
- [X] T060 [US5] Implement `i3pm daemon status` command in home-modules/tools/i3pm/src/commands/daemon.ts
- [X] T061 [P] [US5] Implement `i3pm daemon events` command with --follow, --limit, --type filters
- [X] T062 [US5] Add verbose logging mode with --verbose global flag
- [X] T063 [US5] Implement error message formatter with remediation steps
- [X] T064 [US5] Add CLI help text and examples for all commands using @std/cli

**Checkpoint**: All CLI commands operational - users can manage entire system from terminal

---

## Phase 7: User Story 4 - Save and Restore Project Layouts (Priority: P3)

**Goal**: Save current window arrangement as a project layout and restore it later with exact window matching using I3PM_APP_ID for deterministic identification

**Independent Test**: Arrange windows across workspaces, save layout, close all windows, restore layout - all apps reopen in original positions with exact window identification via application instance IDs

**Why P3**: Productivity enhancement that builds on P1-P3. Valuable but not essential for core registry-centric workflow.

### Implementation for User Story 4

- [X] T065 [P] [US4] Implement layout capture service in home-modules/tools/i3pm/src/services/layout-engine.ts
- [X] T066 [US4] Query window tree via JSON-RPC to daemon (reuse get_window_state from Feature 015)
- [X] T067 [US4] For each window, get PID via xprop and read I3PM_APP_ID from /proc/<pid>/environ
- [X] T068 [US4] Match windows to registry applications by I3PM_APP_NAME from environment
- [X] T069 [US4] Capture window geometry (workspace, x, y, width, height, floating, focused)
- [X] T070 [US4] Store I3PM_APP_ID in layout WindowSnapshot for exact matching on restore
- [X] T071 [US4] Serialize layout to JSON with registry app references and instance IDs
- [X] T072 [US4] Implement CLI command `i3pm layout save <project> [name]` in home-modules/tools/i3pm/src/commands/layout.ts
- [X] T073 [US4] Add --overwrite flag and confirmation prompt for existing layouts
- [X] T074 [US4] Update project's saved_layout field on successful save
- [X] T075 [US4] Implement layout restore service in layout-engine.ts
- [X] T076 [US4] Validate layout applications exist in current registry before restore
- [X] T077 [US4] Implement close_project_windows via JSON-RPC to daemon (FR-012)
- [X] T078 [US4] Launch applications via registry protocol with SAME I3PM_APP_ID as saved layout
- [X] T079 [US4] Wait for window appearance and verify I3PM_APP_ID matches expected value from layout
- [X] T080 [US4] Position windows using i3-msg move and resize commands after exact ID match
- [X] T081 [US4] Focus final window marked as focused in layout
- [X] T082 [US4] Implement CLI command `i3pm layout restore <project>` in home-modules/tools/i3pm/src/commands/layout.ts
- [X] T083 [US4] Add --dry-run flag to preview restore without launching
- [X] T084 [P] [US4] Implement CLI command `i3pm layout delete <project>` with confirmation
- [X] T085 [US4] Handle missing applications gracefully (skip with warning, FR-013)
- [X] T086 [US4] Add error handling for launch failures and positioning errors
- [X] T087 [US4] Add timeout handling (5 seconds per app) if I3PM_APP_ID never matches

**Checkpoint**: All user stories complete - layouts can be saved and restored with exact window matching via application instance IDs

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final cleanup

- [X] T088 [P] Remove XDG isolation from walker.nix (no longer needed with environment-based filtering) in home-modules/desktop/walker.nix
- [ ] T089 [P] Remove legacy application launching code from i3 config (FR-019)
- [ ] T090 [P] Remove legacy project-scoped launch scripts and hardcoded window rules
- [ ] T091 [P] Update i3 keybindings to use new registry-based launchers
- [ ] T092 Verify all variable substitution patterns work correctly ($PROJECT_DIR → I3PM_PROJECT_DIR)
- [ ] T093 [P] Add comprehensive error messages for all validation failures
- [ ] T094 [P] Test all CLI commands with --json output for scripting compatibility
- [ ] T095 Validate quickstart.md workflows work end-to-end
- [ ] T096 [P] Update CLAUDE.md with new environment-based project management workflow documentation
- [ ] T097 Run full system test: create project → switch → launch apps → verify /proc → save layout → restore
- [ ] T098 Performance validation: verify project switch completes in <2 seconds for 20 windows (SC-008)
- [ ] T099 Verify environment injection overhead is <100ms per application launch (plan.md performance goal)
- [ ] T100 Verify /proc reading performance is <5ms per process (plan.md performance goal)
- [ ] T101 [P] Code cleanup and refactoring for maintainability
- [ ] T102 Security audit: verify no shell metacharacters in registry parameters

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-7)**: All depend on Foundational phase completion
  - US1 (P1, Phase 3): Launch with environment injection - can start after Foundational
  - US3 (P1, Phase 4): Deterministic matching - can start IN PARALLEL with US1 after Foundational
  - US2 (P2, Phase 5): Environment-based filtering - depends on US1 and US3 for full functionality
  - US5 (P2, Phase 6): CLI tools - can start after US1, provides debugging for US4
  - US4 (P3, Phase 7): Layouts - depends on US1, US3, US5 for full functionality
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 3 (P1)**: Can start IN PARALLEL with US1 after Foundational - Works together with US1
- **User Story 2 (P2)**: Depends on US1 (environment injection) and US3 (window matching) completion
- **User Story 5 (P2)**: Depends on US1 completion, provides monitoring tools for US4
- **User Story 4 (P3)**: Depends on US1 (launch), US3 (matching via I3PM_APP_ID), US5 (CLI tools) completion

### Within Each User Story

- Models before services (TypeScript interfaces before implementation)
- Services before commands (business logic before CLI)
- Core functionality before edge cases
- Implementation before integration

### Parallel Opportunities

**Phase 2 (Foundational)**:
- T005 (registry types) || T006 (project types) || T007 (layout types) || T008 (environment types)
- T010 (project service) || T011 (daemon client)

**Phase 3 (US1)**:
- T016 (query active project) || T017 (generate ID) || T021 (launcher service)

**Phase 4 (US3)**:
- T028 (window rules module) || T031 (instance ID matching) || T033 (title fallback)

**Phase 5 (US2)**:
- T035 (apps list) || T036 (filters) || T037 (apps show)
- T038 (project create) || T041 (project list) || T042 (project show) || T043 (project current) || T044 (project update) || T045 (project delete)

**Phase 6 (US5)**:
- T055 (JSON output) || T056 (app formatter) || T057 (project formatter) || T061 (daemon events)

**Phase 7 (US4)**:
- T065 (layout capture) || T075 (layout restore) || T084 (layout delete)

**Phase 8 (Polish)**:
- T088 (remove XDG isolation) || T089 (remove legacy code) || T090 (remove legacy scripts) || T091 (update keybindings)
- T093 (error messages) || T094 (JSON output tests) || T101 (code cleanup) || T102 (security audit)

---

## Parallel Example: User Story 1

```bash
# After Foundational phase complete, launch US1 tasks in parallel:

# Terminal 1: Query active project in wrapper
Task T016: "Update app-launcher-wrapper.sh to query daemon for active project via JSON-RPC"

# Terminal 2: Generate instance IDs
Task T017: "Implement generateAppInstanceId() function in wrapper script"

# Terminal 3: Launcher service
Task T021: "Implement application launcher service using registry protocol in home-modules/tools/i3pm/src/services/launcher.ts"
```

---

## Parallel Example: User Story 3 (runs in parallel with US1)

```bash
# While US1 is being implemented, US3 can proceed in parallel:

# Terminal 1: Window rules generation (global apps only)
Task T028: "Create i3-window-rules.nix module to auto-generate window rules from registry for GLOBAL apps only"

# Terminal 2: Instance ID matching
Task T031: "Implement window instance ID matching in window_filter.py by comparing I3PM_APP_ID"

# Terminal 3: Title fallback
Task T033: "Add expected_title_contains fallback matching for apps without reliable window class"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 3 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T015) - CRITICAL - includes environment variable infrastructure
3. Complete Phase 3: User Story 1 (T016-T027) - Environment injection and launch
4. Complete Phase 4: User Story 3 (T028-T034) - Deterministic matching via I3PM_APP_ID
5. **STOP and VALIDATE**: Test US1 and US3 together - apps launch with environment variables, windows identified by unique IDs
6. Deploy/demo if ready

**Estimated Tasks for MVP**: 34 tasks (Setup + Foundational + US1 + US3)

### Incremental Delivery

1. **Foundation** (T001-T015): Setup + Foundational → Environment variable infrastructure ready
2. **MVP** (T016-T034): US1 + US3 → Apps launch with I3PM_* variables, deterministic window matching → **DEPLOY**
3. **Environment-Based Filtering** (T035-T054): US2 → Automatic window filtering by /proc reading → **DEPLOY**
4. **CLI Tools** (T055-T064): US5 → Full terminal management interface → **DEPLOY**
5. **Layouts** (T065-T087): US4 → Save/restore with exact window matching via I3PM_APP_ID → **DEPLOY**
6. **Polish** (T088-T102): Legacy cleanup (remove tags, XDG isolation), validation, documentation → **FINAL RELEASE**

Each deployment adds value without breaking previous functionality.

### Parallel Team Strategy

With 2 developers after Foundational phase:

1. **Team completes** Setup + Foundational together (T001-T015)
2. **Then split**:
   - Developer A: User Story 1 (T016-T027) - Environment injection
   - Developer B: User Story 3 (T028-T034) - Deterministic matching - works in parallel
3. **Merge and validate** MVP together
4. **Continue with**:
   - Developer A: User Story 2 (T035-T054) - Environment-based filtering
   - Developer B: User Story 5 (T055-T064) - CLI tools - works in parallel
5. **Finally**:
   - Both: User Story 4 together (T065-T087) - Layout restore with instance IDs
   - Both: Polish together (T088-T102)

---

## Notes

- [P] tasks = different files, no dependencies - can run in parallel
- [Story] label (US1-US5) maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Tests NOT included per specification (no TDD requirement)
- Registry is single source of truth - no duplicate application definitions
- **Environment variable injection replaces tag-based filtering** (Principle XII - Forward-Only Development)
- **No tags, no XDG isolation** - environment-based approach is simpler and more powerful
- **Deterministic window matching via I3PM_APP_ID** eliminates ambiguity with multiple instances
- All legacy code paths removed, not maintained alongside new implementation (Principle XII)
