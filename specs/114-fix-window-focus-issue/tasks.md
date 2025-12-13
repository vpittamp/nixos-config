# Tasks: Fix Window Focus/Click Issue

**Input**: Design documents from `/specs/114-fix-window-focus-issue/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓, quickstart.md ✓

**Root Cause**: Eww monitoring panel's `:focusable "ondemand"` setting causes the 460px-wide panel to intercept all pointer input in its region, blocking clicks on tiled windows beneath it.

**Tests**: Manual verification per quickstart.md (automated tests optional per spec).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Primary file**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Keybinding file**: `home-modules/desktop/sway.nix` or `sway-keybindings.nix`
- **Specs**: `specs/114-fix-window-focus-issue/`

---

## Phase 1: Setup

**Purpose**: Verify current state and prepare for changes

- [x] T001 Verify root cause by stopping panel: `systemctl --user stop eww-monitoring-panel` and testing clicks
- [x] T002 Create backup of current eww-monitoring-panel.nix: `cp home-modules/desktop/eww-monitoring-panel.nix home-modules/desktop/eww-monitoring-panel.nix.backup`
- [x] T003 Read current toggle-monitoring-panel script logic in home-modules/desktop/eww-monitoring-panel.nix

---

## Phase 2: Foundational (No Blocking Prerequisites)

**Purpose**: This fix is self-contained - no blocking infrastructure changes needed

**⚠️ NOTE**: All required infrastructure (Eww, Sway, systemd user services) already exists. Proceed directly to user stories.

**Checkpoint**: No foundational changes needed - proceed to User Story 1

---

## Phase 3: User Story 1 - Diagnose Root Cause (Priority: P1) 🎯 MVP

**Goal**: Confirm the Eww panel's `:focusable "ondemand"` is causing click interception and document the fix approach

**Independent Test**: Run diagnostic commands to verify panel state and confirm stopping panel restores clicks

### Implementation for User Story 1

- [x] T004 [US1] Query current panel focusable state: `eww --config ~/.config/eww-monitoring-panel get panel_visible` and inspect eww.yuck for `:focusable` value
- [x] T005 [US1] Document current `:focusable "ondemand"` configuration in home-modules/desktop/eww-monitoring-panel.nix (locate exact lines)
- [x] T006 [US1] Test click-through by temporarily closing panel: `eww --config ~/.config/eww-monitoring-panel close monitoring-panel` and verify clicks work on tiled windows
- [x] T007 [US1] Update research.md with confirmation of root cause in specs/114-fix-window-focus-issue/research.md

**Checkpoint**: Root cause confirmed - panel's `:focusable "ondemand"` intercepts clicks. Ready to implement fix.

---

## Phase 4: User Story 2 - Fix Click/Input Issue (Priority: P2)

**Goal**: Implement dynamic focusable mode so panel defaults to click-through but becomes interactive when explicitly requested

**Independent Test**: After rebuild, clicks pass through panel in tiled windows by default; Mod+M enables panel interaction

### Implementation for User Story 2

- [x] T008 [US2] Add `panel_focus_mode` eww variable (default: false) in home-modules/desktop/eww-monitoring-panel.nix defvar section
- [x] T009 [US2] Change `:focusable "ondemand"` to `:focusable false` (static click-through) in defwindow monitoring-panel section
- [x] T010 [US2] Update toggle-monitoring-panel script to use actual open/close instead of CSS visibility
- [x] T011 [US2] Add debounce to prevent rapid toggling crashes
- [x] T012 [US2] Update exit-monitor-mode and toggle-panel-focus scripts for panel_focus_mode
- [x] T013 [US2] Run dry-build to verify configuration compiles: `sudo nixos-rebuild dry-build --flake .#thinkpad`
- [x] T014 [US2] Apply configuration: `sudo nixos-rebuild switch --flake .#thinkpad`
- [x] T015 [US2] Restart panel service: `systemctl --user restart eww-monitoring-panel`
- [x] T016 [US2] Test click-through: verify clicks on tiled windows work when panel is closed
- [x] T017 [US2] Test interactive mode: press Mod+M, verify panel opens and is interactive
- [x] T018 [US2] Test return to click-through: press Mod+M again, verify panel closes and clicks work

