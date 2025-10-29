---
description: "Task list for Feature 048: Multi-Monitor Headless Sway/Wayland Setup"
---

# Tasks: Multi-Monitor Headless Sway/Wayland Setup

**Input**: Design documents from `/etc/nixos/specs/048-multi-monitor-headless/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No tests requested - this is a system configuration feature validated through manual VNC connectivity testing

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- **NixOS configuration**: `/etc/nixos/configurations/`, `/etc/nixos/home-modules/`
- **Documentation**: `/etc/nixos/specs/048-multi-monitor-headless/`, `/etc/nixos/CLAUDE.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare configuration files for multi-display setup

- [X] T001 [P] Backup current hetzner-sway.nix configuration at `/etc/nixos/configurations/hetzner-sway.nix`
- [X] T002 [P] Backup current sway.nix home-manager configuration at `/etc/nixos/home-modules/desktop/sway.nix`
- [X] T003 Validate current single-display configuration works with `sudo nixos-rebuild dry-build --flake .#hetzner-sway`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Update WLR_HEADLESS_OUTPUTS from 1 to 3 in greetd wrapper at `/etc/nixos/configurations/hetzner-sway.nix` (line 74)
- [X] T005 Update WLR_HEADLESS_OUTPUTS in environment.sessionVariables at `/etc/nixos/configurations/hetzner-sway.nix` (line 97)
- [X] T006 Add firewall rules for ports 5901-5902 (5900 already exists) to networking.firewall.interfaces."tailscale0".allowedTCPPorts at `/etc/nixos/configurations/hetzner-sway.nix`
- [X] T007 Test configuration changes with `sudo nixos-rebuild dry-build --flake .#hetzner-sway`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Three Virtual Displays for Multi-Workspace Workflows (Priority: P1) 🎯 MVP

**Goal**: Enable three independent virtual displays (HEADLESS-1, HEADLESS-2, HEADLESS-3) accessible via VNC over Tailscale with workspace distribution (1-2, 3-5, 6-9)

**Independent Test**: Connect three VNC clients (one to each port: 5900, 5901, 5902) over Tailscale and verify each shows a distinct workspace view with independent window content

### Implementation for User Story 1

- [X] T008 [P] [US1] Define HEADLESS-1 output configuration (resolution, position, scale) in `/etc/nixos/home-modules/desktop/sway.nix` output section
- [X] T009 [P] [US1] Define HEADLESS-2 output configuration (resolution, position, scale) in `/etc/nixos/home-modules/desktop/sway.nix` output section
- [X] T010 [P] [US1] Define HEADLESS-3 output configuration (resolution, position, scale) in `/etc/nixos/home-modules/desktop/sway.nix` output section
- [X] T011 [US1] Update workspace assignments for three displays (WS 1-2 → HEADLESS-1, WS 3-5 → HEADLESS-2, WS 6-9 → HEADLESS-3) in `/etc/nixos/home-modules/desktop/sway.nix` workspaceOutputAssign section
- [X] T012 [P] [US1] Create wayvnc@HEADLESS-1.service systemd user service (port 5900) in `/etc/nixos/home-modules/desktop/sway.nix` systemd.user.services section
- [X] T013 [P] [US1] Create wayvnc@HEADLESS-2.service systemd user service (port 5901) in `/etc/nixos/home-modules/desktop/sway.nix` systemd.user.services section
- [X] T014 [P] [US1] Create wayvnc@HEADLESS-3.service systemd user service (port 5902) in `/etc/nixos/home-modules/desktop/sway.nix` systemd.user.services section
- [X] T015 [US1] Update WayVNC config file to remove port specification (handled by services) at `/etc/nixos/home-modules/desktop/sway.nix` xdg.configFile."wayvnc/config" section (line 425-431)
- [X] T016 [US1] Test configuration with `sudo nixos-rebuild dry-build --flake .#hetzner-sway` to validate syntax
- [X] T017 [US1] Apply configuration with `sudo nixos-rebuild switch --flake .#hetzner-sway`
- [X] T018 [US1] Verify three WayVNC services started successfully with `systemctl --user list-units 'wayvnc@*'`
- [X] T019 [US1] Verify three outputs exist with `swaymsg -t get_outputs | jq '.[] | {name, active, current_mode}'`
- [X] T020 [US1] Verify workspace assignments with `swaymsg -t get_workspaces | jq '.[] | {num, output, visible}'`
- [X] T021 [US1] Test VNC connectivity to port 5900 (HEADLESS-1) from local machine via Tailscale
- [X] T022 [US1] Test VNC connectivity to port 5901 (HEADLESS-2) from local machine via Tailscale
- [X] T023 [US1] Test VNC connectivity to port 5902 (HEADLESS-3) from local machine via Tailscale
- [X] T024 [US1] Test workspace switching: move window to WS 5 and verify it appears only on HEADLESS-2
- [X] T025 [US1] Test workspace focus: focus WS 8 and verify HEADLESS-3 shows it as active

