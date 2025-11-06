# Tasks: M1 Configuration Alignment with Hetzner-Sway

**Input**: Design documents from `/specs/051-the-hetzner-sway/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested - no test tasks included

**Organization**: Tasks are grouped by user story to enable independent implementation and verification of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5)
- Include exact file paths in descriptions

## Path Conventions
- **NixOS Configuration**: `/etc/nixos/` at repository root
- **Configuration files**: `configurations/`, `modules/`, `home-modules/`, `home-manager/`
- **Documentation**: `docs/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Pre-alignment verification and backup

- [X] T001 Verify current working branch is `051-the-hetzner-sway`
- [X] T002 [P] Test current M1 configuration builds successfully: `sudo nixos-rebuild dry-build --flake .#m1 --impure`
- [X] T003 [P] Test current hetzner-sway configuration still builds: `sudo nixos-rebuild dry-build --flake .#hetzner-sway`
- [X] T004 Document current M1 module import list for rollback reference
- [X] T005 Create Git checkpoint before any changes: `git commit -am "checkpoint: pre-alignment state"`

**Checkpoint**: Baseline established - alignment work can begin

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core system service configuration that MUST be complete before home-manager alignment can work

**⚠️ CRITICAL**: No home-manager work can succeed until i3pm daemon is properly configured at system level

- [X] T006 Verify i3-project-daemon module exists: check `/etc/nixos/modules/services/i3-project-daemon.nix`
- [X] T007 Verify onepassword-automation module exists: check `/etc/nixos/modules/services/onepassword-automation.nix`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Unified Service Configuration (Priority: P1) 🎯 MVP

**Goal**: Achieve identical core service configuration between M1 and hetzner-sway platforms

**Independent Test**: Compare module import lists between configurations - should achieve 95%+ parity excluding documented architectural differences

### Implementation for User Story 1

- [X] T008 [US1] Add i3-project-daemon import to `/etc/nixos/configurations/m1.nix` after line 28 (onepassword.nix)
  - Add line: `../modules/services/i3-project-daemon.nix       # Feature 037: Project management daemon`
- [X] T009 [US1] Add onepassword-automation import to `/etc/nixos/configurations/m1.nix` after i3-project-daemon
  - Add line: `../modules/services/onepassword-automation.nix  # Service account automation`
- [X] T010 [US1] Configure i3ProjectDaemon service in `/etc/nixos/configurations/m1.nix` after line 60 (services.sway.enable)
  - Add service block with enable=true, user="vpittamp", logLevel="INFO"
- [X] T011 [US1] Configure onepassword-automation service in `/etc/nixos/configurations/m1.nix` after onepassword-password-management block
  - Add service block with enable=true, user="vpittamp", tokenReference from contract
- [X] T012 [US1] Test M1 configuration builds with new services: `sudo nixos-rebuild dry-build --flake .#m1 --impure`
- [X] T013 [US1] Verify hetzner-sway still builds after changes (no regressions): `sudo nixos-rebuild dry-build --flake .#hetzner-sway`
- [X] T014 [US1] Apply M1 system configuration: `sudo nixos-rebuild switch --flake .#m1 --impure`
- [X] T015 [US1] Verify i3pm daemon started successfully: `systemctl --user status i3-project-event-listener`
- [X] T016 [US1] Test i3pm daemon health: `i3pm daemon status` should show running with version info
- [X] T017 [US1] Test project commands work: `i3pm project list` should execute without errors

**Checkpoint**: M1 now has identical system service configuration to hetzner-sway (i3pm, 1Password automation)

---

## Phase 4: User Story 2 - Consistent Home Manager Configuration (Priority: P1)

**Goal**: Achieve identical user environment configuration (shell, editors, terminal, desktop apps) between platforms

**Independent Test**: Compare home-manager module imports and verify XDG config files are identical (keybindings, walker config, etc.)

### Implementation for User Story 2

- [X] T018 [P] [US2] Add declarative-cleanup import to `/etc/nixos/home-manager/base-home.nix` if missing
  - Add line: `../home-modules/desktop/declarative-cleanup.nix  # Automatic XDG cleanup`
- [X] T019 [P] [US2] Remove any incorrect system service imports from `/etc/nixos/home-manager/base-home.nix`
  - Remove if present: `../modules/services/i3-project-daemon.nix` (system service, not home-manager)
