# Tasks: Convert i3pm Project Daemon to User-Level Service

**Input**: Design documents from `/specs/117-convert-project-daemon/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No explicit test tasks requested. Manual verification will be performed at checkpoints.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

This is a NixOS configuration refactor. Paths are at repository root:
- `modules/services/` - System-level NixOS service modules
- `home-modules/` - Home-manager modules (services, tools, desktop)
- `configurations/` - Target system configurations

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the new user service module structure

- [x] T001 Create directory structure for user service module at `home-modules/services/`
- [x] T002 Create new user service module at `home-modules/services/i3-project-daemon.nix` following eww-monitoring-panel pattern

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core user service infrastructure that MUST be complete before socket path updates

**CRITICAL**: No socket path updates can begin until the user service module is complete

- [x] T003 Define module options (enable, logLevel) in `home-modules/services/i3-project-daemon.nix`
- [x] T004 Configure systemd.user.services with Type=notify and watchdog in `home-modules/services/i3-project-daemon.nix`
- [x] T005 Add ExecStartPre for socket directory creation (`mkdir -p %t/i3-project-daemon`) in `home-modules/services/i3-project-daemon.nix`
- [x] T006 Configure ExecStart with direct Python invocation (no wrapper) in `home-modules/services/i3-project-daemon.nix`
- [x] T007 Add Unit section with After/PartOf graphical-session.target in `home-modules/services/i3-project-daemon.nix`
- [x] T008 Add Install section with WantedBy=graphical-session.target in `home-modules/services/i3-project-daemon.nix`
- [x] T009 Preserve resource limits (MemoryMax, CPUQuota, TasksMax) from system service in `home-modules/services/i3-project-daemon.nix`
- [x] T010 Add environment variables (LOG_LEVEL, PYTHONPATH, etc.) in `home-modules/services/i3-project-daemon.nix`
- [x] T011 Import user service module in home-manager configuration entry point

**Checkpoint**: User service module complete - socket path updates can now begin in parallel

---

## Phase 3: User Story 1 - Seamless Session Integration (Priority: P1)

**Goal**: Daemon starts automatically with graphical session, inheriting SWAYSOCK and other session environment variables natively.

**Independent Test**: `systemctl --user status i3-project-daemon` shows running, `journalctl --user -u i3-project-daemon` shows SWAYSOCK from session (no "Cleaning up stale Sway sockets" messages)

### Implementation for User Story 1

- [x] T012 [US1] Update `configurations/hetzner.nix` to disable system service and enable user service
- [x] T013 [P] [US1] Update `configurations/ryzen.nix` to disable system service and enable user service
- [x] T014 [P] [US1] Update `configurations/thinkpad.nix` to disable system service and enable user service (if applicable)
- [x] T015 [US1] Run `sudo nixos-rebuild dry-build --flake .#hetzner-sway` to verify configuration builds

**Checkpoint**: User service enabled in configurations - daemon will start with session after rebuild

---

## Phase 4: User Story 2 - Socket Path Migration (Priority: P2)

**Goal**: All daemon clients use the new user socket path (`$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`) with fallback to system socket for backward compatibility.

**Independent Test**: `i3pm project current` successfully queries daemon at new socket location

### Implementation for User Story 2 - Python Clients

- [x] T016 [P] [US2] Update socket path resolution in `home-modules/tools/i3_project_manager/core/daemon_client.py` (user socket first, system fallback)
- [x] T017 [P] [US2] Update socket path resolution in `home-modules/tools/i3_project_monitor/daemon_client.py`
- [x] T018 [P] [US2] Update socket path in `home-modules/tools/sway-workspace-panel/daemon_client.py`
- [x] T019 [P] [US2] Update socket path in `home-modules/tools/sway-workspace-panel/workspace_panel.py`
- [x] T020 [P] [US2] Update socket path in `home-modules/desktop/i3bar/workspace_mode_block.py`
- [x] T021 [P] [US2] Update socket path in `home-modules/tools/i3pm-diagnostic/i3pm_diagnostic_pkg/i3pm_diagnostic/__main__.py`
- [x] T022 [P] [US2] Update socket path in `home-modules/desktop/swaybar/blocks/system.py`