**Checkpoint**: Click issue fixed on ThinkPad. Panel defaults to click-through, Mod+M enables interaction.

---

## Phase 5: User Story 3 - Prevent Future Regressions (Priority: P3)

**Goal**: Create diagnostic tooling and documentation for this class of issue

**Independent Test**: Diagnostic command provides actionable panel state information

### Implementation for User Story 3

- [ ] T019 [P] [US3] Create verification script to check panel_focus_mode state: add shell alias or script in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T020 [P] [US3] Update quickstart.md with permanent fix verification steps in specs/114-fix-window-focus-issue/quickstart.md
- [ ] T021 [US3] Test on M1 configuration: `sudo nixos-rebuild switch --flake .#m1 --impure` (if accessible)
- [ ] T022 [US3] Test on Hetzner-Sway configuration: `sudo nixos-rebuild switch --flake .#hetzner-sway` (if accessible)
- [ ] T023 [US3] Document fix in research.md with final confirmation in specs/114-fix-window-focus-issue/research.md

**Checkpoint**: Fix documented and tested across configurations. Diagnostic tooling available.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, documentation, and optional automated tests

- [ ] T024 [P] Remove backup file if fix is successful: `rm home-modules/desktop/eww-monitoring-panel.nix.backup`
- [ ] T025 [P] Update CLAUDE.md if any new commands/keybindings added
- [ ] T026 Create git commit with fix: conventional commit format
- [ ] T027 (Optional) Add sway-test framework test for click-through behavior in home-modules/tools/sway-test/tests/sway-tests/114-window-focus/

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: N/A - no blocking prerequisites for this fix
- **User Story 1 (Phase 3)**: Depends on Setup (T001-T003) - Diagnosis
- **User Story 2 (Phase 4)**: Depends on US1 confirmation - Core fix
- **User Story 3 (Phase 5)**: Depends on US2 completion - Documentation and multi-config testing
- **Polish (Phase 6)**: Depends on US2 or US3 completion

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately - diagnosis only, no code changes
- **User Story 2 (P2)**: Depends on US1 confirmation - implements the fix
- **User Story 3 (P3)**: Depends on US2 - tests on other configurations and documents

### Within User Story 2 (Critical Path)

```
T008 (add variable)
  → T009 (change focusable)
    → T010-T011 (update toggle script)
      → T012 (optional escape handler)
        → T013 (dry-build)
          → T014 (switch)
            → T015 (restart)
              → T016-T018 (verify)
```

### Parallel Opportunities

- **Phase 1**: T002, T003 can run in parallel after T001 confirms the issue
- **Phase 5**: T019, T020 can run in parallel
- **Phase 6**: T024, T025 can run in parallel

---

## Parallel Example: User Story 2 Setup

```bash
# After T008 and T009 are complete, these can potentially be combined:
Task: "Update toggle script to set panel_focus_mode=true when showing"
Task: "Update toggle script to set panel_focus_mode=false when hiding"

# These are sequential (build depends on code changes):
Task: "Run dry-build" → Task: "Apply configuration" → Task: "Restart panel"
```

---

## Implementation Strategy

### MVP First (User Story 2 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Confirm diagnosis in Phase 3 (T004-T007)
3. Complete Phase 4: User Story 2 (T008-T018)
4. **STOP and VALIDATE**: Test click-through on ThinkPad
5. If working, proceed to Phase 5 or commit fix

### Quick Fix Path (Minimal Tasks)

If diagnosis is already confirmed:
1. T008-T009: Add variable and change focusable
2. T010-T011: Update toggle script
3. T013-T015: Build and apply
4. T016-T018: Verify fix

### Incremental Delivery

1. US1: Confirm root cause → Document findings
2. US2: Implement fix → Test on ThinkPad → Commit
3. US3: Test other configs → Document → Optional automation

---

## Notes

- **Files modified**: Only `home-modules/desktop/eww-monitoring-panel.nix` for core fix
- **No new files created**: Fix is entirely within existing module
- **Rollback available**: `sudo nixos-rebuild switch --rollback` if issues
- **Test before apply**: Always run `dry-build` before `switch`
- Commit after successful verification on ThinkPad
