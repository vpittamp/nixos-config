# Tasks: Migrate M1 MacBook Pro to Sway with i3pm Integration

**Input**: Design documents from `/specs/045-migrate-m1-macbook/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No test tasks included - not explicitly requested in spec. Python daemon tests remain unchanged and validate protocol compatibility.

**Organization**: Tasks are grouped by user story (P1, P2, P3) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5, US6)
- Include exact file paths in descriptions

## Path Conventions
- NixOS configuration: `/etc/nixos/`
- System modules: `/etc/nixos/modules/desktop/`
- Home-manager modules: `/etc/nixos/home-modules/desktop/`
- Python daemon: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/`
- Target configuration: `/etc/nixos/configurations/m1.nix`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic Sway configuration structure

- [X] T001 Create Sway system module at `/etc/nixos/modules/desktop/sway.nix` (parallel to i3wm.nix structure)
- [X] T002 [P] Create wayvnc system module at `/etc/nixos/modules/desktop/wayvnc.nix` for remote access
- [X] T003 [P] Create Sway home-manager module at `/etc/nixos/home-modules/desktop/sway.nix` (parallel to i3.nix)
- [X] T004 [P] Create swaybar configuration module at `/etc/nixos/home-modules/desktop/swaybar.nix` (parallel to i3bar.nix)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core configuration changes that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 Update M1 target configuration in `/etc/nixos/configurations/m1.nix`: replace KDE Plasma imports with Sway module imports
- [ ] T006 Configure Wayland environment variables in Sway system module (MOZ_ENABLE_WAYLAND, NIXOS_OZONE_WL, QT_QPA_PLATFORM=wayland)
- [ ] T007 Configure per-output display scaling in Sway home-manager module: eDP-1 scale 2.0, external monitors scale 1.0
- [ ] T008 [P] Update Python daemon `connection.py` to remove xprop subprocess calls, use i3ipc container.ipc_data['pid'] directly
- [ ] T009 [P] Update Python daemon `handlers.py` to check app_id before window_properties.class for Wayland-first window identification
- [ ] T010 [P] Update Python daemon `window_filter.py` to use Sway IPC window properties instead of xprop

**Checkpoint**: Foundation ready - Sway modules created, Python daemon adapted for Sway IPC, user story implementation can now begin

---

## Phase 3: User Story 1 - Basic Sway Window Management (Priority: P1) 🎯 MVP

**Goal**: Establish functional tiling window manager with keyboard-driven workflows on M1 MacBook Pro with Retina display scaling

**Independent Test**: Log into Sway session, press Meta+Return to open terminal, verify tiling behavior works correctly with 2x scaling on Retina display, switch workspaces with Ctrl+1-9

### Implementation for User Story 1

- [ ] T011 [P] [US1] Configure Sway keybindings in `home-modules/desktop/sway.nix`: Meta+Return (terminal), Meta+Arrow (focus), Meta+Shift+Q (close), Ctrl+1-9 (workspace switch)
- [ ] T012 [P] [US1] Configure Sway window rules in `home-modules/desktop/sway.nix`: floating rules for Walker, workspace assignments for applications
- [ ] T013 [US1] Configure Sway bar in `home-modules/desktop/swaybar.nix`: position, status_command with i3bar-status-event-driven.sh, workspace buttons
- [ ] T014 [US1] Configure Sway output resolution and refresh rate in `home-modules/desktop/sway.nix`: eDP-1 2560x1600@60Hz, HDMI-A-1 auto-detection
- [ ] T015 [US1] Configure Sway startup commands in `home-modules/desktop/sway.nix`: i3-project-event-listener, Elephant service dependency
- [ ] T016 [US1] Test Sway session startup via remote build: `nixos-rebuild dry-build --flake .#m1 --impure --target-host vpittamp@m1-macbook`
- [ ] T017 [US1] Deploy Sway configuration: `nixos-rebuild switch --flake .#m1 --impure --target-host vpittamp@m1-macbook --use-remote-sudo`

**Checkpoint**: At this point, User Story 1 should be fully functional - Sway starts, keyboard shortcuts work, display scaling correct, windows tile properly