**Checkpoint**: At this point, User Story 1 should be fully functional - three displays accessible via VNC with correct workspace distribution

---

## Phase 4: User Story 2 - Dynamic Resolution and Layout Control (Priority: P2)

**Goal**: Allow independent resolution configuration for each virtual display to optimize for different VNC client setups

**Independent Test**: Change resolution settings for one virtual output (e.g., HEADLESS-2 to 2560x1440) and verify the VNC stream reflects the new resolution without affecting other outputs

### Implementation for User Story 2

- [ ] T026 [US2] Document resolution change procedure in `/etc/nixos/specs/048-multi-monitor-headless/quickstart.md` "Advanced Usage > Changing Display Resolution" section
- [ ] T027 [US2] Test changing HEADLESS-2 resolution to 2560x1440 in `/etc/nixos/home-modules/desktop/sway.nix`
- [ ] T028 [US2] Rebuild configuration with `sudo nixos-rebuild switch --flake .#hetzner-sway`
- [ ] T029 [US2] Restart Sway session (log out and log back in or `swaymsg reload`)
- [ ] T030 [US2] Verify HEADLESS-2 now streams at 2560x1440 resolution via VNC
- [ ] T031 [US2] Verify HEADLESS-1 and HEADLESS-3 resolutions unchanged
- [ ] T032 [US2] Test changing HEADLESS-3 position to vertical layout (e.g., position "0,1080")
- [ ] T033 [US2] Verify workspaces respect new logical layout with no overlap or gaps
- [ ] T034 [US2] Restore all displays to 1920x1080@60Hz horizontal layout
- [ ] T035 [US2] Document supported resolution formats in quickstart.md

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - users can customize display resolutions independently

---

## Phase 5: User Story 3 - Persistent Multi-Display Configuration Across Reboots (Priority: P3)

**Goal**: Ensure the three-display configuration persists across VM reboots and Sway restarts without manual reconfiguration

**Independent Test**: Configure three displays, reboot the VM, and verify all three VNC endpoints are accessible with correct workspace assignments

### Implementation for User Story 3

- [ ] T036 [US3] Verify systemd services are enabled (WantedBy sway-session.target) in service definitions
- [ ] T037 [US3] Test reboot persistence: reboot VM with `sudo reboot`
- [ ] T038 [US3] After reboot, verify all three WayVNC services started automatically with `systemctl --user list-units 'wayvnc@*'`
- [ ] T039 [US3] After reboot, verify workspace assignments persist with `swaymsg -t get_workspaces | jq '.[] | {num, output}'`
- [ ] T040 [US3] After reboot, verify custom resolutions (if configured) persist with `swaymsg -t get_outputs | jq '.[] | {name, current_mode}'`
- [ ] T041 [US3] Test Sway restart persistence: reload Sway with `swaymsg reload`
- [ ] T042 [US3] After reload, verify all three VNC streams remain active
- [ ] T043 [US3] After reload, verify workspace assignments remain correct
- [ ] T044 [US3] Document persistence guarantees in quickstart.md

**Checkpoint**: At this point, User Stories 1, 2, AND 3 should all work - configuration persists across reboots and restarts

---

## Phase 6: User Story 4 - Integration with Existing i3pm Workspace Management (Priority: P2)

**Goal**: Workspace assignments automatically distribute across all three displays based on monitor count detection, integrating with existing i3pm workflows

**Independent Test**: Switch projects and verify workspaces distribute across three displays (e.g., WS 1-2 on HEADLESS-1, WS 3-5 on HEADLESS-2, WS 6-9 on HEADLESS-3) automatically

### Implementation for User Story 4

