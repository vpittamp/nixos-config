# Tasks: Improve Notification Progress Indicators

**Input**: Design documents from `/specs/117-improve-notification-progress-indicators/`
**Prerequisites**: plan.md (tech stack, structure), spec.md (user stories P1-P3), research.md (tmux detection decisions), data-model.md (entities), contracts/badge-state.md (badge file schema v2.0)

**Tests**: Manual testing via sway-test framework and quickstart.md scenarios. No automated test tasks unless explicitly requested.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US6)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- **New Nix modules**: `home-modules/services/`
- **New scripts**: `scripts/tmux-ai-monitor/`
- **Modified Nix**: `home-modules/ai-assistants/`
- **Existing daemon**: `home-modules/desktop/i3-project-event-daemon/`
- **Existing EWW**: `home-modules/tools/monitoring-panel/`
- **Tests**: `tests/117-notification-indicators/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create directory structure and placeholder files for new tmux-ai-monitor service

- [x] T001 Create directory structure: `scripts/tmux-ai-monitor/`
- [x] T002 Create directory structure: `tests/117-notification-indicators/`
- [x] T003 [P] Create placeholder `scripts/tmux-ai-monitor/monitor.sh` with shebang and usage comment
- [x] T004 [P] Create placeholder `scripts/tmux-ai-monitor/notify.sh` with shebang and usage comment

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Create `home-modules/services/tmux-ai-monitor.nix` with service skeleton (empty ExecStart, After=graphical-session.target)
- [x] T006 Add tmux-ai-monitor to home-manager imports in `home-modules/default.nix` or appropriate import point
- [x] T007 Implement window ID resolution helper in `scripts/tmux-ai-monitor/monitor.sh` (tmux client PID → process tree → Ghostty PID → Sway window ID) per research.md R7
- [x] T008 Implement badge directory initialization in `scripts/tmux-ai-monitor/monitor.sh` (create `$XDG_RUNTIME_DIR/i3pm-badges/` if not exists)
- [x] T009 Run `sudo nixos-rebuild dry-build --flake .#hetzner-sway` to verify module imports work

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Universal AI Assistant Progress Detection (Priority: P1)

**Goal**: Detect when claude or codex process becomes foreground in tmux pane, show spinner in EWW panel within 500ms

**Independent Test**: Run `claude` in tmux pane, verify spinner appears on window entry in monitoring panel within 500ms. Exit claude, verify bell badge appears.

### Implementation for User Story 1

- [x] T010 [US1] Implement tmux pane enumeration in `scripts/tmux-ai-monitor/monitor.sh` using `tmux list-panes -a -F '#{pane_pid}|#{pane_id}|#{pane_current_command}'` per research.md R6
- [x] T011 [US1] Implement AI process detection function in `scripts/tmux-ai-monitor/monitor.sh` (match process names: claude, codex)
- [x] T012 [US1] Implement window state tracking in `scripts/tmux-ai-monitor/monitor.sh` using associative array for active panes per window per research.md R8
- [x] T013 [US1] Implement badge file write for "working" state in `scripts/tmux-ai-monitor/monitor.sh` per contracts/badge-state.md v2.0 schema
- [x] T014 [US1] Implement badge file write for "stopped" state in `scripts/tmux-ai-monitor/monitor.sh` when ALL AI processes in window exit
- [x] T015 [US1] Implement main polling loop in `scripts/tmux-ai-monitor/monitor.sh` with configurable interval (default 300ms) per research.md R10
- [x] T016 [US1] Wire monitor.sh into systemd service in `home-modules/services/tmux-ai-monitor.nix` with ExecStart and Environment
- [x] T017 [US1] Add configurable options to `home-modules/services/tmux-ai-monitor.nix`: enable, pollInterval, processes list per quickstart.md configuration section
- [x] T018 [US1] Run `sudo nixos-rebuild dry-build --flake .#hetzner-sway` to verify compilation
- [x] T019 [US1] Manual test: Start tmux-ai-monitor service, run claude in tmux, verify spinner appears via `monitoring-data-backend --mode windows | jq '.windows[].badge'`

**Checkpoint**: User Story 1 complete - AI process detection working for both Claude Code and Codex

---

## Phase 4: User Story 2 - Focus-Aware Notification Dismissal (Priority: P1)

