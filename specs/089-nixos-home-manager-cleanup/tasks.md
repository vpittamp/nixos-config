# Implementation Tasks: NixOS Configuration Cleanup and Consolidation

**Feature Branch**: `089-nixos-home-manager-cleanup`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Quickstart**: [quickstart.md](./quickstart.md)

---

## Task Overview

**Total Tasks**: 47
**User Stories**: 3 (P1, P2, P3)
**Independent Test Criteria**: Defined for each user story
**MVP Scope**: User Story 1 only (P1 - Remove Deprecated Legacy Modules)

### Task Distribution

- **Phase 1 (Setup)**: 5 tasks
- **Phase 2 (Foundational)**: 2 tasks
- **Phase 3 (User Story 1 - P1)**: 17 tasks
- **Phase 4 (User Story 2 - P2)**: 15 tasks
- **Phase 5 (User Story 3 - P3)**: 6 tasks
- **Phase 6 (Polish)**: 2 tasks

---

## Implementation Strategy

### MVP-First Approach

**Minimum Viable Product (MVP)**: User Story 1 (P1) - Remove Deprecated Legacy Modules

**Why this is MVP**: Delivers immediate, high-impact value with lowest risk:
- Removes 1,000+ LOC of dead code
- Zero functional impact (deprecated modules unused by active configurations)
- Immediately improves codebase clarity
- Can be independently tested and validated

**Post-MVP**: User Stories 2 and 3 can be implemented incrementally after MVP validation.

### Incremental Delivery

1. **Deliver User Story 1** → Validate → Commit
2. **Deliver User Story 2** → Validate → Commit
3. **Deliver User Story 3** → Validate → Commit

Each story is independently testable and delivers incremental value.

---

## Dependencies

### User Story Completion Order

```
Phase 1 (Setup) → Phase 2 (Foundational) → Phase 3 (User Story 1 - P1)
                                          ↘
                                            Phase 4 (User Story 2 - P2)
                                          ↗
                                            Phase 5 (User Story 3 - P3) → Phase 6 (Polish)
```

**Parallel Opportunities**:
- User Stories 2 and 3 can be implemented in parallel after User Story 1 completes
- Within each story, tasks marked `[P]` can be parallelized (work on different files)

**Blocking Relationships**:
- Phase 2 MUST complete before any user story implementation
- User Story 1 SHOULD complete before User Stories 2 and 3 (for cleaner git history)
- Phase 6 requires all user stories to be complete

---

## Phase 1: Setup

**Goal**: Prepare environment and validation infrastructure

**Tasks**:

- [X] T001 Verify git working directory is clean (`git status`)
- [X] T002 Verify current branch is `089-nixos-home-manager-cleanup` (`git rev-parse --abbrev-ref HEAD`)
- [X] T003 Make validation scripts executable in specs/089-nixos-home-manager-cleanup/contracts/validation.sh
- [X] T004 Make validation scripts executable in specs/089-nixos-home-manager-cleanup/contracts/hardware-validation.sh
- [X] T005 Create archived directory structure at archived/obsolete-configs/

**Validation**: All setup tasks complete, scripts are executable, directories exist

---

## Phase 2: Foundational (Blocking Prerequisites)

**Goal**: Establish baseline validation before any cleanup

**Tasks**:

- [X] T006 Run baseline dry-build validation for hetzner-sway (`sudo nixos-rebuild dry-build --flake .#hetzner-sway`)
- [X] T007 Run baseline dry-build validation for m1 (`sudo nixos-rebuild dry-build --flake .#m1 --impure`)

**Validation**: Both configurations build successfully, establishing known-good baseline

**Critical**: These tasks MUST complete successfully before proceeding to any user story. If baseline validation fails, fix issues before cleanup.

---

## Phase 3: User Story 1 - Remove Deprecated Legacy Modules (P1)

**Story Goal**: Remove all deprecated modules supporting obsolete features (i3wm, X11/RDP, KDE Plasma, WSL) so that the codebase only contains code relevant to current Sway/Wayland-based systems.

**Independent Test Criteria**:
- Both active configurations (hetzner-sway, m1) successfully complete dry-build without import errors
- Zero backup files remain in active codebase
- `nix flake check` passes after flake input removal
- Deprecated hetzner.nix configuration moved to archived/obsolete-configs/

**Expected Outcome**: ~1,000 LOC removed, 11 modules deleted, 8 backup files removed, unused flake inputs removed

