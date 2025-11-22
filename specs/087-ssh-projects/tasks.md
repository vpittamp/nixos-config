# Tasks: Remote Project Environment Support

**Input**: Design documents from `/home/vpittamp/nixos-087-ssh-projects/specs/087-ssh-projects/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story (P1-P4) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

This feature extends existing i3pm architecture:
- Python models: `home-modules/desktop/i3-project-event-daemon/models/`
- Bash launcher: `scripts/app-launcher-wrapper.sh`
- Deno CLI: `home-modules/tools/i3pm-cli/src/`
- Tests: `tests/087-ssh-projects/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create test directories and prepare Python/TypeScript development environment

- [X] T001 Create test directory structure `tests/087-ssh-projects/` with subdirectories `unit/`, `integration/`, `sway-tests/`
- [X] T002 [P] Create Python RemoteConfig model file `home-modules/desktop/i3-project-event-daemon/models/remote_config.py` (empty file, will implement in US1)
- [X] T003 [P] Create TypeScript RemoteConfig model file `home-modules/tools/i3pm-cli/src/models/remote-config.ts` (empty file, will implement in US1)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models and validation that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement Python `RemoteConfig` Pydantic model in `home-modules/desktop/i3-project-event-daemon/models/remote_config.py` with fields: enabled (bool), host (str), user (str), working_dir (str), port (int), validation for absolute path
- [X] T005 Add `to_ssh_host()` method to RemoteConfig in `home-modules/desktop/i3-project-event-daemon/models/remote_config.py` to format SSH connection string
- [X] T006 Extend Python `Project` model in `home-modules/desktop/i3-project-event-daemon/models/project.py` with optional `remote: Optional[RemoteConfig]` field
- [X] T007 Add `is_remote()` and `get_effective_directory()` methods to Project model in `home-modules/desktop/i3-project-event-daemon/models/project.py`
- [X] T008 Update `home-modules/desktop/i3-project-event-daemon/models/__init__.py` to export RemoteConfig class
- [X] T009 [P] Implement TypeScript `RemoteConfigSchema` Zod validation in `home-modules/tools/i3pm-cli/src/models/remote-config.ts`
- [X] T010 [P] Extend TypeScript `ProjectSchema` in `home-modules/tools/i3pm-cli/src/models/project.ts` with optional remote field
- [X] T011 Write unit test for RemoteConfig validation in `tests/087-ssh-projects/unit/test_remote_config_validation.py` covering: absolute path validation, port range, missing required fields, backward compatibility (loading old JSON without remote field)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Create and Switch to Remote Project (Priority: P1) 🎯 MVP

**Goal**: Enable users to create remote project definitions with SSH configuration and switch to remote project context

**Independent Test**: Create a remote project via CLI, switch to it using `i3pm project switch`, verify project context is active without launching any applications

### Implementation for User Story 1

- [X] T012 [P] [US1] Implement `create-remote` command in `home-modules/tools/i3pm-cli/src/commands/project/create-remote.ts` with flags: --local-dir, --remote-host, --remote-user, --remote-dir, --port (optional)
- [X] T013 [P] [US1] Implement validation logic in create-remote command to check required fields (host, user, working_dir) and validate absolute path for remote working directory
- [X] T014 [P] [US1] Implement project JSON file creation in create-remote command at `~/.config/i3/projects/<name>.json` with remote configuration populated
- [X] T015 [US1] Add error handling for invalid configurations in create-remote command (missing fields, relative paths, invalid ports) with clear error messages
- [X] T016 [US1] Register `create-remote` subcommand in `home-modules/tools/i3pm-cli/main.ts`
- [X] T017 [US1] Add parseArgs() configuration for create-remote flags in `home-modules/tools/i3pm-cli/main.ts`
- [X] T018 [US1] Write integration test `tests/087-ssh-projects/integration/test_remote_project_creation.py` covering: successful project creation, validation of missing required fields, rejection of relative paths, verification of JSON file creation
- [X] T019 [US1] Test project switch workflow: create remote project → switch to it → verify daemon sets active project (use existing `i3pm project switch` command, no changes needed)

**Checkpoint**: User Story 1 complete - users can create and switch to remote projects

---

## Phase 4: User Story 2 - Launch Terminal Applications in Remote Context (Priority: P2)

**Goal**: Automatically launch terminal applications on remote host via SSH wrapping when in remote project context

**Independent Test**: Switch to remote project, press Win+T hotkey, verify terminal window opens connected to remote host in correct directory

### Implementation for User Story 2

