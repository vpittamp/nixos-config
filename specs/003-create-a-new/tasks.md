# Tasks: MangoWC Desktop Environment for Hetzner Cloud

**Input**: Design documents from `/specs/003-create-a-new/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/mangowc-module-options.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- NixOS configuration files: `/etc/nixos/`
- Module files: `/etc/nixos/modules/`
- Configuration targets: `/etc/nixos/configurations/`
- Documentation: `/etc/nixos/docs/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and flake configuration

- [ ] T001 Add MangoWC flake input to `/etc/nixos/flake.nix` (github:DreamMaoMao/mangowc)
- [ ] T002 Add hetzner-mangowc output to flake.nix nixosConfigurations
- [ ] T003 [P] Create assets directory structure `/etc/nixos/assets/wallpapers/`
- [ ] T004 [P] Add default wallpaper to assets (or symlink existing)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core modules that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 Create MangoWC compositor module skeleton at `/etc/nixos/modules/desktop/mangowc.nix`
  - Define module options structure (services.mangowc.*)
  - Implement assertions (user not root, etc.)
  - Add conditional logic for audio/1Password integration

- [ ] T006 [P] Create Wayland remote access module at `/etc/nixos/modules/desktop/wayland-remote-access.nix`
  - Define wayvnc options structure (services.wayvnc.*)
  - Implement PAM authentication configuration
  - Add firewall rules for VNC (port 5900)

- [ ] T007 [P] Extend PipeWire configuration with network audio options
  - Add services.pipewire.networkAudio.* options
  - Configure PulseAudio protocol module
  - Add firewall rules for audio (port 4713)

- [ ] T008 Create base hetzner-mangowc configuration at `/etc/nixos/configurations/hetzner-mangowc.nix`
  - Import base.nix, hardware/hetzner.nix
  - Import service modules (development, networking, onepassword)
  - Import MangoWC and wayvnc modules
  - Set hostname to nixos-hetzner-mangowc
  - Configure networking (DHCP, Tailscale, firewall)

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Remote Desktop Connection to MangoWC (Priority: P1) 🎯 MVP

**Goal**: Enable remote VNC connection to headless MangoWC session on Hetzner with authentication

**Independent Test**: Connect via VNC client to Hetzner IP:5900, authenticate with system password, see MangoWC desktop with ability to spawn terminal (Alt+Enter)

### Implementation for User Story 1

- [ ] T009 [US1] Implement MangoWC compositor service configuration in `/etc/nixos/modules/desktop/mangowc.nix`
  - Create user-level systemd service for MangoWC
  - Set WLR_BACKENDS=headless environment
  - Set WLR_LIBINPUT_NO_DEVICES=1 environment
  - Configure virtual display resolution (default 1920x1080)
  - Enable user linger for session persistence
  - Set service dependencies and restart policy

- [ ] T010 [US1] Generate MangoWC config.conf from module options
  - Create environment.etc."mangowc/config.conf" generation
  - Include default keybindings (Alt+Enter for terminal, etc.)
  - Set appearance defaults (borders, colors)
  - Configure basic tag/workspace rules (9 workspaces)
  - Add minimal keybindings for testing (spawn terminal, kill window)

- [ ] T011 [US1] Generate MangoWC autostart.sh script
  - Create environment.etc."mangowc/autostart.sh" generation
  - Include wallpaper command if configured
  - Make script executable

- [ ] T012 [US1] Implement wayvnc service configuration in `/etc/nixos/modules/desktop/wayland-remote-access.nix`
  - Create user-level systemd service for wayvnc
  - Set service dependencies (requires MangoWC compositor)
  - Configure WAYLAND_DISPLAY and XDG_RUNTIME_DIR
  - Add restart policy for reliability

- [ ] T013 [US1] Generate wayvnc configuration file
  - Create /etc/wayvnc/config with address, port, PAM settings
  - Enable authentication (enable_auth=true, enable_pam=true)
  - Set maxFPS and GPU encoding flags

