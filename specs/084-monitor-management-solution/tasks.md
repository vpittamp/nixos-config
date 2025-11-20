# Tasks: M1 Hybrid Multi-Monitor Management

**Input**: Design documents from `/specs/084-monitor-management-solution/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is a NixOS configuration project:
- **System config**: `configurations/`
- **Home-manager modules**: `home-modules/`
- **Daemon code**: `home-modules/desktop/i3-project-event-daemon/`
- **Scripts**: `home-modules/desktop/scripts/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Enable wayvnc and configure M1 for hybrid mode support

- [x] T001 Enable wayvnc service in configurations/m1.nix
- [x] T002 [P] Add Tailscale-only firewall rules (ports 5900-5901) in configurations/m1.nix
- [x] T003 [P] Add isHybridMode detection flag in home-modules/desktop/sway.nix
- [x] T004 [P] Create tests directory structure in tests/084-monitor-management/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core models and profile infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Add HybridMonitorProfile Pydantic model in home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T006 [P] Add OutputConfig model with physical/virtual type in home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T007 [P] Add HybridOutputState model in home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T008 Create M1 monitor profile JSON files (local-only, local+1vnc, local+2vnc) in home-modules/desktop/sway.nix
- [x] T009 [P] Add WayVNC systemd service definitions for HEADLESS-1 and HEADLESS-2 in home-modules/desktop/sway.nix

**Checkpoint**: Foundation ready - profile definitions and models exist, user story implementation can begin

---

## Phase 3: User Story 1 - Activate VNC Display from Local Machine (Priority: P1) 🎯 MVP

**Goal**: Users can activate VNC displays via keyboard shortcut and connect from other devices

**Independent Test**: Press Mod+Shift+M, select local+1vnc profile, connect via VNC client to port 5900

### Implementation for User Story 1

- [x] T010 [US1] Add Mod+Shift+M keybinding for profile cycling in home-modules/desktop/sway-keybindings.nix
- [x] T011 [US1] Implement create_output command in set-monitor-profile.sh in home-modules/desktop/scripts/active-monitors.sh
- [x] T012 [US1] Implement output configuration (mode, position, scale) after create_output in home-modules/desktop/scripts/active-monitors.sh
- [x] T013 [US1] Add WayVNC service start/stop logic to active-monitors.sh in home-modules/desktop/scripts/active-monitors.sh
- [x] T014 [US1] Extend MonitorProfileService.handle_profile_change() for hybrid mode in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T015 [US1] Add async create_virtual_output() method using swaymsg IPC in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T016 [US1] Add async configure_output() method for resolution/position in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T017 [US1] Update daemon.py to detect hybrid mode and initialize services in home-modules/desktop/i3-project-event-daemon/daemon.py
- [x] T018 [US1] Add notification on profile switch success/failure using SwayNC in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T019 [US1] Run nixos-rebuild dry-build --flake .#m1 --impure to validate configuration

**Checkpoint**: User Story 1 complete - users can switch profiles and connect via VNC

---

## Phase 4: User Story 2 - Workspace Distribution Across Displays (Priority: P2)

**Goal**: Workspaces automatically distribute across displays when profiles change

**Independent Test**: Switch to local+2vnc, verify workspaces 1-3 on eDP-1, 4-6 on V1, 7-9 on V2

### Implementation for User Story 2

- [x] T020 [US2] Add workspace-to-output assignment logic for M1 profiles in home-modules/desktop/sway.nix
- [x] T021 [US2] Implement async reassign_workspaces() in MonitorProfileService in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T022 [US2] Add workspace migration for disabled outputs (move to eDP-1) in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T023 [US2] Preserve window state (size, position) during workspace moves in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T024 [US2] Add PWA workspace assignment (50+) to VNC outputs in home-modules/desktop/sway.nix
- [x] T025 [US2] Wire workspace reassignment to OutputStatesWatcher callback in home-modules/desktop/i3-project-event-daemon/daemon.py

**Checkpoint**: User Story 2 complete - workspaces auto-distribute and migrate on profile changes

---

## Phase 5: User Story 3 - Visual Feedback for Monitor Status (Priority: P3)

**Goal**: Top bar shows current profile and active display indicators (L/V1/V2)

**Independent Test**: Switch profiles, observe top bar updates within 100ms with correct indicators

### Implementation for User Story 3

- [x] T026 [US3] Add get_short_name() function for L/V1/V2 indicators in home-modules/desktop/i3-project-event-daemon/eww_publisher.py
- [x] T027 [US3] Update M1MonitorState model with hybrid mode field in home-modules/desktop/i3-project-event-daemon/models/monitor_profile.py
- [x] T028 [US3] Extend EwwPublisher.publish_from_conn() for hybrid mode in home-modules/desktop/i3-project-event-daemon/eww_publisher.py
- [x] T029 [US3] Update Eww top bar widget to display L/V1/V2 format in home-modules/desktop/eww-top-bar.nix
- [x] T030 [US3] Update Eww monitor state variable schema in home-modules/desktop/eww-top-bar/eww.yuck
- [x] T031 [US3] Add profile name display in teal pill format in home-modules/desktop/eww-top-bar/eww.yuck

