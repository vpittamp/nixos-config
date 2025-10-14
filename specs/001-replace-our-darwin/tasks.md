# Tasks: Migrate Darwin Home-Manager to Nix-Darwin

**Input**: Design documents from `/specs/001-replace-our-darwin/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/darwin-configuration-interface.md

**Tests**: Tests are NOT explicitly requested in the specification. Manual validation workflows are defined using darwin-rebuild commands.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- Configuration management project - paths are Nix files in nixos-config repository
- Main configuration: `configurations/darwin.nix`
- Flake entry point: `flake.nix`
- Module directory: `modules/darwin/` (optional)
- Documentation: `CLAUDE.md`, `README.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify prerequisites and validate current state before making changes

- [X] T001 Verify Nix 2.18+ with flakes enabled: `nix --version && nix flake metadata`
- [X] T002 [P] Verify macOS 12.0+ (Monterey): `sw_vers -productVersion`
- [X] T003 [P] Verify XCode Command Line Tools installed: `xcode-select -p`
- [X] T004 [P] Verify current home-manager Darwin profile works: `home-manager switch --flake .#darwin`
- [X] T005 [P] Backup current Nix profile state: `ls -la ~/.nix-profile && home-manager generations | head -5`
- [X] T006 Document current package count as baseline: `nix-store -q --requisites ~/.nix-profile | wc -l` (732 packages)

**Checkpoint**: Prerequisites validated - ready for foundational configuration

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Flake Configuration (FR-001, FR-006)

- [X] T007 Add darwinConfigurations output to `flake.nix` with correct structure per contracts/darwin-configuration-interface.md
- [X] T008 Configure system detection using `builtins.currentSystem or "aarch64-darwin"` for multi-arch support (FR-005)
- [X] T009 Import home-manager.darwinModules.home-manager as module (FR-002)
- [X] T010 Pass specialArgs with inputs to enable cross-module access
- [X] T011 Verify flake evaluates correctly: `nix flake check --show-trace`

### Base Darwin Configuration File (FR-001, FR-006, FR-012)

- [X] T012 Create `configurations/darwin.nix` with required top-level attributes per contracts (system.stateVersion, nix.settings, nixpkgs.config)
- [X] T013 Configure Nix settings: experimental-features = ["nix-command" "flakes"], trusted-users, nix.optimise.automatic (replaced auto-optimise-store)
- [X] T014 Set up system identification: networking.computerName, networking.hostName, networking.localHostName, system.primaryUser
- [X] T015 Configure system.configurationRevision to track git commits (FR-007, Reproducible Builds)
- [X] T016 Set nixpkgs.config.allowUnfree = true
- [X] T017 Set nixpkgs.hostPlatform automatically from system attribute (removed builtins.currentSystem)
- [X] T018 Configure garbage collection: nix.gc.automatic, nix.gc.interval, nix.gc.options (FR-009)

### Home-Manager Integration Setup (FR-002, FR-007, FR-013)

- [X] T019 Configure home-manager module: useGlobalPkgs = true, useUserPackages = true, backupFileExtension = "backup"
- [X] T020 Import existing `home-darwin.nix` in home-manager.users.vinodpittampalli imports list (FR-013)
- [X] T021 Pass extraSpecialArgs with inputs and pkgs-unstable to home-manager
- [X] T022 home.username, home.homeDirectory, home.stateVersion, and home.enableNixpkgsReleaseCheck set in home-darwin.nix with lib.mkForce

### Build and Validation (Constitution II)

- [X] T023 Test syntax validation: `nix flake check` passed
- [X] T024 Test dry-run: Not needed - build succeeded
- [X] T025 Test build without activation: `nix run nix-darwin -- build --flake .#darwin` - SUCCESS
- [X] T026 Verify result symlink created and points to valid system derivation: /nix/store/bq68xsfm87wqda8svxa8v04hni1bh7j5-darwin-system-25.11.9a9ab01
- [X] T027 Document any warnings or issues found during build: Fixed nerdfonts → nerd-fonts namespace, removed deprecated options, added system.primaryUser