---

## Phase 4: User Story 2 - i3pm Daemon Integration (Priority: P1)

**Goal**: Enable project-scoped window management with automatic marking and filtering based on I3PM environment variables

**Independent Test**: Start i3pm daemon, create two projects (nixos and stacks), launch VS Code for each project, switch projects with Meta+P, verify windows hide/show correctly

### Implementation for User Story 2

- [ ] T018 [US2] Verify i3pm daemon systemd service starts with Sway session in `home-modules/desktop/sway.nix` startup commands
- [ ] T019 [US2] Update daemon startup scan in `handlers.py` to use Sway IPC GET_TREE for initial window marking (unchanged logic, just property access)
- [ ] T020 [US2] Verify window::new event handler in `handlers.py` applies project marks correctly using Sway window properties
- [ ] T021 [US2] Verify tick event handler in `window_filter.py` correctly hides/shows windows based on I3PM_PROJECT_NAME from /proc environ
- [ ] T022 [US2] Test project switching: verify `i3pm project switch nixos` hides non-matching scoped windows, shows matching windows
- [ ] T023 [US2] Validate daemon connection via `i3pm daemon status`: should show "Connection: Sway IPC" with socket path

**Checkpoint**: At this point, User Stories 1 AND 2 should work - Sway functions, daemon connects, project switching works, windows filter correctly

---

## Phase 5: User Story 3 - Walker Launcher with Native Wayland (Priority: P1)

**Goal**: Enable keyboard-driven application launcher with native Wayland operation, correct display scaling, and clipboard support

**Independent Test**: Press Meta+D, verify Walker opens centered with Retina scaling, type application names for fuzzy search, test calculator "=2+2", verify project switcher ";p " works

### Implementation for User Story 3

- [ ] T024 [P] [US3] Remove X11 compatibility mode from `home-modules/desktop/walker.nix`: delete `as_window = true` line from config.toml
- [ ] T025 [P] [US3] Enable clipboard provider in Walker config: set `clipboard = true` in modules section (was disabled for X11)
- [ ] T026 [US3] Update Elephant service environment in `home-modules/desktop/walker.nix`: add WAYLAND_DISPLAY=wayland-1, remove DISPLAY PassEnvironment
- [ ] T027 [US3] Add wl-clipboard package dependency to `home-modules/desktop/walker.nix` for clipboard provider support
- [ ] T028 [US3] Update Walker keybinding in `home-modules/desktop/sway.nix`: remove GDK_BACKEND=x11 override, use native `bindsym $mod+d exec walker`
- [ ] T029 [US3] Test Walker launch via Meta+D: verify centered window, correct scaling, fuzzy search works
- [ ] T030 [US3] Test Walker providers: applications, calculator, files, symbols, websearch, runner, sesh, projects, clipboard
- [ ] T031 [US3] Verify app-launcher-wrapper integration: launched apps receive I3PM_* environment variables and correct project context

**Checkpoint**: All P1 user stories complete - Sway functions, daemon works, Walker launches apps with project context

---

## Phase 6: User Story 4 - Python Daemon Window Tracking (Priority: P2)

**Goal**: Enhance daemon reliability for multi-instance application tracking using Sway native window properties without xprop

**Independent Test**: Launch two VS Code instances for different projects within 1 second, run `i3pm windows --tree`, verify both have distinct project marks and appear on correct workspaces

### Implementation for User Story 4

- [ ] T032 [US4] Implement Sway-compatible window property accessor function in `connection.py`: returns {pid, app_id, window_class, title} from container
- [ ] T033 [US4] Update window correlation logic in `handlers.py` to use Sway window properties for matching pending launches to windows
- [ ] T034 [US4] Add app_id fallback handling in `handlers.py`: if app_id is None, use window_properties.class for XWayland apps
- [ ] T035 [US4] Update startup scan in `handlers.py` to read all windows via Sway IPC GET_TREE, apply marks based on /proc environ
- [ ] T036 [US4] Add error handling for missing PID in Sway tree: log warning, skip marking, continue processing other windows
- [ ] T037 [US4] Test rapid launch scenario: launch two VS Code instances 0.5s apart, verify both receive correct distinct project marks
- [ ] T038 [US4] Validate window tracking via `i3pm diagnose window <window_id>`: should show matched_via_launch, correlation confidence, app_id

