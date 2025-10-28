# Tasks: Hetzner Cloud Sway Configuration with Headless Wayland

**Feature**: 046-revise-my-spec
**Input**: Design documents from `/specs/046-revise-my-spec/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No automated tests required - manual validation via quickstart.md test scenarios

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **NixOS Configuration**: `/etc/nixos/` repository root
- **System modules**: `/etc/nixos/modules/`
- **Home-manager modules**: `/etc/nixos/home-modules/`
- **Configurations**: `/etc/nixos/configurations/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repository state verification and documentation preparation

- [X] T001 Verify Feature 045 (M1 Sway) modules exist: `modules/desktop/sway.nix`, `modules/desktop/wayvnc.nix`, `home-modules/desktop/sway.nix`
- [X] T002 Verify Feature 043 (Walker) exists: `home-modules/desktop/walker.nix` with Elephant backend configured
- [X] T003 [P] Verify i3pm daemon exists: `home-modules/desktop/i3-project-event-daemon/` with Sway-compatible handlers.py
- [X] T004 [P] Read existing hetzner.nix configuration to understand current structure and imports

**Checkpoint**: ✅ Verified all prerequisite modules exist from Features 043 and 045 - ready for hetzner-sway configuration

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core headless Sway configuration infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until headless backend is configured

- [X] T005 Create `/etc/nixos/configurations/hetzner-sway.nix` with base structure (imports base.nix, hardware/hetzner.nix)
- [X] T006 Add hetzner-sway flake output to `/etc/nixos/flake.nix` (nixosConfigurations.hetzner-sway with home-manager integration)
- [X] T007 Configure headless Wayland environment variables in `configurations/hetzner-sway.nix` (WLR_BACKENDS=headless, WLR_LIBINPUT_NO_DEVICES=1, WLR_RENDERER=pixman)
- [X] T008 Import sway.nix module in `configurations/hetzner-sway.nix` (enables Sway compositor)
- [X] T009 Import wayvnc.nix module in `configurations/hetzner-sway.nix` (enables VNC server)
- [X] T010 Configure greetd display manager in `configurations/hetzner-sway.nix` (headless login with tuigreet)
- [X] T011 Enable user lingering for vpittamp in `configurations/hetzner-sway.nix` (persistent session after logout)
- [X] T012 Test configuration builds locally: `nixos-rebuild dry-build --flake .#hetzner-sway`

**Checkpoint**: ✅ Foundation ready - hetzner-sway builds successfully and can be deployed

---

## Phase 3: User Story 1 - Headless Sway Session on Hetzner Cloud (Priority: P1) 🎯 MVP

**Goal**: Establish functional headless Sway session with VNC remote access for basic tiling window management

**Independent Test**: SSH into Hetzner VM after deployment, verify SWAYSOCK is set, connect via VNC client to port 5900, test window creation and tiling with Meta+Return

### Implementation for User Story 1

- [X] T013 [US1] Create `/etc/nixos/home-modules/hetzner-sway.nix` as home-manager entry point (imports: programs, shell, desktop modules)
- [X] T014 [US1] Configure Sway virtual output in `home-modules/desktop/sway.nix` (add headless-specific output config: HEADLESS-1, 1920x1080@60Hz)
- [X] T015 [US1] Configure wayvnc systemd service in `home-modules/desktop/sway.nix` (After=sway-session.target, Requires=sway-session.target)
- [X] T016 [US1] Create wayvnc config template in `home-modules/desktop/sway.nix` (xdg.configFile."wayvnc/config": address=0.0.0.0, port=5900, enable_auth=true)
- [X] T017 [US1] Update flake.nix to include home-manager configuration for hetzner-sway (home-manager.users.vpittamp = import ./home-modules/hetzner-sway.nix)
- [X] T018 [US1] Test home-manager build: `home-manager build --flake .#vpittamp@hetzner-sway`
- [ ] T019 [US1] Deploy to Hetzner VM: `nixos-rebuild switch --flake .#hetzner-sway --target-host vpittamp@hetzner --use-remote-sudo`
- [ ] T020 [US1] Reboot Hetzner VM to start headless Sway session: `ssh vpittamp@hetzner 'sudo reboot'`
- [ ] T021 [US1] Execute Test Scenario 1 from quickstart.md (Steps 1.1-1.5: verify headless Sway running, wayvnc listening, VNC connection working, window management functional)

**Checkpoint**: User Story 1 complete - headless Sway accessible via VNC with functional tiling window management

---

## Phase 4: User Story 2 - i3pm Daemon Integration for Headless Sway (Priority: P1)

