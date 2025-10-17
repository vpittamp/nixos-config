# Tasks: NixOS KDE Plasma to i3wm Migration

**Feature**: 009-let-s-create
**Input**: Design documents from `/etc/nixos/specs/009-let-s-create/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story (US1-US4) to enable independent implementation and testing.

**Tests**: Not explicitly requested in spec.md - no test tasks included.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- NixOS configuration repository: `/etc/nixos/`
- Platform configurations: `configurations/`
- Desktop modules: `modules/desktop/`
- Service modules: `modules/services/`
- Home modules: `home-modules/`
- Documentation: `docs/` and `CLAUDE.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Backup, validation, and repository preparation

- [ ] T001 Create git branch `009-let-s-create` and commit current state
- [ ] T002 Verify all target platforms currently build: `nixos-rebuild dry-build --flake .#hetzner`, `nixos-rebuild dry-build --flake .#m1 --impure`
- [ ] T003 Document baseline metrics: count configuration files, documentation files, measure idle memory usage on Hetzner

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Verify reference configuration and prepare module structure

**⚠️ CRITICAL**: All user stories depend on hetzner-i3.nix being functional and stable

- [ ] T004 Verify hetzner-i3.nix is complete and functional (already implemented per research.md)
- [ ] T005 Verify modules/desktop/i3wm.nix exists and provides required interface per contracts/i3wm-module.md
- [ ] T006 Verify i3wm configuration files generate correctly: check /etc/i3/config, /etc/i3status.conf
- [ ] T007 Verify all critical integrations work on hetzner-i3: 1Password, Firefox PWAs, clipcat, rofi, alacritty
- [ ] T008 Document hetzner-i3.nix as PRIMARY REFERENCE in configuration comments

**Checkpoint**: hetzner-i3.nix validated as stable reference - platform migrations can now begin

---

## Phase 3: User Story 1 - Complete KDE Plasma Removal (Priority: P1) 🎯

**Goal**: Remove all KDE Plasma desktop environment components completely from NixOS configuration

**Independent Test**:
- Build all configurations: no KDE/Plasma packages in closure
- System boots to i3wm (not Plasma)
- No KDE services running
- Memory usage reduced by 200MB vs baseline

### Remove KDE Plasma Desktop Modules

- [ ] T009 [P] [US1] Delete `modules/desktop/kde-plasma.nix` module file
- [ ] T010 [P] [US1] Delete `modules/desktop/kde-plasma-vm.nix` module file
- [ ] T011 [P] [US1] Delete `modules/desktop/mangowc.nix` Wayland compositor module
- [ ] T012 [P] [US1] Delete `modules/desktop/wayland-remote-access.nix` module

### Remove Obsolete Platform Configurations

- [ ] T013 [P] [US1] Delete `configurations/hetzner.nix` (old KDE-based Hetzner config)
- [ ] T014 [P] [US1] Delete `configurations/hetzner-mangowc.nix` (Wayland compositor config)
- [ ] T015 [P] [US1] Delete `configurations/wsl.nix` (WSL environment no longer in use)

### Evaluate and Remove VM/KubeVirt Configurations

- [ ] T016 [US1] Review `configurations/kubevirt-*.nix` files (4 files) - determine if in active use
- [ ] T017 [US1] Review `configurations/vm-*.nix` files (2 files) - determine if experimental/staging only
- [ ] T018 [US1] Review `configurations/hetzner-minimal.nix` and `configurations/hetzner-example.nix` - determine if needed for nixos-anywhere
- [ ] T019 [US1] Delete evaluated obsolete VM/KubeVirt configurations (based on T016-T018 findings)

### Remove KDE Plasma Home Manager Modules

- [ ] T020 [P] [US1] Delete `home-modules/desktop/plasma-config.nix`
- [ ] T021 [P] [US1] Delete `home-modules/desktop/plasma-sync.nix`
- [ ] T022 [P] [US1] Delete `home-modules/desktop/plasma-snapshot-analysis.nix`
- [ ] T023 [P] [US1] Delete `home-modules/desktop/touchpad-gestures.nix` (Wayland-specific)
- [ ] T024 [US1] Check if `home-modules/desktop/activity-aware-apps-native.nix` is KDE-specific; delete if so

