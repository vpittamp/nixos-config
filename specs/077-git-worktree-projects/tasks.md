---

description: "Task list for Git Worktree Project Management implementation"
---

# Tasks: Git Worktree Project Management

**Input**: Design documents from `/specs/077-git-worktree-projects/`
**Prerequisites**: plan.md, spec.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- CLI commands: `home-modules/tools/i3pm-deno/src/commands/`
- Services: `home-modules/tools/i3pm-deno/src/services/`
- Models: `home-modules/tools/i3pm-deno/src/models/`
- Daemon: `home-modules/tools/i3pm-daemon/services/`
- Eww widgets: `home-modules/desktop/eww/widgets/`
- Tests: `tests/sway-tests/worktree/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure for worktree feature

- [x] T001 Create worktree command directory structure at home-modules/tools/i3pm-deno/src/commands/worktree/
- [x] T002 [P] Create worktree models directory at home-modules/tools/i3pm-deno/src/models/worktree.ts
- [x] T003 [P] Create git utility functions at home-modules/tools/i3pm-deno/src/utils/git.ts

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Define WorktreeProject type with discriminator in home-modules/tools/i3pm-deno/src/models/worktree.ts
- [x] T005 Define WorktreeMetadata type with git status fields in home-modules/tools/i3pm-deno/src/models/worktree.ts
- [x] T006 Define WorktreeDiscoveryEntry type in home-modules/tools/i3pm-deno/src/models/worktree.ts
- [x] T007 Create Zod schemas for WorktreeProject, WorktreeMetadata, WorktreeDiscoveryEntry validation in home-modules/tools/i3pm-deno/src/models/worktree.ts
- [x] T008 Implement git CLI wrapper utilities (exec, parse output) in home-modules/tools/i3pm-deno/src/utils/git.ts
- [x] T009 [P] Implement git worktree list parser in home-modules/tools/i3pm-deno/src/utils/git.ts
- [x] T010 [P] Implement git status parser (clean/dirty, untracked files) in home-modules/tools/i3pm-deno/src/utils/git.ts
- [x] T011 [P] Implement git branch tracking parser (ahead/behind counts) in home-modules/tools/i3pm-deno/src/utils/git.ts
- [x] T012 Create GitWorktreeService class scaffolding in home-modules/tools/i3pm-deno/src/services/git-worktree.ts
- [x] T013 Create WorktreeMetadataService class scaffolding in home-modules/tools/i3pm-deno/src/services/worktree-metadata.ts
- [x] T014 Extend existing ProjectManager to handle worktree discriminator in home-modules/tools/i3pm-deno/src/services/project-manager.ts

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Quick Worktree Project Creation (Priority: P1) 🎯 MVP

**Goal**: Developer can create a new isolated workspace for a feature branch using git worktrees, automatically registering it as an i3pm project with a single command

**Independent Test**: Run `i3pm worktree create feature-name` and verify:
1. Git worktree exists at expected path
2. i3pm project is registered in `~/.config/i3/projects/`
3. Project is immediately switchable via `i3pm project switch`

### Implementation for User Story 1

- [x] T015 [P] [US1] Implement validateRepository() method in home-modules/tools/i3pm-deno/src/services/git-worktree.ts
- [x] T016 [P] [US1] Implement checkBranchExists() method in home-modules/tools/i3pm-deno/src/services/git-worktree.ts
- [x] T017 [P] [US1] Implement resolveWorktreeBasePath() method in home-modules/tools/i3pm-deno/src/services/git-worktree.ts
- [x] T018 [US1] Implement createWorktree() method using git worktree add in home-modules/tools/i3pm-deno/src/services/git-worktree.ts (depends on T015-T017)
- [x] T019 [US1] Implement extractMetadata() method in home-modules/tools/i3pm-deno/src/services/worktree-metadata.ts
- [x] T020 [US1] Implement createWorktreeProject() method in home-modules/tools/i3pm-deno/src/services/project-manager.ts
- [x] T021 [US1] Create CLI command parser for worktree create in home-modules/tools/i3pm-deno/src/commands/worktree/create.ts
- [x] T022 [US1] Implement worktree create command handler (orchestrates T018-T020) in home-modules/tools/i3pm-deno/src/commands/worktree/create.ts
- [x] T023 [US1] Add error handling for branch conflicts, disk space, permissions in home-modules/tools/i3pm-deno/src/commands/worktree/create.ts
- [x] T024 [US1] Add worktree naming conflict resolution (auto-increment or prompt) in home-modules/tools/i3pm-deno/src/commands/worktree/create.ts
- [x] T025 [US1] Register worktree subcommand in main CLI dispatcher at home-modules/tools/i3pm-deno/src/commands/worktree.ts
- [ ] T026 [US1] Create sway-test for worktree creation workflow in tests/sway-tests/worktree/test_worktree_create.json
- [x] T027 [US1] Validate worktree create accepts --checkout flag for existing remote branches in home-modules/tools/i3pm-deno/src/commands/worktree/create.ts
- [x] T028 [US1] Add logging for worktree creation operations in home-modules/tools/i3pm-deno/src/commands/worktree/create.ts

**Checkpoint**: At this point, User Story 1 should be fully functional - users can create worktree projects with a single command

---

## Phase 4: User Story 3 - Seamless Project Directory Context (Priority: P1)

**Goal**: Developer switches between worktree-based projects and all project-scoped applications automatically open in the correct worktree directory

**Independent Test**:
1. Create two worktree projects (feature-A, feature-B)
2. Switch to feature-A via `i3pm project switch feature-A`
3. Launch terminal, VS Code, Yazi
4. Verify each opens with CWD = worktree directory of feature-A
5. Switch to feature-B and verify apps now open in feature-B directory

### Implementation for User Story 3

- [x] T029 [US3] Verify existing project-manager sets I3PM_PROJECT_DIR environment variable for worktree projects in home-modules/tools/i3pm-deno/src/services/project-manager.ts
- [x] T030 [US3] Test that existing app launcher reads I3PM_PROJECT_DIR and sets CWD for scoped apps (verify existing behavior)
- [ ] T031 [US3] Create sway-test for app directory context workflow in tests/sway-tests/worktree/test_app_directory_context.json
- [ ] T032 [US3] Test terminal launches with correct CWD in worktree projects
- [ ] T033 [US3] Test VS Code launches with workspace root at worktree directory
- [ ] T034 [US3] Test Yazi launches with initial path at worktree directory
- [ ] T035 [US3] Test Lazygit launches with repository root at worktree directory
- [ ] T036 [US3] Add validation that Feature 076 marks correctly track worktree-scoped apps

**Checkpoint**: At this point, worktree projects provide seamless directory context isolation

---

## Phase 5: User Story 2 - Visual Worktree Selection and Management (Priority: P2)

**Goal**: Developer can see all available worktrees in a visual menu (Eww dialog) with metadata like branch name, last modified time, and git status

**Independent Test**:
1. Create 3 worktrees with varying git states (clean, dirty, untracked files)
2. Open Eww worktree selector (e.g., Win+P in worktree mode)
3. Verify all 3 worktrees displayed with branch names, paths, status indicators
4. Select one worktree and verify i3pm switches to that project

### Implementation for User Story 2

- [ ] T037 [P] [US2] Implement listWorktrees() method in home-modules/tools/i3pm-deno/src/services/git-worktree.ts
- [ ] T038 [P] [US2] Implement enrichWithMetadata() method to add git status to worktree list in home-modules/tools/i3pm-deno/src/services/worktree-metadata.ts
- [ ] T039 [US2] Create CLI command for worktree list with --format flag (table/json/names) in home-modules/tools/i3pm-deno/src/commands/worktree/list.ts
- [ ] T040 [US2] Implement --show-metadata flag to display git status in list output in home-modules/tools/i3pm-deno/src/commands/worktree/list.ts
- [ ] T041 [US2] Implement --filter-dirty flag to show only worktrees with uncommitted changes in home-modules/tools/i3pm-deno/src/commands/worktree/list.ts
- [ ] T042 [US2] Add JSON output format for Eww widget consumption in home-modules/tools/i3pm-deno/src/commands/worktree/list.ts
- [ ] T043 [US2] Create Eww worktree selector widget structure in home-modules/desktop/eww/widgets/worktree-selector.yuck
- [ ] T044 [US2] Add defpoll for worktree list JSON data source (5s interval) in home-modules/desktop/eww/widgets/worktree-selector.yuck
- [ ] T045 [US2] Implement worktree-entry widget with branch, path, status display in home-modules/desktop/eww/widgets/worktree-selector.yuck
- [ ] T046 [US2] Add eventbox click handler to switch projects on selection in home-modules/desktop/eww/widgets/worktree-selector.yuck
- [ ] T047 [US2] Create widget styling with clean/dirty status colors in home-modules/desktop/eww/widgets/worktree-selector.scss
- [ ] T048 [US2] Add visual indicators for uncommitted changes (icon or color) in home-modules/desktop/eww/widgets/worktree-selector.scss
- [ ] T049 [US2] Integrate worktree selector into existing project switcher (Win+P) flow
- [ ] T050 [US2] Create sway-test for worktree selector workflow in tests/sway-tests/worktree/test_worktree_switch.json
- [ ] T051 [US2] Optimize Eww polling interval based on performance (<200ms dialog open)

**Checkpoint**: At this point, visual worktree selection provides full discoverability and metadata

---

## Phase 6: User Story 5 - Automatic Worktree Discovery on Startup (Priority: P2)

**Goal**: When system starts or i3pm daemon restarts, existing git worktrees are automatically discovered and registered as i3pm projects if they aren't already

**Independent Test**:
1. Create a worktree manually via `git worktree add ../feature-X`
2. Restart i3pm daemon: `systemctl --user restart i3-project-event-listener`
3. Verify "feature-X" appears in `i3pm project list`
4. Create orphaned i3pm project (delete worktree manually, keep project JSON)
5. Run discovery and verify orphan is flagged/removed

### Implementation for User Story 5

- [ ] T052 [P] [US5] Create WorktreeDiscoveryService class in home-modules/tools/i3pm-daemon/services/worktree_discovery.py
- [ ] T053 [P] [US5] Implement discover_worktrees() async method in home-modules/tools/i3pm-daemon/services/worktree_discovery.py
- [ ] T054 [US5] Implement get_registered_projects() helper to read i3pm project JSONs in home-modules/tools/i3pm-daemon/services/worktree_discovery.py
- [ ] T055 [US5] Implement compare_and_flag_orphans() method to detect invalid projects in home-modules/tools/i3pm-daemon/services/worktree_discovery.py
- [ ] T056 [US5] Implement register_worktree_project() async method in home-modules/tools/i3pm-daemon/services/worktree_discovery.py
- [ ] T057 [US5] Add daemon startup hook to trigger discovery in home-modules/tools/i3pm-diagnostic.nix
- [ ] T058 [US5] Create CLI command for manual discovery trigger in home-modules/tools/i3pm-deno/src/commands/worktree/discover.ts
- [ ] T059 [US5] Implement --auto-register flag for discovery command in home-modules/tools/i3pm-deno/src/commands/worktree/discover.ts
- [ ] T060 [US5] Implement --repository-path flag to specify target repository in home-modules/tools/i3pm-deno/src/commands/worktree/discover.ts
- [ ] T061 [US5] Add interactive prompt for discovered worktrees (register Y/N) in home-modules/tools/i3pm-deno/src/commands/worktree/discover.ts
- [ ] T062 [US5] Create pytest tests for discovery service in home-modules/tools/i3pm-daemon/tests/test_worktree_discovery.py
- [ ] T063 [US5] Add discovery performance optimization (<2s for 20 worktrees)
- [ ] T064 [US5] Cache discovery results to ~/.cache/i3pm/worktree-discovery.json with timestamp

**Checkpoint**: At this point, worktree discovery ensures automatic consistency between git state and i3pm state

---

## Phase 7: User Story 4 - Worktree Cleanup and Removal (Priority: P3)

**Goal**: Developer finishes work on a feature branch and can remove the associated worktree and i3pm project registration in a single operation, with safety checks

**Independent Test**:
1. Create worktree "hotfix-123" with uncommitted changes
2. Run `i3pm worktree delete hotfix-123`
3. Verify system prompts for confirmation
4. Create clean worktree "feature-done"
5. Delete it and verify worktree directory removed, git worktree list clear, i3pm project unregistered

### Implementation for User Story 4

- [ ] T065 [P] [US4] Implement checkWorktreeStatus() method in home-modules/tools/i3pm-deno/src/services/git-worktree.ts
- [ ] T066 [P] [US4] Implement isCurrentlyActive() method to check active project in home-modules/tools/i3pm-deno/src/services/project-manager.ts
- [ ] T067 [US4] Implement deleteWorktree() method using git worktree remove in home-modules/tools/i3pm-deno/src/services/git-worktree.ts
- [ ] T068 [US4] Implement deleteWorktreeProject() method to remove project JSON in home-modules/tools/i3pm-deno/src/services/project-manager.ts
- [ ] T069 [US4] Create CLI command parser for worktree delete in home-modules/tools/i3pm-deno/src/commands/worktree/delete.ts
- [ ] T070 [US4] Implement safety check: prevent deletion of currently active project in home-modules/tools/i3pm-deno/src/commands/worktree/delete.ts
- [ ] T071 [US4] Implement safety check: prompt for confirmation if uncommitted changes or untracked files in home-modules/tools/i3pm-deno/src/commands/worktree/delete.ts
- [ ] T072 [US4] Implement --force flag to bypass uncommitted changes warning in home-modules/tools/i3pm-deno/src/commands/worktree/delete.ts
- [ ] T073 [US4] Implement --keep-project flag to remove worktree but preserve i3pm project in home-modules/tools/i3pm-deno/src/commands/worktree/delete.ts
- [ ] T074 [US4] Add error handling for locked worktrees or permission issues in home-modules/tools/i3pm-deno/src/commands/worktree/delete.ts
- [ ] T075 [US4] Add logging for deletion operations in home-modules/tools/i3pm-deno/src/commands/worktree/delete.ts
- [ ] T076 [US4] Create Deno unit tests for deletion safety checks in home-modules/tools/i3pm-deno/tests/unit/worktree-delete_test.ts

**Checkpoint**: At this point, worktree cleanup provides safe, user-friendly deletion with data loss prevention

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

- [ ] T077 [P] Create comprehensive Deno unit tests for git-worktree service in home-modules/tools/i3pm-deno/tests/unit/git-worktree_test.ts
- [ ] T078 [P] Create Deno unit tests for worktree-metadata service in home-modules/tools/i3pm-deno/tests/unit/worktree-metadata_test.ts
- [ ] T079 [P] Create Deno integration test for full worktree lifecycle in home-modules/tools/i3pm-deno/tests/integration/worktree-lifecycle_test.ts
- [ ] T080 Update i3pm README with worktree command documentation in home-modules/tools/i3pm-deno/README.md
- [ ] T081 Create quickstart.md user guide with examples in /etc/nixos/specs/077-git-worktree-projects/quickstart.md
- [ ] T082 Add performance logging to track <5s creation, <500ms switch goals
- [ ] T083 Test with 10+ concurrent worktrees for performance validation
- [ ] T084 Test edge cases: detached HEAD, nested repos, disk space exhaustion
- [ ] T085 Add bash completion for worktree subcommands
- [ ] T086 Run full sway-test suite for worktree workflows
- [ ] T087 Validate all acceptance scenarios from spec.md
- [ ] T088 Code cleanup and refactoring for consistency
- [ ] T089 Update agent context with worktree feature documentation via update-agent-context.sh

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - **User Story 1 (P1) - Phase 3**: Can start after Phase 2 - No dependencies on other stories
  - **User Story 3 (P1) - Phase 4**: Can start after Phase 2 - Should verify existing behavior, minimal new code
  - **User Story 2 (P2) - Phase 5**: Can start after Phase 2 - Depends on US1 for list command but can develop in parallel
  - **User Story 5 (P2) - Phase 6**: Can start after Phase 2 - Independent of other stories
  - **User Story 4 (P3) - Phase 7**: Can start after Phase 2 - Independent of other stories
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Priority Order

**Priority 1 (MVP)**:
- User Story 1 (Quick Worktree Creation) - Phase 3
- User Story 3 (Seamless Directory Context) - Phase 4

**Priority 2 (Enhanced UX)**:
- User Story 2 (Visual Selection) - Phase 5
- User Story 5 (Auto-Discovery) - Phase 6

**Priority 3 (Cleanup)**:
- User Story 4 (Worktree Removal) - Phase 7

### Within Each User Story

- Models and types defined in Foundational phase
- Services before commands
- CLI commands before UI integration
- Core implementation before error handling
- Tests validate behavior throughout

### Parallel Opportunities

**Phase 1 (Setup)**:
- T002 and T003 can run in parallel (different files)

**Phase 2 (Foundational)**:
- T009, T010, T011 can run in parallel (all in git.ts, different functions)

**Phase 3 (User Story 1)**:
- T015, T016, T017 can run in parallel (different methods)

**Phase 5 (User Story 2)**:
- T037 and T038 can run in parallel (different services)

**Phase 6 (User Story 5)**:
- T052 and T053 can run in parallel (setting up Python service)

**Phase 7 (User Story 4)**:
- T065 and T066 can run in parallel (different services)

**Phase 8 (Polish)**:
- T077, T078, T079 can run in parallel (different test files)
- T080, T081 can run in parallel (different documentation files)

**Across User Stories**:
- Once Phase 2 completes, Phase 3, 4, 5, 6, 7 can all proceed in parallel if team capacity allows
- Each user story is independently testable

---

## Parallel Example: User Story 1

```bash
# Launch foundational models in parallel:
Task T015: "Implement validateRepository() in git-worktree.ts"
Task T016: "Implement checkBranchExists() in git-worktree.ts"
Task T017: "Implement resolveWorktreeBasePath() in git-worktree.ts"