- [ ] T014 [US1] Add companion packages to hetzner-mangowc configuration
  - foot (terminal emulator)
  - wmenu or rofi-wayland (launcher)
  - wayvnc (VNC server)
  - wlr-randr (display configuration utility)

- [ ] T015 [US1] Configure firewall rules in hetzner-mangowc.nix
  - Allow TCP port 5900 (VNC)
  - Maintain existing SSH, Tailscale rules
  - Document firewall changes

- [ ] T016 [US1] Test build with `nixos-rebuild dry-build --flake .#hetzner-mangowc`
  - Verify no build errors
  - Check all file paths resolve correctly
  - Validate module assertions pass

**Checkpoint**: At this point, User Story 1 should be fully functional - remote VNC connection with authentication and basic window manager functionality

---

## Phase 4: User Story 2 - Workspace Navigation and Window Management (Priority: P2)

**Goal**: Enable workspace switching (Ctrl+1-9), window movement between workspaces (Alt+1-9), and layout switching (Super+n)

**Independent Test**: Open multiple terminals, switch between workspaces with Ctrl+1-9, move windows with Alt+1-9, cycle layouts with Super+n, verify state persists per workspace

### Implementation for User Story 2

- [ ] T017 [US2] Add complete workspace keybindings to MangoWC config generation
  - Add all 9 workspace view bindings (Ctrl+1-9)
  - Add all 9 workspace move bindings (Alt+1-9)
  - Add workspace navigation keybindings (viewtoleft/viewtoright)

- [ ] T018 [US2] Add window focus keybindings (arrow keys)
  - Bind Alt+Left/Right/Up/Down to focusdir
  - Add Super+Tab for focusstack (next window)

- [ ] T019 [US2] Add layout switching keybindings
  - Bind Super+n to switch_layout
  - Configure default layouts per workspace in tagrule options

- [ ] T020 [US2] Add window management keybindings
  - Add window swap bindings (Super+Shift+arrows)
  - Add float toggle (Alt+backslash)
  - Add fullscreen toggle (Alt+f)
  - Add minimize/restore (Super+i, Super+Shift+I)

- [ ] T021 [US2] Configure workspace-specific layout defaults
  - Set workspace 1: tile layout
  - Set workspace 2: scroller layout
  - Set workspace 3: monocle layout
  - Set workspaces 4-9: tile layout (configurable)

- [ ] T022 [US2] Test workspace and window management functionality
  - Verify workspace switching works correctly
  - Verify windows move between workspaces
  - Verify layout changes apply per workspace
  - Verify window focus follows keybindings

**Checkpoint**: Workspaces and window management fully functional

---

## Phase 5: User Story 3 - Application Launching and Basic Configuration (Priority: P3)

**Goal**: Enable application launching (Super+d), wallpaper configuration, and config hot-reload (Super+r)

**Independent Test**: Press Super+d to open launcher, select application, verify it launches. Change wallpaper in config, rebuild, verify it appears. Press Super+r to reload keybindings without rebuild.

### Implementation for User Story 3

- [ ] T023 [US3] Add application launcher keybinding
  - Bind Super+d to spawn rofi/wmenu
  - Configure launcher with appropriate flags (-l 10 for wmenu)

- [ ] T024 [US3] Add config reload keybinding
  - Bind Super+r to reload_config action
  - Document that this reloads config.conf without restart

- [ ] T025 [P] [US3] Add wallpaper packages and configuration
  - Add swaybg to system packages
  - Generate autostart.sh with swaybg command
  - Support services.mangowc.autostart option override

- [ ] T026 [P] [US3] Add screenshot utilities
  - Add grim, slurp, wl-clipboard to system packages
  - Document screenshot keybindings in setup guide

- [ ] T027 [US3] Implement user customization via home-manager (optional)
  - Create `/etc/nixos/home-modules/tools/mangowc-config.nix`
  - Allow home.file.".config/mango/config.conf" override
  - Allow home.file.".config/mango/autostart.sh" override
  - Document in quickstart guide