### Update Flake Configuration

- [ ] T025 [US1] Remove `plasma-manager` input from `flake.nix` if no longer referenced
- [ ] T026 [US1] Remove `mangowc` input from `flake.nix`
- [ ] T027 [US1] Remove `hetzner`, `hetzner-mangowc`, `wsl` entries from `nixosConfigurations` in flake.nix
- [ ] T028 [US1] Update flake.nix comments to reference i3wm as standard desktop environment

### Validate KDE Plasma Removal

- [ ] T029 [US1] Build all remaining configurations: `nixos-rebuild dry-build --flake .#hetzner`, `.#m1 --impure`, `.#container`
- [ ] T030 [US1] Verify no KDE/Plasma packages in closure: `nix-store -q --tree $(readlink ./result) | grep -i kde` (should be empty)
- [ ] T031 [US1] Verify no KDE/Plasma packages in closure: `nix-store -q --tree $(readlink ./result) | grep -i plasma` (should be empty)
- [ ] T032 [US1] Test boot on Hetzner: system boots directly to i3wm (no Plasma Desktop, kwin, plasmashell)
- [ ] T033 [US1] Verify no KDE services running: `systemctl list-units | grep -i kde` (should be empty)

**Checkpoint**: User Story 1 complete - KDE Plasma fully removed, all configurations build successfully

---

## Phase 4: User Story 2 - Configuration Consolidation with Hetzner-i3 as Primary (Priority: P2)

**Goal**: Consolidate all platform configurations to derive from hetzner-i3.nix as primary reference

**Independent Test**:
- M1 and container configurations import hetzner-i3.nix
- 80%+ code reuse measured across platforms
- Only platform-specific settings remain in child configs
- All configurations build successfully

### Refactor M1 Configuration

- [ ] T034 [US2] Backup current `configurations/m1.nix` configuration (copy to m1.nix.bak)
- [ ] T035 [US2] Update `configurations/m1.nix`: Add `./hetzner-i3.nix` to imports list
- [ ] T036 [US2] Update `configurations/m1.nix`: Remove duplicated desktop environment configuration (compare to hetzner-i3.nix)
- [ ] T037 [US2] Update `configurations/m1.nix`: Remove duplicated package lists (already in hetzner-i3.nix)
- [ ] T038 [US2] Update `configurations/m1.nix`: Remove duplicated service configuration (already in hetzner-i3.nix)
- [ ] T039 [US2] Update `configurations/m1.nix`: Keep only M1-specific overrides (hostname, hardware, DPI, firmware)
- [ ] T040 [US2] Update `configurations/m1.nix`: Set `networking.hostName = lib.mkForce "nixos-m1"` with comment
- [ ] T041 [US2] Update `configurations/m1.nix`: Set `services.xserver.dpi = lib.mkForce 180` for Retina with comment
- [ ] T042 [US2] Update `configurations/m1.nix`: Set `services.xrdp-i3.enable = lib.mkForce false` (no remote desktop on laptop) with comment
- [ ] T043 [US2] Update `configurations/m1.nix`: Document all `lib.mkForce` usage with rationale comments

### Refactor Container Configuration

- [ ] T044 [US2] Backup current `configurations/container.nix` configuration (copy to container.nix.bak)
- [ ] T045 [US2] Update `configurations/container.nix`: Add `./hetzner-i3.nix` to imports list
- [ ] T046 [US2] Update `configurations/container.nix`: Disable GUI components: `services.i3wm.enable = lib.mkForce false`
- [ ] T047 [US2] Update `configurations/container.nix`: Disable X11: `services.xserver.enable = lib.mkForce false`
- [ ] T048 [US2] Update `configurations/container.nix`: Remove duplicated configuration (already in hetzner-i3.nix)
- [ ] T049 [US2] Update `configurations/container.nix`: Keep only container-specific settings (package profile, service reduction)
- [ ] T050 [US2] Update `configurations/container.nix`: Document all `lib.mkForce` usage with rationale comments

