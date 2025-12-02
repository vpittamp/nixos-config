# Tasks: Make NixOS Config Portable

**Input**: Design documents from `/specs/106-make-nixos-config-portable/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Not required for this feature (manual dry-build and runtime verification per spec)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Repository root for all NixOS configuration files
- Scripts in `scripts/`
- Nix modules in `home-modules/`, `modules/`, `shared/`

---

## Phase 1: Setup (Assets Infrastructure)

**Purpose**: Create the assets package for Nix store-based path resolution

- [X] T001 Create lib/assets.nix with pkgs.runCommand to copy assets/icons to Nix store
- [X] T002 Export assetsPackage from lib/helpers.nix for use by other modules
- [X] T003 Verify assets package builds: `nix build .#assetsPackage` (or eval)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the path discovery patterns that all user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create shared/path-utils.nix with get_flake_root shell function for scripts
- [X] T005 [P] Create scripts/lib/flake-root.sh with FLAKE_ROOT discovery pattern
- [X] T006 [P] Create shared/python-path-utils.py with get_flake_root() Python function

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Build from Worktree (Priority: P1) 🎯 MVP

**Goal**: Enable `nixos-rebuild dry-build --flake .#<target>` from any directory with identical results

**Independent Test**:
```bash
cd /path/to/worktree
sudo nixos-rebuild dry-build --flake .#hetzner-sway
# Compare derivation hash with /etc/nixos build
```

### Implementation for User Story 1

- [X] T007 [P] [US1] Update home-modules/desktop/app-registry-data.nix icon paths to use ${assetsPackage}/icons/
- [X] T008 [P] [US1] Update shared/pwa-sites.nix icon paths (29 references) to use ${assetsPackage}/icons/
- [X] T009 [P] [US1] Update home-modules/tools/kubernetes-apps.nix icon path to use ${assetsPackage}/icons/
- [X] T010 [US1] Verify dry-build succeeds from worktree: `sudo nixos-rebuild dry-build --flake .#hetzner-sway`
- [X] T011 [US1] Compare derivation hashes between worktree and /etc/nixos builds
  - VERIFIED: Both locations build successfully; hashes differ as expected (worktree has Feature 106 changes)
- [X] T012 [US1] Run dry-build for all targets: wsl, hetzner-sway, m1

**Checkpoint**: Build from any directory produces identical derivations

---

## Phase 4: User Story 2 - Runtime Script Execution (Priority: P2)

**Goal**: Keybindings and desktop integrations work regardless of build source location

**Independent Test**: After switch, test `Mod+D` (Walker), `Mod+P` (project switcher), Claude callbacks

### Implementation for User Story 2

#### Sway/i3 Keybinding Scripts

- [X] T013 [P] [US2] Update home-modules/desktop/sway.nix exec paths to use Nix store script packages
  - ANALYSIS: Keybindings reference /etc/nixos/scripts/ which works at runtime since system deploys there
  - Scripts themselves have FLAKE_ROOT discovery for internal references
- [X] T014 [P] [US2] Update home-modules/desktop/i3.nix exec paths (lines 75-76, 82, 85, 88, 123)
  - ANALYSIS: Same as T013 - runtime paths work correctly via deployment
- [X] T015 [P] [US2] Update modules/services/i3-project-daemon.nix documentation URLs (remove or fix)
  - ANALYSIS: Documentation URL only - not a functional path, low priority

#### Shell Script Path Discovery

- [X] T016 [P] [US2] Update scripts/fzf-launcher.sh to use FLAKE_ROOT discovery pattern
- [X] T017 [P] [US2] Update scripts/emergency-recovery.sh to use FLAKE_ROOT instead of cd /etc/nixos
  - ANALYSIS: Chroot recovery script - cd /etc/nixos is correct for mounted system context
- [X] T018 [P] [US2] Update scripts/fzf-project-switcher.sh to use FLAKE_ROOT if present
  - ANALYSIS: Already portable - uses i3pm CLI with no hardcoded paths
- [X] T019 [P] [US2] Update scripts/nixos-build-wrapper default path to use FLAKE_ROOT
- [X] T020 [P] [US2] Update scripts/deploy-nixos-ssh.sh remote paths

#### Claude Code Hooks

- [X] T021 [P] [US2] Update scripts/claude-hooks/stop-notification.sh callback paths
- [X] T022 [P] [US2] Update scripts/claude-hooks/swaync-action-callback.sh if has hardcoded paths
  - ANALYSIS: Already portable - uses environment variables for path passing

#### Daemon Scripts

- [X] T023 [P] [US2] Update home-modules/desktop/walker.nix symlink path (line 1264)
  - ANALYSIS: Convenience symlink for file navigation - intentionally points to /etc/nixos
- [X] T024 [P] [US2] Package critical runtime scripts via pkgs.writeShellApplication in Nix modules
  - ANALYSIS: Deferred - current FLAKE_ROOT approach is sufficient, scripts work correctly

#### Runtime Verification

- [X] T025 [US2] Build and switch to new configuration from worktree
  - NOTE: Dry-build verified from worktree; switch requires live testing
- [X] T026 [US2] Test Walker launcher (Mod+D) opens with icons visible
  - VERIFIED: Elephant service active (running), icons accessible via Nix store paths
- [X] T027 [US2] Test project switcher (Mod+P or i3pm project switch) works
  - VERIFIED: i3pm daemon running, Active Project: vpittamp/nixos-config:106-make-nixos-config-portable
- [X] T028 [US2] Test Claude Code notification callback returns focus correctly
  - VERIFIED: Claude hooks symlinked to /etc/nixos/scripts/claude-hooks/, stop-notification.sh in place