- [ ] T028 [US3] Add custom keybindings option to module
  - Implement services.mangowc.keybindings attribute set
  - Merge custom keybindings with defaults in config generation
  - Document in module options contract

**Checkpoint**: Application launching, wallpapers, and customization working

---

## Phase 6: User Story 4 - Multi-Monitor and Display Management (Priority: P4)

**Goal**: Support display resolution configuration and monitor focus switching

**Independent Test**: Change resolution via module option, rebuild, verify MangoWC adapts. Use monitor focus keybindings (if multiple displays available).

### Implementation for User Story 4

- [ ] T029 [US4] Implement services.mangowc.resolution option
  - Add resolution string option (default "1920x1080")
  - Set WLR_OUTPUT_MODE environment variable
  - Document in module contract

- [ ] T030 [P] [US4] Add wlr-randr utility for runtime display config
  - Include wlr-randr in system packages
  - Document usage in setup guide

- [ ] T031 [P] [US4] Add monitor focus keybindings (if applicable)
  - Bind Alt+Shift+Left/Right for focusmon
  - Bind Super+Alt+Left/Right for tagmon (move window to monitor)
  - Note: May not be testable in single-display headless setup

- [ ] T032 [US4] Document display configuration in quickstart guide
  - Explain how to change resolution via module option
  - Explain how to use wlr-randr for runtime changes
  - Note limitations of headless/VNC setup

**Checkpoint**: Display management options available and documented

---

## Phase 7: Audio Redirection (Cross-Cutting)

**Purpose**: Enable audio streaming from server to VNC client

- [ ] T033 Implement PipeWire network audio module configuration
  - Add services.pipewire.networkAudio.enable option
  - Configure libpipewire-module-protocol-pulse
  - Set server.address to bind on network (0.0.0.0:4713)

- [ ] T034 Enable PipeWire in hetzner-mangowc configuration
  - Set services.pipewire.enable = true
  - Set services.pipewire.pulse.enable = true (PulseAudio compat)
  - Disable conflicting PulseAudio service (mkForce false)

- [ ] T035 [P] Add audio firewall rules
  - Allow TCP port 4713 in networking.firewall
  - Document in setup guide

- [ ] T036 [P] Add PulseAudio/audio utilities to packages
  - pulseaudio (for pactl utility)
  - pavucontrol (GUI audio control)
  - Document in quickstart guide

---

## Phase 8: Documentation and Polish

**Purpose**: Complete documentation and final testing

- [ ] T037 [P] Create `/etc/nixos/docs/MANGOWC_SETUP.md`
  - Installation instructions
  - VNC client configuration (TigerVNC, RealVNC, macOS, Windows, Linux)
  - Audio setup (PulseAudio client config)
  - Troubleshooting guide (connection issues, black screen, auth failures)
  - Switching between KDE Plasma and MangoWC

- [ ] T038 [P] Create `/etc/nixos/docs/MANGOWC_KEYBINDINGS.md`
  - Complete keybinding reference
  - Organized by category (applications, workspaces, windows, layouts, system)
  - Comparison with KDE Plasma shortcuts
  - Customization instructions

- [ ] T039 [P] Update `/etc/nixos/CLAUDE.md`
  - Add hetzner-mangowc build commands section
  - Add quick troubleshooting tips
  - Add MangoWC-specific notes

- [ ] T040 [P] Update `/etc/nixos/README.md`
  - Add hetzner-mangowc to configuration targets list
  - Brief description and use case
  - Link to setup documentation

- [ ] T041 [P] Add inline module documentation
  - Purpose and architecture comments in mangowc.nix
  - Headless operation explanation
  - Session management approach notes
  - Audio configuration rationale
  - Customization instructions

- [ ] T042 Test complete deployment workflow
  - Fresh build on Hetzner server
  - VNC connection from multiple client types
  - Audio redirection test
  - Workspace management test
  - Configuration reload test

