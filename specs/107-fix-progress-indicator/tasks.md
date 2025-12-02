# Tasks: Fix Progress Indicator Focus State and Event Efficiency

**Input**: Design documents from `/specs/107-fix-progress-indicator/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)
- Includes exact file paths

---

## Phase 1: Setup

**Purpose**: Verify existing infrastructure and prepare test environment

- [x] T001 Verify daemon IPC socket exists at /run/i3-project-daemon/ipc.sock
- [x] T002 Verify badge-ipc-client.sh works via `badge-ipc get-state` in scripts/claude-hooks/badge-ipc-client.sh
- [x] T003 [P] Create test directory structure at tests/107-fix-progress-indicator/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Ensure existing badge system is functioning correctly before modifications

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Test current badge file-based system works end-to-end (create badge file, verify in panel)
- [x] T005 Document current badge CSS classes in home-modules/desktop/eww-monitoring-panel.nix
- [x] T006 Verify window.focused field is present in monitoring data via `eww get monitoring_data | jq`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Badge Reflects Window Focus State (Priority: P1) 🎯 MVP

**Goal**: Users can visually distinguish focused vs. unfocused badged windows at a glance

**Independent Test**: Create badge on focused window → verify dimmed appearance; switch away → verify full prominence

### Implementation for User Story 1

- [x] T007 [US1] Add `.badge-focused-window` CSS class with dimmed styling in home-modules/desktop/eww-monitoring-panel.nix (lines ~7574-7596)
- [x] T008 [US1] Update badge widget :class to include focus-aware modifier in home-modules/desktop/eww-monitoring-panel.nix
- [x] T009 [US1] Test focus-aware badge: focused window shows dimmed badge
- [x] T010 [US1] Test focus-aware badge: switching away restores full prominence

**Checkpoint**: User Story 1 complete - badges now visually indicate focus state

---

## Phase 4: User Story 2 - Event-Driven Badge Updates (Priority: P2)

**Goal**: Hooks use IPC for <100ms badge latency, with file-based fallback for reliability

**Independent Test**: Trigger hook → measure time to badge appearance; stop daemon → verify file fallback works

### Implementation for User Story 2

- [x] T011 [US2] Update prompt-submit-notification.sh to use IPC-first with file fallback in scripts/claude-hooks/prompt-submit-notification.sh
- [x] T012 [P] [US2] Update stop-notification.sh to use IPC-first with file fallback in scripts/claude-hooks/stop-notification.sh
- [x] T013 [US2] Add --state parameter support to badge-ipc-client.sh create command in scripts/claude-hooks/badge-ipc-client.sh
- [x] T014 [US2] Test IPC path: verify badge appears within 100ms of hook via `time badge-ipc create ...`
- [x] T015 [US2] Test fallback path: stop daemon → trigger hook → verify badge file created
- [x] T016 [US2] Test fallback recovery: restart daemon → verify badge state loaded from files

**Checkpoint**: User Story 2 complete - hooks now use fast IPC path with reliable fallback

---

## Phase 5: User Story 3 - Optimized Spinner Animation (Priority: P3)

**Goal**: Spinner animation uses <1% CPU by decoupling from full data refresh

**Independent Test**: Trigger working badge → monitor CPU → verify <2% usage during 60-second animation

### Implementation for User Story 3

- [x] T017 [US3] Add (defvar spinner_frame "⠋") to eww config in home-modules/desktop/eww-monitoring-panel.nix
- [x] T018 [US3] Create spinner-update.sh script at scripts/eww/spinner-update.sh
- [x] T019 [US3] Add (defpoll _spinner_driver) with :run-while condition in home-modules/desktop/eww-monitoring-panel.nix
- [x] T020 [US3] Update badge widget to use spinner_frame variable instead of monitoring_data.spinner_frame in home-modules/desktop/eww-monitoring-panel.nix
- [x] T021 [US3] Verify has_working_badge flag exists in monitoring_data.py output (already present)
- [x] T022 [US3] Test spinner animation renders smoothly (visual inspection)
- [x] T023 [US3] Test CPU usage during animation stays below 2% via htop

**Checkpoint**: User Story 3 complete - spinner animation is CPU-efficient

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Finalize implementation and ensure all success criteria are met

- [x] T024 [P] Run full quickstart.md validation scenarios in specs/107-fix-progress-indicator/quickstart.md
- [x] T025 [P] Verify no regression in existing badge functionality (clear on focus, persistence)
- [x] T026 Measure end-to-end performance metrics (latency, CPU) and document results
- [x] T027 Update CLAUDE.md with Feature 107 documentation in CLAUDE.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - **US1 (Phase 3)**: Independent - can start immediately after Phase 2
  - **US2 (Phase 4)**: Independent - can run parallel with US1
  - **US3 (Phase 5)**: Independent - can run parallel with US1/US2
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

| Story | Depends On | Can Parallel With |
|-------|------------|-------------------|
| US1 (Focus State) | Phase 2 only | US2, US3 |
| US2 (IPC Updates) | Phase 2 only | US1, US3 |
| US3 (Spinner Opt) | Phase 2 only | US1, US2 |

### Within Each User Story

- Implementation tasks execute sequentially within a story
- Tasks marked [P] can run in parallel with each other
- Tests should verify functionality before marking story complete

---

## Parallel Opportunities

### After Phase 2 Completes (All Stories Can Start)

```text
Developer A:
- T007-T010 (US1: Focus State - 4 tasks)

Developer B:
- T011-T016 (US2: IPC Updates - 6 tasks)

Developer C:
- T017-T023 (US3: Spinner Opt - 7 tasks)
```

### Within Phase 4 (US2)

```text
Parallel:
- T011 (prompt-submit-notification.sh)
- T012 [P] (stop-notification.sh)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (3 tasks)
2. Complete Phase 2: Foundational (3 tasks)
3. Complete Phase 3: User Story 1 (4 tasks)
4. **STOP and VALIDATE**: Test focus-aware badges independently
5. Deploy if ready - delivers core UX improvement

**MVP Task Count**: 10 tasks

### Full Implementation

1. Setup + Foundational → 6 tasks
2. User Story 1 (Focus State) → 4 tasks
3. User Story 2 (IPC Updates) → 6 tasks
4. User Story 3 (Spinner Opt) → 7 tasks
5. Polish → 4 tasks

**Total Task Count**: 27 tasks

---

## Task Summary

| Phase | Tasks | Story |
|-------|-------|-------|
| Setup | T001-T003 (3) | - |
| Foundational | T004-T006 (3) | - |
| User Story 1 | T007-T010 (4) | Focus State |
| User Story 2 | T011-T016 (6) | IPC Updates |
| User Story 3 | T017-T023 (7) | Spinner Opt |
| Polish | T024-T027 (4) | - |
| **Total** | **27 tasks** | |

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- Each user story independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- No tests explicitly required (spec didn't mandate TDD) - validation via quickstart.md scenarios