### Update Base Configuration

- [ ] T051 [US2] Review `configurations/base.nix`: Update to reference i3wm patterns instead of KDE Plasma patterns
- [ ] T052 [US2] Update `configurations/base.nix`: Remove any KDE Plasma-specific settings or references
- [ ] T053 [US2] Update `configurations/base.nix`: Ensure consistency with hetzner-i3.nix reference architecture

### Validate Configuration Consolidation

- [ ] T054 [US2] Build all configurations: `nixos-rebuild dry-build --flake .#hetzner`, `.#m1 --impure`, `.#container`
- [ ] T055 [US2] Measure code reuse: Compare lines in m1.nix vs hetzner-i3.nix (target: <20% unique in m1.nix)
- [ ] T056 [US2] Measure code reuse: Compare lines in container.nix vs hetzner-i3.nix (target: <20% unique in container.nix)
- [ ] T057 [US2] Verify M1 configuration imports and extends hetzner-i3.nix correctly
- [ ] T058 [US2] Verify container configuration derives from hetzner-i3.nix with GUI disabled
- [ ] T059 [US2] Verify 80%+ code reuse achieved across all platform configurations

**Checkpoint**: User Story 2 complete - All configurations derive from hetzner-i3.nix, 80%+ code reuse achieved

---

## Phase 5: User Story 4 - M1 Wayland to X11 Migration (Priority: P2)

**Goal**: Migrate M1 display server from Wayland to X11 for consistency with reference configuration

**Independent Test**:
- M1 boots with X11 server running (not Wayland)
- `$DISPLAY` environment variable set
- X11 DPI settings provide equivalent HiDPI scaling (180 DPI)
- All critical tools work: 1Password, Firefox PWAs, terminal, clipboard

**Note**: Running this in parallel with US2 since M1 configuration changes

### Configure X11 Display Server on M1

- [ ] T060 [US4] Update `configurations/m1.nix`: Ensure X11 server is enabled via hetzner-i3.nix import
- [ ] T061 [US4] Update `configurations/m1.nix`: Verify Wayland is not enabled (should be disabled by X11 setup)
- [ ] T062 [US4] Update `configurations/m1.nix`: Configure X11 DPI for Retina display (already set in T041: `services.xserver.dpi = 180`)
- [ ] T063 [US4] Update `configurations/m1.nix`: Add X11 server flags section with DPI override if needed

### Remove Wayland-Specific Configuration

- [ ] T064 [US4] Update `configurations/m1.nix`: Remove Wayland-specific environment variables (`MOZ_ENABLE_WAYLAND`, `NIXOS_OZONE_WL`)
- [ ] T065 [US4] Update `configurations/m1.nix`: Remove wayland-remote-access.nix import (if present)
- [ ] T066 [US4] Update `configurations/m1.nix`: Ensure display manager configured for X11 session (not Wayland session)

### Configure X11 HiDPI Scaling

- [ ] T067 [US4] Update `configurations/m1.nix`: Set cursor size for HiDPI: `environment.sessionVariables.XCURSOR_SIZE = "42"`
- [ ] T068 [US4] Update `configurations/m1.nix`: Set Java UI scale: `environment.sessionVariables._JAVA_OPTIONS = "-Dsun.java2d.uiScale=1.75"`
- [ ] T069 [US4] Update `configurations/m1.nix`: Verify Qt apps will auto-detect DPI from X11 settings

### Validate M1 X11 Migration

- [ ] T070 [US4] Build M1 configuration: `nixos-rebuild dry-build --flake .#m1 --impure`
- [ ] T071 [US4] Apply M1 configuration: `nixos-rebuild switch --flake .#m1 --impure` (on M1 hardware)
- [ ] T072 [US4] Reboot M1 system and verify X11 starts (not Wayland)
- [ ] T073 [US4] Verify `$DISPLAY` environment variable is set (e.g., `:0`)
- [ ] T074 [US4] Verify `$WAYLAND_DISPLAY` is not set
- [ ] T075 [US4] Verify X11 DPI: `xdpyinfo | grep resolution` should show 180x180 dots per inch
- [ ] T076 [US4] Test HiDPI scaling: Check alacritty terminal fonts render correctly
- [ ] T077 [US4] Test HiDPI scaling: Check Firefox UI elements are properly scaled
- [ ] T078 [US4] Test HiDPI scaling: Check VS Code editor is readable at default zoom
- [ ] T079 [US4] Test cursor size appropriate for Retina display
- [ ] T080 [US4] Test rofi menu text is legible
- [ ] T081 [US4] Verify all critical integrations work: 1Password, Firefox PWAs, terminal, clipboard manager

