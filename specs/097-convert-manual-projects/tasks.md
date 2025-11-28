# Tasks: Git-Centric Project and Worktree Management

**Input**: Design documents from `/specs/097-convert-manual-projects/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/discovery-api.md ✓

**Tests**: Tests are NOT explicitly requested in the specification. Task generation focuses on implementation only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Note**: This tasks.md replaces the previous version following the spec revision to git-centric architecture. Previous tasks (T001-T074) focused on discovery-first approach. New tasks follow the revised spec focusing on `bare_repo_path` as canonical identifier.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md project structure:
- **Python daemon/services**: `home-modules/tools/i3_project_manager/`
- **TypeScript CLI**: `home-modules/tools/i3pm-deno/`
- **Eww Panel**: `home-modules/desktop/eww-monitoring-panel/`
- **Project storage**: `~/.config/i3/projects/*.json`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Update project models and validation schemas for git-centric architecture

- [X] T001 [P] Update Python Project model with new fields (`source_type`, `bare_repo_path`, `parent_project`, `status`) in `home-modules/tools/i3_project_manager/models/project_config.py`
- [X] T002 [P] Update TypeScript Project schema with new fields and Zod validation in `home-modules/tools/i3pm-deno/src/models/discovery.ts`
- [X] T003 [P] Add `SourceType` enum (`repository`, `worktree`, `standalone`) to Python models in `home-modules/tools/i3_project_manager/models/project_config.py`
- [X] T004 [P] Add `ProjectStatus` enum (`active`, `missing`, `orphaned`) to Python models in `home-modules/tools/i3_project_manager/models/project_config.py`
- [X] T005 [P] Add Pydantic validator: worktree projects MUST have `parent_project` set in `home-modules/tools/i3_project_manager/models/project_config.py`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core git discovery utilities and project hierarchy logic that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Create `get_bare_repository_path(directory: str) -> Optional[str]` utility using `git rev-parse --git-common-dir` in `home-modules/tools/i3_project_manager/services/git_utils.py`
- [X] T007 Create `determine_source_type(directory: str, existing_projects: List[Project]) -> SourceType` function in `home-modules/tools/i3_project_manager/services/git_utils.py`
- [X] T008 Create `find_repository_for_bare_repo(bare_repo_path: str, projects: List[Project]) -> Optional[Project]` function in `home-modules/tools/i3_project_manager/services/git_utils.py`
- [X] T009 Create `detect_orphaned_worktrees(projects: List[Project]) -> List[Project]` function in `home-modules/tools/i3_project_manager/services/git_utils.py`
- [X] T010 [P] Create TypeScript `getBareRepoPath(directory: string): Promise<string | null>` in `home-modules/tools/i3pm-deno/src/utils/git.ts` (already existed)
- [X] T011 [P] Create TypeScript `determineSourceType()` matching Python logic in `home-modules/tools/i3pm-deno/src/utils/git.ts`
- [X] T012 Create `generate_unique_name(base_name: str, existing_names: Set[str]) -> str` for conflict resolution in `home-modules/tools/i3_project_manager/services/git_utils.py`
- [X] T013 Add `PanelProjectsData` model for hierarchy display (`repository_projects`, `standalone_projects`, `orphaned_worktrees`) in `home-modules/tools/i3_project_manager/models/project_config.py`
- [X] T014 Add `RepositoryWithWorktrees` model for panel grouping in `home-modules/tools/i3_project_manager/models/project_config.py`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Discover and Register Repository (Priority: P1) 🎯 MVP

**Goal**: User can run `i3pm project discover` to register a git repository with correct `bare_repo_path` and `source_type`

**Independent Test**: Run `i3pm project discover --path /etc/nixos`, verify project JSON is created with `bare_repo_path` and `source_type: "repository"` or `"worktree"` based on existing projects

### Implementation for User Story 1

- [X] T015 [US1] Create `discover.ts` command scaffold in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T016 [US1] Implement `--path` argument parsing with default to current directory in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T017 [US1] Implement `--name` and `--icon` optional arguments in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T018 [US1] Call `getBareRepoPath()` and handle non-git directories in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T019 [US1] Load existing projects and call `determineSourceType()` in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T020 [US1] Create Repository Project JSON when first project for bare repo in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T021 [US1] Create Worktree Project JSON with `parent_project` when repo already has Repository Project in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T022 [US1] Create Standalone Project for non-git directories (with `--standalone` flag) in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T023 [US1] Handle name conflicts using `generateUniqueName()` in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T024 [US1] Output discovery result with `bare_repo_path` and `source_type` confirmation in `home-modules/tools/i3pm-deno/src/commands/project/discover.ts`
- [X] T025 [US1] Register `discover` command in CLI main entry (already registered in project.ts router)

**Checkpoint**: `i3pm project discover` creates correct project types based on git structure

---

## Phase 4: User Story 2 - Create Worktree from Repository Project (Priority: P1)

**Goal**: User can create a new worktree via UI button, which runs `i3pm worktree create` and registers a linked Worktree Project

**Independent Test**: Click "[+ Create Worktree]" on a Repository Project in panel, enter branch name, verify git worktree exists and project appears nested under parent

### Implementation for User Story 2

- [X] T026 [US2] Update `create.ts` to set `parent_project` from Repository Project's name in `home-modules/tools/i3pm-deno/src/commands/worktree/create.ts`
- [X] T027 [US2] Update `create.ts` to copy `bare_repo_path` from parent Repository Project in `home-modules/tools/i3pm-deno/src/commands/worktree/create.ts`
- [X] T028 [US2] Add branch existence check and offer `--checkout` option for existing branches in `home-modules/tools/i3pm-deno/src/commands/worktree/create.ts`
- [X] T029 [US2] Add error handling for failed git worktree creation (cleanup partial state) in `home-modules/tools/i3pm-deno/src/commands/worktree/create.ts`
- [X] T030 [P] [US2] Add "[+ Create Worktree]" button to Repository Project rows in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T031 [P] [US2] Create worktree creation dialog widget (branch name input) in `home-modules/desktop/eww-monitoring-panel.nix` (existing Feature 094 dialog reused)
- [X] T032 [US2] Wire dialog submission to execute worktree creation with Feature 097 fields in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T033 [US2] Panel refresh via deflisten stream (automatic via existing architecture, no explicit event needed)

**Checkpoint**: Creating worktrees from panel works end-to-end with correct parent linkage

---

## Phase 5: User Story 3 - View Repository with Worktree Hierarchy (Priority: P1)

**Goal**: Panel displays Repository Projects as expandable containers with Worktree Projects nested underneath

**Independent Test**: Register a Repository Project with 3 worktrees, verify panel shows hierarchy with expand/collapse, worktree count badge, and dirty bubble-up

### Implementation for User Story 3

- [X] T034 [US3] Update `monitoring_data.py` to call `detect_orphaned_worktrees()` and group projects by `bare_repo_path` in `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- [X] T035 [US3] Implement `get_projects_hierarchy()` returning `PanelProjectsData` structure in `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- [X] T036 [US3] Add `worktree_count` calculation per Repository Project in `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- [X] T037 [US3] Add `has_dirty` aggregation (bubble-up from worktrees to parent) in `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- [X] T038 [P] [US3] Create expandable repository container widget in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T039 [P] [US3] Create nested worktree row widget with indentation in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T040 [US3] Add worktree count badge "(N worktrees)" to collapsed repositories in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T041 [US3] Add dirty indicator (●) to worktree rows and bubble-up to parent in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T042 [US3] Add expand/collapse toggle (▼/►) with `is_expanded` state management in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T043 [P] [US3] Style hierarchy with indentation, borders, and Catppuccin Mocha colors in `home-modules/desktop/eww-monitoring-panel.nix`

**Checkpoint**: Panel displays correct hierarchical view with expand/collapse and status indicators

---

## Phase 6: User Story 4 - Delete Worktree from Panel (Priority: P1)

**Goal**: User can delete a worktree via panel button, which runs `i3pm worktree remove` and cleans up project registration

**Independent Test**: Select a Worktree Project, click delete, confirm, verify git worktree is removed and project disappears from panel

### Implementation for User Story 4

- [X] T044 [US4] Update worktree-delete script to delete project JSON after successful `git worktree remove` in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T045 [US4] Add `--force` flag handling for worktrees with uncommitted changes in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T046 [US4] Handle case where git worktree already removed (only cleanup project JSON) in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T047 [P] [US4] Add "[Delete]" button to Worktree Project rows in `home-modules/desktop/eww-monitoring-panel.nix` (existing button updated for Feature 097)
- [X] T048 [P] [US4] Deletion confirmation uses click-twice pattern in worktree-delete script (no modal dialog needed)
- [X] T049 [US4] Add dirty indicator badge and tooltip warning when worktree has uncommitted changes in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T050 [US4] Wire delete button to execute worktree-delete script with Feature 097 fields in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T051 [US4] Panel refresh via deflisten stream (automatic via existing architecture, no explicit event needed)

**Checkpoint**: Deleting worktrees from panel works with proper confirmation and cleanup

---

## Phase 7: User Story 5 - Switch to Project (Priority: P1)

**Goal**: User can switch workspace context to any project (Repository or Worktree) from the panel

**Independent Test**: Click on a Worktree Project and select [Switch], verify scoped apps now use that worktree's directory

### Implementation for User Story 5

- [X] T052 [P] [US5] Add "[Switch]" button to all project rows (Repository, Worktree, Standalone) in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T053 [US5] Wire button click to execute `i3pm project switch <name>` via `switch-project-action` script in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T054 [US5] Add visual highlight for currently active project in hierarchy in `home-modules/desktop/eww-monitoring-panel.nix` (already exists: `.active-project` class)
- [X] T055 [US5] Update `active_project` in panel data stream from daemon in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` (already exists)

**Checkpoint**: Switching between projects works from panel with visual feedback

---

## Phase 8: User Story 6 - Refresh Git Metadata (Priority: P2)

**Goal**: User can refresh git metadata to see updated commit hashes and status indicators

**Independent Test**: Make a commit in a worktree, click [Refresh], verify commit hash updates in panel

### Implementation for User Story 6

**Note**: Implemented as `project-refresh` shell script instead of Deno CLI command for simpler integration with Eww panel buttons.

- [X] T056 [US6] Implement `project-refresh --all` script in `home-modules/desktop/eww-monitoring-panel.nix` (projectRefreshScript)
- [X] T057 [US6] Implement `project-refresh <name>` for single project refresh in `home-modules/desktop/eww-monitoring-panel.nix` (projectRefreshScript)
- [X] T058 [US6] Script reads project JSON directly and updates git_metadata field (no daemon RPC needed)
- [X] T059 [US6] Extract git metadata (branch, commit, clean/dirty, ahead/behind) using git commands in refresh script
- [X] T060 [P] [US6] Add "[⟳ Refresh]" button to Repository Projects in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T061 [P] [US6] Add "[⟳ All]" button to Projects tab header in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T062 [US6] Wire refresh buttons to `project-refresh` script in `home-modules/desktop/eww-monitoring-panel.nix`

**Checkpoint**: Git metadata refreshes correctly with updated values shown in panel

---

## Phase 9: User Story 7 - Handle Orphaned Worktrees (Priority: P2)

**Goal**: Orphaned worktrees (parent Repository Project missing) are shown in a separate section with recovery options

**Independent Test**: Delete a Repository Project, verify its worktrees appear in "Orphaned Worktrees" section with [Recover] button

**Note**: Implemented using shell scripts instead of daemon RPC for simpler integration.

### Implementation for User Story 7

- [X] T063 [US7] `get_projects_hierarchy()` already populates `orphaned_worktrees` list via `detect_orphaned_worktrees()` in `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- [X] T064 [US7] Add "Orphaned Worktrees" section to Projects tab in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T065 [US7] Add warning icon (⚠), hint text, and "no parent" label to orphan cards in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T066 [US7] Add "[🔧 Recover]" button to orphan cards in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T067 [US7] Implement `orphan-recover` script to create Repository Project from bare_repo_path in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T068 [US7] Wire [Recover] button to `orphan-recover` script in `home-modules/desktop/eww-monitoring-panel.nix`
- [X] T069 [US7] Add "[Delete]" button with click-twice confirmation for removing orphan registrations in `home-modules/desktop/eww-monitoring-panel.nix`

**Checkpoint**: Orphaned worktrees are detected, displayed, and recoverable

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T070 [P] Add `i3pm project list --hierarchy` command with tree output format in `home-modules/tools/i3pm-deno/src/commands/project.ts`
- [X] T071 [P] Add `i3pm project list --json` output for scripting in `home-modules/tools/i3pm-deno/src/commands/project.ts`
- [X] T072 [P] Error message formatting already exists in `home-modules/tools/i3pm-deno/src/utils/errors.ts`
- [X] T073 Workflows documented in tasks.md checkpoint sections
- [X] T074 Update CLAUDE.md - Feature 097 documentation already integrated in CLAUDE.md (see "Active Technologies" section)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-9)**: All depend on Foundational phase completion
  - P1 stories (US1-US5) are core functionality
  - P2 stories (US6-US7) enhance the experience
- **Polish (Phase 10)**: Can run after core stories (US1-US5) complete

### User Story Dependencies

```
Phase 1: Setup (T001-T005)
    │
    ▼
Phase 2: Foundational (T006-T014) ← CRITICAL GATE
    │
    ├──────────────────────────────────────────────────────────────┐
    │                                                               │
    ▼                                                               ▼
User Story 1: Discover (T015-T025)                           User Story 3: Hierarchy (T034-T043)
    │                                                               │
    ▼                                                               │
User Story 2: Create Worktree (T026-T033)                          │
    │                                                               │
    ├───────────────────────────────────────────────────────────────┤
    │                                                               │
    ▼                                                               ▼
User Story 4: Delete Worktree (T044-T051)              User Story 5: Switch (T052-T055)
    │
    ├──────────────────────────────────────────────────────────────┐
    │                                                               │
    ▼                                                               ▼
User Story 6: Refresh (T056-T062)                    User Story 7: Orphans (T063-T069)
    │
    ▼
Phase 10: Polish (T070-T074)
```

**Notes**:
- US1 (Discover) must complete before US2 (Create Worktree) to have Repository Projects to create worktrees from
- US3 (Hierarchy) can run in parallel with US1
- US4 (Delete) requires US2 to have worktrees to delete
- US5 (Switch) can run in parallel once hierarchy exists
- US6, US7 are P2 and can run after core stories

### Parallel Opportunities

**Phase 1 (Setup)**: All tasks T001-T005 can run in parallel

**Phase 2 (Foundational)**: T010-T011 (TypeScript) can run in parallel with T006-T009 (Python)

**User Story Phases**: Tasks marked [P] within each story can run in parallel

---

## Parallel Example: User Story 3 (Hierarchy)

```bash
# Launch all parallel tasks for User Story 3 together:
Task T038: "Create expandable repository container widget in eww.yuck"
Task T039: "Create nested worktree row widget with indentation in eww.yuck"
Task T043: "Style hierarchy with indentation, borders, and Catppuccin Mocha colors in eww.scss"

# Then sequential tasks:
Task T034-T037: Python monitoring_data.py updates (sequential)
Task T040-T042: Eww widget integration (sequential after T038-T039)
```

---

## Implementation Strategy

### MVP First (User Stories 1, 3, 5 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete User Story 1: Discover (creates projects with correct types)
4. Complete User Story 3: Hierarchy (displays the grouping)
5. Complete User Story 5: Switch (enables navigation)
6. **STOP and VALIDATE**: Test discovery → view hierarchy → switch workflow
7. Deploy/demo if ready - this is a functional MVP

### Full P1 Delivery

1. MVP above (US1, US3, US5)
2. Add User Story 2: Create Worktree (from UI)
3. Add User Story 4: Delete Worktree (from UI)
4. **VALIDATE**: Full CRUD workflow via panel

### Complete Feature

1. Full P1 delivery above
2. Add User Story 6: Refresh (P2)
3. Add User Story 7: Orphans (P2)
4. Complete Polish phase
5. Final validation against quickstart.md

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence

## Task Metrics

- **Total tasks**: 74
- **Phase 1 (Setup)**: 5 tasks
- **Phase 2 (Foundational)**: 9 tasks
- **User Story 1 (Discover)**: 11 tasks
- **User Story 2 (Create Worktree)**: 8 tasks
- **User Story 3 (Hierarchy)**: 10 tasks
- **User Story 4 (Delete Worktree)**: 8 tasks
- **User Story 5 (Switch)**: 4 tasks
- **User Story 6 (Refresh)**: 7 tasks
- **User Story 7 (Orphans)**: 7 tasks
- **Phase 10 (Polish)**: 5 tasks
- **Parallel tasks**: 27 (marked with [P])
- **Suggested MVP**: US1 + US3 + US5 (25 tasks for minimal viable hierarchy view)
