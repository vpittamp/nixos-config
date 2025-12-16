# Tasks: Improve Socket Discovery and Service Reliability

**Input**: Design documents from `/specs/121-improve-socket-discovery/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Tests**: Not explicitly requested in feature specification - manual verification only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- **Nix modules**: `home-modules/services/`, `home-modules/desktop/`, `home-modules/tools/`
- **Python daemon**: `home-modules/desktop/i3-project-event-daemon/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No setup required - modifying existing modules and creating one new module

- [X] T001 Review current service targets by running `grep -r "graphical-session.target\|sway-session.target" home-modules/`
- [X] T002 Read existing daemon health code in home-modules/desktop/i3-project-event-daemon/recovery/i3_reconnect.py

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational blockers - each user story can proceed independently after setup review

**⚠️ CRITICAL**: User stories are independent and can be implemented in any order

**Checkpoint**: Setup review complete - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Standardize Service Targets (Priority: P1) 🎯 MVP

**Goal**: Migrate 4 Sway-specific services from `graphical-session.target` to `sway-session.target`

**Independent Test**: Run `systemctl --user list-dependencies sway-session.target` after rebuild and verify all 4 services are listed. Reboot and verify all services start correctly.

### Implementation for User Story 1

- [X] T003 [P] [US1] Update i3-project-daemon.nix: Change After/PartOf/WantedBy from graphical-session.target to sway-session.target in home-modules/services/i3-project-daemon.nix (lines 109, 111, 178)
- [X] T004 [P] [US1] Update eww-monitoring-panel.nix: Change After/PartOf/WantedBy from graphical-session.target to sway-session.target in home-modules/desktop/eww-monitoring-panel.nix (lines 12981, 12983, 13008)
- [X] T005 [P] [US1] Update sway-config-manager.nix: Change After/PartOf/WantedBy from graphical-session.target to sway-session.target in home-modules/desktop/sway-config-manager.nix (lines 327, 328, 391)
- [X] T006 [P] [US1] Update i3wsr.nix: Change After/PartOf/WantedBy from graphical-session.target to sway-session.target in home-modules/desktop/i3wsr.nix (lines 159, 160, 171)
- [X] T007 [US1] Run dry-build: `sudo nixos-rebuild dry-build --flake .#hetzner-sway` to verify no build errors
- [ ] T008 [US1] Apply changes: `sudo nixos-rebuild switch --flake .#hetzner-sway`
- [ ] T009 [US1] Verify migration: Run `systemctl --user list-dependencies sway-session.target | grep -E 'i3-project|eww-monitoring|sway-config|i3wsr'` and confirm all 4 services listed
- [ ] T010 [US1] Update daemon nix comment: Remove outdated comment about graphical-session.target in home-modules/services/i3-project-daemon.nix (line 12)

**Checkpoint**: At this point, User Story 1 should be fully functional. All Sway-specific services now use sway-session.target.

---

## Phase 4: User Story 2 - Health Endpoint for Socket Validation (Priority: P2)

**Goal**: Add `i3pm diagnose socket-health` command that queries daemon for socket health status

**Independent Test**: Run `i3pm diagnose socket-health` and verify JSON response with status, socket_path, last_validated, latency_ms fields.

### Implementation for User Story 2

- [X] T011 [P] [US2] Add get_health_status() method to ConnectionManager in home-modules/desktop/i3-project-event-daemon/connection.py returning SocketHealthStatus dict
- [X] T012 [P] [US2] Add SocketHealthStatus dataclass model to home-modules/desktop/i3-project-event-daemon/models.py (if exists) or connection.py
- [X] T013 [US2] Add get_socket_health message handler to IPC handler in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [ ] T014 [US2] Test IPC handler by sending get_socket_health message via socat to daemon socket
- [X] T015 [US2] Add socket-health subcommand to i3pm diagnose CLI (home-modules/tools/i3pm/cli/diagnose.py)
- [ ] T016 [US2] Run dry-build and apply: `sudo nixos-rebuild dry-build --flake .#hetzner-sway && sudo nixos-rebuild switch --flake .#hetzner-sway`
- [ ] T017 [US2] Restart daemon: `systemctl --user restart i3-project-daemon`
- [ ] T018 [US2] Verify endpoint: Run `i3pm diagnose socket-health` and confirm JSON response with status "healthy"

**Checkpoint**: At this point, User Story 2 should be fully functional. Socket health can be queried via CLI.

---

## Phase 5: User Story 3 - Stale Socket Cleanup Timer (Priority: P3)

