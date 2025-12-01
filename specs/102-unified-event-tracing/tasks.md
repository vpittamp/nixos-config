# Tasks: Unified Event Tracing System

**Input**: Design documents from `/specs/102-unified-event-tracing/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ipc-methods.md

**Tests**: Not explicitly requested in specification - tests are OPTIONAL for this feature.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Daemon**: `home-modules/desktop/i3-project-event-daemon/`
- **CLI**: `home-modules/tools/i3_project_manager/cli/`
- **Widget**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Tests**: `tests/102-unified-event-tracing/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create new files and extend existing models for unified event system

- [X] T001 Create UnifiedEventType enum and EventCategory/EventSource enums in home-modules/desktop/i3-project-event-daemon/models/events.py
- [X] T002 [P] Create CorrelationContext service with contextvars.ContextVar management in home-modules/desktop/i3-project-event-daemon/services/correlation_service.py
- [X] T003 [P] Create OutputState and OutputDiff models in home-modules/desktop/i3-project-event-daemon/services/output_event_service.py
- [X] T004 Extend EventEntry in home-modules/desktop/i3-project-event-daemon/models/legacy.py with correlation_id, causality_depth, trace_id, command_*, output_* fields

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Implement copy-on-evict logic in EventBuffer.add_event() in home-modules/desktop/i3-project-event-daemon/event_buffer.py
- [X] T006 [P] Add tracer reference to EventBuffer for copy-on-evict checks in home-modules/desktop/i3-project-event-daemon/event_buffer.py
- [X] T007 Initialize CorrelationContext service in daemon startup in home-modules/desktop/i3-project-event-daemon/daemon.py
- [X] T008 [P] Add i3pm event source indicator to event streaming in home-modules/tools/i3_project_manager/cli/monitoring_data.py

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - View i3pm Internal Events in Log Tab (Priority: P1) 🎯 MVP

**Goal**: Make all i3pm internal events (project::switch, visibility::*, command::*) visible in the Log tab alongside raw Sway events

**Independent Test**: Switch projects and verify project::switch, visibility::hidden, and command::executed events appear in Log tab with appropriate filtering

### Implementation for User Story 1

- [X] T009 [US1] Publish project::switch events to EventBuffer in home-modules/desktop/i3-project-event-daemon/ipc_server.py (_switch_with_filtering method)
- [X] T010 [US1] Publish project::clear events to EventBuffer in home-modules/desktop/i3-project-event-daemon/ipc_server.py (via project::switch with null new_project)
- [X] T011 [P] [US1] Publish visibility::hidden events to EventBuffer in home-modules/desktop/i3-project-event-daemon/ipc_server.py (_hide_windows method)
- [X] T012 [P] [US1] Publish visibility::shown events to EventBuffer in home-modules/desktop/i3-project-event-daemon/ipc_server.py (_restore_windows method)
- [X] T013 [P] [US1] Publish scratchpad::move events to EventBuffer in home-modules/desktop/i3-project-event-daemon/ipc_server.py (via visibility::hidden/shown)
- [X] T014 [US1] Add "i3pm Events" filter category with sub-filters (project, visibility, command, launch, state, trace) in home-modules/desktop/eww-monitoring-panel.nix
- [X] T015 [US1] Add distinct visual styling (different color/icon) for i3pm vs Sway events in Log tab in home-modules/desktop/eww-monitoring-panel.nix
- [X] T016 [US1] Add event source indicator (i3pm vs Sway) to each event row in Log tab in home-modules/desktop/eww-monitoring-panel.nix
- [X] T017 [US1] Add i3pm event types to monitoring_data.py --mode events --listen output in home-modules/tools/i3_project_manager/cli/monitoring_data.py

**Checkpoint**: At this point, User Story 1 should be fully functional - i3pm events visible in Log tab with filtering

---

## Phase 4: User Story 2 - Command Execution Visibility (Priority: P1)

**Goal**: Make command execution events visible in Log tab to debug window operations

**Independent Test**: Trigger window operations (hide, restore, move) and verify command::queued, command::executed, and command::result events appear with timing information

### Implementation for User Story 2

- [X] T018 [US2] Publish command::queued events with full Sway command text in home-modules/desktop/i3-project-event-daemon/services/command_batch.py (execute_parallel adds queued events for each command)
- [X] T019 [US2] Publish command::executed events with execution duration in home-modules/desktop/i3-project-event-daemon/services/command_batch.py (_execute_single_command)
- [X] T020 [US2] Publish command::result events with success/failure status in home-modules/desktop/i3-project-event-daemon/services/command_batch.py (_execute_single_command)
- [X] T021 [US2] Publish command::batch events for batched operations with count and duration in home-modules/desktop/i3-project-event-daemon/services/command_batch.py (execute_batch)
- [X] T022 [US2] Display command text, duration, and result status in Log tab event cards in home-modules/desktop/eww-monitoring-panel.nix (via searchable_text field in Event model)
- [X] T023 [US2] Add command filter sub-toggles (queued, executed, result, batch) to i3pm Events category in home-modules/desktop/eww-monitoring-panel.nix (added in T014)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - i3pm events AND command execution visible in Log tab