**Goal**: Enable i3pm daemon for project-scoped window management on headless Sway (identical behavior to M1 Sway and Hetzner i3)

**Independent Test**: Start i3pm daemon on headless Sway, create two projects (nixos, stacks), launch VS Code for each via VNC, switch projects with Meta+P, verify windows hide/show correctly

### Implementation for User Story 2

- [ ] T022 [US2] Import i3pm daemon systemd service in `home-modules/hetzner-sway.nix` (from home-modules/desktop/i3-project-event-daemon/default.nix)
- [ ] T023 [US2] Update i3pm daemon service dependencies in `home-modules/desktop/i3-project-event-daemon/default.nix` (ensure After=sway-session.target, Requires=sway-session.target)
- [ ] T024 [US2] Verify sway-session.target is defined in `home-modules/desktop/sway.nix` (systemd.user.targets.sway-session)
- [ ] T025 [US2] Deploy updated configuration: `nixos-rebuild switch --flake .#hetzner-sway --target-host vpittamp@hetzner --use-remote-sudo`
- [ ] T026 [US2] Execute Test Scenario 2 from quickstart.md (Steps 2.1-2.6: verify daemon connects to Sway IPC, test project creation, test window marking, test project switching with window hiding/restoration)

**Checkpoint**: User Story 2 complete - i3pm daemon working on headless Sway with identical functionality to other configurations

---

## Phase 5: User Story 3 - Walker Launcher on Headless Sway (Priority: P1)

**Goal**: Enable Walker application launcher for keyboard-driven application launching, file search, calculator, and project switching via VNC

**Independent Test**: Connect to Hetzner Sway via VNC, press Meta+D to launch Walker, test application search, calculator (=2+2), project switcher (;p ), verify all providers work remotely

### Implementation for User Story 3

- [ ] T027 [US3] Import Walker/Elephant configuration in `home-modules/hetzner-sway.nix` (from home-modules/desktop/walker.nix)
- [ ] T028 [US3] Verify Elephant systemd service is configured to start with sway-session.target (check walker.nix for service dependencies)
- [ ] T029 [US3] Verify Walker keybinding (Meta+D) is configured in `home-modules/desktop/sway.nix` (wayland.windowManager.sway.config.keybindings)
- [ ] T030 [US3] Deploy updated configuration: `nixos-rebuild switch --flake .#hetzner-sway --target-host vpittamp@hetzner --use-remote-sudo`
- [ ] T031 [US3] Execute Test Scenario 3 from quickstart.md (Steps 3.1-3.4: test application launcher, calculator provider, project switcher, clipboard provider with wl-clipboard)

**Checkpoint**: User Story 3 complete - Walker fully functional on headless Sway with all providers working via VNC

---

## Phase 6: User Story 4 - Remote Desktop Performance Optimization (Priority: P2)

**Goal**: Optimize headless Sway and wayvnc settings for acceptable VNC performance (window creation <500ms, workspace switching <200ms, keyboard latency <100ms)

**Independent Test**: Connect to Hetzner Sway via VNC, perform rapid window operations, measure response times and visual quality per Test Scenario 4

### Implementation for User Story 4

- [ ] T032 [P] [US4] Review wayvnc config in `home-modules/desktop/sway.nix` and adjust max_rate if needed (default: 60 FPS, consider 30 FPS for lower bandwidth)
- [ ] T033 [P] [US4] Review Sway renderer config and ensure WLR_RENDERER=pixman is set for software rendering (already in configurations/hetzner-sway.nix from T007)
- [ ] T034 [US4] Deploy configuration if changes made: `nixos-rebuild switch --flake .#hetzner-sway --target-host vpittamp@hetzner --use-remote-sudo`
- [ ] T035 [US4] Execute Test Scenario 4 from quickstart.md (Steps 4.1-4.5: measure window creation latency, workspace switching latency, project switching performance, resource usage, keyboard input latency)
- [ ] T036 [US4] Document performance findings in quickstart.md or create performance tuning guide if adjustments were needed

**Checkpoint**: User Story 4 complete - VNC performance optimized and acceptable for remote development workflows

---

## Phase 7: User Story 5 - Configuration Isolation from Existing Hetzner (Priority: P2)

**Goal**: Verify hetzner-sway is completely isolated from existing hetzner i3 configuration, both can coexist, and can switch between them safely

**Independent Test**: Build both hetzner and hetzner-sway configurations, verify they produce different system closures, confirm hetzner.nix is unchanged after hetzner-sway deployment

### Implementation for User Story 5

