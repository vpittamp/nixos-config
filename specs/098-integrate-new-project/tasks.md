# Tasks: Worktree-Aware Project Environment Integration

**Input**: Design documents from `/specs/098-integrate-new-project/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ipc-methods.md, quickstart.md

**Tests**: Tests are NOT explicitly requested in the feature specification. Implementation tasks only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md project structure:
- **Daemon source**: `home-modules/desktop/i3-project-event-daemon/`
- **Models**: `home-modules/desktop/i3-project-event-daemon/models/`
- **Services**: `home-modules/desktop/i3-project-event-daemon/services/`
- **Scripts**: `scripts/`

---

## Phase 1: Setup

**Purpose**: Add new model and extend existing models for branch metadata support

- [X] T001 [P] Create BranchMetadata model in home-modules/desktop/i3-project-event-daemon/models/discovery.py
- [X] T002 [P] Add parent_project and branch_metadata fields to Project model in home-modules/desktop/i3-project-event-daemon/models/project.py
- [X] T003 Add parse_branch_metadata() function in home-modules/desktop/i3-project-event-daemon/models/discovery.py

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core parsing and resolution logic that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement 5-pattern branch name parser (number-type-desc, type-number-desc, number-desc, type-desc, standard) in home-modules/desktop/i3-project-event-daemon/models/discovery.py
- [X] T005 Add parent project name resolution in discovery phase using find_by_directory() in home-modules/desktop/i3-project-event-daemon/services/project_service.py:_create_from_discovery()
- [X] T006 Extend WorktreeEnvironment.from_project() factory method in home-modules/desktop/i3-project-event-daemon/models/worktree_environment.py

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Automatic Worktree Environment Context (Priority: P1)

**Goal**: Developers switching to a worktree project receive complete environment context (parent, branch number, branch type, full branch name) in all launched applications

**Independent Test**: Switch to a worktree project, launch a terminal, verify `echo $I3PM_IS_WORKTREE $I3PM_PARENT_PROJECT $I3PM_BRANCH_NUMBER $I3PM_BRANCH_TYPE $I3PM_FULL_BRANCH_NAME` shows correct values

### Implementation for User Story 1

- [X] T007 [US1] Extend app-launcher-wrapper.sh to inject I3PM_IS_WORKTREE variable in scripts/app-launcher-wrapper.sh
- [X] T008 [US1] Extend app-launcher-wrapper.sh to inject I3PM_PARENT_PROJECT variable (conditional on not null) in scripts/app-launcher-wrapper.sh
- [X] T009 [US1] Extend app-launcher-wrapper.sh to inject I3PM_BRANCH_NUMBER variable (conditional on not null) in scripts/app-launcher-wrapper.sh
- [X] T010 [US1] Extend app-launcher-wrapper.sh to inject I3PM_BRANCH_TYPE variable (conditional on not null) in scripts/app-launcher-wrapper.sh
- [X] T011 [US1] Extend app-launcher-wrapper.sh to inject I3PM_FULL_BRANCH_NAME variable in scripts/app-launcher-wrapper.sh
- [X] T012 [US1] Update project.current IPC response to include parent_project and branch_metadata in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T013 [US1] Update project.switch IPC response to include parent_project and branch_metadata in home-modules/desktop/i3-project-event-daemon/ipc_server.py

**Checkpoint**: User Story 1 complete - terminals in worktree projects have complete worktree identity environment variables

---

## Phase 4: User Story 2 - Project Directory Association (Priority: P1)

**Goal**: All launched applications automatically use the correct working directory for the active project

**Independent Test**: Switch to a project, launch a terminal, verify `pwd` shows the project directory

### Implementation for User Story 2

- [X] T014 [US2] Verify app-launcher-wrapper.sh uses I3PM_PROJECT_DIR for CWD (existing functionality) in scripts/app-launcher-wrapper.sh
- [X] T015 [US2] Ensure project directory is correctly populated from Project model during switch in home-modules/desktop/i3-project-event-daemon/services/project_service.py

**Checkpoint**: User Story 2 complete - application CWD matches project directory

---

## Phase 5: User Story 3 - Branch Metadata Extraction and Storage (Priority: P2)

**Goal**: Branch metadata (number, type, full name) automatically extracted and persisted during project discovery

**Independent Test**: Run `i3pm discover`, check project JSON files contain branch_metadata fields with correct parsed values

### Implementation for User Story 3

- [X] T016 [US3] Integrate parse_branch_metadata() into discovery flow in home-modules/desktop/i3-project-event-daemon/services/discovery_service.py
- [X] T017 [US3] Store branch_metadata in project JSON during _create_from_discovery() in home-modules/desktop/i3-project-event-daemon/services/project_service.py
- [X] T018 [US3] Add branch_metadata to Project.save_to_file() serialization in home-modules/desktop/i3-project-event-daemon/models/project.py
- [X] T019 [US3] Add branch_metadata to Project.load_from_file() deserialization in home-modules/desktop/i3-project-event-daemon/models/project.py

**Checkpoint**: User Story 3 complete - discovery creates projects with parsed branch metadata

---

## Phase 6: User Story 4 - Parent Project Linking (Priority: P2)

**Goal**: Worktree projects maintain a reference to their parent repository project by name

**Independent Test**: Create a worktree from a parent repo, run discovery, verify worktree project JSON has parent_project field set to parent's name

### Implementation for User Story 4

- [X] T020 [US4] Resolve parent_repo_path to parent project name using find_by_directory() in home-modules/desktop/i3-project-event-daemon/services/project_service.py:_create_from_discovery()
- [X] T021 [US4] Store parent_project name in project JSON in home-modules/desktop/i3-project-event-daemon/services/project_service.py
- [X] T022 [US4] Implement worktree.list IPC method in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T023 [US4] Add CLI command `i3pm worktree list <parent>` in home-modules/tools/i3pm-deno/src/commands/worktree.ts

**Checkpoint**: User Story 4 complete - worktrees linked to parents, can list all worktrees for a parent

---

## Phase 7: User Story 5 - Git Metadata Environment Variables (Priority: P3)

**Goal**: Launched applications receive git-related environment variables (branch, commit, clean status, ahead/behind)

**Independent Test**: Launch a terminal in a project with uncommitted changes, verify `echo $I3PM_GIT_IS_CLEAN` shows "false"

### Implementation for User Story 5

- [X] T024 [P] [US5] Extend app-launcher-wrapper.sh to inject I3PM_GIT_BRANCH variable (conditional on not null) in scripts/app-launcher-wrapper.sh
- [X] T025 [P] [US5] Extend app-launcher-wrapper.sh to inject I3PM_GIT_COMMIT variable (conditional on not null) in scripts/app-launcher-wrapper.sh
- [X] T026 [P] [US5] Extend app-launcher-wrapper.sh to inject I3PM_GIT_IS_CLEAN variable as "true"/"false" (conditional on not null) in scripts/app-launcher-wrapper.sh
- [X] T027 [P] [US5] Extend app-launcher-wrapper.sh to inject I3PM_GIT_AHEAD variable (conditional on not null) in scripts/app-launcher-wrapper.sh
- [X] T028 [P] [US5] Extend app-launcher-wrapper.sh to inject I3PM_GIT_BEHIND variable (conditional on not null) in scripts/app-launcher-wrapper.sh

**Checkpoint**: User Story 5 complete - applications have git metadata environment variables

---

## Phase 8: Status Validation & Refresh (FR-008, FR-009)

**Purpose**: Prevent switching to missing projects, enable metadata refresh without full discovery

- [X] T029 Add project status validation to _switch_project() in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T030 Return error code -32001 with actionable message for missing projects in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T031 Implement project.refresh IPC method in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T032 Add refresh() method to ProjectService to re-extract git and branch metadata in home-modules/desktop/i3-project-event-daemon/services/project_service.py
- [X] T033 Add CLI command `i3pm project refresh <name>` in home-modules/tools/i3pm-deno/src/commands/project.ts

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and cleanup

- [X] T034 [P] Validate quickstart.md scenarios manually (switch to worktree, check env vars)
- [X] T035 [P] Update CLAUDE.md with Feature 098 documentation section
- [X] T036 Run existing i3pm tests to ensure no regressions (all Python syntax checks pass, 12 tests pass)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational (Phase 2) completion
  - US1 and US2 can run in parallel (both P1, no cross-dependencies)
  - US3 can start after Phase 2 (P2, no US1/US2 dependency)
  - US4 can start after Phase 2 (P2, no US1/US2/US3 dependency)
  - US5 can start after Phase 2 (P3, no other US dependencies)
- **Status Validation (Phase 8)**: Can run in parallel with user stories
- **Polish (Phase 9)**: Depends on all previous phases

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Depends on Foundational - No dependencies on other stories (US1 and US2 parallel)
- **User Story 3 (P2)**: Depends on Foundational - Independent of US1/US2
- **User Story 4 (P2)**: Depends on Foundational - Independent of other stories
- **User Story 5 (P3)**: Depends on Foundational - Independent of other stories

### Within Each User Story

- Models/extensions before services
- Services before IPC handlers
- IPC handlers before CLI/scripts
- Core implementation before integration

### Parallel Opportunities

- T001, T002 can run in parallel (different model files)
- T007-T011 can run in parallel (same file but different variables - may need coordination)
- T024-T028 can run in parallel (same file but different variables - may need coordination)
- US1 and US2 can be worked on in parallel after Foundational phase
- US3, US4, US5 can all be worked on in parallel after Foundational phase

---

## Parallel Example: User Story 1

```bash
# Once Foundational phase complete, launch US1 tasks:
Task: "Extend app-launcher-wrapper.sh to inject I3PM_IS_WORKTREE variable"
Task: "Extend app-launcher-wrapper.sh to inject I3PM_PARENT_PROJECT variable"
Task: "Extend app-launcher-wrapper.sh to inject I3PM_BRANCH_NUMBER variable"
Task: "Extend app-launcher-wrapper.sh to inject I3PM_BRANCH_TYPE variable"
Task: "Extend app-launcher-wrapper.sh to inject I3PM_FULL_BRANCH_NAME variable"
# Note: These modify the same file so require coordination
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T006)
3. Complete Phase 3: User Story 1 (T007-T013) - Worktree environment context
4. Complete Phase 4: User Story 2 (T014-T015) - Project directory association
5. **STOP and VALIDATE**: Test by switching to worktree project, launching terminal, checking env vars
6. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 + 2 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 3 → Test discovery → Deploy/Demo
4. Add User Story 4 → Test parent linking → Deploy/Demo
5. Add User Story 5 → Test git metadata → Deploy/Demo
6. Add Phase 8 → Test validation/refresh → Deploy/Demo
7. Each story adds value without breaking previous stories

### Recommended Single Developer Order

Given all user stories are independent after Foundational:

1. Phase 1 → Phase 2 (sequential, blocking)
2. Phase 3 (US1) + Phase 4 (US2) together (both P1, high value)
3. Phase 5 (US3) - discovery integration
4. Phase 6 (US4) - parent linking
5. Phase 7 (US5) - git metadata
6. Phase 8 - validation/refresh
7. Phase 9 - polish

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Grace handling: missing fields MUST be omitted (not set to empty string)
- All environment variable injection conditional on field presence (per contracts/ipc-methods.md)
