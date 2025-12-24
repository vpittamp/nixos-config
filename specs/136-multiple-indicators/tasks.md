# Tasks: Multiple AI Indicators Per Terminal Window

**Input**: Design documents from `/specs/136-multiple-indicators/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in the feature specification. Manual verification via quickstart.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md project structure:
- **otel-ai-monitor**: `scripts/otel-ai-monitor/`
- **EWW widgets**: `home-modules/desktop/eww-monitoring-panel/`
- **CLI monitoring**: `home-modules/tools/i3_project_manager/cli/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No new project setup required - modifications to existing modules

- [X] T001 Create feature branch `136-multiple-indicators` from main
- [X] T002 Read existing code: `scripts/otel-ai-monitor/models.py`, `scripts/otel-ai-monitor/session_tracker.py`, `scripts/otel-ai-monitor/output_writer.py`
- [X] T003 [P] Read existing code: `home-modules/tools/i3_project_manager/cli/monitoring_data.py` (lines 1580-1620 for otel_sessions_by_window)
- [X] T004 [P] Read existing EWW widgets: `home-modules/desktop/eww-monitoring-panel/yuck/windows-view.yuck.nix`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend data model changes that MUST be complete before ANY UI story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Extend `SessionList` model in `scripts/otel-ai-monitor/models.py` to add `sessions_by_window: dict[int, list[SessionListItem]]` field
- [X] T006 Remove feature-based deduplication in `scripts/otel-ai-monitor/session_tracker.py` broadcast logic (lines ~1100-1108)
- [X] T007 Add window grouping logic in `scripts/otel-ai-monitor/session_tracker.py` to populate `sessions_by_window` dict
- [X] T008 Update `scripts/otel-ai-monitor/output_writer.py` to emit the new `sessions_by_window` field in JSON output
- [X] T009 Update `home-modules/tools/i3_project_manager/cli/monitoring_data.py` to change `otel_sessions_by_window` from `Dict[int, Dict]` to `Dict[int, List[Dict]]`
- [X] T010 Add state priority sorting in `monitoring_data.py` (WORKING=3 > ATTENTION=2 > COMPLETED=1 > IDLE=0)
- [X] T011 Create `_build_otel_badges()` helper function in `monitoring_data.py` to replace `_merge_badge_with_otel()`
- [X] T012 Update `transform_window()` in `monitoring_data.py` to set `otel_badges: List[Dict]` instead of merging single badge
- [X] T013 Validate JSON output matches `contracts/session-list.json` schema
- [X] T014 Validate window output matches `contracts/window-otel-badges.json` schema

**Checkpoint**: Foundation ready - backend emits arrays of session badges per window

---

## Phase 3: User Story 1 - View Multiple Active AI Sessions in One Terminal (Priority: P1) MVP

**Goal**: Display distinct indicators for each active AI session in a single terminal window's tab in the monitoring panel

**Independent Test**: Open tmux with two panes, run Claude Code in one and Codex in the other, verify both indicators appear in the monitoring panel window row

### Implementation for User Story 1

- [X] T015 [US1] Update `windows-view.yuck.nix` to iterate over `otel_badges` array instead of single badge
- [X] T016 [US1] Replace `window.badge.otel_state` references with `(for badge in window.otel_badges ...)` loop in `windows-view.yuck.nix`
- [X] T017 [US1] Create badge container box in `windows-view.yuck.nix` with horizontal orientation for multiple badges
- [X] T018 [US1] Render each badge with pulsing animation based on `badge.otel_state == "working"` in `windows-view.yuck.nix`
- [X] T019 [US1] Handle empty `otel_badges` array gracefully (no badges displayed) in `windows-view.yuck.nix`
- [X] T020 [US1] Add badge-container class styling in `home-modules/desktop/eww-monitoring-panel/scss/components.scss`
- [X] T021 [US1] Test independent state transitions: one session completes while other remains working
- [X] T022 [US1] Validate indicator count matches actual running AI sessions per quickstart.md Scenario 1 & 2

**Checkpoint**: Users can see multiple AI indicators per window - US1 fully functional

---

## Phase 4: User Story 2 - Distinguish Between AI Tool Types in Multi-Session View (Priority: P2)

**Goal**: Visually distinguish which indicator corresponds to which AI tool (Claude Code vs Codex vs Gemini)

**Independent Test**: Run different AI tools in tmux panes, verify each indicator shows the correct tool-specific icon

### Implementation for User Story 2

- [X] T023 [US2] Update badge rendering in `windows-view.yuck.nix` to select icon based on `badge.otel_tool` value
- [X] T024 [US2] Ensure Claude Code icon path is used when `otel_tool == "claude-code"` in `windows-view.yuck.nix`
- [X] T025 [US2] Ensure Codex icon path is used when `otel_tool == "codex"` in `windows-view.yuck.nix`
- [X] T026 [US2] Ensure Gemini icon path is used when `otel_tool == "gemini"` in `windows-view.yuck.nix`
- [X] T027 [US2] Add tooltip to each badge showing tool name and session state in `windows-view.yuck.nix`
- [X] T028 [US2] Validate tool icons are visually distinguishable per quickstart.md Scenario 4