**Goal**: Badge clears automatically when user focuses the terminal window (with 1s minimum age)

**Independent Test**: Let AI assistant complete (bell badge visible), focus terminal window, verify badge disappears within 500ms

### Implementation for User Story 2

- [x] T020 [US2] Verify existing focus-aware dismissal logic in `home-modules/desktop/i3-project-event-daemon/handlers.py` handles badge files correctly
- [x] T021 [US2] Verify BADGE_MIN_AGE_FOR_DISMISS constant is set to 1.0 seconds in handlers.py per quickstart.md configuration section
- [x] T022 [US2] Manual test: Create stopped badge via quickstart.md test script, verify focus dismisses it after 1s but not before

**Checkpoint**: User Story 2 complete - focus-aware dismissal working

---

## Phase 5: User Story 3 - Desktop Notification with Direct Navigation (Priority: P2)

**Goal**: Send desktop notification when AI assistant completes, with "Return to Window" action that focuses correct terminal

**Independent Test**: Run AI assistant, switch workspaces, wait for completion, click notification action, verify correct terminal focused

### Implementation for User Story 3

- [x] T023 [US3] Implement notification sender in `scripts/tmux-ai-monitor/notify.sh` using notify-send with -w flag and --action per research.md R11
- [x] T024 [US3] Implement project name detection in `scripts/tmux-ai-monitor/notify.sh` (read from i3pm project context if available)
- [x] T025 [US3] Add call to notify.sh from monitor.sh when badge transitions from working to stopped state
- [x] T026 [US3] Implement notification action handler in `scripts/tmux-ai-monitor/notify.sh` to focus window via swaymsg and clear badge file
- [x] T027 [US3] Manual test: Run AI assistant, wait for completion, click "Return to Window" action, verify window focused and badge cleared

**Checkpoint**: User Story 3 complete - desktop notifications with navigation working

---

## Phase 6: User Story 4 - Concise Notification Content (Priority: P2)

**Goal**: Notification shows "[Assistant] Ready" title and project name only, no verbose details

**Independent Test**: Receive notification, verify 2 lines or less with assistant type and project clearly shown

### Implementation for User Story 4

- [x] T028 [US4] Implement assistant name mapping in `scripts/tmux-ai-monitor/notify.sh` (claude → "Claude Code Ready", codex → "Codex Ready") per spec.md Supported AI Assistants table
- [x] T029 [US4] Ensure notification body is single line: project name or "Awaiting input" if no project per research.md R4
- [x] T030 [US4] Manual test: Trigger notifications from both claude and codex, verify correct titles and concise content

**Checkpoint**: User Story 4 complete - notifications are concise and clear

---

## Phase 7: User Story 5 - Stale Badge Cleanup (Priority: P3)

**Goal**: Orphaned badges for closed windows removed automatically within 30 seconds

**Independent Test**: Close terminal window with active badge, verify badge file removed within 30 seconds

### Implementation for User Story 5

- [x] T031 [US5] Verify existing orphan cleanup logic in `home-modules/tools/monitoring-panel/monitoring_data.py` validates badges against window tree
- [x] T032 [US5] Verify BADGE_MAX_AGE (TTL) constant is set to 300 seconds in monitoring_data.py per quickstart.md configuration section
- [x] T033 [US5] Manual test: Create badge for window via quickstart.md test script, close window, verify badge removed within cleanup cycle

**Checkpoint**: User Story 5 complete - stale badge cleanup working

---

## Phase 8: User Story 6 - Suppressed Legacy Hooks (Priority: P3)

**Goal**: Legacy Claude Code hooks suppressed while tmux detection active, reversible via config

**Independent Test**: Verify no hook scripts execute when submitting prompts to Claude Code with tmux monitor enabled

### Implementation for User Story 6

- [x] T034 [US6] Add `config.services.tmux-ai-monitor.enable` option to `home-modules/services/tmux-ai-monitor.nix` per research.md R9
- [x] T035 [US6] Modify `home-modules/ai-assistants/claude-code.nix` to suppress hooks when `config.services.tmux-ai-monitor.enable` is true per research.md R9
- [x] T036 [US6] Ensure hooks remain in code but wrapped with `lib.mkIf (!config.services.tmux-ai-monitor.enable)` for easy rollback
- [x] T037 [US6] Run `sudo nixos-rebuild dry-build --flake .#hetzner-sway` to verify conditional compilation
- [x] T038 [US6] Manual test: Run claude, verify no hook output in `journalctl --user -t claude-callback`