**Checkpoint**: Foundation ready - flake builds successfully, home-manager integrated. User story implementation can now begin.

---

## Phase 3: User Story 1 - System-Level Package Management (Priority: P1) 🎯 MVP

**Goal**: Enable nix-darwin to manage system-level packages so development tools are available system-wide and consistent with NixOS systems.

**Independent Test**: Run `darwin-rebuild switch --flake .#darwin` and verify core packages (git, vim, curl, wget, etc.) are available in `/run/current-system/sw/bin`

### Implementation for User Story 1

#### Core System Packages (FR-003)

- [ ] T028 [US1] Add core utilities to environment.systemPackages in `configurations/darwin.nix`: git, vim, wget, curl, htop, tmux, tree
- [ ] T029 [P] [US1] Add additional utilities: ripgrep, fd, ncdu, rsync, openssl, jq, yq
- [ ] T030 [P] [US1] Add Nix tools: nix-prefetch-git, nixpkgs-fmt
- [ ] T031 [P] [US1] Configure system fonts (FR-008): fonts.packages with Nerd Fonts matching NixOS config

#### PATH Configuration (FR-014)

- [ ] T032 [US1] Verify environment.systemPath includes /run/current-system/sw/bin (should be default, check if override needed)
- [ ] T033 [US1] Add module comment explaining system vs user package organization strategy

#### Activation and Verification (AS1.1, AS1.2, AS1.3)

- [ ] T034 [US1] Run initial activation: `./result/sw/bin/darwin-rebuild switch --flake .#darwin`
- [ ] T035 [US1] Verify darwin-rebuild is now in PATH: `which darwin-rebuild`
- [ ] T036 [US1] Verify system profile: `ls -l /run/current-system && ls -l /run/current-system/sw`
- [ ] T037 [US1] Test AS1.1: Verify core tools available system-wide: `which git vim curl wget htop tmux tree ripgrep fd`
- [ ] T038 [US1] Verify tools are from system profile: `which git | grep /run/current-system`
- [ ] T039 [US1] Test AS1.2: Add new package (e.g., bat), rebuild, verify installed
- [ ] T040 [US1] Test AS1.3: Compare package list with NixOS base.nix, document Darwin-specific exclusions
- [ ] T041 [US1] Verify generations created: `darwin-rebuild --list-generations`
- [ ] T042 [US1] Test rollback mechanism: `darwin-rebuild rollback && darwin-rebuild switch --flake .#darwin`

**Checkpoint**: System-level package management functional. Core tools available system-wide. Foundation for all other user stories complete.

---

## Phase 4: User Story 2 - Home-Manager Integration (Priority: P1)

**Goal**: Ensure home-manager integrates seamlessly with nix-darwin so user-level dotfiles and configurations work identically to current setup.

**Independent Test**: Verify bash, tmux, neovim, and other user-level configurations from home-modules work correctly after darwin-rebuild.

### Implementation for User Story 2

#### Verify Home-Manager Activation (FR-002, FR-013)

- [ ] T043 [US2] Verify home-manager activates during darwin-rebuild: check activation output for "Activating *" messages
- [ ] T044 [US2] Verify user profile updated: `ls -l ~/.nix-profile`
- [ ] T045 [US2] Verify home-manager generations tracked: `home-manager generations | head -5`
- [ ] T046 [US2] Compare package count with baseline from T006: should be same or more

#### User Configuration Validation (AS2.1, AS2.2, AS2.3, SC-003, SC-008)

- [ ] T047 [US2] Test AS2.1 - Shell configs: Open new terminal, verify bash 5.3+ active: `bash --version`
- [ ] T048 [US2] Test AS2.1 - Starship prompt: Verify prompt appears with colors and OS icon
- [ ] T049 [US2] Test AS2.2 - Bash config: Verify aliases work: `ll` (eza), `cat` (bat), `grep` (rg)
- [ ] T050 [US2] Test AS2.2 - Tmux config: `tmux new -s test` and verify custom config active (status bar, key bindings)
- [ ] T051 [US2] Test AS2.2 - Tmux: Kill test session: `tmux kill-session -t test`
- [ ] T052 [US2] Test AS2.3 - Neovim: Launch `nvim`, verify plugins loaded: `:checkhealth` and `:Lazy`
- [ ] T053 [US2] Verify zoxide integration: `zoxide query -l` shows database
- [ ] T054 [US2] Verify fzf key bindings work: Ctrl+T for file search
- [ ] T055 [US2] Verify direnv works if project uses it: `cd` into project with .envrc