- [ ] T045 [US4] Verify i3pm monitor detection reports 3 outputs with `i3pm monitors status`
- [ ] T046 [US4] Verify i3pm workspace distribution matches 3-monitor rule (1-2, 3-5, 6-9) with `i3pm monitors config show`
- [ ] T047 [US4] Test project switching: switch to "nixos" project with `pswitch nixos`
- [ ] T048 [US4] Verify project-scoped windows hide across all three displays when switching projects
- [ ] T049 [US4] Verify project-scoped windows restore to correct displays when switching back
- [ ] T050 [US4] Test workspace reassignment: run `i3pm monitors reassign` (or `Win+Shift+M`)
- [ ] T051 [US4] Verify workspaces redistribute correctly across three displays after reassignment
- [ ] T052 [US4] Test i3pm daemon compatibility: check daemon events with `i3pm daemon events --type=output --limit=10`
- [ ] T053 [US4] Verify i3pm windows visualization shows three outputs with `i3pm windows --tree`
- [ ] T054 [US4] Test launching project-scoped apps: launch VS Code with `Win+C` and verify it opens on correct workspace
- [ ] T055 [US4] Document i3pm integration in quickstart.md "Integration with i3pm" section

**Checkpoint**: All user stories should now be independently functional - full multi-monitor workflow with i3pm integration

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and documentation completeness

- [ ] T056 [P] Update `/etc/nixos/CLAUDE.md` with VNC connection instructions (section: Quick Debugging or new section)
- [ ] T057 [P] Update `/etc/nixos/CLAUDE.md` with multi-monitor troubleshooting tips
- [ ] T058 [P] Add quickstart.md reference to CLAUDE.md for easy discoverability
- [ ] T059 Validate all quickstart.md test scenarios from spec.md acceptance criteria
- [ ] T060 Test edge case: disconnect one VNC client while others remain connected
- [ ] T061 Test edge case: no VNC clients connected, verify Sway continues managing workspaces
- [ ] T062 Test edge case: port conflict simulation (stop one service, manually start on same port)
- [ ] T063 Test edge case: window positioning across displays with different resolutions (if US2 tested mixed resolutions)
- [ ] T064 Security validation: verify VNC ports NOT accessible from public internet (use `nc -zv <public-ip> 5900`)
- [ ] T065 Security validation: verify VNC ports ARE accessible from Tailscale network (use `nc -zv <tailscale-ip> 5900`)
- [ ] T066 Performance validation: measure VNC stream latency over Tailscale (target <200ms)
- [ ] T067 Performance validation: verify all three WayVNC services start within 10 seconds of Sway initialization
- [ ] T068 Document common troubleshooting scenarios in quickstart.md (VNC connection refused, blank screen, workspace on wrong display)
- [ ] T069 Add service management commands to quickstart.md (start/stop/restart individual displays)
- [ ] T070 Create rollback procedure documentation in case of issues

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can proceed in priority order (P1 → P2)
  - US1 (P1) must complete before US2 (P2) since US2 tests resolution changes on top of US1's base setup
  - US3 (P3) should be tested after US1 is stable
  - US4 (P2) can be tested in parallel with US2/US3 as it's integration testing
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories - CORE MVP
- **User Story 2 (P2)**: Depends on User Story 1 (needs base three-display setup to test resolution changes)
- **User Story 3 (P3)**: Depends on User Story 1 (needs base setup to test persistence)
- **User Story 4 (P2)**: Depends on User Story 1 (needs three displays for i3pm integration testing)

### Within Each User Story

- **US1**: Output definitions (T008-T010) before workspace assignments (T011)
- **US1**: Service definitions (T012-T014) can run in parallel with output definitions
- **US1**: Configuration changes (T008-T015) before dry-build test (T016)
- **US1**: Apply configuration (T017) before verification steps (T018-T025)
- **US2**: Documentation (T026) in parallel with testing (T027-T034)
- **US3**: All tasks sequential (reboot testing requires previous steps)
- **US4**: All tasks sequential (integration testing builds on previous validations)

### Parallel Opportunities

- **Phase 1 Setup**: All tasks (T001-T002) can run in parallel
- **Phase 2 Foundational**: T004-T005 can run in parallel, then T006, then T007 (validation)
- **Phase 3 US1**:
  - T008-T010 (output definitions) in parallel
  - T012-T014 (service definitions) in parallel
  - T021-T023 (VNC connectivity tests) in parallel