**Goal**: Create systemd timer that removes orphaned sway-ipc.*.sock files every 5 minutes

**Independent Test**: Create fake stale socket file with `touch /run/user/$(id -u)/sway-ipc.$(id -u).99999.sock`, wait for timer (or run service manually), verify socket removed.

### Implementation for User Story 3

- [X] T019 [US3] Create cleanup module directory: `mkdir -p home-modules/tools/sway-socket-cleanup`
- [X] T020 [US3] Create default.nix with cleanup script and systemd timer in home-modules/tools/sway-socket-cleanup/default.nix
- [X] T021 [US3] Implement cleanup script logic: iterate sway-ipc.*.sock, extract PID, check /proc/$PID/comm, remove orphans
- [X] T022 [US3] Configure systemd timer: OnBootSec=5min, OnUnitActiveSec=5min, journal logging
- [X] T023 [US3] Import module: Add sway-socket-cleanup to home-modules/hetzner.nix imports and enable
- [ ] T024 [US3] Run dry-build and apply: `sudo nixos-rebuild dry-build --flake .#hetzner-sway && sudo nixos-rebuild switch --flake .#hetzner-sway`
- [ ] T025 [US3] Verify timer installed: `systemctl --user list-timers | grep sway-socket`
- [ ] T026 [US3] Test cleanup: Create fake stale socket and run `systemctl --user start sway-socket-cleanup.service`
- [ ] T027 [US3] Verify logging: Check `journalctl --user -u sway-socket-cleanup.service` for cleanup messages

**Checkpoint**: At this point, User Story 3 should be fully functional. Stale sockets are automatically cleaned.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and validation across all user stories

- [X] T028 [P] Update quickstart.md with actual command outputs in specs/121-improve-socket-discovery/quickstart.md
- [X] T029 [P] Update CLAUDE.md Active Technologies section if new tools were added
- [ ] T030 Run full validation: Reboot system, verify all services start, check socket health, confirm no stale sockets
- [ ] T031 Commit all changes with feature reference: `git add -A && git commit -m "feat(121): Improve socket discovery and service reliability"`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - review only
- **Foundational (Phase 2)**: N/A - no foundational blockers
- **User Stories (Phase 3-5)**: All independent - can proceed in any order
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately - No dependencies
- **User Story 2 (P2)**: Can start immediately - No dependencies on US1
- **User Story 3 (P3)**: Can start immediately - No dependencies on US1/US2

### Within Each User Story

- File edits (T003-T006) can be done in parallel [P]
- dry-build must complete before switch
- Verification must follow apply

### Parallel Opportunities

Within US1 (all target migrations):
```
T003 (daemon) | T004 (eww-panel) | T005 (config-mgr) | T006 (i3wsr) → T007 (dry-build)
```

Within US2 (health endpoint):
```
T011 (health method) | T012 (model) → T013 (handler) → T014-T018 (test & verify)
```

---

## Parallel Example: User Story 1

```bash
# Launch all Nix file edits in parallel (different files, no conflicts):
Task: "Update i3-project-daemon.nix target in home-modules/services/i3-project-daemon.nix"
Task: "Update eww-monitoring-panel.nix target in home-modules/desktop/eww-monitoring-panel.nix"
Task: "Update sway-config-manager.nix target in home-modules/desktop/sway-config-manager.nix"
Task: "Update i3wsr.nix target in home-modules/desktop/i3wsr.nix"

# Then sequential:
Task: "Run dry-build to verify changes"
Task: "Apply changes with nixos-rebuild switch"
Task: "Verify all services on sway-session.target"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup review
2. Complete Phase 3: User Story 1 (target standardization)
3. **STOP and VALIDATE**: Reboot, verify all services start with sway-session.target
4. Deploy if ready - system is more reliable with consistent targets

### Incremental Delivery

1. Complete User Story 1 → Test independently → More reliable startup ✓
2. Add User Story 2 → Test independently → Observable socket health ✓
3. Add User Story 3 → Test independently → No stale socket accumulation ✓
4. Each story adds value without breaking previous stories

### Single Developer Strategy (Recommended)

1. Complete US1 first (highest value, simplest changes)
2. Complete US2 second (observability)
3. Complete US3 last (optimization)

---

## Notes

- All Nix module edits in US1 are [P] - can be edited in parallel (different files)
- Each user story is independently testable after completion
- No tests explicitly requested - manual verification via systemctl and CLI
- Commit after each user story phase for clean git history
- Stop at any checkpoint to validate story independently