**Checkpoint**: Users can identify which AI tool each indicator represents - US2 fully functional

---

## Phase 5: User Story 3 - Handle Indicator Overflow Gracefully (Priority: P3)

**Goal**: When more than 3 AI sessions are active in one terminal, show first 3 indicators plus a "+N more" count badge

**Independent Test**: Run 4+ AI sessions in one terminal, verify 3 indicators + overflow badge appear, tooltip shows full list

### Implementation for User Story 3

- [X] T029 [US3] Add conditional logic in `windows-view.yuck.nix` to limit visible badges to first 3 using `(take 3 otel_badges)`
- [X] T030 [US3] Add overflow count badge when `(length otel_badges) > 3` in `windows-view.yuck.nix`
- [X] T031 [US3] Display count text as `+${(length otel_badges) - 3} more` in overflow badge
- [X] T032 [US3] Add tooltip to overflow badge listing all sessions (tool type + state) using `(map ... otel_badges)` and `(join "\n" ...)`
- [X] T033 [US3] Add overflow-badge styling in `components.scss` (distinct from regular badges)
- [X] T034 [US3] Validate overflow handling with 4+ sessions per quickstart.md Scenario 3

**Checkpoint**: UI handles many concurrent sessions gracefully - US3 fully functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [X] T035 Verify update latency remains under 2 seconds (FR-008) for session state changes
- [X] T036 Test with 5+ concurrent sessions to verify UI stability (FR-006)
- [X] T037 [P] Validate no regression in single-session behavior (SC-006)
- [X] T038 Run `sudo nixos-rebuild dry-build --flake .#hetzner-sway` to verify build
- [X] T039 Apply configuration and run full quickstart.md validation
- [X] T040 Update CLAUDE.md if any new commands or behaviors added (N/A - no new commands)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User stories can proceed sequentially in priority order (P1 → P2 → P3)
  - Alternatively, US2 and US3 can start after US1 model tasks complete
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after US1 badge rendering is complete (T015-T020) - Uses same badge iteration structure
- **User Story 3 (P3)**: Can start after US1 badge rendering is complete (T015-T020) - Adds conditional logic on top

### Within Each User Story

- Widget structure before styling
- Core rendering before edge cases
- Implementation before validation

### Parallel Opportunities

- T002, T003, T004 can run in parallel (reading different files)
- T013, T014 can run in parallel (validating different schemas)
- T023, T024, T025, T026 can run in parallel (different tool icon mappings)
- T035, T036, T037 can run in parallel (different validation scenarios)

---

## Parallel Example: Foundational Phase

```bash
# Read all existing code in parallel:
Task: "Read existing code: scripts/otel-ai-monitor/models.py, session_tracker.py, output_writer.py"
Task: "Read existing code: monitoring_data.py (lines 1580-1620)"
Task: "Read existing EWW widgets: windows-view.yuck.nix"
```

## Parallel Example: User Story 2

```bash
# Launch all icon mapping tasks together:
Task: "Ensure Claude Code icon path when otel_tool == 'claude-code'"
Task: "Ensure Codex icon path when otel_tool == 'codex'"
Task: "Ensure Gemini icon path when otel_tool == 'gemini'"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (read existing code)
2. Complete Phase 2: Foundational (backend data model changes)
3. Complete Phase 3: User Story 1 (display multiple badges)
4. **STOP and VALIDATE**: Test with two AI sessions in tmux per quickstart.md
5. Deploy if ready - users can now see multiple AI indicators

### Incremental Delivery

1. Complete Setup + Foundational → Backend emits session arrays
2. Add User Story 1 → Multiple indicators visible → Deploy/Demo (MVP!)
3. Add User Story 2 → Tool icons distinguish sessions → Deploy/Demo
4. Add User Story 3 → Overflow handling for power users → Deploy/Demo
5. Each story adds value without breaking previous stories

---

## Files Modified (Summary)

| File | Changes |
|------|---------|
| `scripts/otel-ai-monitor/models.py` | Add `sessions_by_window` field to `SessionList` |
| `scripts/otel-ai-monitor/session_tracker.py` | Remove deduplication, add window grouping |
| `scripts/otel-ai-monitor/output_writer.py` | Emit grouped session data |
| `home-modules/tools/i3_project_manager/cli/monitoring_data.py` | Change to List-based lookup, add `_build_otel_badges()` |
| `home-modules/desktop/eww-monitoring-panel/yuck/windows-view.yuck.nix` | Iterate over `otel_badges` array, add overflow handling |
| `home-modules/desktop/eww-monitoring-panel/scss/components.scss` | Badge container and overflow styles |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Breaking change: `window.badge.otel_*` → `window.otel_badges[].otel_*`
- Per Constitution Principle XII: No backward compatibility layer
- Verify tests fail before implementing (if tests added later)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
