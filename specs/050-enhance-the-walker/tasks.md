---
description: "Task list for Enhanced Walker/Elephant Launcher Functionality"
---

# Tasks: Enhanced Walker/Elephant Launcher Functionality

**Input**: Design documents from `/specs/050-enhance-the-walker/`
**Prerequisites**: plan.md, spec.md, research.md, quickstart.md
**Feature**: Configuration-only enhancement to enable additional Walker/Elephant providers

**Tests**: No automated tests required - manual acceptance testing per spec.md scenarios

**Organization**: Tasks are grouped by user story (priority P1 → P3) to enable incremental delivery

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different configuration sections, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- Primary configuration: `home-modules/desktop/walker.nix`
- Generated configs: `~/.config/walker/config.toml`, `~/.config/elephant/*.toml`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare for configuration changes

- [X] T001 Read existing walker.nix configuration structure to understand current provider setup (home-modules/desktop/walker.nix)
- [X] T002 [P] Review Walker documentation for provider configuration syntax and options
- [X] T003 [P] Review Elephant documentation for TOML configuration file formats

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core configuration structure that ALL user stories depend on

**⚠️ CRITICAL**: No user story implementation can begin until this phase is complete

- [X] T004 Update `[modules]` section in walker.nix to enable new providers: todo, windows, bookmarks, customcommands (home-modules/desktop/walker.nix:337)
- [X] T005 Verify isWaylandMode detection is working correctly for conditional clipboard provider (home-modules/desktop/walker.nix:7)

**Checkpoint**: Base provider modules enabled - user story configurations can now proceed

---

## Phase 3: User Story 1 - Quick Task Management (Priority: P1) 🎯 MVP

**Goal**: Enable todo list provider with `!` prefix for quick task capture and management without leaving workflow

**Independent Test**: Type `!buy groceries` in Walker → verify task created → type `!` → verify task list shows → mark task complete → verify task removed from active list

### Implementation for User Story 1

- [X] T006 [US1] Add todo provider prefix configuration to providers.prefixes section (home-modules/desktop/walker.nix:390-397)
- [X] T007 [US1] Create elephant/todo.toml configuration file via xdg.configFile with empty initial state (home-modules/desktop/walker.nix after line 468)
- [ ] T008 [US1] Test todo list creation with `!buy groceries` command
- [ ] T009 [US1] Test todo list viewing with `!` prefix (no search term)
- [ ] T010 [US1] Test todo task completion workflow
- [ ] T011 [US1] Test todo list persistence across Walker/Elephant restarts

**Checkpoint**: Todo list provider functional - users can create, view, and complete tasks via `!` prefix

---

## Phase 4: User Story 2 - Window Navigation (Priority: P1)

**Goal**: Enable window switcher provider for fuzzy window search and focus without Alt+Tab

**Independent Test**: Open multiple windows (Firefox, VS Code, terminal) → type partial window title in Walker → verify window list appears → select window → verify focus switches correctly

### Implementation for User Story 2

- [X] T012 [P] [US2] Verify windows provider is enabled in modules section (already done in T004, validate only)
- [ ] T013 [US2] Test window switcher with multiple open windows on same workspace
- [ ] T014 [US2] Test window switcher with windows on different workspaces (verify workspace switching)
- [ ] T015 [US2] Test window switcher with minimized windows
- [ ] T016 [US2] Test fuzzy matching with partial window titles

**Checkpoint**: Window switcher operational - users can navigate between windows via fuzzy search

---

## Phase 5: User Story 3 - Saved Bookmarks Access (Priority: P2)

**Goal**: Enable bookmarks provider for quick URL access without browser navigation

**Independent Test**: Search for "github" in Walker → verify GitHub bookmark appears → press Return → verify browser opens to GitHub.com

### Implementation for User Story 3

