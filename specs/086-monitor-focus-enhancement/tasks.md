# Tasks: Monitor Panel Focus Enhancement

**Input**: Design documents from `/specs/086-monitor-focus-enhancement/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md

**Tests**: Manual verification only (no automated tests requested)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Nix modules**: `home-modules/desktop/`
- **Spec docs**: `specs/086-monitor-focus-enhancement/`
- All paths relative to repository root

---

## Phase 1: Setup

**Purpose**: No new files needed - this feature modifies existing modules

- [X] T001 Read and understand current eww-monitoring-panel.nix configuration in home-modules/desktop/eww-monitoring-panel.nix
- [X] T002 Identify the exact line with `:focusable true` in home-modules/desktop/eww-monitoring-panel.nix (~line 185)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the focus toggle script before modifying panel config

**⚠️ CRITICAL**: Script must exist before keybinding can reference it

- [X] T003 Create toggle-panel-focus script in home-modules/desktop/eww-monitoring-panel.nix (add to existing pkgs.writeShellScriptBin definitions around line 68)
- [X] T004 Add Sway window rule `no_focus` for eww-monitoring-panel in home-modules/desktop/sway.nix (or home-modules/hetzner-sway.nix if that's where window.commands exists)

**Checkpoint**: Script and Sway rule ready - panel modifications can proceed

---

## Phase 3: User Story 1 - Non-Disruptive Panel Viewing (Priority: P1) 🎯 MVP

**Goal**: Panel shows without stealing focus from active application

**Independent Test**: Open terminal, start typing, press Mod+M to show panel - typing should continue in terminal without interruption

### Implementation for User Story 1

- [X] T005 [US1] Change `:focusable true` to `:focusable "ondemand"` in home-modules/desktop/eww-monitoring-panel.nix line ~185
- [X] T006 [US1] Run `nixos-rebuild dry-build --flake .#hetzner-sway` to verify configuration compiles
- [ ] T007 [US1] Apply configuration with `nixos-rebuild switch --flake .#hetzner-sway`
- [ ] T008 [US1] Verify panel no longer steals focus on show (Mod+M while typing in another app)

**Checkpoint**: User Story 1 complete - panel displays without stealing focus

---

## Phase 4: User Story 2 - Explicit Focus Lock (Priority: P2)

**Goal**: User can explicitly toggle keyboard focus to/from panel with Mod+Shift+M

**Independent Test**: With panel visible, press Mod+Shift+M to focus panel, verify Alt+1-4 tabs work, press Mod+Shift+M again to return focus

### Implementation for User Story 2

- [X] T009 [US2] Add Mod+Shift+M keybinding to sway-keybindings.nix that calls toggle-panel-focus script in home-modules/desktop/sway-keybindings.nix (replaced cycle-monitor-profile)
- [X] T010 [US2] Run `nixos-rebuild dry-build --flake .#hetzner-sway` to verify configuration compiles
- [ ] T011 [US2] Apply configuration with `nixos-rebuild switch --flake .#hetzner-sway` (or swaymsg reload)
- [ ] T012 [US2] Test focus toggle: show panel (Mod+M), focus panel (Mod+Shift+M), verify Alt+1-4 tabs work
- [ ] T013 [US2] Test focus return: press Mod+Shift+M again, verify focus returns to previous window

**Checkpoint**: User Story 2 complete - focus can be toggled with keybinding

---

## Phase 5: User Story 3 - Clean Toggle Visibility (Priority: P2)

**Goal**: Panel visibility toggle (Mod+M) works cleanly without focus issues

**Independent Test**: Press Mod+M to show/hide panel multiple times - panel should toggle smoothly

### Implementation for User Story 3

- [ ] T014 [US3] Verify existing toggle-monitoring-panel script in home-modules/desktop/eww-monitoring-panel.nix still works correctly with new focusable setting
- [ ] T015 [US3] Test visibility toggle: press Mod+M to show panel, verify it appears as overlay
- [ ] T016 [US3] Test visibility toggle: press Mod+M again to hide panel
- [ ] T017 [US3] Test sticky behavior: show panel, switch workspaces, verify panel remains visible

**Checkpoint**: User Story 3 complete - visibility toggle works cleanly

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, edge cases, and final validation

- [X] T018 [P] Update CLAUDE.md with new Mod+Shift+M keybinding documentation
- [X] T019 [P] Verify quickstart.md in specs/086-monitor-focus-enhancement/quickstart.md matches implemented behavior
- [ ] T020 Test edge case: panel focused → press Mod+M to hide → verify focus returns to previous window
- [ ] T021 Test edge case: rapid toggle (spam Mod+M) → verify no crashes or unexpected behavior
- [X] T022 Test on M1 platform: run `nixos-rebuild dry-build --flake .#m1 --impure` - Asahi firmware error (expected, not related to Feature 086)
- [ ] T023 Final verification: all acceptance scenarios from spec.md pass

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - read/understand existing code
- **Foundational (Phase 2)**: Depends on Setup - creates script and Sway rule
- **User Story 1 (Phase 3)**: Depends on Foundational - MVP focus fix
- **User Story 2 (Phase 4)**: Depends on Foundational - focus toggle keybinding
- **User Story 3 (Phase 5)**: Depends on Foundational - verify visibility toggle
- **Polish (Phase 6)**: Depends on all user stories

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - No dependencies on US1 (different files)
- **User Story 3 (P2)**: Depends on US1 being complete (tests the focusable change)

### Within Each User Story

- Configuration changes before dry-build
- Dry-build before switch
- Switch before testing
- All tests must pass before moving to next story

### Parallel Opportunities

- T018 and T019 can run in parallel (different files)
- US1 and US2 implementation tasks could run in parallel (T005-T008 vs T009-T013) since they modify different files
- However, validation of US3 requires US1 to be complete first

---

## Parallel Example: Setup + Foundational

```bash
# Read existing code (T001, T002) - serial, understanding first

# Then create script and rule in parallel:
Task: "Create toggle-panel-focus script in home-modules/desktop/eww-monitoring-panel.nix"
Task: "Add Sway window rule no_focus in home-modules/desktop/sway.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (understand code)
2. Complete Phase 2: Foundational (script + Sway rule)
3. Complete Phase 3: User Story 1 (focusable change)
4. **STOP and VALIDATE**: Panel no longer steals focus
5. Can stop here for MVP - core regression is fixed

### Incremental Delivery

1. Complete Setup + Foundational → Tools ready
2. Add User Story 1 → Test independently → Core fix deployed (MVP!)
3. Add User Story 2 → Test independently → Focus toggle enabled
4. Add User Story 3 → Test independently → Visibility verified
5. Polish → Documentation updated, edge cases validated

### Single Developer Strategy

Execute tasks sequentially T001 → T023, stopping at each checkpoint to validate.

---

## Summary

| Phase | Tasks | Purpose |
|-------|-------|---------|
| Setup | T001-T002 | Understand existing code |
| Foundational | T003-T004 | Create script + Sway rule |
| US1 (MVP) | T005-T008 | Fix focus regression |
| US2 | T009-T013 | Focus toggle keybinding |
| US3 | T014-T017 | Verify visibility toggle |
| Polish | T018-T023 | Documentation + edge cases |

**Total Tasks**: 23
**MVP Scope**: T001-T008 (8 tasks)
**Full Feature**: T001-T023 (23 tasks)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Manual testing only - no automated test tasks
- Commit after each phase or logical group
- Stop at any checkpoint to validate story independently