### Delete Deprecated Desktop Modules

- [X] T008 [P] [US1] Delete i3-only module at modules/desktop/i3-project-workspace.nix (537 LOC)
- [X] T009 [P] [US1] Delete X11/RDP module at modules/desktop/xrdp.nix (126 LOC)
- [X] T010 [P] [US1] Delete X11/RDP module at modules/desktop/remote-access.nix (166 LOC)
- [X] T011 [P] [US1] Delete X11/RDP module at modules/desktop/rdp-display.nix (163 LOC)
- [X] T012 [P] [US1] Delete X11/RDP module at modules/desktop/wireless-display.nix
- [X] T013 [P] [US1] Delete KDE-specific module at modules/desktop/firefox-virtual-optimization.nix

### Delete Deprecated Service Modules

- [X] T014 [P] [US1] Delete X11-specific service at modules/services/audio-network.nix
- [X] T015 [P] [US1] Delete KDE optimization at modules/services/kde-optimization.nix
- [X] T016 [P] [US1] Delete WSL Docker integration at modules/services/wsl-docker.nix

### Delete WSL Modules

- [X] T017 [P] [US1] Delete WSL assertion at modules/assertions/wsl-check.nix
- [X] T018 [P] [US1] Delete WSL configuration at modules/wsl/wsl-config.nix
- [X] T019 [US1] Remove empty wsl directory at modules/wsl/ (if empty after T018)

### Remove Backup Files

- [X] T020 [US1] Find all backup files (`find . -name "*.backup*" -type f | grep -v archived | grep -v specs`)
- [X] T021 [US1] Delete all backup files using git rm (8 files total)

### Archive Deprecated Configuration

- [X] T022 [US1] Move deprecated configuration from configurations/hetzner.nix to archived/obsolete-configs/hetzner.nix
- [X] T023 [US1] Create archive documentation at archived/obsolete-configs/README.md explaining why hetzner.nix was archived

### Remove Unused Flake Inputs

- [X] T024 [US1] Edit flake.nix to remove plasma-manager input
- [X] T025 [US1] Edit flake.nix to remove flake-utils input (if confirmed unused by research)
- [X] T026 [US1] Update flake.lock to reflect removed inputs (`nix flake update`)

### Validation & Commit

- [X] T027 [US1] Run validation script at specs/089-nixos-home-manager-cleanup/contracts/validation.sh
- [X] T028 [US1] Run hardware validation script at specs/089-nixos-home-manager-cleanup/contracts/hardware-validation.sh
- [X] T029 [US1] Verify zero backup files remain (`find . -name "*.backup*" | wc -l` returns 0)
- [X] T030 [US1] Commit Phase 1 changes with message: "feat(089): Phase 1 - Remove deprecated legacy modules"

**User Story 1 Acceptance**: All deprecated modules deleted, backup files removed, flake inputs cleaned up, both configurations build successfully, hardware features validated

---

## Phase 4: User Story 2 - Consolidate Duplicate Modules (P2)

**Story Goal**: Consolidate duplicate functionality across multiple modules (1Password modules, Firefox+PWA modules, hetzner-sway configuration variants) so that configuration changes only need to be made in one place.

**Independent Test Criteria**:
- Systems using 1Password maintain all original functionality with 150-180 fewer lines of code
- Both Firefox-only and Firefox+PWA systems work correctly with 40-50 fewer lines of code
- All four hetzner-sway use cases remain supported with reduced code duplication
- Configuration changes require updates in only one location instead of multiple files

**Expected Outcome**: ~200 LOC reduction, single sources of truth established

### Consolidate 1Password Modules

- [ ] T031 [US2] Create consolidated 1Password module at modules/services/onepassword.nix with feature flags (gui, automation, passwordManagement, ssh)
- [ ] T032 [US2] Update configurations to use new consolidated 1Password module options
- [ ] T033 [US2] Test 1Password GUI functionality with consolidated module
- [ ] T034 [US2] Test 1Password automation/CLI functionality with consolidated module
- [ ] T035 [US2] Delete old module at modules/services/onepassword-automation.nix
- [ ] T036 [US2] Delete old module at modules/services/onepassword-password-management.nix

### Consolidate Firefox+PWA Modules

