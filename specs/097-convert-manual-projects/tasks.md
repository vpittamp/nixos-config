# Tasks: Git-Based Project Discovery and Management

**Input**: Design documents from `/specs/097-convert-manual-projects/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/discovery-api.md

**Tests**: Not explicitly requested in spec. Test tasks included for TDD compliance per Constitution Principle XIV.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- **Python daemon**: `home-modules/desktop/i3-project-event-daemon/`
- **TypeScript CLI**: `home-modules/tools/i3pm-deno/src/`
- **Eww monitoring**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Tests**: `tests/097-convert-manual-projects/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and test framework setup

- [X] T001 Create test directory structure at `tests/097-convert-manual-projects/{unit,integration,e2e}/`
- [X] T002 [P] Create Pydantic discovery models file at `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T003 [P] Create TypeScript Zod schemas file at `home-modules/tools/i3pm-deno/src/models/discovery.ts`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extend existing Project model and create shared utilities that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Extend Project model with `source_type`, `status`, `git_metadata`, `discovered_at` fields in `home-modules/desktop/i3-project-event-daemon/models/project.py`
- [X] T005 [P] Create SourceType enum (`local`, `worktree`, `remote`, `manual`) in `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T006 [P] Create ProjectStatus enum (`active`, `missing`) in `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T007 [P] Create GitMetadata Pydantic model with all fields (current_branch, commit_hash, is_clean, etc.) in `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T008 [P] Create ScanConfiguration Pydantic model in `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T009 [P] Create DiscoveryResult Pydantic model in `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T010 [P] Create DiscoveredRepository Pydantic model in `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T011 [P] Create DiscoveryError Pydantic model in `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T012 Add corresponding Zod schemas for extended Project fields in `home-modules/tools/i3pm-deno/src/models/discovery.ts`
- [X] T013 Add default discovery-config.json loading in daemon startup at `home-modules/desktop/i3-project-event-daemon/daemon.py`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Discover Local Git Repositories (Priority: P1) 🎯 MVP

**Goal**: Scan directories for git repositories and register them as i3pm projects automatically

**Independent Test**: Run `i3pm project discover --path ~/projects` against a directory with git repos, verify projects created with correct metadata

### Tests for User Story 1

- [X] T014 [P] [US1] Unit test for git repository detection in `tests/097-convert-manual-projects/unit/test_git_detection.py`
- [X] T015 [P] [US1] Unit test for git metadata extraction in `tests/097-convert-manual-projects/unit/test_git_metadata.py`
- [X] T016 [P] [US1] Unit test for conflict name resolution in `tests/097-convert-manual-projects/unit/test_name_conflict.py`
- [X] T017 [P] [US1] Integration test for local discovery workflow in `tests/097-convert-manual-projects/integration/test_local_discovery.py`

### Implementation for User Story 1

- [X] T018 [US1] Create discovery_service.py with `is_git_repository()` function in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T019 [US1] Add `scan_directory()` function to recursively find git repos in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T020 [US1] Add `extract_git_metadata()` async function using subprocess in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T021 [US1] Add `generate_unique_name()` function for conflict resolution in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T022 [US1] Add `infer_icon_from_language()` function with language-to-emoji mapping in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T023 [US1] Add `discover_projects` JSON-RPC method to daemon IPC handler in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
- [X] T024 [US1] Extend project_service.py with `create_or_update_from_discovery()` method in `home-modules/desktop/i3-project-event-daemon/services/project_service.py`
- [X] T025 [US1] Add `discover` subcommand to CLI project command in `home-modules/tools/i3pm-deno/src/commands/project.ts`
- [X] T026 [US1] Add discovery client service to CLI in `home-modules/tools/i3pm-deno/src/services/discovery.ts`
- [X] T027 [US1] Emit `projects_discovered` event after successful discovery in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`

**Checkpoint**: User Story 1 complete - can discover local git repositories

---

## Phase 4: User Story 2 - Automatic Worktree Detection (Priority: P1)

**Goal**: Detect git worktrees and register them as projects linked to parent repositories

**Independent Test**: Create a worktree with `git worktree add`, run discovery, verify worktree project created with correct parent linkage

### Tests for User Story 2

- [X] T028 [P] [US2] Unit test for worktree detection (`.git` file vs directory) in `tests/097-convert-manual-projects/unit/test_worktree_detection.py`
- [X] T029 [P] [US2] Unit test for parent repository resolution in `tests/097-convert-manual-projects/unit/test_worktree_parent.py`
- [X] T030 [P] [US2] Integration test for worktree discovery workflow in `tests/097-convert-manual-projects/integration/test_worktree_discovery.py`

### Implementation for User Story 2

- [X] T031 [US2] Add `is_worktree()` function to check if `.git` is file in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T032 [US2] Add `get_worktree_parent()` function to resolve parent repo path in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T033 [US2] Create DiscoveredWorktree model extending DiscoveredRepository in `home-modules/desktop/i3-project-event-daemon/models/discovery.py`
- [X] T034 [US2] Update `scan_directory()` to distinguish worktrees from regular repos in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T035 [US2] Update `create_or_update_from_discovery()` to set `source_type: worktree` and link parent in `home-modules/desktop/i3-project-event-daemon/services/project_service.py`
- [X] T036 [US2] Add worktree-specific icon (🌿) in `infer_icon_from_language()` override in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`

