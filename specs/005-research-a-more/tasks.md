# Tasks: Lightweight X11 Desktop Environment for Hetzner Cloud

**Input**: Design documents from `/specs/005-research-a-more/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: This project uses NixOS integration testing approach. Test tasks are included for VM validation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- NixOS configuration project structure:
  - `modules/desktop/` - Desktop environment modules
  - `configurations/` - System configurations
  - `flake.nix` - Flake entry point

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and NixOS module structure

- [X] T001 Create module directory structure: `modules/desktop/i3wm.nix` and `modules/desktop/xrdp.nix`
- [X] T002 [P] Create testing configuration: `configurations/hetzner-i3.nix` for Phase 1 parallel deployment
- [X] T003 [P] Add configuration to flake.nix: Register `hetzner-i3` configuration output

**Checkpoint**: ✅ Basic structure in place for module development

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core X11 and XRDP infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create base i3wm module skeleton in `modules/desktop/i3wm.nix` with enable option
- [X] T005 [P] Create base XRDP module in `modules/desktop/xrdp.nix` extracted from existing remote-access.nix
- [X] T006 Configure X11 server integration: Set `services.xserver.windowManager.i3.enable` based on module option
- [X] T007 Configure display manager session: Set `defaultSession = "none+i3"` for direct i3 login
- [X] T008 Add PulseAudio audio integration: Ensure `pulseaudio-module-xrdp` package installed
- [X] T009 Create i3 config file generation: Implement `/etc/i3/config` generation from module options
- [X] T010 Create XRDP startwm.sh generation: Generate `/etc/xrdp/startwm.sh` to launch i3
- [X] T011 Add module validation: Assertions for workspace numbers (1-10), port ranges, etc.

**Checkpoint**: ✅ Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Remote Desktop Access to Lightweight X11 Environment (Priority: P1) 🎯 MVP

**Goal**: Enable remote desktop connection via XRDP to i3wm window manager with basic functionality

**Independent Test**: Connect via RDP from macOS/Windows client, see i3 desktop, launch terminal, verify window management works

### Implementation for User Story 1

- [ ] T012 [P] [US1] Implement core i3 keybindings in `modules/desktop/i3wm.nix`: terminal, launcher, window close
- [ ] T013 [P] [US1] Implement XRDP core configuration in `modules/desktop/xrdp.nix`: port, firewall, defaultWindowManager
- [ ] T014 [US1] Add default package installation: dmenu, i3status, i3lock, alacritty in `services.i3wm.extraPackages`
- [ ] T015 [US1] Configure i3 fonts and basic appearance: Set default fonts, border width, colors
- [ ] T016 [US1] Configure XRDP authentication: PAM integration with system users
- [ ] T017 [US1] Add i3 status bar configuration: Enable i3bar with i3status at bottom
- [ ] T018 [US1] Configure XRDP display settings: Default resolution 1920x1080, 24-bit color
- [ ] T019 [US1] Update `configurations/hetzner-i3.nix`: Enable both modules with minimal config
- [ ] T020 [US1] Test build: `nixos-rebuild dry-build --flake .#hetzner-i3`
- [ ] T021 [US1] Test in VM: `nixos-rebuild build-vm --flake .#hetzner-i3` and verify RDP connection
- [ ] T022 [US1] Deploy to test server: `nixos-rebuild switch --flake .#hetzner-i3 --target-host vpittamp@hetzner`
- [X] T023 [US1] Validate core functionality: Connect via RDP, launch terminal, close windows, verify session persistence on disconnect

**Checkpoint**: User Story 1 complete - basic remote desktop with i3wm fully functional and independently testable

---

## Phase 4: User Story 2 - Multiple Workspace Management (Priority: P2)

**Goal**: Organize GUI applications across multiple virtual workspaces with keyboard shortcuts

**Independent Test**: Switch between workspaces using Ctrl+1-4, move windows between workspaces using Mod+Shift+1-4, verify windows stay on assigned workspaces

### Implementation for User Story 2