- [X] T020 [US2] Test home-manager configuration builds: `home-manager build --flake .#vpittamp@m1`
- [X] T021 [US2] Apply home-manager configuration: `home-manager switch --flake .#vpittamp@m1`
- [X] T022 [US2] Verify walker launcher configuration is identical: compare `~/.config/elephant/` files
- [X] T023 [US2] Verify sway-config-manager templates deployed: check `~/.config/sway/keybindings.toml`, `appearance.json`
- [X] T024 [US2] Test walker launcher works: press `Meta+D` or `Alt+Space` and verify it launches
- [X] T025 [US2] Test Sway config hot-reload: modify `keybindings.toml`, run `swaymsg reload`, verify changes applied

**Checkpoint**: M1 user environment now matches hetzner-sway structure with identical desktop applications

---

## Phase 5: User Story 3 - Hardware-Aware Platform Differentiation (Priority: P2)

**Goal**: Verify platform-specific settings (display, audio, input) are correctly isolated and don't leak between platforms

**Independent Test**: Verify M1 uses physical display settings and hetzner uses headless settings without cross-contamination

### Implementation for User Story 3

- [ ] T026 [P] [US3] Verify M1 Sway output configuration uses eDP-1 and HDMI-A-1: check `/etc/nixos/home-modules/desktop/sway.nix` conditionals
- [ ] T027 [P] [US3] Verify M1 has libinput touchpad configuration: check Sway config for natural scrolling, tap-to-click
- [ ] T028 [P] [US3] Verify M1 does NOT have headless environment variables: check for absence of WLR_BACKENDS=headless
- [ ] T029 [P] [US3] Verify hetzner-sway still has headless outputs: test build doesn't remove HEADLESS-1/2/3
- [ ] T030 [US3] Rebuild both configurations to verify separation: dry-build both m1 and hetzner-sway
- [ ] T031 [US3] Test M1 Sway session starts with physical display: reboot or restart Sway session
- [ ] T032 [US3] Verify M1 touchpad gestures work: test natural scrolling and tap-to-click
- [ ] T033 [US3] Check M1 display scaling is 2x for Retina: `swaymsg -t get_outputs | jq '.[] | {name, scale}'`

**Checkpoint**: Platform-specific hardware configurations are correctly isolated between M1 and hetzner-sway

---

## Phase 6: User Story 4 - Service Daemon Alignment (Priority: P2)

**Goal**: Ensure i3pm daemon, walker, and sway-config-manager function identically on both platforms

**Independent Test**: Verify identical daemon behavior by testing project switching, window filtering, and config hot-reload on both platforms

### Implementation for User Story 4

- [X] T034 [US4] Fix workspace-mode-handler hardcoded outputs in `/etc/nixos/home-modules/desktop/sway-config-manager.nix` lines 44-147
  - Add dynamic output detection before "Handle mode parameter" (around line 54)
  - Add: OUTPUTS detection with swaymsg -t get_outputs, OUTPUT_COUNT validation, PRIMARY/SECONDARY/TERTIARY assignment
- [X] T035 [US4] Replace all HEADLESS-1 references with $PRIMARY in workspace-mode-handler (single mode case)
- [X] T036 [US4] Replace all HEADLESS-1/2 references with $PRIMARY/$SECONDARY in workspace-mode-handler (dual mode case)
- [X] T037 [US4] Replace all HEADLESS-1/2/3 references with $PRIMARY/$SECONDARY/$TERTIARY in workspace-mode-handler (tri mode case)
- [X] T038 [US4] Test home-manager builds with updated workspace-mode-handler: `home-manager build --flake .#vpittamp@m1`
- [ ] T039 [US4] Apply home-manager changes: `home-manager switch --flake .#vpittamp@m1`
- [ ] T040 [US4] Restart Sway session to load new workspace-mode-handler: `swaymsg reload`
- [ ] T041 [US4] Test workspace mode detection: check detected outputs with `swaymsg -t get_outputs | jq -r '.[].name'`
- [ ] T042 [US4] Test workspace mode switching: run `workspace-mode single`, verify no errors
- [ ] T043 [US4] Test dual mode (if 2+ monitors): run `workspace-mode dual`, verify workspaces distributed correctly
- [ ] T044 [US4] Verify workspace distribution: `swaymsg -t get_workspaces | jq '.[] | {num: .num, output: .output}'`
- [ ] T045 [US4] Test project switching with new daemon: `i3pm project switch nixos`, verify windows filter correctly
- [ ] T046 [US4] Test window filtering behavior: create project, launch scoped app, switch projects, verify hiding

**Checkpoint**: All service daemons (i3pm, walker, sway-config-manager) now work identically on M1 and hetzner-sway

---

## Phase 7: User Story 5 - Documentation and Maintenance Parity (Priority: P3)