#### Backward Compatibility Verification (FR-013, SC-008)

- [ ] T056 [US2] Verify all packages from T006 baseline still available
- [ ] T057 [US2] Verify dotfile locations unchanged: `ls -la ~/.config ~/.bashrc ~/.tmux.conf`
- [ ] T058 [US2] Verify no file conflicts or .backup files created unexpectedly
- [ ] T059 [US2] Compare home-manager config with pre-migration: should be identical

**Checkpoint**: Home-manager integration complete. All user-level configurations work identically to pre-migration state.

---

## Phase 5: User Story 3 - 1Password Integration (Priority: P2)

**Goal**: Configure 1Password CLI and SSH agent for consistent secret access and SSH authentication across all systems.

**Independent Test**: Run `op signin`, test SSH authentication with `ssh -T git@github.com`, verify Git commit signing works.

### Implementation for User Story 3

#### SSH Configuration for 1Password (FR-004, FR-010)

- [ ] T060 [US3] Configure programs.ssh.extraConfig in `configurations/darwin.nix` with macOS-specific socket path per research.md Q4
- [ ] T061 [US3] Add SSH config: `Host *` → `IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"`
- [ ] T062 [US3] Add SSH config: `IdentitiesOnly yes` and `PreferredAuthentications publickey`
- [ ] T063 [US3] Set environment variable: SSH_AUTH_SOCK with macOS-specific path
- [ ] T064 [US3] Add comment explaining 1Password SSH agent integration for macOS

#### Rebuild and Verification (AS3.1, AS3.2, AS3.3, SC-004)

- [ ] T065 [US3] Rebuild to apply SSH configuration: `darwin-rebuild switch --flake .#darwin`
- [ ] T066 [US3] Verify 1Password GUI is running: `ps aux | grep -i 1password`
- [ ] T067 [US3] Verify SSH agent socket exists: `ls -la ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock`
- [ ] T068 [US3] Test AS3.1 - CLI access: `op signin && op item list`
- [ ] T069 [US3] Test AS3.2 - SSH agent: `ssh-add -l` (should list keys from 1Password)
- [ ] T070 [US3] Test AS3.2 - SSH authentication: `ssh -T git@github.com` (should authenticate via 1Password)
- [ ] T071 [US3] Test AS3.3 - Git signing: Verify git signing configured: `git config --get commit.gpgsign`
- [ ] T072 [US3] Test AS3.3 - Git signing: Create test commit with signing: `git commit --allow-empty -m "test signing" --gpg-sign`
- [ ] T073 [US3] Verify Git signing user config from home-modules/tools/git.nix unchanged (should already work)

**Checkpoint**: 1Password integration complete. SSH agent and Git signing work consistently with other systems.

---

## Phase 6: User Story 4 - Development Services (Priority: P2)

**Goal**: Configure Docker and development tools so the development workflow matches Linux systems.

**Independent Test**: Run `docker ps`, verify kubectl/k9s work, test that compilers (node, python, go, rust) are available.

### Implementation for User Story 4

#### Development Packages (FR-003, FR-011)

- [ ] T074 [US4] Add compilers to environment.systemPackages in `configurations/darwin.nix`: nodejs, python3, go, rustc, cargo
- [ ] T075 [P] [US4] Add build tools: gcc, gnumake, cmake, pkg-config
- [ ] T076 [P] [US4] Add container tools: docker-compose (Docker Desktop provides docker CLI)
- [ ] T077 [P] [US4] Add Kubernetes tools: kubectl, kubernetes-helm, k9s, kind, argocd
- [ ] T078 [P] [US4] Add cloud CLIs: terraform, google-cloud-sdk, hcloud (Hetzner Cloud)
- [ ] T079 [US4] Add module comment explaining Docker Desktop must be installed separately (not managed by Nix)