**Checkpoint**: User Story 4 complete - daemon reliably tracks multi-instance applications using Sway IPC without xprop subprocess overhead

---

## Phase 7: User Story 5 - Multi-Monitor Workspace Distribution (Priority: P2)

**Goal**: Automatically distribute workspaces across built-in Retina display and external monitors using same configuration as Hetzner

**Independent Test**: Connect external monitor, run `i3pm monitors status`, verify workspace 1-2 on built-in display (eDP-1), workspace 3+ on external monitor

### Implementation for User Story 5

- [ ] T039 [US5] Verify existing workspace-monitor-mapping.json configuration compatible with Sway (protocol-agnostic, no changes needed)
- [ ] T040 [US5] Test output::added event subscription in daemon: connect external monitor, verify daemon receives event and triggers reassignment
- [ ] T041 [US5] Update workspace-monitor-mapping.json with Sway output names: query via `swaymsg -t get_outputs`, record eDP-1, HDMI-A-1, etc.
- [ ] T042 [US5] Test workspace distribution with 1 monitor (built-in only): verify all workspaces 1-70 assigned to eDP-1
- [ ] T043 [US5] Test workspace distribution with 2 monitors: verify WS 1-2 on eDP-1 (built-in), WS 3-70 on HDMI-A-1 (external)
- [ ] T044 [US5] Test monitor disconnection: remove external monitor, verify workspaces consolidate to built-in display after 1s debounce
- [ ] T045 [US5] Validate via `i3pm monitors workspaces`: should show correct workspace-to-output assignments matching configuration

**Checkpoint**: User Story 5 complete - multi-monitor workspace distribution works identically to Hetzner i3 configuration

---

## Phase 8: User Story 6 - Remote Access via VNC (Priority: P3)

**Goal**: Provide VNC remote access to M1 Sway desktop for remote work scenarios

**Independent Test**: Start wayvnc service via systemd, connect from remote machine with VNC client, verify Sway desktop visible and interactive

### Implementation for User Story 6

- [ ] T046 [P] [US6] Create wayvnc configuration file template in `modules/desktop/wayvnc.nix`: enable_auth=true, enable_pam=true, port=5900
- [ ] T047 [P] [US6] Configure wayvnc systemd user service in `modules/desktop/wayvnc.nix`: Type=notify, ExecStart, Restart=on-failure, after graphical-session.target
- [ ] T048 [US6] Add wayvnc package to system packages in `modules/desktop/wayvnc.nix`
- [ ] T049 [US6] Generate wayvnc config file via xdg.configFile in `modules/desktop/wayvnc.nix`: write to ~/.config/wayvnc/config
- [ ] T050 [US6] Enable wayvnc module in M1 configuration: import wayvnc.nix in `configurations/m1.nix`
- [ ] T051 [US6] Test wayvnc service startup: `systemctl --user status wayvnc`, verify listening on port 5900
- [ ] T052 [US6] Test VNC connection from remote client: connect to M1 IP:5900, authenticate, verify Sway desktop visible
- [ ] T053 [US6] Test VNC input: type in remote client, move mouse, verify events reach Sway applications correctly

**Checkpoint**: All user stories complete (P1, P2, P3) - full Sway migration with i3pm integration and remote access functional

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and final integration testing

