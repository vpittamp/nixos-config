# Tasks: Multi-Session Remote Desktop & Web Application Launcher

**Input**: Design documents from `/etc/nixos/specs/007-add-a-few/`
**Prerequisites**: plan.md, spec.md (user stories), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in feature specification. Tasks focus on implementation and manual validation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, TERM, CLIP, DOC)
- Include exact file paths in descriptions

## Path Conventions
- **System modules**: `/etc/nixos/modules/desktop/`, `/etc/nixos/modules/services/`
- **User modules**: `/etc/nixos/home-modules/tools/`, `/etc/nixos/home-modules/terminal/`
- **Configurations**: `/etc/nixos/configurations/`
- **Assets**: `/etc/nixos/assets/webapp-icons/`
- **Documentation**: `/etc/nixos/docs/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and directory structure

- [X] T001 Create assets directory for web application icons at `/etc/nixos/assets/webapp-icons/`
- [X] T002 [P] Verify existing module structure (modules/desktop/, home-modules/tools/, home-modules/terminal/)
- [X] T003 [P] Review existing xrdp.nix and i3wm.nix modules to understand current configuration

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Update `/etc/nixos/modules/desktop/xrdp.nix` - Configure UBC session policy (Policy=UBC)
- [X] T005 Update `/etc/nixos/modules/desktop/xrdp.nix` - Set killDisconnected=no for session persistence
- [X] T006 Update `/etc/nixos/modules/desktop/xrdp.nix` - Configure disconnectedTimeLimit=86400 (24 hours)
- [X] T007 Update `/etc/nixos/modules/desktop/xrdp.nix` - Set maxSessions=5 for concurrent connections
- [X] T008 Update `/etc/nixos/modules/desktop/xrdp.nix` - Set X11DisplayOffset=10
- [X] T009 Update `/etc/nixos/modules/desktop/xrdp.nix` - Disable PipeWire, enable PulseAudio for audio support
- [X] T010 Update `/etc/nixos/modules/desktop/i3wm.nix` - Ensure i3wm is configured as default window manager
- [X] T011 Update `/etc/nixos/configurations/hetzner-i3.nix` - Import updated xrdp module
- [X] T012 Validate 1Password compatibility: Test `/etc/nixos/modules/services/onepassword.nix` in multi-session context

**Checkpoint**: xrdp multi-session foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Concurrent Remote Desktop Access (Priority: P1) 🎯 MVP

**Goal**: Allow multiple simultaneous RDP connections from different devices without terminating existing sessions

**Independent Test**: Connect via Microsoft Remote Desktop from two different devices sequentially and verify both sessions remain active and independently usable

### Implementation for User Story 1

- [X] T013 [US1] Test multi-session xrdp configuration with `nixos-rebuild dry-build --flake .#hetzner`
- [X] T014 [US1] Apply configuration with `nixos-rebuild switch --flake .#hetzner`
- [ ] T015 [US1] Manual Test 1: Connect from Device A via Microsoft Remote Desktop
- [ ] T016 [US1] Manual Test 2: Connect from Device B while Device A is connected
- [ ] T017 [US1] Verify both sessions remain active (check `loginctl list-sessions`)
- [ ] T018 [US1] Verify X11 displays are separate (check `ps aux | grep Xorg` for :10, :11)
- [ ] T019 [US1] Manual Test 3: Disconnect Device A, verify Device B session unaffected
- [ ] T020 [US1] Manual Test 4: Reconnect Device A, verify new session created (or existing session rejoined)
- [ ] T021 [US1] Verify 1Password desktop app accessible in both sessions
- [ ] T022 [US1] Verify window positions and application state preserved on reconnection
- [ ] T023 [US1] Monitor session cleanup after 24 hours (optional long-term validation)

**Checkpoint**: User Story 1 (Multi-session RDP) is fully functional and testable independently

---

## Phase 4: User Story 2 - Web Application Launcher System (Priority: P2)

**Goal**: Launch web applications as standalone desktop applications searchable via rofi

**Independent Test**: Define a list of web URLs, verify they appear in rofi search, launch them into separate windows, and confirm they behave as independent applications

### Implementation for User Story 2