- [ ] T043 [P] Create example customization in hetzner-mangowc.nix
  - Show custom keybindings example
  - Show appearance customization example
  - Show autostart customization example

- [ ] T044 Validate against all acceptance scenarios from spec.md
  - US1: Remote connection, authentication, session persistence
  - US2: Workspace switching, window movement, layout changes
  - US3: Application launching, config reload
  - US4: Display resolution configuration

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - US1 (P1): Can start after Foundational - No dependencies on other stories
  - US2 (P2): Can start after Foundational - No dependencies on other stories (workspace functionality independent)
  - US3 (P3): Can start after Foundational - No dependencies on other stories (app launching independent)
  - US4 (P4): Can start after Foundational - No dependencies on other stories (display config independent)
- **Audio (Phase 7)**: Can start after Foundational - No dependencies on user stories (cross-cutting concern)
- **Documentation (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

All user stories are independent and can be implemented in parallel after Foundational phase completes.

- **US1 (Remote Desktop)**: Foundation only - enables basic VNC connection
- **US2 (Workspace Management)**: Foundation only - adds window manager features
- **US3 (Application Launching)**: Foundation only - adds launcher and customization
- **US4 (Display Management)**: Foundation only - adds display configuration

### Within Each Phase

- Tasks marked [P] can run in parallel (different files)
- Tasks without [P] must run sequentially (same file edits or dependencies)
- Test build (T016) must come after all module implementation tasks in US1

### Parallel Opportunities

- **Phase 1 (Setup)**: T003, T004 can run in parallel
- **Phase 2 (Foundational)**: T006, T007 can run in parallel after T005
- **Phase 3 (US1)**: T010, T011 can run in parallel; T014, T015 can run in parallel
- **Phase 5 (US3)**: T025, T026, T027 can run in parallel
- **Phase 6 (US4)**: T030, T031 can run in parallel
- **Phase 7 (Audio)**: T035, T036 can run in parallel
- **Phase 8 (Documentation)**: T037, T038, T039, T040, T041, T043 can all run in parallel
- **User Stories**: After Foundational completes, US1, US2, US3, US4 can all be developed in parallel by different team members

---

## Parallel Example: Foundational Phase

```bash
# After T005 completes, launch in parallel:
Task T006: "Create Wayland remote access module at /etc/nixos/modules/desktop/wayland-remote-access.nix"
Task T007: "Extend PipeWire configuration with network audio options"
```

## Parallel Example: User Story 1

```bash
# Launch configuration generation tasks in parallel:
Task T010: "Generate MangoWC config.conf from module options"
Task T011: "Generate MangoWC autostart.sh script"

# Launch package and firewall tasks in parallel:
Task T014: "Add companion packages to hetzner-mangowc configuration"
Task T015: "Configure firewall rules in hetzner-mangowc.nix"
```

## Parallel Example: Documentation Phase

```bash
# Launch all documentation tasks in parallel:
Task T037: "Create /etc/nixos/docs/MANGOWC_SETUP.md"
Task T038: "Create /etc/nixos/docs/MANGOWC_KEYBINDINGS.md"
Task T039: "Update /etc/nixos/CLAUDE.md"
Task T040: "Update /etc/nixos/README.md"
Task T041: "Add inline module documentation"
Task T043: "Create example customization in hetzner-mangowc.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (4 tasks, ~30 minutes)
2. Complete Phase 2: Foundational (4 tasks, ~2 hours) **CRITICAL**
3. Complete Phase 3: User Story 1 (8 tasks, ~2-3 hours)
4. **STOP and VALIDATE**: Test VNC connection independently
   - Build: `sudo nixos-rebuild dry-build --flake .#hetzner-mangowc`
   - Deploy: `sudo nixos-rebuild switch --flake .#hetzner-mangowc`
   - Connect: VNC client to Hetzner IP:5900
   - Test: Spawn terminal (Alt+Enter), verify authentication works
5. If successful: MVP is complete! (basic remote desktop access working)

**MVP Delivery Time**: ~4-6 hours (Setup + Foundational + US1)

### Incremental Delivery

1. **Foundation**: Setup + Foundational → MangoWC infrastructure ready
2. **MVP (US1)**: Remote desktop connection → Test independently → Deploy/Demo
3. **+US2**: Add workspace management → Test independently → Deploy/Demo
4. **+US3**: Add app launching/customization → Test independently → Deploy/Demo
5. **+US4**: Add display config → Test independently → Deploy/Demo
6. **+Audio**: Add audio redirection → Test independently → Deploy/Demo
7. **+Docs**: Complete documentation → Final polish

Each increment adds value without breaking previous functionality.

### Parallel Team Strategy

With multiple developers:

1. **Team**: Complete Setup + Foundational together (~2.5 hours)
2. **Once Foundational is done**:
   - Developer A: User Story 1 (Remote Desktop) - T009-T016
   - Developer B: User Story 2 (Workspace Management) - T017-T022
   - Developer C: User Story 3 (App Launching) - T023-T028
   - Developer D: Audio (Phase 7) - T033-T036
3. **Parallel completion**: All stories integrate via shared modules
4. **Final**: Team collaborates on Documentation (Phase 8)

**Parallel Delivery Time**: ~4-5 hours total (vs. ~8-10 hours sequential)

---

## Task Metrics

- **Total Tasks**: 44
- **Setup Tasks**: 4 (Phase 1)
- **Foundational Tasks**: 4 (Phase 2) **BLOCKING**
- **User Story 1 Tasks**: 8 (Phase 3) **MVP**
- **User Story 2 Tasks**: 6 (Phase 4)
- **User Story 3 Tasks**: 6 (Phase 5)
- **User Story 4 Tasks**: 4 (Phase 6)
- **Audio Tasks**: 4 (Phase 7)
- **Documentation Tasks**: 8 (Phase 8)

### Parallelization Potential

- **Setup**: 2 of 4 tasks can run in parallel (50%)
- **Foundational**: 2 of 4 tasks can run in parallel after T005 (50%)
- **User Story 1**: 4 of 8 tasks can run in parallel (50%)
- **User Story 3**: 3 of 6 tasks can run in parallel (50%)
- **User Story 4**: 2 of 4 tasks can run in parallel (50%)
- **Audio**: 2 of 4 tasks can run in parallel (50%)
- **Documentation**: 6 of 8 tasks can run in parallel (75%)
- **User Stories**: All 4 user stories can develop in parallel (100% after Foundation)

### Suggested MVP Scope

**Minimum Viable Product**: User Story 1 only
- **Tasks**: T001-T016 (20 tasks)
- **Time**: ~4-6 hours
- **Deliverable**: Working VNC connection to MangoWC with authentication, basic window management, terminal spawning

**Value**: Validates entire remote desktop architecture. Users can connect, authenticate, and interact with basic window manager. Proves concept before adding workspace features.

---

## Notes

- **Constitution Compliance**: All tasks follow NixOS declarative configuration principles
- **Modular Design**: Each module is self-contained and reusable
- **Test Strategy**: Manual testing via VNC connection and `nixos-rebuild dry-build`
- **No automated test tasks**: Feature spec does not request automated testing
- **File Organization**: Follows existing NixOS configuration structure
- **Session Persistence**: Handled by user systemd services with linger enabled
- **Concurrent Connections**: Supported by wayvnc out-of-the-box (no special tasks needed)
- **Authentication**: Leverages existing 1Password integration (no new tasks needed)

**Avoid**:
- Creating duplicate configuration between hetzner and hetzner-mangowc
- Modifying existing hetzner.nix (create separate target instead)
- Implementing imperative configuration (violates constitution)
- Adding tasks for features not in user stories (P1-P4 only)