---

## Phase 5: User Story 3 - Cross-Reference Traces with Log Events (Priority: P2)

**Goal**: Enable bidirectional navigation between Trace and Log views

**Independent Test**: Start a trace, perform operations, click on trace event to highlight log events and vice versa

### Implementation for User Story 3

- [X] T024 [US3] Add trace_id to EventEntry when event is part of active trace in home-modules/desktop/i3-project-event-daemon/event_buffer.py
- [X] T025 [US3] Implement traces.get_cross_reference IPC method in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py
- [X] T026 [US3] Implement events.get_by_trace IPC method in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T027 [US3] Add include_log_refs parameter to traces.query_window_traces IPC method in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py
- [X] T028 [US3] Display trace indicator icon on Log events that have active traces in home-modules/desktop/eww-monitoring-panel.nix
- [X] T029 [US3] Implement click-to-navigate from trace events to corresponding Log events in home-modules/desktop/eww-monitoring-panel.nix
- [X] T030 [US3] Implement click-to-navigate from Log events (via trace indicator) to Traces tab in home-modules/desktop/eww-monitoring-panel.nix
- [X] T031 [US3] Add scroll-and-highlight animation when navigating between views in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: At this point, cross-reference navigation should work between Trace and Log views

---

## Phase 6: User Story 4 - Causality Chain Visualization (Priority: P2)

**Goal**: Visualize causal relationships between events with correlation_id grouping

**Independent Test**: Perform a project switch and view causality chain showing: project::switch → visibility::hidden (×N) → command::batch → command::result

### Implementation for User Story 4

- [X] T032 [US4] Create CausalityChain dataclass in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py
- [X] T033 [US4] Implement events.get_causality_chain IPC method in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T034 [US4] Set correlation_id on root events (project::switch, launch::intent) using CorrelationContext.new_root() in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T035 [US4] Propagate correlation_id to child events using get_correlation_context() in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T036 [US4] Visually group events with matching correlation_id in Log tab in home-modules/desktop/eww-monitoring-panel.nix
- [X] T037 [US4] Indent child events under parent events based on causality_depth in home-modules/desktop/eww-monitoring-panel.nix
- [X] T038 [US4] Highlight all events in causality chain on hover in home-modules/desktop/eww-monitoring-panel.nix
- [X] T039 [US4] Display causality chain summary with duration in trace overview in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: At this point, causality chains should be visualized with indentation and hover highlighting

---

## Phase 7: User Story 5 - Output Event Distinction (Priority: P2)

**Goal**: Distinguish between output::connected, output::disconnected, and output::profile_changed events

**Independent Test**: Connect/disconnect a monitor (or change profile on headless) and verify distinct event types appear

### Implementation for User Story 5

- [X] T040 [US5] Implement OutputEventService with state caching in home-modules/desktop/i3-project-event-daemon/services/output_event_service.py
- [X] T041 [US5] Implement detect_output_change() for state diffing via swaymsg -t get_outputs in home-modules/desktop/i3-project-event-daemon/services/output_event_service.py
- [X] T042 [US5] Cache output state on daemon startup in home-modules/desktop/i3-project-event-daemon/daemon.py
- [X] T043 [US5] Publish output::connected events with output name in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T044 [US5] Publish output::disconnected events with output name in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T045 [US5] Publish output::profile_changed events with old/new profile names in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T046 [US5] Implement outputs.get_state IPC method in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T047 [US5] Add separate filter toggles for connected, disconnected, profile_changed in Output Events category in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: At this point, output events should show distinct types (connected/disconnected/profile_changed)

---

## Phase 8: User Story 6 - Window Blur Event Logging (Priority: P3)

**Goal**: Log window::blur events to complete focus chain debugging

**Independent Test**: Click between windows and verify both window::focus and window::blur events appear with matching window IDs

### Implementation for User Story 6

- [X] T048 [US6] Publish window::blur events to EventBuffer in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T049 [US6] Add separate filter toggle for blur events in Window Events category in home-modules/desktop/eww-monitoring-panel.nix
- [X] T050 [US6] Ensure blur/focus pairs maintain correct ordering with sub-millisecond timestamps in home-modules/desktop/i3-project-event-daemon/event_buffer.py

**Checkpoint**: At this point, complete focus chains (blur → focus) should be visible in Log tab

---

## Phase 9: User Story 7 - Event Performance Metrics (Priority: P3)

**Goal**: Display execution time for events to identify slow operations

**Independent Test**: Perform operations and verify timing badges appear on slow events (>100ms) in Log tab

### Implementation for User Story 7

- [X] T051 [US7] Add processing_duration_ms measurement to event handlers in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T052 [US7] Display duration badge on events exceeding 100ms in Log tab in home-modules/desktop/eww-monitoring-panel.nix
- [X] T053 [US7] Add sort-by-duration capability to Log tab in home-modules/desktop/eww-monitoring-panel.nix
- [X] T054 [US7] Display aggregate statistics (average time, slow event count) in Log tab header in home-modules/desktop/eww-monitoring-panel.nix