### Implementation for User Story 2 - Bash Scripts

- [x] T023 [P] [US2] Update SOCK variable in `home-modules/tools/scripts/i3pm-workspace-mode.sh` to use XDG_RUNTIME_DIR with fallback
- [x] T024 [P] [US2] Update socket path in `home-modules/tools/sway-workspace-panel/workspace-preview-daemon`

### Implementation for User Story 2 - TypeScript/Deno Clients

- [x] T025 [P] [US2] Update getI3pmSocketPath function in `home-modules/tools/i3pm/src/utils/socket.ts`
- [x] T026 [P] [US2] Update socketPath default in `home-modules/tools/i3pm/src/services/daemon-client.ts`

### Implementation for User Story 2 - Nix Modules

- [x] T027 [P] [US2] Update daemonSocketPath constant in `home-modules/tools/app-launcher.nix`
- [x] T028 [P] [US2] Update I3PM_DAEMON_SOCKET and all hardcoded paths (5 locations) in `home-modules/desktop/eww-monitoring-panel.nix`
- [x] T029 [P] [US2] Update socket path in `home-modules/tools/i3_project_manager/cli/monitoring_data.py` (2 locations)

**Checkpoint**: All daemon clients updated - tools will connect to new socket location

---

## Phase 5: User Story 3 - Clean Wrapper Removal (Priority: P3)

**Goal**: Remove the 55-line socket discovery wrapper script entirely. Service uses direct Python invocation.

**Independent Test**: `systemctl --user cat i3-project-daemon` shows ExecStart with direct Python path (no wrapper script)

### Implementation for User Story 3

- [x] T030 [US3] Verify user service module uses direct Python invocation in ExecStart (should be done in Phase 2)
- [x] T031 [US3] Remove daemonWrapper script definition from `modules/services/i3-project-daemon.nix`
- [x] T032 [US3] Remove systemd.tmpfiles.rules for `/run/i3-project-daemon` from `modules/services/i3-project-daemon.nix`
- [x] T033 [US3] Remove systemd.sockets.i3-project-daemon definition from `modules/services/i3-project-daemon.nix`
- [x] T034 [US3] Remove systemd.services.i3-project-daemon definition from `modules/services/i3-project-daemon.nix`
- [x] T035 [US3] Delete entire system service module file `modules/services/i3-project-daemon.nix`

**Checkpoint**: System service module removed - no legacy code remains

---

## Phase 6: User Story 4 - Service Dependencies Updated (Priority: P4)

**Goal**: Service properly declares dependencies on graphical session targets for correct lifecycle binding.

**Independent Test**: `systemctl --user show i3-project-daemon` shows PartOf=graphical-session.target

### Implementation for User Story 4

- [x] T036 [US4] Verify PartOf=graphical-session.target in user service module (should be done in Phase 2, T007)
- [x] T037 [US4] Verify After=graphical-session.target in user service module (should be done in Phase 2, T007)
- [x] T038 [US4] Verify WantedBy=graphical-session.target in user service module (should be done in Phase 2, T008)

**Checkpoint**: Service lifecycle binding complete - daemon will restart with session

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup

- [x] T039 Run `sudo nixos-rebuild dry-build --flake .#hetzner` to verify complete build
- [ ] T040 [P] Run `sudo nixos-rebuild dry-build --flake .#m1 --impure` to verify M1 build (skipped - no M1 config in flake)
- [x] T041 [P] Run `sudo nixos-rebuild dry-build --flake .#ryzen` to verify Ryzen build
- [x] T042 Verify no remaining references to `/run/i3-project-daemon` in codebase (fallback paths are intentional)
- [x] T043 Update quickstart.md migration documentation at `specs/117-convert-project-daemon/quickstart.md`
- [ ] T044 Apply configuration with `sudo nixos-rebuild switch --flake .#<target>` (requires user action)
- [ ] T045 Manual verification: `systemctl --user status i3-project-daemon` (requires user action)
- [ ] T046 Manual verification: `journalctl --user -u i3-project-daemon` (no wrapper messages) (requires user action)
- [ ] T047 Manual verification: `i3pm daemon status` (confirms daemon communication) (requires user action)
- [ ] T048 Manual verification: `i3pm project switch <project>` (confirms project switching) (requires user action)
- [ ] T049 Manual verification: Verify monitoring panel receives data (requires user action)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 - Configuration enablement
- **User Story 2 (Phase 4)**: Depends on Phase 2 - Socket path updates (can parallel with US1)
- **User Story 3 (Phase 5)**: Depends on Phase 3 and Phase 4 - System service removal
- **User Story 4 (Phase 6)**: Verification only - depends on Phase 2
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational - Can run in parallel with US1
- **User Story 3 (P3)**: Depends on US1 and US2 completion (safe to remove system service)
- **User Story 4 (P4)**: Verification phase - depends on Phase 2 completion