- [X] T017 [P] [US3] Create elephant/bookmarks.toml configuration file with initial curated bookmark set (home-modules/desktop/walker.nix after todo.toml config)
- [X] T018 [US3] Add bookmarks for common development resources (NixOS Manual, GitHub, Google AI Studio, Stack Overflow)
- [X] T019 [US3] Add bookmarks with descriptions and tags for better searchability
- [ ] T020 [US3] Test bookmark search with fuzzy matching
- [ ] T021 [US3] Test bookmark opening in default browser
- [ ] T022 [US3] Test bookmark search by tags and descriptions

**Checkpoint**: Bookmarks provider functional - users can quickly access saved URLs from Walker

---

## Phase 6: User Story 4 - Custom Command Shortcuts (Priority: P2)

**Goal**: Enable custom commands provider for user-defined system operation shortcuts

**Independent Test**: Type "reload sway" in Walker → verify command appears → press Return → verify `swaymsg reload` executes successfully

### Implementation for User Story 4

- [X] T023 [P] [US4] Create elephant/commands.toml configuration file with useful system commands (home-modules/desktop/walker.nix after bookmarks.toml config)
- [X] T024 [US4] Add Sway/window manager commands (reload config, restart waybar, lock screen)
- [X] T025 [US4] Add system management commands (suspend, reboot, rebuild nixos)
- [X] T026 [US4] Add project-specific commands (git operations, build commands)
- [ ] T027 [US4] Test custom command execution from Walker
- [ ] T028 [US4] Test custom command search with fuzzy matching
- [ ] T029 [US4] Verify command output handling and Walker close behavior

**Checkpoint**: Custom commands provider operational - users can execute system shortcuts from Walker

---

## Phase 7: User Story 5 - Enhanced Web Search (Priority: P3)

**Goal**: Add domain-specific search engines to existing web search provider (@google, @github, @nix, @arch, @so, @rust)

**Independent Test**: Type `@nix hyprland` in Walker → verify NixOS packages search opens → type `@arch bluetooth` → verify Arch Wiki search opens

### Implementation for User Story 5