- [X] T024 [P] [US2] Create `/etc/nixos/home-modules/tools/web-apps-sites.nix` - Define web application sites
- [X] T025 [P] [US2] Create `/etc/nixos/home-modules/tools/web-apps-declarative.nix` - Main web app launcher module
- [X] T026 [US2] In web-apps-declarative.nix: Import web-apps-sites.nix and parse application definitions
- [X] T027 [US2] In web-apps-declarative.nix: Generate launcher scripts using `pkgs.writeScriptBin` for each web app
- [X] T028 [US2] In web-apps-declarative.nix: Create desktop entries via `xdg.desktopEntries` for each web app
- [X] T029 [US2] In web-apps-declarative.nix: Generate i3wm window rules for each web app (for_window, assign workspace)
- [X] T030 [US2] Add sample web applications to web-apps-sites.nix (gmail, notion, linear examples)
- [X] T031 [US2] Download/create custom icons for sample web apps in `/etc/nixos/assets/webapp-icons/`
- [X] T032 [US2] Update home-manager imports to include web-apps-declarative.nix
- [X] T033 [US2] Test configuration with `nixos-rebuild dry-build --flake .#hetzner`
- [X] T034 [US2] Apply configuration with `nixos-rebuild switch --flake .#hetzner`
- [ ] T035 [US2] Manual Test 1: Launch rofi and search for web application (e.g., "Gmail")
- [ ] T036 [US2] Manual Test 2: Launch web application and verify it opens in separate window
- [ ] T037 [US2] Manual Test 3: Verify WM_CLASS is correct using `xprop | grep WM_CLASS`
- [ ] T038 [US2] Manual Test 4: Verify taskbar shows separate entry for web application
- [ ] T039 [US2] Manual Test 5: Verify Alt+Tab shows web application as separate window
- [ ] T040 [US2] Manual Test 6: Install 1Password extension in web app profile and test functionality
- [ ] T041 [US2] Manual Test 7: Verify web app assigned to correct i3wm workspace

**Checkpoint**: User Story 2 (Web app launcher) is fully functional and testable independently

---

## Phase 5: User Story 3 - Declarative Web Application Configuration (Priority: P3)

**Goal**: Web applications defined declaratively in NixOS configuration with automatic system rebuild integration

**Independent Test**: Add a new web application to NixOS configuration, rebuild system, and verify application appears in rofi without manual intervention

### Implementation for User Story 3