- [ ] T037 [US5] Verify hetzner.nix has not been modified (git diff configurations/hetzner.nix should show no changes)
- [ ] T038 [US5] Build hetzner configuration locally: `nixos-rebuild dry-build --flake .#hetzner`
- [ ] T039 [US5] Compare system closures: `nix build .#nixosConfigurations.hetzner.config.system.build.toplevel -o result-hetzner && nix build .#nixosConfigurations.hetzner-sway.config.system.build.toplevel -o result-hetzner-sway`
- [ ] T040 [US5] Execute Test Scenario 5 from quickstart.md (Steps 5.1-5.4: verify hetzner config unchanged, test switching between configurations, verify no Wayland packages in hetzner, verify both configs build from same flake)
- [ ] T041 [US5] Document rollback procedure in quickstart.md (how to switch from hetzner-sway back to hetzner if needed)

**Checkpoint**: User Story 5 complete - configuration isolation validated, both configs coexist safely

---

## Phase 8: User Story 6 - Multi-Monitor Support via Virtual Displays (Priority: P3) [OPTIONAL]

**Goal**: Support multiple virtual outputs (HEADLESS-1, HEADLESS-2) with workspace distribution across outputs for advanced multi-monitor remote workflows

**Independent Test**: Configure headless Sway with two virtual outputs, run `i3pm monitors status`, verify workspace 1-2 on HEADLESS-1 and workspace 3-70 on HEADLESS-2

### Implementation for User Story 6

- [ ] T042 [US6] Update Sway output configuration in `home-modules/desktop/sway.nix` to add second virtual output (HEADLESS-2, 1920x1080@60Hz, positioned at x=1920, y=0)
- [ ] T043 [US6] Update i3pm workspace-monitor mapping config if needed (ensure workspace distribution logic handles virtual outputs correctly)
- [ ] T044 [US6] Deploy configuration: `nixos-rebuild switch --flake .#hetzner-sway --target-host vpittamp@hetzner --use-remote-sudo`
- [ ] T045 [US6] Execute Test Scenario 6 from quickstart.md (Steps 6.1-6.5: verify two virtual outputs created, test workspace distribution, test VNC access to second output, verify monitor status command)
- [ ] T046 [US6] Document multi-output configuration process and limitations (wayvnc exposes one output at a time, switching requires config change and restart)

**Checkpoint**: User Story 6 complete - multi-virtual-output support functional for advanced workflows

---

## Phase 9: Polish & Documentation

**Purpose**: Final integration testing, documentation updates, and edge case validation

- [ ] T047 Run automated test suite from quickstart.md: `bash test-feature-046.sh` (create test script based on quickstart.md test scenarios)
- [ ] T048 Execute all 5 edge case tests from quickstart.md (VNC disconnection handling, wayvnc failure recovery, display scaling, software rendering, parallel deployments)
- [ ] T049 Update `/etc/nixos/CLAUDE.md` with Feature 046 quickstart reference and common commands
- [ ] T050 Document troubleshooting tips based on test findings in quickstart.md (expand troubleshooting section with actual issues encountered)
- [ ] T051 [P] Create git commit for Feature 046: `git add . && git commit -m "feat(hetzner-sway): Add headless Sway configuration for Hetzner Cloud VM with VNC remote access (Feature 046)"`
- [ ] T052 [P] Validate all success criteria from spec.md are met (SC-001 through SC-010)

**Checkpoint**: Feature 046 complete and validated - ready for production use

---

## Task Summary

**Total Tasks**: 52
- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Foundational)**: 8 tasks (BLOCKING - must complete before user stories)
- **Phase 3 (US1 - Headless Sway)**: 9 tasks (P1 - MVP)
- **Phase 4 (US2 - i3pm Daemon)**: 5 tasks (P1)
- **Phase 5 (US3 - Walker Launcher)**: 5 tasks (P1)
- **Phase 6 (US4 - Performance)**: 5 tasks (P2)
- **Phase 7 (US5 - Configuration Isolation)**: 5 tasks (P2)
- **Phase 8 (US6 - Multi-Monitor)**: 5 tasks (P3 - OPTIONAL)
- **Phase 9 (Polish)**: 6 tasks

**Parallel Opportunities**:
- Phase 1: T002, T003, T004 can run in parallel (independent verification tasks)
- Phase 6: T032, T033 can run in parallel (different config files)
- Phase 9: T051, T052 can run in parallel (independent validation)

**User Story Dependencies**:
```
Phase 1 (Setup) → Phase 2 (Foundational) → [US1, US2, US3 can run in parallel after Phase 2]
                                         → [US4 depends on US1, US2, US3 complete]
                                         → [US5 can run in parallel with US1-US4]
                                         → [US6 depends on US1 complete]
```