### Within Each User Story

- All tasks marked [P] within a story can run in parallel (different files)
- Sequential tasks must complete in order

### Parallel Opportunities

**Phase 2 (Foundational)**: T003-T010 are sequential (same file: `home-modules/services/i3-project-daemon.nix`)

**Phase 3 (US1)**: T012-T014 can run in parallel (different configuration files)

**Phase 4 (US2)**: Maximum parallelism - T016-T029 can ALL run in parallel (different files):
- Python clients: T016-T022 (7 files)
- Bash scripts: T023-T024 (2 files)
- TypeScript: T025-T026 (2 files)
- Nix modules: T027-T029 (3 files)

**Phase 5 (US3)**: T031-T035 are sequential (same file before deletion)

**Phase 7 (Polish)**: T039-T041 can run in parallel (different targets)

---

## Parallel Example: User Story 2

```bash
# Launch ALL socket path updates in parallel (14 files):
Task: "Update socket path in home-modules/tools/i3_project_manager/core/daemon_client.py"
Task: "Update socket path in home-modules/tools/i3_project_monitor/daemon_client.py"
Task: "Update socket path in home-modules/tools/sway-workspace-panel/daemon_client.py"
Task: "Update socket path in home-modules/tools/sway-workspace-panel/workspace_panel.py"
Task: "Update socket path in home-modules/desktop/i3bar/workspace_mode_block.py"
Task: "Update socket path in home-modules/tools/i3pm-diagnostic/i3pm_diagnostic_pkg/i3pm_diagnostic/__main__.py"
Task: "Update socket path in home-modules/desktop/swaybar/blocks/system.py"
Task: "Update socket path in home-modules/tools/scripts/i3pm-workspace-mode.sh"
Task: "Update socket path in home-modules/tools/sway-workspace-panel/workspace-preview-daemon"
Task: "Update socket path in home-modules/tools/i3pm/src/utils/socket.ts"
Task: "Update socket path in home-modules/tools/i3pm/src/services/daemon-client.ts"
Task: "Update socket path in home-modules/tools/app-launcher.nix"
Task: "Update socket path in home-modules/desktop/eww-monitoring-panel.nix"
Task: "Update socket path in home-modules/tools/i3_project_manager/cli/monitoring_data.py"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - creates user service module)
3. Complete Phase 3: User Story 1 (Configuration enablement)
4. Complete Phase 4: User Story 2 (Socket path migration)
5. **STOP and VALIDATE**: dry-build and test daemon functionality
6. Deploy if ready - system service can remain in codebase temporarily

### Incremental Delivery

1. Complete Setup + Foundational → User service module ready
2. Add User Story 1 + 2 → Test independently → Deploy (MVP!)
3. Add User Story 3 → Remove system service → Deploy
4. Add User Story 4 → Verify lifecycle binding → Deploy
5. Polish → Final validation

### Serial Execution (Single Developer)

For this feature, serial execution is recommended:
1. Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7
2. Stop at any checkpoint to validate

---

## Notes

- [P] tasks = different files, no dependencies within the phase
- [US#] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts

## Task Summary

| Phase | Description | Task Count |
|-------|-------------|------------|
| Phase 1 | Setup | 2 |
| Phase 2 | Foundational | 9 |
| Phase 3 | User Story 1 (P1) | 4 |
| Phase 4 | User Story 2 (P2) | 14 |
| Phase 5 | User Story 3 (P3) | 6 |
| Phase 6 | User Story 4 (P4) | 3 |
| Phase 7 | Polish | 11 |
| **Total** | | **49** |