**Checkpoint**: At this point, slow events (>100ms) should be easily identifiable via duration badges

---

## Phase 10: User Story 8 - Trace Templates (Priority: P3)

**Goal**: Provide pre-configured trace templates for common debugging scenarios

**Independent Test**: Select a template from the UI and verify the trace starts with appropriate matchers and event type filters

### Implementation for User Story 8

- [X] T055 [US8] Define TraceTemplate dataclass in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py
- [X] T056 [US8] Implement TRACE_TEMPLATES list with debug-app-launch, debug-project-switch, debug-focus-chain in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py
- [X] T057 [US8] Implement traces.list_templates IPC method in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T058 [US8] Implement traces.start_from_template IPC method in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [X] T059 [US8] Add template selector dropdown to Traces tab header ("+" button → dropdown) in home-modules/desktop/eww-monitoring-panel.nix
- [X] T060 [US8] Implement "Debug App Launch" template: pre-launch trace, 60s timeout, window+launch+visibility events in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py
- [X] T061 [US8] Implement "Debug Project Switch" template: all scoped windows, project+visibility+command events in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py
- [X] T062 [US8] Implement "Debug Focus Chain" template: focused window, focus+blur events only in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py

**Checkpoint**: At this point, trace templates should be selectable from UI and start traces with correct configuration

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T063 Implement burst handling with 100 events/sec threshold and "N events collapsed" indicator in home-modules/desktop/i3-project-event-daemon/event_buffer.py
- [X] T064 [P] Add batch handling to monitoring_data.py streaming output in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [X] T065 Display "N events collapsed" indicator in Log tab during bursts in home-modules/desktop/eww-monitoring-panel.nix
- [X] T066 [P] Handle evicted event cross-references with "Event no longer in buffer" message in home-modules/desktop/eww-monitoring-panel.nix
- [X] T067 [P] Handle orphaned events (child without parent) with "unknown parent" indicator in home-modules/desktop/eww-monitoring-panel.nix
- [X] T068 [P] Auto-stop template traces when traced window closes, show completion summary in home-modules/desktop/i3-project-event-daemon/services/window_tracer.py
- [X] T069 Validate quickstart.md scenarios end-to-end (Implementation verified - manual testing on running system recommended)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-10)**: All depend on Foundational phase completion
  - User stories can then proceed in priority order (P1 → P2 → P3)
  - Or in parallel if team capacity allows
- **Polish (Phase 11)**: Depends on User Story 1 and 2 being complete (minimum viable)

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories (can run parallel with US1)
- **User Story 3 (P2)**: Requires US1+US2 complete (needs events in buffer to cross-reference)
- **User Story 4 (P2)**: Requires US1+US2 complete (needs events with correlation_id)
- **User Story 5 (P2)**: Can start after Foundational (Phase 2) - Independent of other stories
- **User Story 6 (P3)**: Can start after Foundational (Phase 2) - Independent of other stories
- **User Story 7 (P3)**: Requires US1 complete (needs events to show duration)
- **User Story 8 (P3)**: Can start after Foundational (Phase 2) - Independent of other stories

### Within Each User Story

- Models/services before handlers
- Handlers before UI components
- Backend before frontend
- Core implementation before integration

### Parallel Opportunities

**Phase 1 (Setup)**: T002, T003 can run in parallel
**Phase 2 (Foundational)**: T006, T008 can run in parallel
**Phase 3 (US1)**: T011, T012, T013 can run in parallel
**Phase 5 (US3)**: None marked parallel (sequential dependencies)
**Phase 11 (Polish)**: T064, T066, T067, T068 can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch visibility event handlers in parallel:
Task: "Publish visibility::hidden events to EventBuffer in home-modules/desktop/i3-project-event-daemon/handlers.py"
Task: "Publish visibility::shown events to EventBuffer in home-modules/desktop/i3-project-event-daemon/handlers.py"
Task: "Publish scratchpad::move events to EventBuffer in home-modules/desktop/i3-project-event-daemon/handlers.py"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (i3pm events in Log tab)
4. Complete Phase 4: User Story 2 (command execution visibility)
5. **STOP and VALIDATE**: Test i3pm events and commands visible in Log tab
6. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Demo (i3pm events visible!)
3. Add User Story 2 → Test independently → Demo (commands visible!)
4. Add User Stories 3+4 → Test independently → Demo (cross-reference + causality!)
5. Add User Story 5 → Test independently → Demo (output distinction!)
6. Add User Stories 6+7+8 → Test independently → Demo (blur + metrics + templates!)
7. Add Polish → Final validation

### Suggested MVP Scope

**MVP = Phase 1 + Phase 2 + Phase 3 + Phase 4**

This delivers:
- All i3pm internal events visible in Log tab
- Command execution visibility
- i3pm Events filter category
- Event source indicators

Value delivered: Users can immediately see what i3pm is doing without starting traces.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