**Checkpoint**: User Story 4 complete - M1 runs X11 with functional HiDPI scaling

---

## Phase 6: User Story 3 - Remove Obsolete Configurations and Documentation (Priority: P3)

**Goal**: Remove all obsolete documentation to reduce codebase size and prevent confusion

**Independent Test**:
- Obsolete docs removed (PLASMA_*, IPHONE_KDECONNECT_GUIDE)
- PWA docs updated for i3wm context (no KDE panel references)
- Configuration file count reduced by 30% (17→12 or fewer)
- Documentation file count reduced by 15% (45→38 or fewer)

### Remove Obsolete Documentation Files

- [ ] T082 [P] [US3] Delete `docs/PLASMA_CONFIG_STRATEGY.md`
- [ ] T083 [P] [US3] Delete `docs/PLASMA_MANAGER.md`
- [ ] T084 [P] [US3] Delete `docs/IPHONE_KDECONNECT_GUIDE.md`

### Update PWA Documentation for i3wm Context

- [ ] T085 [US3] Update `docs/PWA_SYSTEM.md`: Remove KDE panel integration references
- [ ] T086 [US3] Update `docs/PWA_SYSTEM.md`: Add i3wm workspace integration documentation
- [ ] T087 [US3] Update `docs/PWA_SYSTEM.md`: Document i3wsr dynamic workspace naming with PWA icons
- [ ] T088 [US3] Update `docs/PWA_COMPARISON.md`: Remove KDE-specific comparison points
- [ ] T089 [US3] Update `docs/PWA_PARAMETERIZATION.md`: Focus on i3wm workspace integration instead of KDE taskbar

### Update Core Documentation

- [ ] T090 [US3] Update `CLAUDE.md`: Replace all KDE Plasma references with i3wm references
- [ ] T091 [US3] Update `CLAUDE.md`: Update quick start commands for i3wm desktop
- [ ] T092 [US3] Update `CLAUDE.md`: Update directory structure (remove KDE modules, show i3wm modules)
- [ ] T093 [US3] Update `CLAUDE.md`: Update configuration targets section (remove WSL, document hetzner-i3 as primary)
- [ ] T094 [US3] Update `CLAUDE.md`: Add i3wm keybindings reference or link to quickstart.md

### Update Architecture Documentation

- [ ] T095 [US3] Update `docs/ARCHITECTURE.md`: Document hetzner-i3.nix as primary reference configuration
- [ ] T096 [US3] Update `docs/ARCHITECTURE.md`: Update configuration hierarchy diagram (show hetzner-i3 → m1, container)
- [ ] T097 [US3] Update `docs/ARCHITECTURE.md`: Update module list (remove KDE modules, keep i3wm)
- [ ] T098 [US3] Update `docs/ARCHITECTURE.md`: Document configuration inheritance pattern with code reuse targets

### Update M1 Setup Documentation

- [ ] T099 [US3] Update `docs/M1_SETUP.md`: Document X11 configuration instead of Wayland
- [ ] T100 [US3] Update `docs/M1_SETUP.md`: Add X11 DPI settings documentation (180 DPI for Retina)
- [ ] T101 [US3] Update `docs/M1_SETUP.md`: Remove Wayland-specific setup instructions
- [ ] T102 [US3] Update `docs/M1_SETUP.md`: Update gesture support documentation (X11 touchegg vs Wayland native)

### Create Migration Documentation

