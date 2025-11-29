# Tasks: Structured Git Repository Management

**Input**: Design documents from `/specs/100-automate-project-and/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are NOT explicitly requested in the feature specification. Only essential integration tests included for critical flows.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- **Python daemon**: `home-modules/tools/i3_project_manager/`
- **TypeScript CLI**: `home-modules/tools/i3pm-cli/src/`
- **Bash scripts**: `scripts/`
- **Tests**: `tests/100-automate-project-and/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create directory structure for new models in `home-modules/tools/i3_project_manager/models/`
- [X] T002 [P] Create directory structure for new services in `home-modules/tools/i3_project_manager/services/`
- [X] T003 [P] Create test fixtures directory at `tests/100-automate-project-and/fixtures/mock_repos/`
- [X] T004 [P] Create TypeScript model directory at `home-modules/tools/i3pm-cli/src/models/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create AccountConfig Pydantic model in `home-modules/tools/i3_project_manager/models/account.py` (from data-model.md)
- [X] T006 [P] Create AccountConfig Zod schema in `home-modules/tools/i3pm-cli/src/models/account.ts` (from data-model.md)
- [X] T007 Create storage schema for `~/.config/i3/accounts.json` with version field
- [X] T008 [P] Implement git URL parsing utility in `home-modules/tools/i3_project_manager/services/git_utils.py` with SSH and HTTPS patterns (from research.md)
- [X] T009 [P] Implement default branch detection in `home-modules/tools/i3_project_manager/services/git_utils.py` using `refs/remotes/origin/HEAD` (from research.md)
- [X] T010 Create `i3pm account add` CLI command in `home-modules/tools/i3pm-cli/src/commands/account/add.ts`
- [X] T011 Create `i3pm account list` CLI command in `home-modules/tools/i3pm-cli/src/commands/account/list.ts`
- [X] T012 Add IPC handler for `account.add` method in daemon
- [X] T013 Add IPC handler for `account.list` method in daemon

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Bare Repository + Worktree Structure (Priority: P1) 🎯 MVP

**Goal**: Users can clone repositories using bare repositories with main worktree, enabling clean parallel Claude Code development

**Independent Test**: Run `i3pm clone git@github.com:vpittamp/test-repo.git` and verify:
- `.bare/` directory exists with git database
- `.git` pointer file contains `gitdir: ./.bare`
- `main/` worktree exists with working files

### Implementation for User Story 1

- [X] T014 [P] [US1] Create BareRepository Pydantic model in `home-modules/tools/i3_project_manager/models/bare_repo.py` (from data-model.md)
- [X] T015 [P] [US1] Create Worktree Pydantic model in `home-modules/tools/i3_project_manager/models/worktree.py` (from data-model.md)
- [X] T016 [P] [US1] Create BareRepository Zod schema in `home-modules/tools/i3pm-cli/src/models/repository.ts`
- [X] T017 [P] [US1] Create Worktree Zod schema in `home-modules/tools/i3pm-cli/src/models/repository.ts`
- [X] T018 [US1] Implement CloneService in `home-modules/tools/i3_project_manager/services/clone_service.py` with bare clone workflow:
  - `git clone --bare <url> .bare`
  - Create `.git` pointer file
  - Detect default branch via git_utils
  - Create main worktree with `git worktree add main <default_branch>`
- [X] T019 [US1] Create Bash wrapper script `scripts/i3pm-clone.sh` for bare clone (shell-level helper)
- [X] T020 [US1] Create `i3pm clone <url>` CLI command in `home-modules/tools/i3pm-cli/src/commands/clone/index.ts` (from contracts/discovery-api.yaml)
- [X] T021 [US1] Add IPC handler for `clone` method in daemon
- [X] T022 [US1] Implement WorktreeService.create in `home-modules/tools/i3_project_manager/services/worktree_service.py`:
  - Validate branch name
  - Create worktree as sibling to main via `git worktree add <branch> -b <branch>`
- [X] T023 [US1] Create `i3pm worktree create <branch>` CLI command in `home-modules/tools/i3pm-cli/src/commands/worktree/create.ts` (from contracts/discovery-api.yaml)
- [X] T024 [US1] Add IPC handler for `worktree.create` method in daemon
- [X] T025 [US1] Add validation for existing worktree (return WORKTREE_EXISTS error per contracts)
- [X] T026 [US1] Add logging for clone and worktree operations

**Checkpoint**: Users can clone repos with bare structure and create feature worktrees

---

## Phase 4: User Story 2 - Account-Based Repository Organization (Priority: P1)

**Goal**: All repositories organized in predictable structure based on GitHub account ownership with automatic discovery

**Independent Test**: Create directories `~/repos/vpittamp/nixos/.bare/` and `~/repos/PittampalliOrg/api/.bare/`, run `i3pm discover`, verify both appear with correct account association

### Implementation for User Story 2

- [X] T027 [P] [US2] Create DiscoveredProject Pydantic model in `home-modules/tools/i3_project_manager/models/discovered_project.py` (from data-model.md, includes GitStatus submodel)
- [X] T028 [P] [US2] Create storage schema for `~/.config/i3/repos.json` with version and last_discovery fields
- [X] T029 [US2] Implement DiscoveryService in `home-modules/tools/i3_project_manager/services/discovery_service.py`:
  - Scan configured account directories
  - Find directories containing `.bare/` folder
  - Parse remote URL to extract account/repo name
  - Return list of BareRepository objects
- [X] T030 [US2] Create `i3pm discover` CLI command in `home-modules/tools/i3pm-cli/src/commands/discover/index.ts` (from contracts/discovery-api.yaml)
- [X] T031 [US2] Add IPC handler for `discover` method in daemon
- [X] T032 [US2] Create `i3pm repo list` CLI command in `home-modules/tools/i3pm-cli/src/commands/repo/list.ts` (from contracts/discovery-api.yaml)
- [X] T033 [US2] Create `i3pm repo get <account>/<repo>` CLI command in `home-modules/tools/i3pm-cli/src/commands/repo/get.ts`
- [X] T034 [US2] Add IPC handlers for `repo.list` and `repo.get` methods in daemon
- [X] T035 [US2] Implement qualified name generation: `<account>/<repo>` for repos
- [X] T036 [US2] Handle same repo name in different accounts (test with `vpittamp/api` and `PittampalliOrg/api`)

**Checkpoint**: Discovery finds all repos in configured account directories

---

## Phase 5: User Story 3 - Worktree Discovery and Linking (Priority: P2)

**Goal**: Worktrees automatically discovered and linked to their parent bare repository

**Independent Test**: Create bare repo with main and feature worktrees, run `i3pm discover`, verify both appear as `account/repo:main` and `account/repo:feature`

### Implementation for User Story 3

- [X] T037 [US3] Extend DiscoveryService to enumerate worktrees using `git worktree list --porcelain` (from research.md parsing strategy)
- [X] T038 [US3] Link discovered worktrees to parent BareRepository via worktrees field
- [X] T039 [US3] Implement qualified name generation for worktrees: `<account>/<repo>:<branch>`
- [X] T040 [US3] Extract git metadata for each worktree: commit hash, clean/dirty, ahead/behind (from data-model.md Worktree fields)
- [X] T041 [US3] Create `i3pm worktree list [repo]` CLI command in `home-modules/tools/i3pm-cli/src/commands/worktree/list.ts` (from contracts/discovery-api.yaml)
- [X] T042 [US3] Add IPC handler for `worktree.list` method in daemon (existed from Feature 098)
- [X] T043 [US3] Implement `git worktree prune` during discovery to clean stale references (FR-012)

**Checkpoint**: All worktrees discovered with correct parent linking and qualified names

---

## Phase 6: User Story 4 - Clone Helper with Bare Setup (Priority: P2)

**Goal**: Simple command to clone repos into correct directory structure with automatic bare setup

**Independent Test**: Run `i3pm clone git@github.com:vpittamp/dotfiles.git`, verify bare repo at correct path with main worktree

### Implementation for User Story 4

- [X] T044 [US4] Extend CloneService to derive account from URL and create in correct directory
- [X] T045 [US4] Create account directory if it doesn't exist (e.g., `~/repos/vpittamp/`)
- [X] T046 [US4] Return REPO_EXISTS error if repository already cloned (from contracts/discovery-api.yaml ErrorResponse)
- [X] T047 [US4] Register cloned repository via DiscoveryService after clone (done via re-running discover)
- [X] T048 [US4] Create `i3pm worktree remove <branch>` CLI command in `home-modules/tools/i3pm-cli/src/commands/worktree/remove.ts`
- [X] T049 [US4] Add IPC handler for `worktree.remove` method with force option and WORKTREE_DIRTY/CANNOT_REMOVE_MAIN errors

**Checkpoint**: Clone command creates full bare+main structure in correct account directory

---

## Phase 7: User Story 5 - Real-time Discovery (Priority: P4)

**Goal**: New repos and worktrees detected automatically without manual scans

**Independent Test**: Create worktree while monitoring, verify it appears within 30 seconds

### Implementation for User Story 5

- [ ] T050 [US5] Implement file system watcher for account directories using inotify or watchfiles
- [ ] T051 [US5] Trigger incremental discovery on directory changes (debounced to 30 seconds)
- [ ] T052 [US5] Emit event when new repo/worktree discovered for UI updates
- [ ] T053 [US5] Add configuration option to enable/disable file watching

**Checkpoint**: Worktrees appear automatically without running `i3pm discover`

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T054 [P] Update quickstart.md with final command syntax and examples
- [X] T055 [P] Replace existing ProjectEditor with DiscoveryService-based project listing
- [X] T056 [P] Update monitoring panel Projects tab to use new qualified names
- [X] T057 Create integration test for bare clone + worktree workflow in `tests/100-automate-project-and/integration/test_bare_clone_workflow.py`
- [X] T058 Performance validation: Verify discovery <5s for 50 repos + 100 worktrees (SC-001)
- [X] T059 [P] Clean up deprecated project management code from existing implementation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - US1 and US2 are both P1 and can proceed in parallel
  - US3 and US4 are P2 and can proceed in parallel (after US1/US2 foundation)
  - US5 is P4 (optional enhancement)
- **Polish (Final Phase)**: Depends on US1-US4 being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational - Creates bare repos and worktrees
- **User Story 2 (P1)**: Depends on Foundational - Discovers existing repos
- **User Story 3 (P2)**: Depends on US1 and US2 - Extends discovery with worktree linking
- **User Story 4 (P2)**: Depends on US1 and US2 - Enhances clone with auto-registration
- **User Story 5 (P4)**: Depends on US3 - Adds file watching on top of discovery

### Within Each User Story

- Models before services
- Services before CLI commands
- CLI commands before IPC handlers
- Core implementation before edge case handling

### Parallel Opportunities

**Phase 1 (Setup)**: T001, T002, T003, T004 can all run in parallel

**Phase 2 (Foundational)**: T006, T008, T009 can run in parallel

**Phase 3 (US1)**: T014, T015, T016, T017 can run in parallel (models)

**Phase 4 (US2)**: T027, T028 can run in parallel

**Phase 8 (Polish)**: T054, T055, T056, T059 can run in parallel

---

## Parallel Example: User Story 1 Models

```bash
# Launch all models for User Story 1 together:
Task: "Create BareRepository Pydantic model in home-modules/tools/i3_project_manager/models/bare_repo.py"
Task: "Create Worktree Pydantic model in home-modules/tools/i3_project_manager/models/worktree.py"
Task: "Create BareRepository Zod schema in home-modules/tools/i3pm-cli/src/models/repository.ts"
Task: "Create Worktree Zod schema in home-modules/tools/i3pm-cli/src/models/repository.ts"
```

## Parallel Example: User Story 2 Discovery

```bash
# Launch discovery components in parallel:
Task: "Create DiscoveredProject Pydantic model in home-modules/tools/i3_project_manager/models/discovered_project.py"
Task: "Create storage schema for ~/.config/i3/repos.json with version and last_discovery fields"
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (bare clone + worktree create)
4. Complete Phase 4: User Story 2 (discovery)
5. **STOP and VALIDATE**: Test bare clone workflow end-to-end
6. Can ship MVP with manual discovery (`i3pm discover`)

### Incremental Delivery

1. **MVP**: US1 + US2 = Clone repos, create worktrees, discover all
2. **Enhancement 1**: US3 = Worktree linking with git metadata
3. **Enhancement 2**: US4 = Enhanced clone with auto-registration
4. **Enhancement 3**: US5 = Real-time discovery (optional)

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (bare clone)
   - Developer B: User Story 2 (discovery)
3. After US1 + US2 complete:
   - Developer A: User Story 3 (worktree linking)
   - Developer B: User Story 4 (clone enhancements)
4. User Story 5 can be deferred or done last

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- US5 (Real-time Discovery) is P4 - can be deferred or skipped for MVP
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