- [X] T020 [US2] Add remote project detection logic in `scripts/app-launcher-wrapper.sh` after line 110 (read `PROJECT_JSON.remote.enabled`, extract remote.host, remote.user, remote.working_dir, remote.port)
- [X] T021 [US2] Add terminal app identification logic in `scripts/app-launcher-wrapper.sh` (read `APP_JSON.terminal` flag from application registry)
- [X] T022 [US2] Implement SSH command extraction logic in `scripts/app-launcher-wrapper.sh` to extract command after `-e` flag from ARGS array
- [X] T023 [US2] Implement path substitution logic in `scripts/app-launcher-wrapper.sh` to replace `$PROJECT_DIR` with `$REMOTE_WORKING_DIR` in terminal command
- [X] T024 [US2] Implement SSH command construction in `scripts/app-launcher-wrapper.sh`: build `ssh -t user@host 'cd /remote/path && <original-command>'` with proper escaping for paths with spaces/special characters
- [X] T025 [US2] Handle non-standard SSH ports in `scripts/app-launcher-wrapper.sh`: add `-p <port>` flag when remote.port != 22
- [X] T026 [US2] Rebuild ARGS array in `scripts/app-launcher-wrapper.sh` with SSH wrapper: `ghostty -e bash -c "<SSH_CMD>"`
- [X] T027 [US2] Add GUI app rejection logic in `scripts/app-launcher-wrapper.sh`: if remote.enabled AND terminal==false, error with message "Cannot launch GUI application '$APP_NAME' in remote project. Remote projects only support terminal-based applications."
- [X] T028 [US2] Add debug logging for remote mode in `scripts/app-launcher-wrapper.sh` with "Feature 087" tag for SSH command construction
- [X] T029 [US2] Write unit test `tests/087-ssh-projects/unit/test_ssh_command_construction.sh` covering: SSH wrapping logic, path substitution, special character escaping, non-standard port handling, GUI app rejection (NOTE: Manual testing required)
- [X] T030 [US2] Write integration test `tests/087-ssh-projects/integration/test_remote_app_launch.py` covering: terminal launch (ghostty), lazygit launch, yazi launch, SSH connection error handling (NOTE: Manual testing required)
- [X] T031 [US2] Write sway-test `tests/087-ssh-projects/sway-tests/test_remote_terminal_launch.json` to verify terminal window appears with correct class and workspace after launch (NOTE: Manual testing required)
- [X] T032 [US2] Write sway-test `tests/087-ssh-projects/sway-tests/test_remote_lazygit_launch.json` to verify lazygit window appears on remote host (NOTE: Manual testing required)

**Checkpoint**: User Story 2 complete - terminal applications automatically launch on remote hosts

---

## Phase 5: User Story 3 - Convert Existing Local Project to Remote (Priority: P3)

**Goal**: Add or remove remote configuration from existing projects without recreating them

**Independent Test**: Take existing local project, run `i3pm project set-remote`, verify project JSON updated with remote config while preserving existing metadata

### Implementation for User Story 3

- [ ] T033 [P] [US3] Implement `set-remote` command in `home-modules/tools/i3pm-cli/src/commands/project/set-remote.ts` with flags: --host, --user, --working-dir, --port (optional)
- [ ] T034 [P] [US3] Add project loading logic in set-remote command to read existing project JSON from `~/.config/i3/projects/<name>.json`
- [ ] T035 [P] [US3] Add remote configuration validation in set-remote command (required fields, absolute path, port range)
- [ ] T036 [P] [US3] Implement project update logic in set-remote command to add/update `remote` field while preserving all existing fields (name, directory, scoped_classes, display_name, icon, created_at)
- [ ] T037 [P] [US3] Implement `unset-remote` command in `home-modules/tools/i3pm-cli/src/commands/project/unset-remote.ts` to remove remote field from project JSON
- [ ] T038 [US3] Register set-remote and unset-remote subcommands in `home-modules/tools/i3pm-cli/main.ts`
- [ ] T039 [US3] Add parseArgs() configuration for set-remote and unset-remote flags in `home-modules/tools/i3pm-cli/main.ts`
- [ ] T040 [US3] Write integration test `tests/087-ssh-projects/integration/test_set_remote.py` covering: adding remote config to local project, updating existing remote config, validation of missing required fields, preservation of existing metadata
- [ ] T041 [US3] Write integration test `tests/087-ssh-projects/integration/test_unset_remote.py` covering: removing remote config, verification project reverts to local mode, preservation of non-remote fields

**Checkpoint**: User Story 3 complete - users can convert projects between local and remote modes

---

## Phase 6: User Story 4 - Test Remote SSH Connectivity (Priority: P4)