- [ ] T054 [P] Update CLAUDE.md with M1 Sway build instructions: document --impure flag requirement, remote build commands, Sway-specific commands
- [ ] T055 [P] Update quickstart.md with post-deployment validation steps: Sway session startup, daemon connection, Walker launch, project switching
- [ ] T056 [P] Document Sway vs i3 differences in migration guide: app_id vs window_class, output names (DRM vs X11), wayvnc vs XRDP limitations
- [ ] T057 Run existing Python daemon test suite: `pytest tests/i3-project-daemon/` - all tests should pass without modification (protocol compatibility)
- [ ] T058 Run quickstart.md validation: follow all test procedures, verify Sway session, daemon, Walker, project switching, multi-monitor, VNC
- [ ] T059 Stage all modified files for git: `git add modules/desktop/sway.nix home-modules/desktop/sway.nix configurations/m1.nix home-modules/desktop/i3-project-event-daemon/*.py`
- [ ] T060 Create feature branch commit: `git commit -m "feat(m1): Migrate from KDE Plasma to Sway with i3pm integration"` with co-authored-by Claude

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - P1 stories (US1, US2, US3) should complete first (core functionality)
  - P2 stories (US4, US5) can start after P1 if desired (enhancements)
  - P3 story (US6) can start after P1 (nice-to-have)
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1) - Sway Window Management**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1) - i3pm Daemon**: Depends on US1 (needs Sway session running) - Tests project switching
- **User Story 3 (P1) - Walker Launcher**: Depends on US1 and US2 (needs Sway + daemon for project context) - Launches apps with I3PM variables
- **User Story 4 (P2) - Window Tracking**: Depends on US2 (enhances daemon reliability) - Can test independently
- **User Story 5 (P2) - Multi-Monitor**: Depends on US1 (needs Sway running) - Can test independently with external monitor
- **User Story 6 (P3) - VNC Remote Access**: Depends on US1 (needs Sway session) - Can test independently

### Within Each User Story

- Setup tasks (Phase 1) before Foundational tasks (Phase 2)
- Foundational tasks complete before any user story implementation
- Configuration changes before testing/validation tasks
- Core implementation before integration testing
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1 Setup**: All 4 tasks marked [P] can run in parallel (creating different module files)
- **Phase 2 Foundational**: Tasks T005-T007 (configuration) can run in parallel with T008-T010 (Python daemon changes)
- **Once Foundational completes**:
  - US1, US5, US6 can technically start in parallel (independent of each other)
  - US2 must wait for US1 (needs running Sway session)
  - US3 must wait for US1+US2 (needs daemon for project context)
  - US4 must wait for US2 (enhances daemon functionality)
- **Within stories**: Tasks marked [P] can run in parallel (e.g., T024, T025, T026 in US3 are independent config changes)

---

## Parallel Example: Phase 1 Setup

```bash
# Launch all setup tasks together (creating different files):
Task T001: "Create modules/desktop/sway.nix"
Task T002: "Create modules/desktop/wayvnc.nix" [P]
Task T003: "Create home-modules/desktop/sway.nix" [P]
Task T004: "Create home-modules/desktop/swaybar.nix" [P]
```

## Parallel Example: User Story 3

```bash
# Launch Walker configuration changes together:
Task T024: "Remove as_window from walker.nix" [P]
Task T025: "Enable clipboard in walker.nix" [P]
Task T026: "Update Elephant environment in walker.nix" [P]
Task T027: "Add wl-clipboard dependency" [P]
Task T028: "Update keybinding in sway.nix" (can run in parallel with T024-T027)
```

---

## Implementation Strategy

### MVP First (User Stories 1-3 Only - All P1)