**Independent Test Criteria** (each user story):
- **US1**: Can test by SSHing into VM, verifying Sway headless running, connecting via VNC, testing window management
- **US2**: Can test by launching apps via VNC, switching projects, verifying window hiding/restoration
- **US3**: Can test by opening Walker via VNC (Meta+D), testing all providers (apps, calculator, projects, clipboard)
- **US4**: Can test by measuring latencies and resource usage during various operations
- **US5**: Can test by building both configs, comparing system closures, verifying isolation
- **US6**: Can test by configuring two virtual outputs, verifying workspace distribution

**MVP Scope** (Phases 1-3): Tasks T001-T021
- Establishes headless Sway with VNC access
- Core window management functional
- Minimal viable remote development environment
- **Estimated time**: 3-4 hours

**Full P1 Scope** (Phases 1-5): Tasks T001-T031
- Adds i3pm daemon and Walker launcher
- Complete project-scoped workflow
- Matches feature parity with M1 Sway for P1 user stories
- **Estimated time**: 5-7 hours

**Complete Feature** (Phases 1-9): Tasks T001-T052
- Includes performance optimization, configuration isolation validation, optional multi-monitor, polish
- Production-ready with full documentation
- **Estimated time**: 10-14 hours (8-12 hours excluding optional US6)

---

## Implementation Strategy

**Recommended Approach**: Incremental delivery by user story

1. **Start with MVP** (US1 - Phase 3):
   - Delivers basic headless Sway with VNC
   - Validates technical approach (headless backend, wayvnc, virtual outputs)
   - Testable end-to-end within 3-4 hours
   - Provides immediate value for basic remote access

2. **Add Core Workflows** (US2-US3 - Phases 4-5):
   - Enables project management (US2)
   - Enables keyboard-driven launcher (US3)
   - Completes P1 scope for daily development use
   - Testable incrementally as each story completes

3. **Optimize and Validate** (US4-US5 - Phases 6-7):
   - Improve performance for production use (US4)
   - Validate configuration isolation and safety (US5)
   - Completes P2 scope for production deployment

4. **Optional Enhancement** (US6 - Phase 8):
   - Multi-monitor support for advanced users
   - Can be deferred to future iteration if not immediately needed
   - Testable independently from other stories

5. **Polish and Deploy** (Phase 9):
   - Final integration testing
   - Documentation updates
   - Edge case validation
   - Ready for production

**Rollback Plan**: If issues arise during testing, can switch back to hetzner configuration:
```bash
nixos-rebuild switch --flake .#hetzner --target-host vpittamp@hetzner --use-remote-sudo
sudo reboot
```

**Testing Approach**: Manual validation via quickstart.md test scenarios (no automated tests required per spec)

---

## Dependencies on Other Features

**Hard Dependencies** (must be complete):
- ✅ **Feature 043**: Walker/Elephant Wayland-native support (COMPLETE)
- ✅ **Feature 045**: M1 Sway migration with i3pm daemon Sway compatibility (Phases 1-2 COMPLETE - sufficient for Feature 046)

**Soft Dependencies** (nice to have):
- 🔵 **Feature 045 Complete**: Full M1 Sway validation (not blocking - hetzner-sway can proceed independently)

---

## Validation Checklist

After completing all phases, validate these success criteria from spec.md:

- [ ] **SC-001**: User can log into headless Sway session and perform basic window management via VNC
- [ ] **SC-002**: i3pm daemon connects to Sway IPC within 2 seconds of session start
- [ ] **SC-003**: Project switch hides/shows windows within 500ms
- [ ] **SC-004**: Walker and all providers function correctly on headless Sway
- [ ] **SC-005**: VNC session provides acceptable performance (<500ms window creation, <200ms workspace switch, <100ms keyboard latency)
- [ ] **SC-006**: Multi-instance applications (e.g., VS Code) receive correct project marks
- [ ] **SC-007**: Both hetzner and hetzner-sway configurations are buildable and deployable simultaneously
- [ ] **SC-008**: hetzner configuration remains unchanged after hetzner-sway deployment
- [ ] **SC-009**: Existing i3pm daemon test suite passes (validates Sway IPC compatibility)
- [ ] **SC-010**: `nixos-rebuild switch --flake .#hetzner-sway` succeeds without errors

---

**Tasks Generated**: 2025-10-28
**Ready for Implementation**: Yes
**Next Step**: Begin with Phase 1 (Setup) - Tasks T001-T004