- [ ] T103 [US3] Create or update `docs/MIGRATION.md`: Document KDE Plasma → i3wm migration process
- [ ] T104 [US3] Update `docs/MIGRATION.md`: Include rollback procedures (`nixos-rebuild switch --rollback`)
- [ ] T105 [US3] Update `docs/MIGRATION.md`: Document troubleshooting steps for common migration issues
- [ ] T106 [US3] Update `docs/MIGRATION.md`: Add platform-specific considerations (M1 DPI, container headless)

### Update Constitution

- [ ] T107 [US3] Update `.specify/memory/constitution.md`: Update Principle II to reference hetzner-i3.nix as reference implementation
- [ ] T108 [US3] Update `.specify/memory/constitution.md`: Update Principle VIII with i3wm as standard tiling window manager
- [ ] T109 [US3] Update `.specify/memory/constitution.md`: Document migration as constitutional change from KDE Plasma to i3wm

### Validate Documentation Updates

- [ ] T110 [US3] Count configuration files: Should be ≤12 files (baseline 17, target reduction 30%)
- [ ] T111 [US3] Count documentation files: Should be ≤38 files (baseline 45, target reduction 15%)
- [ ] T112 [US3] Verify all documentation references are accurate (no broken links to deleted files)
- [ ] T113 [US3] Verify all code examples in documentation use i3wm patterns (not KDE Plasma)
- [ ] T114 [US3] Verify quickstart.md reflects current i3wm system architecture

**Checkpoint**: User Story 3 complete - Repository is lean, documentation accurate and i3wm-focused

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, optimization, and cleanup across all user stories

### Final Build and Integration Testing

- [ ] T115 [P] Build all configurations and verify build time <5 minutes: `time nixos-rebuild dry-build --flake .#hetzner`
- [ ] T116 [P] Build M1: `time nixos-rebuild dry-build --flake .#m1 --impure`
- [ ] T117 [P] Build container: `time nixos-rebuild dry-build --flake .#container`

### Performance Validation on Hetzner

- [ ] T118 Measure boot time on Hetzner: Should be <30 seconds to usable i3wm desktop
- [ ] T119 Measure idle memory usage on Hetzner: Should be reduced by 200MB vs KDE Plasma baseline
- [ ] T120 Verify all critical integrations on Hetzner: 1Password (GUI), Firefox PWAs, clipcat, rofi, tmux

### Remote Desktop Multi-Session Testing (Hetzner)

- [ ] T121 Verify xrdp service running on Hetzner: `systemctl status xrdp`
- [ ] T122 Test multi-session RDP: Connect 2-3 concurrent RDP sessions from remote clients
- [ ] T123 Verify each RDP session has independent i3 desktop with separate workspace state
- [ ] T124 Verify clipboard works across RDP sessions
- [ ] T125 Verify sessions persist across disconnection/reconnection

### Container Build and Validation

- [ ] T126 Build minimal container image: `nix build .#container-minimal`
- [ ] T127 Build development container image: `nix build .#container-dev`
- [ ] T128 Verify container images have no GUI packages (i3, X11 disabled)
- [ ] T129 Load and test minimal container: `docker load < result && docker run -it nixos-container:minimal`

### Success Criteria Validation

- [ ] T130 Validate SC-001: Configuration file count reduced by 30% (17→12 or fewer)
- [ ] T131 Validate SC-002: Documentation file count reduced by 15% (45→38 or fewer)
- [ ] T132 Validate SC-003: All configs build without errors in <5 minutes
- [ ] T133 Validate SC-004: Boot time to i3wm desktop <30s on Hetzner
- [ ] T134 Validate SC-005: Memory usage reduced by 200MB vs KDE Plasma
- [ ] T135 Validate SC-006: All critical integrations functional (1Password, PWAs, clipboard, terminal)
- [ ] T136 Validate SC-007: M1 X11 with functional HiDPI scaling
- [ ] T137 Validate SC-008: No KDE/Plasma packages in nix-store for any config
- [ ] T138 Validate SC-009: 80%+ code reuse from hetzner-i3.nix
- [ ] T139 Validate SC-010: Developer can rebuild any config in <10 minutes using updated docs

### Run Quickstart Validation