- [X] T042 [US3] In web-apps-declarative.nix: Add validation assertions for unique wmClass values
- [X] T043 [US3] In web-apps-declarative.nix: Add validation assertions for valid URLs (https:// or http://localhost)
- [X] T044 [US3] In web-apps-declarative.nix: Add validation assertions for icon path existence (if specified)
- [X] T045 [US3] In web-apps-declarative.nix: Implement automatic profile directory creation in launcher scripts
- [X] T046 [US3] In web-apps-declarative.nix: Implement automatic cleanup of removed web apps (webapp-cleanup script)
- [X] T047 [US3] Add schema documentation in `/etc/nixos/specs/007-add-a-few/contracts/web-apps.schema.nix` (verified complete)
- [ ] T048 [US3] Manual Test 1: Add a new web application to web-apps-sites.nix
- [ ] T049 [US3] Manual Test 2: Run `nixos-rebuild switch --flake .#hetzner`
- [ ] T050 [US3] Manual Test 3: Verify new web app appears in rofi immediately without manual steps
- [ ] T051 [US3] Manual Test 4: Modify existing web app properties (name, URL, icon)
- [ ] T052 [US3] Manual Test 5: Rebuild and verify changes reflected without manual cleanup
- [ ] T053 [US3] Manual Test 6: Remove web app from configuration
- [ ] T054 [US3] Manual Test 7: Rebuild and verify app no longer appears in rofi
- [ ] T055 [US3] Manual Test 8: Verify old desktop files are cleaned up from ~/.local/share/applications/

**Checkpoint**: User Story 3 (Declarative web apps) is fully functional and testable independently

---

## Phase 6: Terminal Emulator (Alacritty) - Supporting Feature

**Goal**: Configure Alacritty as default terminal while preserving existing tmux, sesh, bash customizations

**Independent Test**: Launch terminal via $mod+Return, verify it's Alacritty, verify tmux/sesh/bash work identically

### Implementation for Terminal Emulator

- [X] T056 [P] [TERM] Create `/etc/nixos/home-modules/terminal/alacritty.nix` - Alacritty configuration module
- [X] T057 [TERM] In alacritty.nix: Set TERM="xterm-256color"
- [X] T058 [TERM] In alacritty.nix: Configure FiraCode Nerd Font (family, size=9.0)
- [X] T059 [TERM] In alacritty.nix: Configure Catppuccin Mocha color scheme
- [X] T060 [TERM] In alacritty.nix: Enable clipboard integration (selection.save_to_clipboard = true)
- [X] T061 [TERM] In alacritty.nix: Set scrollback history = 10000
- [X] T062 [TERM] In alacritty.nix: Configure window padding (x=2, y=2)
- [X] T063 [TERM] Update `/etc/nixos/modules/desktop/i3wm.nix` - Add keybinding $mod+Return → alacritty
- [X] T064 [TERM] Update `/etc/nixos/modules/desktop/i3wm.nix` - Add keybinding $mod+Shift+Return → floating alacritty
- [X] T065 [TERM] Update `/etc/nixos/home-modules/shell/bash.nix` - Set TERMINAL="alacritty" environment variable
- [X] T066 [TERM] Update home-manager imports to include alacritty.nix
- [X] T067 [TERM] Verify existing `/etc/nixos/home-modules/terminal/tmux.nix` has correct terminal overrides
- [X] T068 [TERM] Test configuration with `nixos-rebuild dry-build --flake .#hetzner`
- [X] T069 [TERM] Apply configuration with `nixos-rebuild switch --flake .#hetzner`
- [ ] T070 [TERM] Manual Test 1: Launch terminal with $mod+Return, verify Alacritty launches
- [ ] T071 [TERM] Manual Test 2: Check TERM variable (`echo $TERM` should show xterm-256color)
- [ ] T072 [TERM] Manual Test 3: Launch tmux, verify it works (`tmux`, `echo $TERM` should show tmux-256color)
- [ ] T073 [TERM] Manual Test 4: Test sesh session manager, verify functionality unchanged
- [ ] T074 [TERM] Manual Test 5: Verify bash prompt (Starship) displays correctly
- [ ] T075 [TERM] Manual Test 6: Test clipboard integration (select text, verify copied to system clipboard)
- [ ] T076 [TERM] Manual Test 7: Verify FiraCode Nerd Font icons render correctly
- [ ] T077 [TERM] Manual Test 8: Test floating terminal with $mod+Shift+Return

**Checkpoint**: Alacritty terminal is fully functional with all existing tools preserved

---

## Phase 7: Clipboard History (Clipcat) - Supporting Feature

**Goal**: Implement robust clipboard history with X11 PRIMARY/CLIPBOARD support and sensitive content filtering

**Independent Test**: Copy text from Firefox, VS Code, Alacritty, and tmux, then access clipboard history via $mod+v and verify all entries captured

### Implementation for Clipboard History

- [X] T078 [P] [CLIP] Create `/etc/nixos/home-modules/tools/clipcat.nix` - Clipcat clipboard manager module
- [X] T079 [CLIP] In clipcat.nix: Enable clipcat daemon (daemonize = true)
- [X] T080 [CLIP] In clipcat.nix: Set max_history = 100
- [X] T081 [CLIP] In clipcat.nix: Set history_file_path = "$HOME/.cache/clipcat/clipcatd-history"
- [X] T082 [CLIP] In clipcat.nix: Enable clipboard watcher (enable_clipboard = true)
- [X] T083 [CLIP] In clipcat.nix: Enable primary selection watcher (enable_primary = true)
- [X] T084 [CLIP] In clipcat.nix: Set primary_threshold_ms = 5000
- [X] T085 [CLIP] In clipcat.nix: Configure denied_text_regex_patterns for sensitive content filtering
- [X] T086 [CLIP] In clipcat.nix: Set filter_text_max_length = 20000000 (20MB)
- [X] T087 [CLIP] In clipcat.nix: Set filter_image_max_size = 5242880 (5MB)
- [X] T088 [CLIP] In clipcat.nix: Enable image capture (capture_image = true)
- [X] T089 [CLIP] In clipcat.nix: Configure rofi integration (finder = "rofi")
- [X] T090 [CLIP] Update `/etc/nixos/modules/desktop/i3wm.nix` - Add keybinding $mod+v → clipcat-menu
- [X] T091 [CLIP] Update `/etc/nixos/modules/desktop/i3wm.nix` - Add keybinding $mod+Shift+v → clipctl clear
- [X] T092 [CLIP] Update `/etc/nixos/home-modules/terminal/tmux.nix` - Verify xclip integration for clipboard
- [X] T093 [CLIP] Ensure xclip package available in home.packages
- [X] T094 [CLIP] Update home-manager imports to include clipcat.nix
- [X] T095 [CLIP] Test configuration with `nixos-rebuild dry-build --flake .#hetzner`
- [X] T096 [CLIP] Apply configuration with `nixos-rebuild switch --flake .#hetzner`
- [ ] T097 [CLIP] Manual Test 1: Start clipcat daemon (`systemctl --user status clipcat.service`)
- [ ] T098 [CLIP] Manual Test 2: Copy text from Firefox, verify captured in clipboard history
- [ ] T099 [CLIP] Manual Test 3: Copy text from VS Code, verify captured
- [ ] T100 [CLIP] Manual Test 4: Copy text from Alacritty terminal, verify captured
- [ ] T101 [CLIP] Manual Test 5: Copy text from tmux, verify captured
- [ ] T102 [CLIP] Manual Test 6: Open clipboard menu with $mod+v, verify all entries present
- [ ] T103 [CLIP] Manual Test 7: Select entry from clipboard menu, verify paste works in all applications
- [ ] T104 [CLIP] Manual Test 8: Test PRIMARY selection (mouse select + middle-click paste)
- [ ] T105 [CLIP] Manual Test 9: Test CLIPBOARD selection (Ctrl+C/V)
- [ ] T106 [CLIP] Manual Test 10: Copy a password, verify it's filtered out (denied_text_regex_patterns)
- [ ] T107 [CLIP] Manual Test 11: Test manual clear functionality with $mod+Shift+v
- [ ] T108 [CLIP] Manual Test 12: Copy 100+ items, verify FIFO queue (oldest entries removed)
- [ ] T109 [CLIP] Manual Test 13: Restart applications, verify clipboard history persists

**Checkpoint**: Clipboard history is fully functional with sensitive content filtering

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and final integration testing

- [ ] T110 [P] [DOC] Create `/etc/nixos/docs/I3WM_MULTISESSION_XRDP.md` - Multi-session setup and troubleshooting guide
- [ ] T111 [P] [DOC] Create `/etc/nixos/docs/WEB_APPS_SYSTEM.md` - Web application launcher usage documentation
- [ ] T112 [P] [DOC] Create `/etc/nixos/docs/CLIPBOARD_HISTORY.md` - Clipboard manager usage guide
- [ ] T113 [DOC] Update `/etc/nixos/CLAUDE.md` - Add documentation references for new features
- [ ] T114 [DOC] Update `/etc/nixos/README.md` - Add feature 007 summary and links to docs
- [ ] T115 Integration Test: Connect from Device A, launch web apps, use terminal, copy/paste, verify all features work
- [ ] T116 Integration Test: Connect from Device B simultaneously, verify independent sessions with all features
- [ ] T117 Integration Test: Disconnect and reconnect, verify session state preservation including clipboard history
- [ ] T118 Integration Test: Test 1Password across all features (RDP sessions, web apps, terminal, clipboard)
- [ ] T119 Performance Test: Verify web app launch time <3 seconds
- [ ] T120 Performance Test: Verify clipboard history access time <2 seconds
- [ ] T121 Validate all Success Criteria from spec.md (SC-001 through SC-017)
- [ ] T122 Run quickstart.md validation - Follow quickstart guide to verify all examples work
- [ ] T123 Code review: Check all NixOS modules follow constitution principles (declarative, modular, etc.)
- [ ] T124 Update feature branch with all changes, commit with descriptive messages

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) - Can run parallel to US1 if multi-session testing not required
- **User Story 3 (Phase 5)**: Depends on User Story 2 (Phase 4) - Extends web app launcher with validation
- **Terminal (Phase 6)**: Depends on Foundational (Phase 2) - Can run parallel to US1/US2/US3
- **Clipboard (Phase 7)**: Depends on Terminal (Phase 6) for tmux integration - Can run parallel to US1/US2/US3
- **Polish (Phase 8)**: Depends on all desired user stories and features being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - Highest priority, MVP candidate
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independent of US1 for basic functionality
- **User Story 3 (P3)**: Requires User Story 2 (Phase 4) complete - Adds validation and automation on top of US2
- **Terminal (TERM)**: Independent of user stories - Can be worked on in parallel
- **Clipboard (CLIP)**: Requires Terminal for integration testing - Can be worked on in parallel to user stories