#### Rebuild and Verification (AS4.1, AS4.2, AS4.3, SC-005)

- [ ] T080 [US4] Rebuild system: `darwin-rebuild switch --flake .#darwin`
- [ ] T081 [US4] Test AS4.3 - Verify compilers: `node --version && python3 --version && go version && rustc --version`
- [ ] T082 [US4] Verify build tools: `gcc --version && make --version && cmake --version`
- [ ] T083 [US4] Verify Docker Desktop running: `ps aux | grep -i docker.app`
- [ ] T084 [US4] Test AS4.1 - Docker access: `docker ps` (should not require sudo)
- [ ] T085 [US4] Verify docker-compose: `docker-compose --version`
- [ ] T086 [US4] Test AS4.2 - Kubernetes tools: `kubectl version --client && helm version && k9s version`
- [ ] T087 [US4] Verify cloud CLIs: `terraform version && gcloud version && hcloud version`
- [ ] T088 [US4] Test a simple development workflow: create test Node.js project, install deps, run

**Checkpoint**: Development services configured. All compilers, container tools, and cloud CLIs available and functional.

---

## Phase 7: User Story 5 - macOS System Preferences (Priority: P3)

**Goal**: Manage common macOS system preferences declaratively so system settings are reproducible.

**Independent Test**: Verify dock settings, keyboard preferences, and trackpad configurations are applied after rebuild and persist after logout/reboot.

### Implementation for User Story 5

#### macOS Defaults Configuration (FR-015)

- [ ] T089 [US5] Add system.defaults.dock configuration to `configurations/darwin.nix` per research.md Q5:
  - autohide = true
  - orientation = "bottom"
  - show-recents = false
  - tilesize = 48
- [ ] T090 [P] [US5] Add system.defaults.finder configuration:
  - AppleShowAllExtensions = true
  - FXEnableExtensionChangeWarning = false
  - _FXShowPosixPathInTitle = true
- [ ] T091 [P] [US5] Add system.defaults.trackpad configuration:
  - Clicking = true (tap to click)
  - TrackpadRightClick = true
  - TrackpadThreeFingerDrag = false
- [ ] T092 [P] [US5] Add system.defaults.NSGlobalDomain configuration:
  - AppleKeyboardUIMode = 3 (full keyboard control)
  - ApplePressAndHoldEnabled = false (enable key repeat)
  - InitialKeyRepeat = 15
  - KeyRepeat = 2
  - NSAutomaticCapitalizationEnabled = false
  - NSAutomaticSpellingCorrectionEnabled = false
  - "com.apple.mouse.tapBehavior" = 1
- [ ] T093 [US5] Add module comments explaining each preference group and why chosen

#### Activation and Verification (AS5.1, AS5.2, AS5.3, SC-010)

- [ ] T094 [US5] Rebuild system: `darwin-rebuild switch --flake .#darwin`
- [ ] T095 [US5] Test AS5.1 - Verify dock autohide: `defaults read com.apple.dock autohide` (should return 1)
- [ ] T096 [US5] Test AS5.1 - Verify dock tilesize: `defaults read com.apple.dock tilesize` (should return 48)
- [ ] T097 [US5] Test AS5.1 - Restart Dock to apply: `killall Dock` and verify settings visible
- [ ] T098 [US5] Verify Finder preferences: `defaults read com.apple.finder AppleShowAllExtensions` (should return 1)
- [ ] T099 [US5] Restart Finder: `killall Finder` and verify extensions shown
- [ ] T100 [US5] Test AS5.2 - Verify keyboard repeat enabled: type and hold key, should repeat
- [ ] T101 [US5] Verify trackpad preferences: `defaults read NSGlobalDomain com.apple.mouse.tapBehavior` (should return 1)
- [ ] T102 [US5] Test AS5.3 - Verify tap-to-click works on trackpad
- [ ] T103 [US5] Test persistence: Log out and log back in, verify all preferences still applied
- [ ] T104 [US5] Test persistence: Reboot system, verify all preferences still applied after startup