- [ ] T024 [US2] Implement workspace configuration in `modules/desktop/i3wm.nix`: Add `workspaces` option (list of submodules)
- [ ] T025 [US2] Add workspace submodule options: number, name, defaultLayout, output fields
- [ ] T026 [US2] Generate workspace declarations in i3 config: `workspace "1" output primary` entries
- [ ] T027 [US2] Implement workspace switching keybindings: Ctrl+1-9 → `workspace number N`
- [ ] T028 [US2] Implement move-to-workspace keybindings: Mod+Shift+1-9 → `move container to workspace number N`
- [ ] T029 [US2] Add workspace layout configuration: Generate `workspace N layout tabbed/stacking/default` directives
- [ ] T030 [US2] Add workspace naming support: Generate i3 workspace naming config
- [ ] T031 [US2] Update `configurations/hetzner-i3.nix`: Configure 4 workspaces (Main, Code, Web, Chat)
- [ ] T032 [US2] Validate workspace configuration: Assert unique numbers, valid layouts, count ≥4
- [ ] T033 [US2] Test workspace functionality: Build VM, verify workspace switching and window movement
- [ ] T034 [US2] Update quickstart.md: Document workspace keybindings and workflow examples

**Checkpoint**: User Stories 1 AND 2 both work independently - remote desktop + workspace management complete

---

## Phase 5: User Story 3 - Customizable Window Layouts and Keyboard Shortcuts (Priority: P3)

**Goal**: Enable users to customize keyboard shortcuts and window layouts for efficient keyboard-driven workflows

**Independent Test**: Define custom keybindings in configuration, rebuild, verify custom shortcuts work, test layout toggling (stacking/tabbed/split)

### Implementation for User Story 3

- [ ] T035 [US3] Implement keybindings option in `modules/desktop/i3wm.nix`: `attrsOf string` type
- [ ] T036 [US3] Create default keybindings set: Window focus, movement, layouts, system commands
- [ ] T037 [US3] Implement keybinding merge logic: User keybindings override defaults
- [ ] T038 [US3] Generate keybindings in i3 config: `bindsym $mod+Key command` entries
- [ ] T039 [US3] Add layout management keybindings: Toggle split, stacking, tabbed layouts
- [ ] T040 [US3] Implement window management keybindings: Fullscreen, floating, focus direction
- [ ] T041 [US3] Add gaps configuration in `modules/desktop/i3wm.nix`: `gaps` submodule (inner, outer, smartGaps)
- [ ] T042 [US3] Add borders configuration: `borders` submodule (width, style, hideEdgeBorders)
- [ ] T043 [US3] Generate gaps config in i3: `gaps inner N`, `gaps outer N`, `smart_gaps on`
- [ ] T044 [US3] Generate borders config in i3: `default_border pixel N`, `hide_edge_borders smart`
- [ ] T045 [US3] Implement color scheme option: `colors` submodule with focused/unfocused colorSets
- [ ] T046 [US3] Generate color directives in i3 config: `client.focused`, `client.unfocused` entries
- [ ] T047 [US3] Add extraConfig option: Allow raw i3 config appending for advanced customization
- [ ] T048 [US3] Update `configurations/hetzner-i3.nix`: Add custom keybindings, gaps, and colors
- [ ] T049 [US3] Test customization: Verify custom shortcuts work, gaps render correctly, colors apply
- [ ] T050 [US3] Update quickstart.md: Add customization examples for keybindings, colors, gaps

**Checkpoint**: User Stories 1, 2, AND 3 complete - fully customizable i3 environment

---

## Phase 6: User Story 4 - Session Persistence Across Reboots (Priority: P4)

**Goal**: Preserve desktop session configuration (workspaces, keybindings, WM settings) across system reboots

**Independent Test**: Configure i3 with custom settings, reboot server, reconnect via RDP, verify all customizations still active

### Implementation for User Story 4

- [ ] T051 [US4] Implement startup commands option in `modules/desktop/i3wm.nix`: `startup` list of submodules
- [ ] T052 [US4] Add startup submodule: command, always, notification fields
- [ ] T053 [US4] Generate exec directives in i3 config: `exec` and `exec_always` for startup commands
- [ ] T054 [US4] Configure loginctl linger for user persistence: Enable systemd user session persistence
- [ ] T055 [US4] Configure XRDP session policy: Set `sessionPolicy = "Default"` for reconnection support
- [ ] T056 [US4] Add environment.etc entries: Ensure i3 config persists in `/etc/i3/config` across reboots
- [ ] T057 [US4] Test reboot persistence: Deploy config, reboot server, verify i3 config unchanged
- [ ] T058 [US4] Test session reconnection: Disconnect RDP, reboot, reconnect, verify applications still running (if applicable)
- [ ] T059 [US4] Update quickstart.md: Document session persistence behavior and startup commands