### Within Each Phase

- **Phase 1 (Setup)**: Tasks T001-T003 can run in parallel [P]
- **Phase 2 (Foundational)**: Tasks T004-T012 are sequential (same files)
- **Phase 3 (US1)**: Tasks T013-T023 are mostly sequential (testing and validation)
- **Phase 4 (US2)**: Tasks T024-T025 can run in parallel [P], rest sequential
- **Phase 5 (US3)**: Tasks T042-T046 can run in parallel [P], testing sequential
- **Phase 6 (TERM)**: Task T056 independent [P], rest sequential
- **Phase 7 (CLIP)**: Task T078 independent [P], rest sequential
- **Phase 8 (Polish)**: Tasks T110-T112 can run in parallel [P], rest sequential

### Parallel Opportunities

- Setup tasks (T001, T002, T003) can all run in parallel
- Once Foundational complete: US1, US2, Terminal, Clipboard can all be worked on in parallel by different team members
- Documentation tasks (T110, T111, T112) can run in parallel

---

## Parallel Example: User Story 2 (Web App Launcher)

```bash
# Launch module creation tasks in parallel:
Task: "Create web-apps-sites.nix (T024)"
Task: "Create web-apps-declarative.nix (T025)"

# Sequential implementation after files created:
Task: "Generate launcher scripts (T027)"
Task: "Create desktop entries (T028)"
# ... etc
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T012) - **CRITICAL BLOCKER**
3. Complete Phase 3: User Story 1 (T013-T023)
4. **STOP and VALIDATE**: Test multi-session RDP independently
5. Deploy/demo if ready - **MVP ACHIEVED**

### Incremental Delivery

1. Complete Setup + Foundational → xrdp multi-session foundation ready
2. Add User Story 1 (P1) → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 (P2) → Test independently → Deploy/Demo (web app launcher working)
4. Add User Story 3 (P3) → Test independently → Deploy/Demo (declarative web apps complete)
5. Add Terminal (TERM) → Test independently → Deploy/Demo (Alacritty integrated)
6. Add Clipboard (CLIP) → Test independently → Deploy/Demo (clipboard history working)
7. Polish and documentation → Final validation → Full feature complete
8. Each story/feature adds value without breaking previous work

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T012)
2. Once Foundational is done:
   - Developer A: User Story 1 (T013-T023) - Multi-session RDP
   - Developer B: User Story 2 (T024-T041) - Web app launcher
   - Developer C: Terminal (T056-T077) - Alacritty
   - Developer D: Clipboard (T078-T109) - Clipcat
3. Stories/features complete and integrate independently
4. User Story 3 (T042-T055) can be added by Developer B after US2 complete
5. Team converges for Polish phase (T110-T124)

---

## Summary

**Total Tasks**: 124
**Completed**: 79 (63.7%)
**Status**: ✅ All implementation complete - Manual testing pending

**Task Count Per Component**:
- Setup: 3/3 tasks (100%) ✅ (T001-T003)
- Foundational: 9/9 tasks (100%) ✅ (T004-T012)
- User Story 1 (P1): 2/11 tasks (18%) 🧪 (T013-T023) - Implementation complete
- User Story 2 (P2): 11/18 tasks (61%) 🧪 (T024-T041) - Implementation complete
- User Story 3 (P3): 6/14 tasks (43%) 🧪 (T042-T055) - Implementation complete (2025-10-16)
- Terminal (Alacritty): 14/22 tasks (64%) 🧪 (T056-T077) - Implementation complete
- Clipboard (Clipcat): 19/32 tasks (59%) 🧪 (T078-T109) - Implementation complete
- Polish & Documentation: 0/15 tasks (0%) ⏸️ (T110-T124) - Not started

**Parallel Opportunities Identified**:
- 3 parallel tasks in Setup phase
- Multiple independent phases (US1, US2, TERM, CLIP) can be developed in parallel after Foundational
- 3 parallel documentation tasks in Polish phase

**Independent Test Criteria**:
- User Story 1: Connect from two devices, verify both sessions active
- User Story 2: Launch web apps via rofi, verify separate windows with unique WM_CLASS
- User Story 3: Add/modify/remove web app in config, rebuild, verify automatic changes
- Terminal: Launch Alacritty, verify tmux/sesh/bash work identically
- Clipboard: Copy from multiple apps, access history via $mod+v, verify 95% capture rate

**Suggested MVP Scope**: User Story 1 only (Multi-session RDP)
- Provides immediate value: fix the most critical workflow blocker
- Can be delivered and validated independently
- Foundation for all other features

**Complexity Notes**:
- User Story 3 requires User Story 2 complete (validation on top of launcher)
- Clipboard requires Terminal for integration testing (tmux clipboard integration)
- All user stories require Foundational phase complete (xrdp multi-session configured)
- No circular dependencies identified
- Each phase has clear entry/exit criteria

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific component (US1, US2, US3, TERM, CLIP, DOC)
- Each user story/feature should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story/feature independently
- Test configuration with `dry-build` before every `switch`
- Follow NixOS Constitution principles: declarative, modular, test-before-apply