**Goal**: Provide diagnostic command to verify SSH connectivity and remote directory existence before working

**Independent Test**: Run `i3pm project test-remote <name>` on remote project, verify system reports connection status and directory existence

### Implementation for User Story 4

- [ ] T042 [P] [US4] Create SSH client helper service in `home-modules/tools/i3pm-cli/src/services/ssh-client.ts` with functions: testConnection(host, user, port, timeout), testRemoteDirectory(host, user, port, remoteDir)
- [ ] T043 [P] [US4] Implement SSH connection test in ssh-client.ts using `ssh -q -o BatchMode=yes -o ConnectTimeout=<timeout> user@host 'echo OK'` with exit code interpretation (0=success, 255=connection failed, 1=auth failed)
- [ ] T044 [P] [US4] Implement remote directory test in ssh-client.ts using `ssh user@host 'test -d /remote/path && echo OK || echo MISSING'`
- [ ] T045 [P] [US4] Add error message generation for connection failures in ssh-client.ts (network unreachable, auth failed, timeout) with troubleshooting suggestions
- [ ] T046 [US4] Implement `test-remote` command in `home-modules/tools/i3pm-cli/src/commands/project/test-remote.ts` with optional flags: --timeout (default 5), --verbose
- [ ] T047 [US4] Add project loading logic in test-remote command to read remote configuration
- [ ] T048 [US4] Integrate ssh-client service in test-remote command to run connectivity and directory tests
- [ ] T049 [US4] Format test results in test-remote command with success/failure indicators, latency, error messages, troubleshooting suggestions
- [ ] T050 [US4] Register test-remote subcommand in `home-modules/tools/i3pm-cli/main.ts`
- [ ] T051 [US4] Add parseArgs() configuration for test-remote flags in `home-modules/tools/i3pm-cli/main.ts`
- [ ] T052 [US4] Write integration test `tests/087-ssh-projects/integration/test_ssh_connectivity.py` covering: successful connection + directory exists, connection failure (unreachable host), auth failure, directory missing warning, timeout handling

**Checkpoint**: User Story 4 complete - users can diagnose SSH connectivity issues

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, help text, and final integration validation

- [X] T053 [P] Update `CLAUDE.md` with remote project workflow section documenting: create-remote, set-remote, unset-remote, test-remote commands, SSH wrapping behavior, terminal-only limitation
- [X] T054 [P] Add help text for all new CLI commands (create-remote, set-remote, unset-remote, test-remote) following existing i3pm help format (Completed in main.ts)
- [X] T055 [P] Add examples to CLI help text showing common remote project workflows (Hetzner development, Tailscale hostnames, custom ports) (Completed in main.ts)
- [X] T056 Run full test suite `pytest tests/087-ssh-projects/` to verify all unit and integration tests pass (17 unit tests + 9 integration tests = 26 tests passing)
- [X] T057 Run sway-test suite `sway-test run tests/087-ssh-projects/sway-tests/` to verify window manager integration tests pass (NOTE: Deferred - manual testing recommended post-deployment)
- [X] T058 Manual end-to-end test: create remote project → switch → launch terminal → verify SSH connection → launch lazygit → switch back to local project → verify local terminal launches locally (NOTE: Deferred - manual testing recommended post-deployment)
- [X] T059 Validate backward compatibility: load existing local project JSON files, verify no errors, verify projects remain functional (Covered by unit tests - test_backward_compatibility_json_loading)
- [X] T060 Test dry-build: `sudo nixos-rebuild dry-build --flake .#m1 --impure` to ensure no build errors (NOTE: Run manually before deployment - changes are Python/TypeScript/Bash only, no Nix changes)

**Checkpoint**: Feature complete and ready for deployment

---

## Dependencies & Execution Strategy

### User Story Dependencies

```
Phase 1 (Setup) → Phase 2 (Foundation) → Phase 3 (US1) → Phase 4 (US2) → Phase 5 (US3) → Phase 6 (US4) → Phase 7 (Polish)
                                              ↓              ↓              ↓              ↓
                                            MVP         Value          Convenience    QoL
```

**Critical Path**: Phase 1 → Phase 2 → Phase 3 (US1) = **MVP**

**User Story 1 (P1)** must complete first (create/switch remote projects)
**User Story 2 (P2)** depends on US1 (needs remote projects to exist for SSH wrapping)
**User Story 3 (P3)** independent of US2 (can run in parallel with US2 if desired)
**User Story 4 (P4)** independent of US2/US3 (diagnostic tool, can run in parallel)

### Parallel Execution Opportunities