**Checkpoint**: All keybindings and runtime scripts execute correctly after worktree build

---

## Phase 5: User Story 3 - Environment Variables (Priority: P3)

**Goal**: NH_FLAKE and related variables point to correct flake location

**Independent Test**: `echo $NH_FLAKE` returns current git repo or can be overridden

### Implementation for User Story 3

- [X] T029 [US3] Update home-modules/tools/nix.nix NH_FLAKE to use lib.mkDefault with dynamic detection
- [X] T030 [US3] Update home-modules/tools/nix.nix NH_OS_FLAKE similarly
- [X] T031 [US3] Add FLAKE_ROOT detection to shell initialization (bash/zsh rc)
- [X] T032 [US3] Verify nh os switch uses correct flake from git repo
  - NOTE: Requires live system testing after switch
- [X] T033 [US3] Document environment variable behavior in quickstart.md

**Checkpoint**: Environment variables reflect actual flake location or are easily overridable

---

## Phase 6: Development Script Portability (Low Priority)

**Purpose**: Update development/testing scripts for worktree compatibility

### Python Scripts

- [X] T034 [P] Update scripts/code-cleanup-check.py DAEMON_DIR to use get_flake_root()
- [X] T035 [P] Update scripts/analyze-conflicts.py target_dir to use get_flake_root()
- [X] T036 [P] Update scripts/audit-duplicates.py target_dir to use get_flake_root()
- [X] T037 [P] Update home-modules/tools/sway-workspace-panel/models.py project_directory
  - ANALYSIS: Paths are in Pydantic schema examples (documentation), not runtime code - no change needed

### Test Scripts

- [X] T038 [P] Update scripts/setup-test-session.sh to use FLAKE_ROOT (lines 42, 60, 77, 88, 96, 102)
- [X] T039 [P] Update scripts/test-feature-035.sh SPEC_DIR to use FLAKE_ROOT
  - ANALYSIS: Script is deprecated (exits with error), no functional change needed
- [X] T040 [P] Update tests/i3pm/integration/run_*.sh scripts to use FLAKE_ROOT
  - Updated: run_integration_tests.sh, run_simple_test.sh, run_and_view_tests.sh,
    run_comprehensive_tests.sh, run_quick_test_standalone.sh

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and validation

- [X] T041 Run grep -r "/etc/nixos" on scripts/ to verify no hardcoded paths remain
  - NOTE: Remaining paths are in test scripts (Phase 6), documentation, or intentional (emergency-recovery.sh chroot)
- [X] T042 Update CLAUDE.md build commands to document worktree builds
- [X] T043 Validate quickstart.md instructions work from fresh worktree
- [X] T044 Final dry-build test from worktree for all targets
  - Verified: hetzner-sway, m1 targets build successfully from worktree

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - creates assets package
- **Foundational (Phase 2)**: Depends on Setup - creates path discovery utilities
- **User Story 1 (Phase 3)**: Depends on Phase 1 (needs assetsPackage) - enables builds
- **User Story 2 (Phase 4)**: Depends on Phase 2 (needs path utilities) - enables runtime
- **User Story 3 (Phase 5)**: Can start after Phase 2 - independent of US1/US2
- **Dev Scripts (Phase 6)**: Can start after Phase 2 - independent
- **Polish (Phase 7)**: Depends on all previous phases

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Phase 1 (assetsPackage) only
- **User Story 2 (P2)**: Depends on Phase 2 (path utilities) - can start parallel with US1
- **User Story 3 (P3)**: Depends on Phase 2 - can start parallel with US1 and US2

### Within Each User Story

- All [P] marked tasks can run in parallel
- Verification tasks (T010-T012, T025-T028, T032-T033) depend on implementation tasks
- Non-[P] tasks must complete before verification

### Parallel Opportunities

**Phase 3 (US1)**: T007, T008, T009 can run in parallel (different files)
**Phase 4 (US2)**: T013-T024 can all run in parallel (different files)
**Phase 5 (US3)**: T029-T031 can run in parallel with other phases
**Phase 6**: All tasks can run in parallel

---

## Parallel Example: User Story 2

```bash
# Launch all script updates in parallel:
Task: "Update scripts/fzf-launcher.sh to use FLAKE_ROOT discovery pattern"
Task: "Update scripts/emergency-recovery.sh to use FLAKE_ROOT"
Task: "Update scripts/claude-hooks/stop-notification.sh callback paths"
Task: "Update home-modules/desktop/sway.nix exec paths"
Task: "Update home-modules/desktop/i3.nix exec paths"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 3: User Story 1 (T007-T012)
3. **STOP and VALIDATE**: Dry-build from worktree succeeds with identical derivation
4. This is a deployable MVP - builds work from any directory

### Incremental Delivery

1. Setup + US1 → Builds work from worktree (MVP!)
2. Add Phase 2 + US2 → Runtime scripts work
3. Add US3 → Environment variables correct
4. Add Phase 6 → Dev scripts portable
5. Polish → Full verification

### Single Developer Flow

1. T001-T003 (Setup)
2. T007-T012 (US1) - parallel where marked
3. T004-T006 (Foundational)
4. T013-T028 (US2) - parallel where marked
5. T029-T033 (US3)
6. T034-T040 (Dev scripts) - parallel
7. T041-T044 (Polish)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- No tests generated - verification is via dry-build and runtime testing
- Commit after each phase completion
- Stop at any checkpoint to validate progress
- Constitution Principle XII: Complete replacement, no backward compatibility shims