**Checkpoint**: User Story 6 complete - legacy hooks suppressed, rollback path available

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [x] T039 Run full quickstart.md test scenarios from specs/117-improve-notification-progress-indicators/quickstart.md
- [x] T040 Update quickstart.md with any corrections discovered during testing
- [x] T041 Run `sudo nixos-rebuild switch --flake .#thinkpad` to apply changes
- [x] T042 Verify all success criteria SC-001 through SC-009 from spec.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational - Core detection
- **User Story 2 (Phase 4)**: Depends on US1 (needs badges to exist for dismissal testing)
- **User Story 3 (Phase 5)**: Depends on US1 (triggered by badge state change to stopped)
- **User Story 4 (Phase 6)**: Depends on US3 (notification content refinement)
- **User Story 5 (Phase 7)**: Can start after Foundational (independent cleanup logic)
- **User Story 6 (Phase 8)**: Can start after Foundational (independent hook suppression)
- **Polish (Phase 9)**: Depends on all user stories complete

### User Story Dependencies

```
      Setup (T001-T004)
             │
             ▼
      Foundational (T005-T009)
             │
     ┌───────┼───────┐
     │       │       │
     ▼       ▼       ▼
   US1     US5     US6
  (Core)  (Cleanup) (Hooks)
     │
     ▼
   US2 (Focus Dismiss)
     │
     ▼
   US3 (Notifications)
     │
     ▼
   US4 (Content)
     │
     ▼
   Polish (T039-T042)
```

### Parallel Opportunities

After Foundational phase completes, these can run in parallel:
- US1 (T010-T019), US5 (T031-T033), US6 (T034-T038)

Within US1:
- T010, T011 can potentially run in parallel (different functions in same file)
- T013, T014 can potentially run in parallel (different badge state handlers)

---

## Parallel Example: Foundational Phase

```bash
# After T005-T006 complete, these can run in parallel:
Task: "T007 Implement window ID resolution helper"
Task: "T008 Implement badge directory initialization"
```

## Parallel Example: After Foundational

```bash
# Once Foundational (T009) completes, start in parallel:
Task: "T010 [US1] Implement tmux pane enumeration"
Task: "T031 [US5] Verify existing orphan cleanup"
Task: "T034 [US6] Add config.services.tmux-ai-monitor.enable option"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test detection works for both Claude Code and Codex
5. This alone provides 80% of the value

### Incremental Delivery

1. Setup + Foundational → Structure ready
2. Add US1 → Core detection working (MVP!)
3. Add US2 → Focus dismissal removes friction
4. Add US3 + US4 → Notifications provide cross-desktop awareness
5. Add US5 + US6 → Cleanup and hook suppression for polish

### Suggested MVP Scope

**MVP = Phase 1 + Phase 2 + Phase 3 (Tasks T001-T019)**

This delivers:
- tmux-based AI process detection for Claude Code and Codex
- Badge file creation for working/stopped states
- EWW panel integration via existing inotify

Remaining stories add polish but core value is in MVP.

---

## Summary

| Metric | Value |
|--------|-------|
| Total task count | 42 |
| Phase 1 (Setup) | 4 tasks |
| Phase 2 (Foundational) | 5 tasks |
| Phase 3 (US1 - Detection) | 10 tasks |
| Phase 4 (US2 - Focus Dismiss) | 3 tasks |
| Phase 5 (US3 - Notifications) | 5 tasks |
| Phase 6 (US4 - Content) | 3 tasks |
| Phase 7 (US5 - Cleanup) | 3 tasks |
| Phase 8 (US6 - Hooks) | 5 tasks |
| Phase 9 (Polish) | 4 tasks |
| MVP tasks (T001-T019) | 19 tasks |
| Parallel opportunities | 3 groups identified |

---

## Notes

- [P] tasks = different files, no dependencies within that phase
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Run `dry-build` after each phase to catch Nix errors early
- Commit after each task or logical group
- Manual tests reference quickstart.md scenarios where applicable
- This replaces hook-based detection with tmux polling per spec.md v2.0