**Checkpoint**: macOS system preferences configured declaratively. All settings persist across logout and reboot.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

### Documentation Updates (Constitution V, FR-Documentation)

- [ ] T105 [P] Update `CLAUDE.md` with nix-darwin commands per plan.md section "Documentation Updates Required"
- [ ] T106 [P] Update `CLAUDE.md` with Darwin-specific troubleshooting section
- [ ] T107 [P] Optionally update `README.md` to mention nix-darwin as alternative to standalone home-manager
- [ ] T108 [P] Add inline comments to `configurations/darwin.nix` explaining key decisions and structure
- [ ] T109 [P] Verify quickstart.md instructions match actual implementation

### Final Validation (All Success Criteria)

- [ ] T110 Comprehensive validation - SC-001: Test complete rebuild: `darwin-rebuild switch --flake .#darwin` (exit code 0)
- [ ] T111 Comprehensive validation - SC-002: Verify all core tools from base.nix available system-wide
- [ ] T112 Comprehensive validation - SC-003: Verify bash, tmux, neovim configs identical to pre-migration
- [ ] T113 Comprehensive validation - SC-004: Verify 1Password SSH agent works for Git and SSH
- [ ] T114 Comprehensive validation - SC-005: Verify Docker commands work without sudo
- [ ] T115 Comprehensive validation - SC-006: Document macOS version (for future upgrade testing)
- [ ] T116 Comprehensive validation - SC-007: Measure rebuild time, compare to baseline from T006: `time darwin-rebuild switch --flake .#darwin`
- [ ] T117 Comprehensive validation - SC-008: Verify all packages from pre-migration functional
- [ ] T118 Comprehensive validation - SC-009: Verify system attribute supports both architectures: `nix eval --raw .#darwinConfigurations.darwin.system`
- [ ] T119 Comprehensive validation - SC-010: Verify system preferences persist after reboot

### Performance and Cleanup

- [ ] T120 [P] Run garbage collection: `nix-collect-garbage -d` (clean up old generations from testing)
- [ ] T121 [P] Verify store optimization enabled: `nix-store --optimize` or check nix.settings.auto-optimise-store
- [ ] T122 [P] Document store size: `du -sh /nix/store`
- [ ] T123 [P] Document system profile size: `du -sh /run/current-system`

### Rollback Testing (Constitution VII)

- [ ] T124 Test rollback to previous generation: `darwin-rebuild rollback`
- [ ] T125 Verify system reverted correctly after rollback
- [ ] T126 Switch back to latest: `darwin-rebuild switch --flake .#darwin`
- [ ] T127 Document rollback process in case of issues

### Final Integration Testing

- [ ] T128 Run full workflow test: Create new project, install dependencies, use Docker, commit with signing
- [ ] T129 Test edge case: Add package that doesn't exist on Darwin, verify build fails gracefully
- [ ] T130 Test edge case: Temporarily break syntax, verify `darwin-rebuild check` catches it
- [ ] T131 Verify constitution compliance: Test-first deployment workflow documented and followed
- [ ] T132 Verify constitution compliance: All configuration declarative, no manual modifications
- [ ] T133 Verify constitution compliance: Modular composition maintained, no duplication

**Checkpoint**: All features complete, validated, and documented. Ready for production use.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - User Story 1 (P1) and User Story 2 (P1) can proceed in parallel after Foundational
  - User Story 3 (P2) can start after US1/US2 or in parallel (minimal dependencies)
  - User Story 4 (P2) can start after US1/US2 or in parallel (minimal dependencies)
  - User Story 5 (P3) can start after US1/US2 or in parallel (independent from US3/US4)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Requires Foundational (Phase 2) complete - No dependencies on other stories
- **User Story 2 (P1)**: Requires Foundational (Phase 2) complete - Depends on US1 for system to be activatable
- **User Story 3 (P2)**: Requires Foundational (Phase 2) complete - Minimal dependencies (could start after US1)
- **User Story 4 (P2)**: Requires Foundational (Phase 2) complete - Depends on US1 (needs system packages) but independent of US2/US3
- **User Story 5 (P3)**: Requires Foundational (Phase 2) complete - Independent of all other stories