- [X] T030 [P] [US5] Add Stack Overflow search engine to elephant/websearch.toml (home-modules/desktop/walker.nix:443-468)
- [X] T031 [P] [US5] Add Arch Wiki search engine to websearch.toml
- [X] T032 [P] [US5] Add Nix Packages search engine to websearch.toml
- [X] T033 [P] [US5] Add Rust Docs search engine to websearch.toml
- [ ] T034 [US5] Test each new search engine with sample queries
- [ ] T035 [US5] Test URL encoding for queries with special characters (spaces, &, #)
- [ ] T036 [US5] Verify default search engine behavior (Google)

**Checkpoint**: Enhanced web search operational - users can search domain-specific engines from Walker

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, cleanup, and final validation

- [X] T037 [P] Update CLAUDE.md Walker section with provider reference table showing all enabled providers and prefixes
- [X] T038 [P] Add troubleshooting section to quickstart.md for common provider issues
- [X] T039 [P] Add customization examples to quickstart.md (adding bookmarks, commands, search engines)
- [ ] T040 Test Walker startup time with all providers enabled (target: <200ms increase per SC-007)
- [ ] T041 Run full acceptance test suite from spec.md (all 5 user stories)
- [ ] T042 Validate quickstart.md workflows match actual implementation
- [ ] T043 Create git commit with descriptive message about all enabled providers

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 (Todo List) can start after Foundational - No dependencies
  - US2 (Windows) can start after Foundational - No dependencies
  - US3 (Bookmarks) can start after Foundational - No dependencies
  - US4 (Commands) can start after Foundational - No dependencies
  - US5 (Web Search) can start after Foundational - Modifies existing config, no dependencies
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (Todo List - P1)**: Independent - can complete standalone
- **US2 (Windows - P1)**: Independent - can complete standalone
- **US3 (Bookmarks - P2)**: Independent - can complete standalone
- **US4 (Commands - P2)**: Independent - can complete standalone
- **US5 (Web Search - P3)**: Independent - enhances existing provider

### Within Each User Story

- Configuration changes before testing
- Manual testing after each configuration change
- Validation testing at end of each story
- Story checkpoint before moving to next priority

### Parallel Opportunities

- Phase 1 setup tasks (T002, T003) can run in parallel - different documentation sources
- Phase 3-7 user stories can ALL run in parallel after Foundational phase completes (if team capacity allows)
- Within US5: Adding search engines (T030-T033) can run in parallel - different TOML entries
- Phase 8 documentation tasks (T037-T039) can run in parallel - different files

---

## Parallel Example: User Story 5 (Enhanced Web Search)

```bash
# All search engine additions can happen simultaneously:
Task T030: Add Stack Overflow search engine to websearch.toml
Task T031: Add Arch Wiki search engine to websearch.toml
Task T032: Add Nix Packages search engine to websearch.toml
Task T033: Add Rust Docs search engine to websearch.toml

# These tasks modify different sections of the same TOML array
# Can be done in parallel by adding all [[engines]] entries at once
```

---

## Parallel Example: Multiple User Stories

```bash
# After Foundational phase completes, if multiple team members available:
Developer A: Phase 3 (US1 - Todo List) - T006 → T011
Developer B: Phase 4 (US2 - Windows) - T012 → T016
Developer C: Phase 5 (US3 - Bookmarks) - T017 → T022
Developer D: Phase 6 (US4 - Commands) - T023 → T029
Developer E: Phase 7 (US5 - Web Search) - T030 → T036

# All stories are independent and can proceed in parallel
# Single developer: Follow priority order (US1 → US2 → US3 → US4 → US5)
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T005) - CRITICAL checkpoint
3. Complete Phase 3: User Story 1 - Todo List (T006-T011)
4. Complete Phase 4: User Story 2 - Windows (T012-T016)
5. **STOP and VALIDATE**: Test both US1 and US2 independently
6. Rebuild NixOS: `home-manager switch --flake .#hetzner-sway`
7. Validate with real usage for 1-2 days before continuing

**MVP Delivers**: Task management (`!` prefix) + Window navigation (fuzzy search)

### Incremental Delivery

1. MVP (US1 + US2) → Rebuild → Validate → Commit
2. Add US3 (Bookmarks) → Rebuild → Validate → Commit
3. Add US4 (Commands) → Rebuild → Validate → Commit
4. Add US5 (Enhanced Search) → Rebuild → Validate → Commit
5. Polish & Documentation → Rebuild → Validate → Final commit

Each story adds value without breaking previous functionality.

### Single-Session Strategy

For experienced developers who want to complete all at once:

1. Phase 1: Setup (quick review - 5 minutes)
2. Phase 2: Foundational (enable modules - 5 minutes)
3. Phase 3-7: All user stories (configure all providers - 30 minutes)
   - Add all configuration sections to walker.nix in one edit
   - Create all TOML config files via xdg.configFile
4. Rebuild: `home-manager switch --flake .#hetzner-sway`
5. Phase 8: Test all providers systematically (20 minutes)
6. Phase 8: Documentation updates (15 minutes)

**Total time**: ~75 minutes for complete implementation

---

## Notes

- **[P] tasks** = different configuration sections or files, no dependencies between them
- **[Story] label** maps task to specific user story for traceability and incremental delivery
- **Configuration-only feature**: No source code, data models, or APIs - only TOML/Nix config changes
- **Manual testing required**: Each user story has acceptance scenarios in spec.md - validate after implementation
- **Rebuild required**: Run `home-manager switch --flake .#hetzner-sway` after configuration changes
- **Restart services**: May need `systemctl --user restart elephant` for changes to take effect
- **Independent stories**: Each user story delivers standalone value and can be validated independently
- **No automated tests**: This is a configuration feature - testing is manual per acceptance scenarios
- **Clipboard history note**: Already enabled for Wayland mode, conditionally disabled for X11 (no action needed)