- [ ] T037 [US2] Merge firefox-pwa-1password.nix functionality into home-modules/desktop/firefox-1password.nix with enablePWA flag
- [ ] T038 [US2] Update configurations to use consolidated Firefox module with enablePWA option
- [ ] T039 [US2] Test Firefox-only scenario (enablePWA = false)
- [ ] T040 [US2] Test Firefox+PWA scenario (enablePWA = true)
- [ ] T041 [US2] Delete old module at home-modules/desktop/firefox-pwa-1password.nix

### Consolidate Hetzner-Sway Variants

- [ ] T042 [US2] Extract common configuration to modules/hetzner-sway-common.nix (base configuration shared by all variants)
- [ ] T043 [US2] Create profile module at modules/profiles/hetzner-sway-production.nix
- [ ] T044 [US2] Create profile module at modules/profiles/hetzner-sway-image.nix
- [ ] T045 [US2] Create profile module at modules/profiles/hetzner-sway-minimal.nix
- [ ] T046 [US2] Create profile module at modules/profiles/hetzner-sway-ultra-minimal.nix
- [ ] T047 [US2] Update configurations/hetzner-sway.nix to import profile + common
- [ ] T048 [US2] Update configurations/hetzner-sway-image.nix to import profile + common
- [ ] T049 [US2] Update configurations/hetzner-sway-minimal.nix to import profile + common
- [ ] T050 [US2] Update configurations/hetzner-sway-ultra-minimal.nix to import profile + common

### Validation & Commit

- [ ] T051 [US2] Run validation script at specs/089-nixos-home-manager-cleanup/contracts/validation.sh
- [ ] T052 [US2] Run hardware validation script at specs/089-nixos-home-manager-cleanup/contracts/hardware-validation.sh
- [ ] T053 [US2] Test all four hetzner-sway variants build correctly (`nix flake show`)
- [ ] T054 [US2] Commit Phase 2 changes with message: "feat(089): Phase 2 - Consolidate duplicate modules"

**User Story 2 Acceptance**: All duplicate modules consolidated, all original functionality preserved, ~200 LOC reduction achieved

---

## Phase 5: User Story 3 - Document and Validate Active System Boundary (P3)

**Story Goal**: Clear documentation of what is actively used versus archived so that future contributors can confidently make changes without fear of breaking unused features.

**Independent Test Criteria**:
- Only active configurations (hetzner-sway, m1) listed as current targets in documentation
- Only modules supporting active Sway/Wayland systems remain in main codebase
- New contributors can quickly identify two active system targets without encountering confusing deprecated code
- Archived features documented with clear explanations of why they were deprecated

**Expected Outcome**: Documentation accurately reflects current system state

### Update Documentation

- [ ] T055 [US3] Update docs/CLAUDE.md to remove all WSL references as current target
- [ ] T056 [US3] Update docs/CLAUDE.md to remove hetzner (i3) configuration references
- [ ] T057 [US3] Update docs/CLAUDE.md to remove KDE Plasma references
- [ ] T058 [US3] Update docs/CLAUDE.md Configuration Targets section to list only hetzner-sway and m1
- [ ] T059 [US3] Update README.md to reflect only active targets (hetzner-sway, m1) and remove WSL setup instructions
- [ ] T060 [US3] Create archived/DEPRECATED_FEATURES.md documenting deprecated features (WSL, KDE Plasma, X11/RDP, i3)

### Validation & Commit

- [ ] T061 [US3] Verify documentation consistency (no WSL, hetzner.nix, or KDE Plasma references in docs/)
- [ ] T062 [US3] Run validation script at specs/089-nixos-home-manager-cleanup/contracts/validation.sh
- [ ] T063 [US3] Commit Phase 3 changes with message: "feat(089): Phase 3 - Update documentation for active system boundary"

**User Story 3 Acceptance**: Documentation accurately reflects active system boundary, deprecated features clearly documented

---

## Phase 6: Polish & Cross-Cutting Concerns

**Goal**: Final validation and cleanup

**Tasks**:

- [ ] T064 Run full validation suite (validation.sh + hardware-validation.sh) on both configurations
- [ ] T065 Verify success criteria: LOC reduction (1,200-1,500), file count (20+ files deleted/archived), zero backup files, documentation accuracy

**Validation**: All success criteria met, both configurations build successfully, all active features working

---

## Parallel Execution Examples

### User Story 1 (P1) - Maximum Parallelization

Tasks T008-T018 can all be executed in parallel (marked with `[P]`) as they operate on different files:

```bash
# Terminal 1
git rm modules/desktop/i3-project-workspace.nix
git rm modules/desktop/xrdp.nix

# Terminal 2
git rm modules/desktop/remote-access.nix
git rm modules/desktop/rdp-display.nix

# Terminal 3
git rm modules/desktop/wireless-display.nix
git rm modules/desktop/firefox-virtual-optimization.nix

# Terminal 4
git rm modules/services/audio-network.nix
git rm modules/services/kde-optimization.nix
git rm modules/services/wsl-docker.nix

# Terminal 5
git rm modules/assertions/wsl-check.nix
git rm modules/wsl/wsl-config.nix
```

**Benefit**: 11 deletions can be parallelized, reducing time by ~80%

### User Story 2 (P2) - Module Group Parallelization

Each consolidation group can be worked on independently:

```bash
# Developer 1: 1Password consolidation (T031-T036)
# Developer 2: Firefox+PWA consolidation (T037-T041)
# Developer 3: Hetzner-Sway variant consolidation (T042-T050)
```

**Benefit**: 3 independent consolidation efforts can proceed in parallel

### User Story 3 (P3) - Documentation Parallelization

Documentation updates can be parallelized:

```bash
# Developer 1: Update CLAUDE.md (T055-T058)
# Developer 2: Update README.md (T059)
# Developer 3: Create DEPRECATED_FEATURES.md (T060)
```

**Benefit**: 3 documentation tasks can proceed in parallel

---

## Testing & Validation

### Independent Test Criteria per User Story

**User Story 1 (P1)**:
```bash
# Run validation
specs/089-nixos-home-manager-cleanup/contracts/validation.sh

# Expected: Both configurations build successfully
# Expected: nix flake check passes
# Expected: Zero backup files remain

# Verify
find . -name "*.backup*" | wc -l  # Should return 0
```

**User Story 2 (P2)**:
```bash
# Run validation
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
specs/089-nixos-home-manager-cleanup/contracts/hardware-validation.sh

# Test consolidated modules
# - 1Password GUI, automation, SSH agent all functional
# - Firefox with and without PWAs works correctly
# - All four hetzner-sway variants build correctly

# Verify
wc -l modules/services/onepassword*.nix  # Should show reduction
nix flake show  # Should list all 4 hetzner-sway variants
```

**User Story 3 (P3)**:
```bash
# Verify documentation accuracy
grep -r "WSL" docs/CLAUDE.md docs/README.md  # Should return no matches
grep -r "hetzner.nix" docs/ | grep -v archived  # Should return no active references

# Run final validation
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
```

### Rollback Procedures

**Before Commit (Any Phase)**:
```bash
# Discard all uncommitted changes
git reset --hard HEAD

# Re-run baseline validation
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
```

**After Commit**:
```bash
# Rollback to previous commit
git reset --hard HEAD~1

# Or rollback to specific commit
git log --oneline
git reset --hard <commit-hash>

# Re-run validation
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
```

**System Won't Boot** (Emergency):
1. Boot into previous NixOS generation at bootloader
2. `sudo nix-env --rollback --profile /nix/var/nix/profiles/system`
3. `sudo reboot`

---

## Success Metrics

**Code Reduction**:
- [ ] Codebase reduced by 1,200-1,500 LOC (verify with `wc -l modules/**/*.nix` before/after)
- [ ] User Story 1: ~1,000 LOC removed
- [ ] User Story 2: ~200 LOC removed

**File Management**:
- [ ] 20+ files moved to archived/ or deleted (verify with `git log --stat`)
- [ ] Zero backup files remain (verify with `find . -name "*.backup*"`)

**Configuration Quality**:
- [ ] Both configurations build successfully (`validation.sh` passes)
- [ ] Hardware features preserved (`hardware-validation.sh` passes)
- [ ] `nix flake check` passes
- [ ] All 88 active features continue working (manual smoke tests)

**Documentation**:
- [ ] Only hetzner-sway and m1 listed as active targets in CLAUDE.md
- [ ] No references to deprecated targets (WSL, hetzner i3, KDE Plasma) in user-facing docs
- [ ] Archived features documented with deprecation rationale

---

## Next Steps After Implementation

1. **Deploy to Actual Systems**: Test on hetzner-sway and m1 with `nixos-rebuild switch`
2. **Monitor for Regressions**: Watch for any functionality issues
3. **Update Feature Documentation**: Ensure specs/ accurately reflects current state
4. **Create Release Notes**: Document cleanup in project changelog

---

**End of Tasks**