**Goal**: Document all architectural differences and create maintenance workflow to prevent future drift

**Independent Test**: Review CLAUDE.md and verify all intentional differences are documented with rationale

### Implementation for User Story 5

- [X] T047 [P] [US5] Add M1-specific quick start section to `/etc/nixos/docs/CLAUDE.md`
  - Include: i3pm daemon service configuration for M1, workspace mode handler behavior, platform differences
- [X] T048 [P] [US5] Document i3pm daemon setup for M1 in CLAUDE.md
  - Add service configuration example, systemctl commands, troubleshooting steps
- [X] T049 [P] [US5] Add troubleshooting section for M1-specific issues in CLAUDE.md
  - Include: daemon not starting, workspace mode failures, output detection issues
- [X] T050 [P] [US5] Document workspace mode handler dynamic output detection in CLAUDE.md
  - Explain how it works, what outputs are detected, how PRIMARY/SECONDARY/TERTIARY are assigned
- [ ] T051 [US5] Update CLAUDE.md architectural differences section with alignment changes
  - Document that i3pm daemon now works on both platforms, workspace-mode-handler is platform-agnostic
- [ ] T052 [US5] Create maintenance workflow guidelines in CLAUDE.md
  - When to apply changes to both platforms, how to verify cross-platform compatibility
- [ ] T053 [US5] Generate configuration diff report: document remaining intentional differences
  - List all modules present in hetzner-sway but not M1 (with rationale)
  - List all modules present in M1 but not hetzner-sway (with rationale)

**Checkpoint**: Comprehensive documentation ensures future maintainability and prevents configuration drift

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup

- [ ] T054 [P] Test complete M1 system rebuild from scratch: `sudo nixos-rebuild switch --flake .#m1 --impure`
- [ ] T055 [P] Test complete hetzner-sway rebuild (ensure no regressions): `sudo nixos-rebuild switch --flake .#hetzner-sway`
- [ ] T056 Verify all i3pm workflows on M1: project create, switch, clear, window filtering
- [ ] T057 Verify walker launcher workflows on M1: app search, file search, web search, custom commands
- [ ] T058 Verify Sway configuration hot-reload on M1: edit keybindings, reload, verify changes
- [ ] T059 Run validation from quickstart.md: verify all success criteria met
- [ ] T060 Git commit all changes with comprehensive message: `git commit -am "feat(051): Complete M1 alignment with hetzner-sway"`
- [ ] T061 Create summary report: list all changes made, module parity achieved, remaining differences

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: Sequential dependencies
  - **US1 (Phase 3)**: Depends on Foundational - MUST complete before US2
  - **US2 (Phase 4)**: Depends on US1 (needs i3pm daemon configured at system level)
  - **US3 (Phase 5)**: Can run in parallel with US4 after US2 completes
  - **US4 (Phase 6)**: Depends on US2 (needs home-manager structure aligned)
  - **US5 (Phase 7)**: Depends on US1-US4 completion (documents final state)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: System service configuration - Foundation for all home-manager work
- **User Story 2 (P1)**: Home-manager alignment - Requires US1 system services to exist
- **User Story 3 (P2)**: Hardware verification - Independent, can run after US2
- **User Story 4 (P2)**: Daemon alignment - Requires US2 home-manager structure
- **User Story 5 (P3)**: Documentation - Requires US1-US4 to be complete to document final state

### Within Each User Story

**User Story 1 (System Services)**:
- Module import additions before service configuration
- Service configuration before testing
- Testing before applying changes
- Verification after application

**User Story 2 (Home Manager)**:
- Import additions/removals before building
- Build before applying
- Verification after application

**User Story 4 (Workspace Handler)**:
- Dynamic output detection code before replacing hardcoded values
- All replacements before testing
- Testing before applying
- Multiple workspace modes tested after application

### Parallel Opportunities

- **Phase 1 Setup**: T002 and T003 can run in parallel (different targets)
- **Phase 2 Foundational**: T006 and T007 can run in parallel (verification only)
- **User Story 2**: T018 and T019 can run in parallel (different operations on same file)
- **User Story 3**: T026, T027, T028, T029 can run in parallel (verification tasks on different aspects)
- **User Story 5**: T047, T048, T049, T050 can run in parallel (different sections of documentation)
- **Phase 8 Polish**: T054 and T055 can run in parallel (different build targets)

---

## Parallel Example: User Story 2 (Home Manager)

```bash
# Launch import changes together (different types of changes):
Task: "Add declarative-cleanup import"
Task: "Remove incorrect system service imports"

# Then build and test sequentially:
Task: "Test home-manager configuration builds"
Task: "Apply home-manager configuration"
```