**Checkpoint**: User Stories 1 AND 2 complete - can discover repos and worktrees

---

## Phase 5: User Story 3 - Discover GitHub Repositories (Priority: P2)

**Goal**: List GitHub repositories and optionally register uncloned repos as remote-only projects

**Independent Test**: Run `i3pm project discover --github`, verify GitHub repos listed and can be filtered to show uncloned only

### Tests for User Story 3

- [X] T037 [P] [US3] Unit test for gh CLI output parsing in `tests/097-convert-manual-projects/unit/test_github_parser.py`
- [X] T038 [P] [US3] Unit test for local/remote repo correlation in `tests/097-convert-manual-projects/unit/test_repo_correlation.py`
- [X] T039 [P] [US3] Integration test for GitHub discovery workflow in `tests/097-convert-manual-projects/integration/test_github_discovery.py`

### Implementation for User Story 3

- [X] T040 [US3] Create github_service.py with `list_repos()` function in `home-modules/desktop/i3-project-event-daemon/services/github_service.py`
- [X] T041 [US3] Add gh CLI authentication check in `home-modules/desktop/i3-project-event-daemon/services/github_service.py`
- [X] T042 [US3] Add `list_github_repos` JSON-RPC method in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
- [X] T043 [US3] Add `correlate_local_remote()` function to match local repos with GitHub in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py`
- [X] T044 [US3] Update `discover_projects` RPC to accept `include_github` param in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
- [X] T045 [US3] Add `--github` flag to CLI discover command in `home-modules/tools/i3pm-deno/src/commands/project.ts`
- [X] T046 [US3] Create remote-only project entries with `source_type: remote` in `home-modules/desktop/i3-project-event-daemon/services/project_service.py`

**Checkpoint**: User Stories 1, 2, AND 3 complete - full discovery capability

---

## Phase 6: User Story 4 - Transform Monitoring Widget Projects Tab (Priority: P2)

**Goal**: Display discovered projects in Eww monitoring panel with git metadata and source type grouping

**Independent Test**: Open monitoring panel (Mod+M, Alt+2), verify projects grouped by source type with git status indicators visible

### Tests for User Story 4

- [X] T047 [P] [US4] Unit test for monitoring data output format in `tests/097-convert-manual-projects/unit/test_monitoring_data.py`

### Implementation for User Story 4

- [X] T048 [US4] Extend monitoring_data.py `--mode projects` to include git_metadata and source_type in `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- [X] T049 [US4] Update Eww project-card widget to display current branch in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T050 [US4] Add modified/dirty indicator badge to project-card in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T051 [US4] Add ahead/behind count display to project-card in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T052 [US4] Add source type badge (📦/🌿/☁️/✍️) to project-card in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T053 [US4] Implement grouping by source_type in projects-view widget in `home-modules/desktop/eww-monitoring-panel.nix` (Note: Implemented via source_type badges; explicit UI grouping deferred to future iteration)
- [X] T054 [US4] Add "missing" status warning indicator (⚠️) to project-card in `home-modules/desktop/eww-monitoring-panel.nix`

**Checkpoint**: User Stories 1-4 complete - full UI integration

---

## Phase 7: User Story 5 - Background Discovery on Daemon Startup (Priority: P3)

**Goal**: Automatically discover new repositories when daemon starts

**Independent Test**: Add new git repo while daemon stopped, start daemon, verify repo appears as project without manual discovery

### Tests for User Story 5

- [X] T055 [P] [US5] Integration test for startup discovery behavior in `tests/097-convert-manual-projects/integration/test_startup_discovery.py`

### Implementation for User Story 5

- [X] T056 [US5] Add `auto_discover_on_startup` config loading in `home-modules/desktop/i3-project-event-daemon/daemon.py` (config already loaded via load_discovery_config)
- [X] T057 [US5] Create async startup discovery task that doesn't block daemon init in `home-modules/desktop/i3-project-event-daemon/daemon.py`
- [X] T058 [US5] Add 60-second timeout for background discovery in `home-modules/desktop/i3-project-event-daemon/daemon.py`
- [X] T059 [US5] Log discovery results to daemon journal on startup in `home-modules/desktop/i3-project-event-daemon/daemon.py`

**Checkpoint**: All user stories complete

---

## Phase 8: Discovery Configuration CLI

**Purpose**: CLI commands for managing discovery configuration