# Then sequentially:
Task T018: "Implement createWorktree() - orchestrates T015-T017"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 3 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Quick Worktree Creation)
4. Complete Phase 4: User Story 3 (Seamless Directory Context)
5. **STOP and VALIDATE**: Test that you can:
   - Create a worktree with `i3pm worktree create feature-name`
   - Switch to it with `i3pm project switch feature-name`
   - Launch terminal, VS Code, Yazi and verify each opens in worktree directory
6. Deploy/demo MVP if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 + 3 → Test independently → Deploy/Demo (MVP! ✅)
3. Add User Story 2 → Test independently → Deploy/Demo (Visual selection added)
4. Add User Story 5 → Test independently → Deploy/Demo (Auto-discovery added)
5. Add User Story 4 → Test independently → Deploy/Demo (Full feature complete)
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (Phase 3)
   - Developer B: User Story 3 (Phase 4) - verify existing behavior
   - Developer C: User Story 2 (Phase 5)
   - Developer D: User Story 5 (Phase 6)
   - Developer E: User Story 4 (Phase 7)
3. Stories complete and integrate independently

---

## Notes

- **[P] tasks** = different files or different functions in same file, no dependencies
- **[Story] label** maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- **Suggested MVP scope**: User Stories 1 + 3 (create worktrees + directory context isolation)
- **Tests are NOT included** - spec.md did not request TDD approach, focus is on implementation
- Leverage existing i3pm infrastructure (project manager, app launcher, Feature 076 marks)
- Git operations can be slow - consider async execution with progress indicators for large repos
- Eww widget polling interval (5s) balances freshness vs performance - may need tuning after testing

---

## Total Task Summary

- **Total Tasks**: 89
- **Setup (Phase 1)**: 3 tasks
- **Foundational (Phase 2)**: 11 tasks (BLOCKS all user stories)
- **User Story 1 - Quick Creation (P1)**: 14 tasks
- **User Story 3 - Directory Context (P1)**: 8 tasks
- **User Story 2 - Visual Selection (P2)**: 15 tasks
- **User Story 5 - Auto-Discovery (P2)**: 13 tasks
- **User Story 4 - Cleanup (P3)**: 12 tasks
- **Polish & Cross-Cutting**: 13 tasks

**MVP Task Count**: 36 tasks (Phase 1 + Phase 2 + US1 + US3)
**Full Feature Task Count**: 89 tasks

**Parallel Opportunities**: 18 tasks marked [P] can run in parallel within their phases