---

## Parallel Example: User Story 5 (Documentation)

```bash
# Launch all documentation tasks together (different sections):
Task: "Add M1-specific quick start section to CLAUDE.md"
Task: "Document i3pm daemon setup for M1"
Task: "Add troubleshooting section for M1-specific issues"
Task: "Document workspace mode handler dynamic output detection"

# Then sequential tasks for finalization:
Task: "Update architectural differences section"
Task: "Create maintenance workflow guidelines"
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only)

1. Complete Phase 1: Setup (baseline)
2. Complete Phase 2: Foundational (verify modules exist)
3. Complete Phase 3: User Story 1 (system services)
4. Complete Phase 4: User Story 2 (home-manager alignment)
5. **STOP and VALIDATE**: Test i3pm daemon works, home-manager configured correctly
6. This gives you full i3pm functionality on M1!

### Incremental Delivery

1. **Setup + Foundational** → Baseline established
2. **Add User Story 1** → System services configured → Test daemon works (CRITICAL MVP!)
3. **Add User Story 2** → Home-manager aligned → Test user environment identical
4. **Add User Story 3** → Hardware verified → Test platform separation working
5. **Add User Story 4** → Workspace handler fixed → Test multi-monitor workflows
6. **Add User Story 5** → Documentation complete → Maintenance workflow established
7. Each story adds value and can be tested independently

### Sequential Strategy (Recommended for Solo Implementation)

Due to dependencies, this feature is best implemented sequentially:

1. Complete User Story 1 (system services) - Foundation
2. Complete User Story 2 (home-manager) - Requires US1 daemon
3. Complete User Story 3 and 4 in parallel (if desired) - Both require US2
4. Complete User Story 5 (documentation) - Requires US1-4 completion

---

## Notes

- **[P] tasks**: Different files or different verification aspects, no dependencies
- **[Story] label**: Maps task to specific user story for traceability
- **Critical path**: US1 → US2 → (US3 + US4) → US5
  - US1 MUST complete before US2 (system service required for home-manager daemons)
  - US2 MUST complete before US4 (home-manager structure required for workspace handler)
  - US3 is independent verification, can run anytime after US2
- **Verification points**: After each user story, test independently before proceeding
- **Rollback**: Git commit after each phase for easy rollback if needed
- **Testing**: Focus on `nixos-rebuild dry-build` before applying changes
- **Platform parity**: Target is 95%+ configuration overlap (excluding documented architectural differences)
- **No test tasks**: Testing not explicitly requested, so focus on implementation and manual verification

---

## Estimated Timeline

- **Phase 1 (Setup)**: 15 minutes - Verification and baseline
- **Phase 2 (Foundational)**: 5 minutes - Quick module checks
- **Phase 3 (US1 - System Services)**: 45 minutes - Critical path
- **Phase 4 (US2 - Home Manager)**: 30 minutes - Alignment work
- **Phase 5 (US3 - Hardware)**: 20 minutes - Verification only
- **Phase 6 (US4 - Workspace Handler)**: 45 minutes - Code changes + testing
- **Phase 7 (US5 - Documentation)**: 30 minutes - Documentation updates
- **Phase 8 (Polish)**: 20 minutes - Final validation

**Total**: ~3.5 hours for complete implementation

**MVP (US1 + US2)**: ~1.5 hours for essential functionality

---

## Success Criteria (From Spec)

After completing all tasks, verify:

- ✅ **SC-001**: 95% or higher module import parity achieved (excluding documented differences)
- ✅ **SC-002**: 100% home-manager module parity for user environment
- ✅ **SC-003**: Zero behavioral differences in i3pm workflows between platforms
- ✅ **SC-004**: 100% walker launcher feature parity
- ✅ **SC-005**: Sway config hot-reload works identically (<100ms latency)
- ✅ **SC-006**: All architectural differences documented with rationale
- ✅ **SC-007**: Both configurations build successfully without errors
- ✅ **SC-008**: Users can switch between platforms without relearning workflows
- ✅ **SC-009**: Package availability consistent (≥98%) across architectures
- ✅ **SC-010**: Configuration maintenance effort reduced (single commit affects both)

---

## Rollback Procedures

If issues arise during implementation:

1. **System configuration**: `sudo nixos-rebuild switch --rollback`
2. **Home-manager**: Use previous generation from `home-manager generations`
3. **Git revert**: `git revert <commit-hash>` to undo specific changes
4. **Complete rollback**: `git reset --hard` to checkpoint commit from T005

All rollback procedures documented in quickstart.md Phase 5.