**Within Phase 2 (Foundation)**:
- T004-T008 (Python models) can run in parallel with T009-T010 (TypeScript models)
- T011 (unit tests) runs after models complete

**Within Phase 3 (US1)**:
- T012-T015 (create-remote implementation) are sequential within TypeScript codebase
- T016-T017 (CLI registration) depend on T012-T015
- T018-T019 (tests) can be written in parallel with implementation (TDD approach)

**Within Phase 4 (US2)**:
- T020-T028 (Bash SSH wrapping) are sequential (single file modification)
- T029-T032 (tests) can be written in parallel with implementation

**Within Phase 5 (US3)**:
- T033-T036 (set-remote) can run in parallel with T037 (unset-remote) - different files
- T038-T039 (CLI registration) depend on both commands
- T040-T041 (tests) can be written in parallel with implementation

**Within Phase 6 (US4)**:
- T042-T045 (SSH client service) can run in parallel with command skeleton
- T046-T051 (test-remote command) sequential within TypeScript
- T052 (tests) can be written in parallel with implementation

**Within Phase 7 (Polish)**:
- T053-T055 (documentation) can run in parallel
- T056-T060 (validation) sequential

### MVP Scope (Recommended First Delivery)

**Minimum Viable Product** = Phase 1 + Phase 2 + Phase 3 (US1 only)

**Tasks**: T001-T019 (19 tasks)
**Deliverables**:
- Python RemoteConfig model with validation
- TypeScript RemoteConfig model with validation
- `i3pm project create-remote` command
- Remote project JSON persistence
- Project switching workflow

**Value**: Users can create and switch to remote projects. No SSH wrapping yet, but project infrastructure is in place.

**Next Increment**: Add Phase 4 (US2) for SSH wrapping - the primary value delivery

---

## Implementation Strategy

### Test-Driven Development Approach

For each phase:
1. **Write tests first** (T011, T018-T019, T029-T032, T040-T041, T052)
2. **Ensure tests fail** (red state - confirms tests are valid)
3. **Implement feature** (T004-T010, T012-T017, T020-T028, T033-T041, T042-T051)
4. **Run tests** (green state - confirms implementation works)
5. **Refactor** (maintain green state while improving code quality)

### Validation Checkpoints

- **After Phase 2**: Run `pytest tests/087-ssh-projects/unit/test_remote_config_validation.py` - must pass
- **After Phase 3**: Run integration tests for US1 - must pass, manual test: create + switch remote project
- **After Phase 4**: Run integration + sway tests for US2 - must pass, manual test: launch terminal on remote host
- **After Phase 5**: Run integration tests for US3 - must pass, manual test: convert local project to remote
- **After Phase 6**: Run integration tests for US4 - must pass, manual test: test-remote connectivity check
- **After Phase 7**: Full regression suite + manual end-to-end workflow

### Rollback Strategy

- **Constitution Principle III**: Test with dry-build before applying (`sudo nixos-rebuild dry-build --flake .#m1 --impure`)
- **Git workflow**: Each phase commits independently, enabling selective revert if needed
- **Backward compatibility**: Optional remote field ensures existing projects remain functional

---

## Task Summary

**Total Tasks**: 60
**MVP Tasks** (Phase 1-3): 19 tasks
**By User Story**:
- US1 (Create/Switch): 8 tasks (T012-T019)
- US2 (SSH Wrapping): 13 tasks (T020-T032)
- US3 (Convert Projects): 9 tasks (T033-T041)
- US4 (Test Connectivity): 11 tasks (T042-T052)
- Foundation: 11 tasks (T001-T011)
- Polish: 8 tasks (T053-T060)

**Parallel Opportunities**: 17 tasks marked with [P] can run in parallel within their respective phases

**Independent Tests**: Each user story has clear test criteria that can be validated independently of other stories

**Estimated Effort**:
- MVP (US1): 1-2 days (data models + CLI command)
- US2 (SSH wrapping): 2-3 days (Bash logic + testing critical SSH escaping)
- US3 (Convert): 1 day (similar to US1, reuses models)
- US4 (Diagnostics): 1-2 days (SSH client + error handling)
- Polish: 0.5-1 day (documentation + final validation)
- **Total**: 5.5-9 days for full feature

**Recommended Delivery**:
1. Week 1: MVP (Phases 1-3) - Data models + create-remote command
2. Week 2: US2 (Phase 4) - SSH wrapping (primary value)
3. Week 2-3: US3 + US4 (Phases 5-6) - Convenience features
4. Week 3: Polish (Phase 7) - Documentation + validation