### Within Each Phase

- Setup: All tasks can run in parallel (marked [P])
- Foundational:
  - T007-T011 (Flake config) must complete before T023-T027 (validation)
  - T012-T022 can progress in parallel with flake work
  - T023-T027 (validation) must be last
- User Story 1: T028-T033 (implementation) before T034-T042 (activation/validation)
- User Story 2: Verification tasks are sequential (need to test each config area)
- User Story 3: T060-T064 (config) before T065-T073 (validation)
- User Story 4: T074-T079 (packages) before T080-T088 (validation)
- User Story 5: T089-T093 (config) can be parallel [P], then T094-T104 (validation)
- Polish: Documentation tasks [P] can be parallel, validation tasks sequential

### Parallel Opportunities

- All Setup tasks (T001-T006) can run in parallel
- Within Foundational:
  - T012-T018 (base config attributes) can be added in any order
  - T019-T022 (home-manager config) can be parallel with T012-T018
- User Story 1:
  - T028-T031 (package additions) can all be parallel [P]
- User Story 4:
  - T074-T078 (package additions) can all be parallel [P]
- User Story 5:
  - T089-T093 (system.defaults groups) can all be parallel [P]
- Polish Phase:
  - T105-T109 (documentation) can all be parallel [P]
  - T120-T123 (cleanup) can all be parallel [P]

---

## Parallel Example: Foundational Phase

```bash
# After T007-T011 (flake config) complete:

# Launch all base config tasks together:
Task: "Add core utilities to environment.systemPackages"
Task: "Configure Nix settings"
Task: "Configure system identification"
Task: "Configure garbage collection"

# Home-manager config can happen in parallel:
Task: "Configure home-manager module settings"
Task: "Import existing home-darwin.nix"
```

## Parallel Example: User Story 1

```bash
# Launch all package addition tasks together:
Task: "Add core utilities: git, vim, wget, curl, htop, tmux, tree"
Task: "Add additional utilities: ripgrep, fd, ncdu, rsync, openssl, jq, yq"
Task: "Add Nix tools: nix-prefetch-git, nixpkgs-fmt"
Task: "Configure system fonts with Nerd Fonts"
```

## Parallel Example: User Story 4