**Checkpoint**: All 4 user stories complete - full i3wm desktop environment with session persistence

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Quality improvements, documentation, and production readiness

- [ ] T060 [P] Update CLAUDE.md: Add i3wm configuration examples and troubleshooting section
- [ ] T061 [P] Add comprehensive module documentation: Document all options in modules/desktop/i3wm.nix with examples
- [ ] T062 Code cleanup: Remove any debug code, ensure consistent formatting
- [ ] T063 Add security hardening: Review XRDP TLS settings, firewall rules
- [ ] T064 Performance optimization: Verify i3 memory footprint <50MB, test with 10 applications
- [ ] T065 Create migration guide: Document KDE Plasma → i3wm migration steps in quickstart.md
- [ ] T066 [P] Add troubleshooting section to quickstart.md: Common issues and solutions
- [ ] T067 Final validation: Run all acceptance scenarios from spec.md
- [ ] T068 Update `configurations/hetzner.nix`: Replace KDE Plasma with i3wm as primary desktop (Phase 3 final migration)
- [ ] T069 Deploy to production: `nixos-rebuild switch --flake .#hetzner --target-host vpittamp@hetzner`
- [ ] T070 Production validation: Verify all success criteria from spec.md (SC-001 through SC-010)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User Story 1 (P1): Can start after Foundational - No dependencies on other stories
  - User Story 2 (P2): Can start after Foundational - No dependencies on US1 (independent)
  - User Story 3 (P3): Can start after Foundational - No dependencies on US1/US2 (independent)
  - User Story 4 (P4): Can start after Foundational - No dependencies on other stories (independent)
- **Polish (Phase 7)**: Depends on completion of desired user stories

### Within Each User Story

- Configuration implementation before testing
- Build validation before VM testing
- VM testing before deployment
- Deployment before functional validation

### Parallel Opportunities

- **Setup (Phase 1)**: T002 and T003 can run in parallel (different files)
- **Foundational (Phase 2)**: T005 can run in parallel with T004 (different modules)
- **User Story 1**: T012 and T013 can run in parallel (different modules)
- **Once Foundational completes**: All user stories can be implemented in parallel by different developers
- **Polish**: T060, T061, T066 can run in parallel (different files)

---

## Parallel Example: Foundational Phase

```bash
# Launch foundational module skeletons in parallel:
Task: "Create base i3wm module skeleton in modules/desktop/i3wm.nix"
Task: "Create base XRDP module in modules/desktop/xrdp.nix"

# These are different files with no dependencies between them
```

## Parallel Example: User Story 1

```bash
# Launch core configuration tasks in parallel:
Task: "Implement core i3 keybindings in modules/desktop/i3wm.nix"
Task: "Implement XRDP core configuration in modules/desktop/xrdp.nix"

# These are different modules and can be developed independently
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011) **CRITICAL - blocks all stories**
3. Complete Phase 3: User Story 1 (T012-T023)
4. **STOP and VALIDATE**: Test User Story 1 independently via RDP connection
5. Deploy to test server if ready

This delivers: **Remote desktop access to lightweight i3wm environment** - the core MVP functionality

### Incremental Delivery

1. **Foundation** (Phases 1-2): Setup + Foundational → NixOS modules ready
2. **MVP** (Phase 3): Add User Story 1 → Test independently → Deploy (Basic remote desktop working!)
3. **Enhanced** (Phase 4): Add User Story 2 → Test independently → Deploy (Workspace management added)
4. **Power User** (Phase 5): Add User Story 3 → Test independently → Deploy (Full customization enabled)
5. **Production Ready** (Phase 6): Add User Story 4 → Test independently → Deploy (Session persistence complete)
6. **Polished** (Phase 7): Final quality improvements and production deployment

Each phase adds value without breaking previous functionality.

### Parallel Team Strategy

With multiple developers available:

1. **Week 1**: Team completes Setup + Foundational together (T001-T011)
2. **Week 2+**: Once Foundational done, split work:
   - Developer A: User Story 1 (Remote Desktop) - T012-T023
   - Developer B: User Story 2 (Workspaces) - T024-T034
   - Developer C: User Story 3 (Customization) - T035-T050
   - Developer D: User Story 4 (Persistence) - T051-T059
3. **Integration**: Stories integrate naturally (all build on same i3wm module)
4. **Validation**: Each developer validates their story independently

---

## Testing Strategy

### NixOS VM Testing

For each user story phase, validate with VM testing:

```bash
# Build VM for testing
nixos-rebuild build-vm --flake .#hetzner-i3