1. Complete Phase 1: Setup (4 tasks, can run in parallel)
2. Complete Phase 2: Foundational (6 tasks, CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 - Sway Window Management (7 tasks)
4. Complete Phase 4: User Story 2 - i3pm Daemon Integration (6 tasks, depends on US1)
5. Complete Phase 5: User Story 3 - Walker Launcher (8 tasks, depends on US1+US2)
6. **STOP and VALIDATE**: Test all P1 stories work together
7. Deploy and demo if ready

**MVP Milestone**: At this point, M1 MacBook Pro has functional Sway with keyboard-driven workflows, project-scoped window management, and application launcher with project context inheritance - matching core Hetzner i3 functionality.

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (10 tasks)
2. Add User Story 1 → Test independently → Basic Sway works (7 tasks, 17 total)
3. Add User Story 2 → Test independently → Project management works (6 tasks, 23 total)
4. Add User Story 3 → Test independently → Walker launcher works (8 tasks, 31 total) **← MVP COMPLETE**
5. Add User Story 4 → Test independently → Enhanced daemon reliability (7 tasks, 38 total)
6. Add User Story 5 → Test independently → Multi-monitor support (7 tasks, 45 total)
7. Add User Story 6 → Test independently → Remote VNC access (8 tasks, 53 total)
8. Polish phase → Documentation and validation (7 tasks, 60 total)

Each story adds value without breaking previous stories.

### Sequential Strategy (Recommended for Single Developer)

With one developer (remote build workflow):

1. Complete Phase 1 Setup (can parallelize file creation)
2. Complete Phase 2 Foundational (critical path - Python daemon + config)
3. US1: Sway Window Management → Test → Validate
4. US2: i3pm Daemon Integration → Test → Validate
5. US3: Walker Launcher → Test → Validate (MVP checkpoint)
6. US4: Window Tracking Enhancement → Test → Validate
7. US5: Multi-Monitor Support → Test → Validate
8. US6: VNC Remote Access → Test → Validate
9. Phase 9: Polish and documentation

**Build/Deploy Pattern**: After each user story completion, run remote build validation:
```bash
nixos-rebuild dry-build --flake .#m1 --impure --target-host vpittamp@m1-macbook
nixos-rebuild switch --flake .#m1 --impure --target-host vpittamp@m1-macbook --use-remote-sudo
```

---

## Notes

- **[P] tasks**: Different files, no dependencies, can run in parallel
- **[Story] label**: Maps task to specific user story for traceability (US1-US6)
- **Remote build workflow**: All builds deployed from development machine to M1 via SSH
- **--impure flag required**: M1 needs --impure for Asahi firmware access in /boot/asahi
- **Python daemon tests**: Remain unchanged, validate i3 IPC protocol compatibility
- **Sway IPC compatibility**: 100% i3 protocol compatible, minimal code changes needed
- **Display scaling**: Integer scaling (2.0) for Retina built-in, 1.0 for external monitors
- **Commit frequently**: After each task or logical group, stage files and commit
- **Stop at checkpoints**: Validate story independence before proceeding
- **Rollback available**: NixOS generations enable easy rollback if issues arise

---

## Task Count Summary

- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Foundational)**: 6 tasks (BLOCKS all user stories)
- **Phase 3 (US1 - Sway Window Management - P1)**: 7 tasks
- **Phase 4 (US2 - i3pm Daemon - P1)**: 6 tasks
- **Phase 5 (US3 - Walker Launcher - P1)**: 8 tasks
- **Phase 6 (US4 - Window Tracking - P2)**: 7 tasks
- **Phase 7 (US5 - Multi-Monitor - P2)**: 7 tasks
- **Phase 8 (US6 - VNC Remote Access - P3)**: 8 tasks
- **Phase 9 (Polish)**: 7 tasks

**Total**: 60 tasks

**MVP Scope** (P1 stories only): 31 tasks (Setup + Foundational + US1 + US2 + US3)

---

## Success Criteria Mapping

### Measurable Outcomes from Spec

- **SC-001** (US1): User can log into Sway session and perform window management with Retina scaling → T011-T017
- **SC-002** (US2): Daemon connects to Sway IPC within 2s, processes events <100ms → T018-T023
- **SC-003** (US2): Project switching hides/shows windows within 500ms → T022
- **SC-004** (US3): Walker launches with all 7 providers functional → T024-T031
- **SC-005** (US3): Walker displays with correct Retina scaling in native Wayland → T024, T028, T029
- **SC-006** (US4): Multi-instance apps receive correct project marks 100% accuracy → T032-T038
- **SC-007** (US5): External monitor triggers workspace redistribution within 2s → T039-T045
- **SC-008** (US4): Python daemon tests pass without modification → T057 (tests validate protocol compatibility)
- **SC-009** (US6): User can connect via VNC and interact with Sway → T046-T053
- **SC-010** (All): System builds successfully with nixos-rebuild dry-build → T016, T058

Each success criterion maps to specific tasks that implement and validate the functionality.