```bash
# Launch all development package tasks together:
Task: "Add compilers: nodejs, python3, go, rustc, cargo"
Task: "Add build tools: gcc, gnumake, cmake, pkg-config"
Task: "Add container tools: docker-compose"
Task: "Add Kubernetes tools: kubectl, kubernetes-helm, k9s, kind"
Task: "Add cloud CLIs: terraform, google-cloud-sdk, hcloud"
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only)

The minimum viable product delivers system-level package management and home-manager integration:

1. Complete Phase 1: Setup (verify prerequisites)
2. Complete Phase 2: Foundational (CRITICAL - creates working nix-darwin config)
3. Complete Phase 3: User Story 1 (system packages available system-wide)
4. Complete Phase 4: User Story 2 (user dotfiles work identically)
5. **STOP and VALIDATE**: Test independently - you now have a working nix-darwin system!
6. Document experience, measure rebuild time, verify all configs work

At this point you have a functional replacement for standalone home-manager with added system-level management.

### Incremental Delivery (Recommended)

Each user story adds value without breaking previous stories:

1. **Foundation** (Setup + Foundational) → Can build darwin system
2. **+ US1** (System Packages) → System-wide tools available → **DEMO/VALIDATE**
3. **+ US2** (Home-Manager) → User dotfiles integrated → **DEMO/VALIDATE** (🎯 MVP!)
4. **+ US3** (1Password) → Secure SSH/Git signing → **DEMO/VALIDATE**
5. **+ US4** (Dev Services) → Full dev environment → **DEMO/VALIDATE**
6. **+ US5** (macOS Preferences) → System settings managed → **DEMO/VALIDATE**
7. **+ Polish** → Documentation complete, fully validated → **PRODUCTION READY**

Stop and validate after each user story. Each is independently testable and deployable.

### Parallel Team Strategy

If multiple people are working on this:

1. **Team completes Setup + Foundational together** (T001-T027)
2. **Once T027 checkpoint reached:**
   - Person A: User Story 1 (T028-T042) - System packages
   - Person B: Can start User Story 3 (T060-T073) - 1Password (minimal dependency on US1)
   - Person C: Can start User Story 5 (T089-T104) - macOS preferences (independent)
3. **After US1 complete:**
   - Person A: User Story 2 (T043-T059) - Home-manager integration
   - Person D: Can start User Story 4 (T074-T088) - Development services
4. **Converge on Polish Phase** (T105-T133) together

---

## Notes

- [P] tasks = different files or independent config sections, no dependencies
- [Story] label (e.g., US1, US2) maps task to specific user story for traceability
- Each user story is independently completable and testable
- Configuration management = no traditional unit tests, validation via rebuild + manual checks
- Test-first deployment = always check/dry-run/build before switch (Constitution II)
- All changes are declarative in .nix files (Constitution I)
- Commit after each phase or logical group of tasks
- Use `darwin-rebuild --show-trace` for debugging evaluation errors
- Rollback is always available via `darwin-rebuild rollback` or generation switching

### Constitution Compliance Reminders

- **Test-First (II)**: Run check → dry-run → build → switch workflow for every change
- **Declarative (I)**: All changes in .nix files, no manual `defaults write` commands
- **Modular (III)**: Follow established patterns, use lib.mkDefault, no duplication
- **Platform Compatible (IV)**: Changes only affect Darwin, all other platforms unchanged
- **Documented (V)**: Update CLAUDE.md and add inline comments
- **Single Source (VI)**: Reuse existing modules, no copy-paste from NixOS configs
- **Reproducible (VII)**: Git commits tracked, generations enable rollback

### Key Functional Requirements Map

- FR-001: T007-T012 (nix-darwin configuration)
- FR-002: T009, T019-T022 (home-manager integration)
- FR-003: T028-T031 (core packages matching base.nix)
- FR-004: T060-T064 (1Password configuration)
- FR-005: T008, T017 (multi-architecture support)
- FR-006: T007, T013 (Nix with flakes)
- FR-007: T020 (import darwin-home.nix)
- FR-008: T031 (system fonts)
- FR-009: T018 (garbage collection)
- FR-010: T060-T064 (SSH with 1Password)
- FR-011: T074-T079 (development.nix equivalent)
- FR-012: Throughout (lib.mkDefault convention)
- FR-013: T020, T056-T059 (compatibility with darwin-home.nix)
- FR-014: T032 (PATH configuration)
- FR-015: T089-T093 (macOS system preferences)

### Success Criteria Validation Map

- SC-001: T034, T110 (darwin-rebuild switch works)
- SC-002: T037-T038, T111 (core tools system-wide)
- SC-003: T047-T055, T112 (configs work identically)
- SC-004: T068-T072, T113 (1Password SSH agent works)
- SC-005: T084-T085, T114 (Docker without sudo)
- SC-006: T115 (documented for future testing)
- SC-007: T006, T116 (rebuild time comparison)
- SC-008: T056, T117 (all packages functional)
- SC-009: T008, T118 (multi-architecture support)
- SC-010: T095-T104, T119 (preferences persist)

---

**Total Tasks**: 133
- Setup: 6 tasks
- Foundational: 21 tasks (BLOCKS all stories)
- User Story 1 (P1): 15 tasks
- User Story 2 (P1): 17 tasks
- User Story 3 (P2): 14 tasks
- User Story 4 (P2): 15 tasks
- User Story 5 (P3): 16 tasks
- Polish: 29 tasks

**Parallel Opportunities**: 47 tasks marked [P] can run concurrently within their phase

**MVP Scope**: Complete through User Story 2 (T001-T059) = 59 tasks for fully functional nix-darwin system

**Suggested First Milestone**: Setup + Foundational + US1 + US2 = Working nix-darwin with home-manager integration (59 tasks)