# Run VM
./result/bin/run-nixos-vm

# Connect via RDP to localhost:3389 (VM forwards port)
```

### On-Server Testing

For deployment validation:

```bash
# Dry-build first (ALWAYS)
nixos-rebuild dry-build --flake .#hetzner-i3 --target-host vpittamp@hetzner

# Deploy if dry-build succeeds
nixos-rebuild switch --flake .#hetzner-i3 --target-host vpittamp@hetzner

# Verify services
ssh vpittamp@hetzner "systemctl status xrdp"

# Test connection
# Use Microsoft Remote Desktop or xfreerdp to connect
```

### Acceptance Testing

Map each user story to its acceptance criteria from spec.md:

**User Story 1**:
- ✓ Scenario 1: Connect via RDP, see functional desktop with i3
- ✓ Scenario 2: Launch GUI application, verify window appears and is interactive
- ✓ Scenario 3: Disconnect and reconnect, verify session state preserved

**User Story 2**:
- ✓ Scenario 1: Switch to workspace 2, see only windows from workspace 2
- ✓ Scenario 2: Move window from workspace 1 to 3, verify it disappears from 1 and appears on 3
- ✓ Scenario 3: Create new window on workspace 2, verify it appears on current workspace

**User Story 3**:
- ✓ Scenario 1: Define custom terminal keybinding, verify it works
- ✓ Scenario 2: Toggle floating mode, verify window switches modes
- ✓ Scenario 3: Configure custom layout for workspace 1, verify it applies

**User Story 4**:
- ✓ Scenario 1: Reboot server, verify workspace configuration preserved
- ✓ Scenario 2: Reboot server, verify custom keybindings still active

---

## Success Criteria Validation

After completing all user stories, validate against spec.md success criteria:

- **SC-001**: Remote desktop connection established within 30 seconds ✓
- **SC-002**: Window manager memory <500MB (expect <50MB) ✓
- **SC-003**: Input latency <100ms on local network ✓
- **SC-004**: Workspace switching <200ms ✓
- **SC-005**: 7-day continuous operation without crashes ✓
- **SC-006**: Session reconnection success rate ≥95% ✓
- **SC-007**: Audio from remote applications plays on client ✓
- **SC-008**: NixOS rebuild completes in <10 minutes ✓
- **SC-009**: Input response <50ms ✓
- **SC-010**: 90%+ of GUI applications work correctly ✓

---

## Edge Cases Handling

Tasks address edge cases identified in spec.md:

- **Network Interruption**: XRDP session policy configured for reconnection (T055)
- **Multiple Concurrent Connections**: XRDP maxSessions configured (handled in T013)
- **No GPU Available**: Software rendering via llvmpipe (implicit in X11 config, T006)
- **Audio Redirection**: PulseAudio XRDP module integration (T008, T016)
- **Display Resolution Changes**: XRDP display settings configurable (T018)
- **X11 Extensions**: Standard X11 server provides all needed extensions (T006)

---

## Notes

- All tasks use declarative NixOS configuration - no imperative setup required
- Test-Before-Apply is NON-NEGOTIABLE: Always dry-build before deploying (T020, T064, T069)
- Each user story is independently testable and deliverable
- Module options follow NixOS conventions: `lib.mkDefault` for overridable, `lib.mkForce` only when mandatory
- i3 config is generated from NixOS options - never manually edited
- XRDP already proven working with KDE Plasma - migration is low-risk window manager swap
- Memory savings: KDE Plasma ~500MB → i3wm <50MB (10x improvement!)

---

## Quick Reference: Task Count by Phase

- **Phase 1 (Setup)**: 3 tasks
- **Phase 2 (Foundational)**: 8 tasks ⚠️ BLOCKS all user stories
- **Phase 3 (US1 - Remote Desktop)**: 12 tasks 🎯 MVP
- **Phase 4 (US2 - Workspaces)**: 11 tasks
- **Phase 5 (US3 - Customization)**: 16 tasks
- **Phase 6 (US4 - Persistence)**: 9 tasks
- **Phase 7 (Polish)**: 11 tasks

**Total**: 70 tasks

**MVP Scope** (Minimum Viable Product): Phases 1-3 only (23 tasks) delivers functional remote desktop with i3wm