**Checkpoint**: User Story 3 complete - top bar shows real-time profile and output status

---

## Phase 6: User Story 4 - Secure Remote Access via Tailscale (Priority: P4)

**Goal**: VNC access restricted to Tailscale network only

**Independent Test**: Connect to VNC from Tailscale device (success), attempt from public IP (fail)

### Implementation for User Story 4

- [x] T032 [US4] Verify firewall rules block non-tailscale0 interfaces in configurations/m1.nix
- [x] T033 [US4] Add security documentation to quickstart.md in specs/084-monitor-management-solution/quickstart.md
- [x] T034 [US4] Test firewall rules by attempting external connection (manual verification)

**Checkpoint**: User Story 4 complete - VNC access is Tailscale-only

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Error handling, documentation, and validation across all stories

- [x] T035 [P] Add rollback logic for failed profile switches in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T036 [P] Handle edge case: VNC client disconnect during profile switch in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T037 [P] Handle edge case: virtual output creation failure in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T038 [P] Limit virtual outputs to maximum 2 with user notification in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T039 [P] Add Feature 084 logging with structured tags in home-modules/desktop/i3-project-event-daemon/monitor_profile_service.py
- [x] T040 Update CLAUDE.md with M1 monitor management section in CLAUDE.md
- [ ] T041 [P] Create sway-test for profile switching in tests/084-monitor-management/test_profile_switch.json
- [ ] T042 [P] Create sway-test for VNC activation in tests/084-monitor-management/test_vnc_activation.json
- [ ] T043 [P] Create sway-test for workspace distribution in tests/084-monitor-management/test_workspace_distribution.json
- [x] T044 Final nixos-rebuild dry-build --flake .#m1 --impure validation
- [ ] T045 End-to-end manual test: full profile cycle with VNC connection

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3 → P4)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational - Independent of US1 (different components)
- **User Story 3 (P3)**: Can start after Foundational - Uses EwwPublisher independently
- **User Story 4 (P4)**: Minimal work - firewall rules set in Setup

### Within Each User Story

- Models/Nix config before service code
- Service implementation before daemon integration
- Core implementation before edge cases
- nixos-rebuild dry-build after each major change

### Parallel Opportunities

**Phase 1 (Setup)**:
- T002, T003, T004 can all run in parallel

**Phase 2 (Foundational)**:
- T006, T007, T009 can run in parallel (different files)

**Phase 7 (Polish)**:
- T035, T036, T037, T038, T039 can run in parallel (different concerns)
- T041, T042, T043 can run in parallel (different test files)

**Cross-Story Parallelism**:
- After Phase 2, all user stories CAN be implemented in parallel if desired
- US3 (Eww updates) has no code dependencies on US1/US2

---

## Parallel Example: User Story 3 (Eww Updates)

```bash
# These tasks can be launched together (different files):
Task: "T026 Add get_short_name() function in eww_publisher.py"
Task: "T027 Update M1MonitorState model in monitor_profile.py"
Task: "T029 Update Eww top bar widget in eww-top-bar.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T009)
3. Complete Phase 3: User Story 1 (T010-T019)
4. **STOP and VALIDATE**: Test profile switching with VNC connection
5. Deploy if ready - users can now extend display via VNC

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Test VNC activation → Deploy (MVP!)
3. Add User Story 2 → Test workspace distribution → Deploy
4. Add User Story 3 → Test top bar feedback → Deploy
5. Add User Story 4 → Test security → Deploy (Complete feature)

### Suggested MVP Scope

**MVP = Phase 1 + Phase 2 + Phase 3 (User Story 1)**

This delivers:
- Profile switching via Mod+Shift+M
- VNC display activation
- Remote connection capability

Total MVP tasks: **19 tasks** (T001-T019)

---

## Summary

| Phase | Tasks | Parallel | Purpose |
|-------|-------|----------|---------|
| Setup | 4 | 3 | Enable wayvnc, firewall, detection flags |
| Foundational | 5 | 3 | Models, profiles, WayVNC services |
| User Story 1 | 10 | 0 | Core VNC activation (MVP) |
| User Story 2 | 6 | 0 | Workspace distribution |
| User Story 3 | 6 | 3 | Top bar indicators |
| User Story 4 | 3 | 0 | Security hardening |
| Polish | 11 | 8 | Error handling, docs, tests |

**Total: 45 tasks**

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- Each user story is independently testable after completion
- Commit after each task or logical group
- Run `nixos-rebuild dry-build --flake .#m1 --impure` frequently
- Stop at any checkpoint to validate story independently