- [ ] T140 Follow `specs/009-let-s-create/quickstart.md` on Hetzner system and verify all commands work
- [ ] T141 Follow `specs/009-let-s-create/quickstart.md` on M1 system and verify all commands work
- [ ] T142 Follow quickstart.md PWA workflow: `pwa-list`, `pwa-install-all`, `pwa-get-ids`
- [ ] T143 Follow quickstart.md clipboard workflow: `Win+v`, `clipcatctl list`
- [ ] T144 Follow quickstart.md troubleshooting section and verify diagnostic commands work

### Code Cleanup and Repository Hygiene

- [ ] T145 Remove all `.bak` backup files created during refactoring (m1.nix.bak, container.nix.bak)
- [ ] T146 Run `nix flake check` to verify flake is valid and evaluates correctly
- [ ] T147 Update flake.lock with latest inputs: `nix flake update`
- [ ] T148 Clean up nix store garbage: `nix-collect-garbage -d` (optional, for space savings)

### Final Git Commit and Documentation

- [ ] T149 Review all changes in git: `git status`, `git diff`
- [ ] T150 Create final commit with comprehensive message documenting migration
- [ ] T151 Tag release: `git tag -a v009-i3wm-migration -m "KDE Plasma to i3wm migration complete"`
- [ ] T152 Update branch `009-let-s-create` and prepare for merge to main

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 - KDE Removal (Phase 3)**: Depends on Foundational phase - Priority P1
- **User Story 2 - Consolidation (Phase 4)**: Depends on US1 completion (KDE removed) - Priority P2
- **User Story 4 - M1 X11 (Phase 5)**: Depends on US1 completion, can run in parallel with US2 - Priority P2
- **User Story 3 - Documentation (Phase 6)**: Depends on US1, US2, US4 completion - Priority P3
- **Polish (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

- **User Story 1 (P1) - KDE Removal**: Foundation for all other work - MUST complete first
- **User Story 2 (P2) - Consolidation**: Depends on US1 (KDE must be removed before consolidating configs)
- **User Story 4 (P2) - M1 X11**: Depends on US1 (KDE/Wayland must be removed), can parallel with US2
- **User Story 3 (P3) - Documentation**: Depends on all implementation (US1, US2, US4) being complete

### Within Each User Story

**User Story 1 (KDE Removal)**:
- Module deletions can all run in parallel (T009-T012)
- Configuration deletions can all run in parallel (T013-T015)
- Home module deletions can all run in parallel (T020-T023)
- Validation tasks are sequential (build → verify closure → test boot)

**User Story 2 (Consolidation)**:
- M1 refactoring is sequential (backup → update imports → remove duplication → add overrides)
- Container refactoring is sequential (backup → update imports → disable GUI → cleanup)
- M1 and Container refactoring can run in parallel
- Base.nix updates can run in parallel with platform refactoring

**User Story 4 (M1 X11)**:
- X11 configuration tasks are sequential (configure → remove Wayland → add HiDPI)
- Validation tasks are sequential (build → apply → reboot → verify)

**User Story 3 (Documentation)**:
- Documentation deletions can run in parallel (T082-T084)
- PWA doc updates can run in parallel (T085-T089)
- Core doc updates can run sequentially or in parallel by document
- Architecture and M1 docs can be updated in parallel

### Parallel Opportunities

#### Setup Phase (Phase 1)
All tasks run sequentially for safety (backup → verify → measure)

#### Foundational Phase (Phase 2)
Verification tasks run sequentially (need to validate reference before proceeding)

#### User Story 1 - Module Deletions
```bash
# Can delete all desktop modules in parallel:
Task T009: Delete modules/desktop/kde-plasma.nix
Task T010: Delete modules/desktop/kde-plasma-vm.nix
Task T011: Delete modules/desktop/mangowc.nix
Task T012: Delete modules/desktop/wayland-remote-access.nix

# Can delete all configuration files in parallel:
Task T013: Delete configurations/hetzner.nix
Task T014: Delete configurations/hetzner-mangowc.nix
Task T015: Delete configurations/wsl.nix

# Can delete all home modules in parallel:
Task T020-T024: Delete home-modules/desktop/plasma-*.nix files
```

#### User Story 2 - Platform Refactoring
```bash
# Can refactor M1 and Container in parallel (different files):
# Team A: M1 refactoring (T034-T043)
# Team B: Container refactoring (T044-T050)
# Team C: Base configuration updates (T051-T053)

# All validation builds can run in parallel:
Task T115: Build hetzner
Task T116: Build m1
Task T117: Build container
```

#### User Story 3 - Documentation
```bash
# Can update all documentation files in parallel:
Task T090-T094: Update CLAUDE.md
Task T095-T098: Update ARCHITECTURE.md
Task T099-T102: Update M1_SETUP.md
Task T082-T089: Update/delete PWA docs
Task T103-T106: Update MIGRATION.md
```

---

## Parallel Example: User Story 1 (KDE Removal)

```bash
# Launch all module deletions together:
Task T009: "Delete modules/desktop/kde-plasma.nix"
Task T010: "Delete modules/desktop/kde-plasma-vm.nix"
Task T011: "Delete modules/desktop/mangowc.nix"
Task T012: "Delete modules/desktop/wayland-remote-access.nix"

# Launch all configuration deletions together:
Task T013: "Delete configurations/hetzner.nix"
Task T014: "Delete configurations/hetzner-mangowc.nix"
Task T015: "Delete configurations/wsl.nix"

# Then validation sequentially:
Task T029: Build all configurations
Task T030-T031: Verify no KDE packages in closure
Task T032: Test boot to i3wm
Task T033: Verify no KDE services running
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (backup, verify baseline)
2. Complete Phase 2: Foundational (verify hetzner-i3.nix stable)
3. Complete Phase 3: User Story 1 (remove all KDE Plasma)
4. **STOP and VALIDATE**: Test that system boots to i3wm, no KDE packages
5. Deploy to Hetzner if ready

**Result**: Clean i3wm-only system, ready for consolidation

### Incremental Delivery

1. Complete Setup + Foundational → Foundation validated
2. Add User Story 1 → Test independently → All KDE removed, i3wm working
3. Add User Story 2 → Test independently → Configurations consolidated, 80% code reuse
4. Add User Story 4 → Test independently → M1 on X11 with HiDPI working
5. Add User Story 3 → Test independently → Documentation clean and accurate
6. Polish phase → All success criteria validated

### Parallel Team Strategy

With multiple team members:

1. All complete Setup + Foundational together
2. User Story 1 (KDE Removal): One person or sequential completion
3. After US1 complete, parallelize:
   - **Team Member A**: User Story 2 - M1 refactoring
   - **Team Member B**: User Story 2 - Container refactoring
   - **Team Member C**: User Story 4 - M1 X11 migration
4. After US1, US2, US4 complete:
   - **Team Member A**: User Story 3 - Update CLAUDE.md, ARCHITECTURE.md
   - **Team Member B**: User Story 3 - Update PWA docs, M1_SETUP.md
   - **Team Member C**: User Story 3 - Create MIGRATION.md, update constitution
5. All team members participate in Polish phase validation

---

## Notes

- **[P] tasks** = different files, no dependencies, can run in parallel
- **[Story] label** maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each logical task group (e.g., after all module deletions, after M1 refactor)
- Stop at any checkpoint to validate story independently before proceeding
- Use `git diff` frequently to verify changes match intent
- Always run `nixos-rebuild dry-build` before `switch`
- Keep backups (.bak files) until final validation passes
- NixOS generations enable rollback: `nixos-rebuild switch --rollback`

**Total Tasks**: 152 tasks across 7 phases (1 Setup, 1 Foundational, 4 User Stories, 1 Polish)

**Estimated Duration**:
- MVP (Setup + Foundational + US1): ~6-8 hours (KDE removal, i3wm validated)
- Full Implementation (All phases): ~16-20 hours (all user stories + polish)
- With parallel team (3 people): ~8-12 hours (significant parallelization in US2, US3, US4)

**Critical Path**: Setup → Foundational → US1 (KDE Removal) → US2 (Consolidation) → US3 (Documentation) → Polish