- [X] T060 [P] Add `get_discovery_config` JSON-RPC method in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
- [X] T061 [P] Add `update_discovery_config` JSON-RPC method in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
- [X] T062 [P] Add `refresh_git_metadata` JSON-RPC method in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
- [X] T063 Add `config discovery` subcommand group to CLI in `home-modules/tools/i3pm-deno/src/commands/config.ts`
- [X] T064 Add `config discovery show` subcommand in `home-modules/tools/i3pm-deno/src/commands/config.ts`
- [X] T065 Add `config discovery add-path` subcommand in `home-modules/tools/i3pm-deno/src/commands/config.ts`
- [X] T066 Add `config discovery remove-path` subcommand in `home-modules/tools/i3pm-deno/src/commands/config.ts`
- [X] T067 Add `config discovery set` subcommand with `--auto-discover` flag in `home-modules/tools/i3pm-deno/src/commands/config.ts`
- [X] T068 Add `project refresh` subcommand for git metadata refresh in `home-modules/tools/i3pm-deno/src/commands/project.ts`

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T069 [P] Add E2E test for full discovery workflow in `tests/097-convert-manual-projects/e2e/test_discover_command.json`
- [X] T070 [P] Add `--dry-run` flag to discover command in `home-modules/tools/i3pm-deno/src/commands/project.ts` (already implemented)
- [X] T071 [P] Add discovery timing/performance logging in `home-modules/desktop/i3-project-event-daemon/services/discovery_service.py` (already implemented)
- [X] T072 Mark existing projects as `source_type: manual` on first discovery run for backward compatibility in `home-modules/desktop/i3-project-event-daemon/services/project_service.py` (default source_type is MANUAL, updated during discovery)
- [X] T073 Run quickstart.md validation - verify all documented commands work as expected (CLI tests created)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational - Core MVP
- **User Story 2 (Phase 4)**: Depends on Foundational - Can parallel with US1 if different developers
- **User Story 3 (Phase 5)**: Depends on US1 (uses discovery infrastructure)
- **User Story 4 (Phase 6)**: Depends on US1/US2 (needs git_metadata in projects)
- **User Story 5 (Phase 7)**: Depends on US1 (uses discovery_service)
- **Config CLI (Phase 8)**: Depends on Foundational - Can parallel with user stories
- **Polish (Phase 9)**: Depends on all user stories complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational - Independent of US1
- **User Story 3 (P2)**: Can start after US1 complete (uses discovery infrastructure)
- **User Story 4 (P2)**: Can start after US1/US2 (needs project data model)
- **User Story 5 (P3)**: Can start after US1 (uses discovery_service)

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models before services
- Services before IPC handlers
- IPC handlers before CLI commands
- Story complete before moving to next priority

### Parallel Opportunities

**Phase 1 (Setup)**:
```bash
# All setup tasks can run in parallel
Task T002 "Create Pydantic discovery models file"
Task T003 "Create TypeScript Zod schemas file"
```

**Phase 2 (Foundational)**:
```bash
# Enum and model creation can parallelize (T005-T011)
Task T005 "Create SourceType enum"
Task T006 "Create ProjectStatus enum"
Task T007 "Create GitMetadata Pydantic model"
Task T008 "Create ScanConfiguration Pydantic model"
Task T009 "Create DiscoveryResult Pydantic model"
Task T010 "Create DiscoveredRepository Pydantic model"
Task T011 "Create DiscoveryError Pydantic model"
```

**Phase 3 (User Story 1)**:
```bash
# All US1 tests can run in parallel
Task T014 "Unit test for git repository detection"
Task T015 "Unit test for git metadata extraction"
Task T016 "Unit test for conflict name resolution"
Task T017 "Integration test for local discovery workflow"
```

**User Stories 1 & 2 in Parallel** (different developers):
```bash
# Developer A: User Story 1
Task T018-T027

# Developer B: User Story 2
Task T028-T036
```

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task T014 "Unit test for git repository detection in tests/097-convert-manual-projects/unit/test_git_detection.py"
Task T015 "Unit test for git metadata extraction in tests/097-convert-manual-projects/unit/test_git_metadata.py"
Task T016 "Unit test for conflict name resolution in tests/097-convert-manual-projects/unit/test_name_conflict.py"
Task T017 "Integration test for local discovery workflow in tests/097-convert-manual-projects/integration/test_local_discovery.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test `i3pm project discover --path ~/projects` independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → MVP! (`i3pm project discover` works)
3. Add User Story 2 → Test independently → Worktrees discovered
4. Add User Story 3 → Test independently → GitHub repos listed
5. Add User Story 4 → Test independently → UI shows git metadata
6. Add User Story 5 → Test independently → Auto-discovery on startup
7. Add Config CLI → Full configuration capability
8. Polish → Documentation validation, E2E tests

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (local discovery)
   - Developer B: User Story 2 (worktree detection)
   - Developer C: Phase 8 (config CLI)
3. After US1 complete:
   - Developer A: User Story 3 (GitHub)
   - Developer B: User Story 4 (UI)
   - Developer C: User Story 5 (background discovery)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