- **Phase 4 US2**: T026 (documentation) in parallel with testing tasks
- **Phase 7 Polish**: T056-T058 (documentation) can run in parallel

---

## Parallel Example: User Story 1 Core Configuration

```bash
# Launch all output definitions together:
Task: "Define HEADLESS-1 output configuration in /etc/nixos/home-modules/desktop/sway.nix"
Task: "Define HEADLESS-2 output configuration in /etc/nixos/home-modules/desktop/sway.nix"
Task: "Define HEADLESS-3 output configuration in /etc/nixos/home-modules/desktop/sway.nix"

# Launch all service definitions together:
Task: "Create wayvnc@HEADLESS-1.service systemd user service (port 5900)"
Task: "Create wayvnc@HEADLESS-2.service systemd user service (port 5901)"
Task: "Create wayvnc@HEADLESS-3.service systemd user service (port 5902)"

# Launch all VNC connectivity tests together:
Task: "Test VNC connectivity to port 5900 (HEADLESS-1) from local machine"
Task: "Test VNC connectivity to port 5901 (HEADLESS-2) from local machine"
Task: "Test VNC connectivity to port 5902 (HEADLESS-3) from local machine"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T007) - CRITICAL
3. Complete Phase 3: User Story 1 (T008-T025)
4. **STOP and VALIDATE**: Test three displays via VNC independently
5. Demo/use the multi-monitor setup before proceeding

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (T008-T025) → Test independently → Deploy/Demo (MVP! - Three working displays)
3. Add User Story 2 (T026-T035) → Test independently → Enhanced (Custom resolutions)
4. Add User Story 3 (T036-T044) → Test independently → Production-ready (Persistence)
5. Add User Story 4 (T045-T055) → Test independently → Fully integrated (i3pm)
6. Add Polish (T056-T070) → Complete (Documentation and edge cases)

### Sequential Strategy (Recommended for single developer)

1. Complete Setup + Foundational together (T001-T007)
2. Focus on User Story 1 until fully working (T008-T025)
3. Validate MVP before moving on
4. Add User Story 4 (i3pm integration) next as it's P2 and critical for workflow (T045-T055)
5. Add User Story 2 (resolution customization) if needed (T026-T035)
6. Add User Story 3 (persistence testing) to ensure robustness (T036-T044)
7. Polish and document (T056-T070)

---

## Notes

- [P] tasks = different sections of same file or different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- This is a system configuration feature, not application code - testing is primarily manual via VNC connectivity
- Always run `sudo nixos-rebuild dry-build` before `switch` to catch configuration errors
- Keep backups of working configurations (T001-T002) for easy rollback
- Commit after each phase or logical group of tasks
- Stop at any checkpoint to validate story independently
- User Story 1 is the MVP - everything else is enhancement

---

## Task Summary

- **Total Tasks**: 70
- **Phase 1 (Setup)**: 3 tasks
- **Phase 2 (Foundational)**: 4 tasks (BLOCKS all user stories)
- **Phase 3 (User Story 1 - P1)**: 18 tasks (MVP - Three virtual displays)
- **Phase 4 (User Story 2 - P2)**: 10 tasks (Resolution customization)
- **Phase 5 (User Story 3 - P3)**: 9 tasks (Persistence)
- **Phase 6 (User Story 4 - P2)**: 11 tasks (i3pm integration)
- **Phase 7 (Polish)**: 15 tasks (Documentation and edge cases)

**MVP Scope (Recommended)**: Phase 1 + Phase 2 + Phase 3 = 25 tasks
**Full Feature**: All 70 tasks

**Parallel Opportunities**:
- 9 tasks can run in parallel (output definitions, service definitions, documentation)
- Reduces total execution time by ~15-20% if parallelized

**Independent Test Criteria**:
- **US1**: Connect three VNC clients, verify distinct workspace views
- **US2**: Change one display resolution, verify it alone changes
- **US3**: Reboot VM, verify all displays and workspaces persist
- **US4**: Switch projects, verify workspaces distribute across three displays

**Suggested MVP Delivery**: User Story 1 only (25 tasks) provides core multi-monitor functionality - deploy this first, then incrementally add US4 (i3pm), US2 (customization), and US3 (persistence) based on user needs.
