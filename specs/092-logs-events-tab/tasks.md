# Tasks: Real-Time Event Log and Activity Stream

**Feature**: 092-logs-events-tab
**Input**: Design documents from `/specs/092-logs-events-tab/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓

**Tests**: Test tasks included per TDD principle (Constitution Principle XIV)

**Organization**: Tasks grouped by user story to enable independent implementation and testing

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Per plan.md, this is an **extension feature** modifying existing files:
- Backend: `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- Frontend: `home-modules/desktop/eww-monitoring-panel.nix`
- Tests: `tests/092-logs-events-tab/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Test directory initialization and dependency verification

- [X] T001 Create test directory structure at tests/092-logs-events-tab/ with subdirectories: unit/, integration/, fixtures/
- [X] T002 [P] Verify Python 3.11+ environment with i3ipc.aio, asyncio, Pydantic dependencies available
- [X] T003 [P] Verify Eww 0.4+ installation and GTK3 availability on system

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core event infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Add `--mode events` argument handling to monitoring_data.py main() function
- [X] T005 Implement Event Pydantic model in monitoring_data.py with fields: timestamp, timestamp_friendly, event_type, change_type, payload, enrichment, icon, color, category, searchable_text
- [X] T006 [P] Implement SwayEventPayload Pydantic model for raw Sway IPC event data
- [X] T007 [P] Implement EventEnrichment Pydantic model for i3pm daemon metadata
- [X] T008 Implement EventBuffer class using collections.deque(maxlen=500) in monitoring_data.py
- [X] T009 [P] Implement EventsViewData Pydantic model for response structure
- [X] T010 Create EVENT_ICONS dictionary mapping event types to {icon, color} tuples with Nerd Font icons and Catppuccin Mocha colors
- [X] T011 Implement format_friendly_timestamp() helper (reuse existing from monitoring_data.py)

**Checkpoint**: Foundation ready - backend can now handle events, user story implementation can begin

---

## Phase 3: User Story 1 - View Real-Time Window Activity (Priority: P1) 🎯 MVP

**Goal**: Display real-time window management events (window::new, window::focus, window::close, workspace::focus) with timestamps and basic metadata

**Independent Test**: Open monitoring panel, switch to Logs tab, create a new window (e.g., open terminal), verify event appears with timestamp, icon, and app name within 100ms

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T012 [P] [US1] Create test_event_models.py with unit tests for Event Pydantic model validation (timestamp, event_type, icon, color)
- [X] T013 [P] [US1] Create test_event_buffer.py with unit tests for EventBuffer FIFO eviction (append 501 events, verify oldest evicted)
- [X] T014 [P] [US1] Create test_sway_ipc_subscriptions.py with integration test for i3ipc.aio window event subscription
- [X] T015 [P] [US1] Create fixtures/mock_sway_events.py with sample window::new, window::focus, workspace::focus event payloads

### Implementation for User Story 1

- [X] T016 [US1] Implement query_events_data() async function in monitoring_data.py for one-shot mode (returns EventsViewData with empty events list initially)
- [X] T017 [US1] Implement stream_events() async function in monitoring_data.py with i3ipc.aio SUBSCRIBE to window, workspace events
- [X] T018 [US1] Add event handler on_window_event() to extract event type, create Event object with timestamp, icon, category="window"
- [X] T019 [US1] Add event handler on_workspace_event() to extract workspace focus changes, create Event object with category="workspace"
- [X] T020 [US1] Implement event appending to EventBuffer in event handlers
- [X] T021 [US1] Implement JSON output to stdout in stream_events() (single-line JSON per event, deflisten compatible)
- [X] T022 [US1] Add Eww deflisten variable events_data in eww-monitoring-panel.nix with command: monitoring-data-backend --mode events --listen
- [X] T023 [US1] Add Logs tab button to panel header (5th tab after Health) with onclick handler
- [X] T024 [US1] Implement logs-view Yuck widget with scroll container and event list iteration
- [X] T025 [US1] Implement event-card Yuck widget to display single event with icon, timestamp, event type, basic payload info
- [X] T026 [US1] Add keyboard handler for '5' and 'Alt+5' keys to switch to Logs tab in handleKeyScript
- [X] T027 [US1] Add Catppuccin Mocha CSS styling for event-card widget (border colors match event.color)

**Checkpoint**: User Story 1 complete - can view window/workspace events in real-time with timestamps and icons

---

## Phase 4: User Story 2 - Filter and Search Event History (Priority: P2)

**Goal**: Enable users to filter events by type (window, workspace, output) and search by text to narrow down event history

**Independent Test**: Accumulate 50+ events, click "Window" filter button, verify only window:: events displayed; enter "firefox" in search box, verify only Firefox-related events shown

### Tests for User Story 2

- [ ] T028 [P] [US2] Create test_event_filtering.py with unit tests for EventFilter.matches() logic (type filter, search text filter, combined filters)
- [ ] T029 [P] [US2] Create integration test for frontend filter application with mock events_data

### Implementation for User Story 2

- [ ] T030 [P] [US2] Implement generate_searchable_text() helper in monitoring_data.py (concatenates app_name, project, workspace, title fields)
- [ ] T031 [US2] Add searchable_text field population in event handlers (call generate_searchable_text() for each Event)
- [ ] T032 [US2] Add Eww variable event_filter_type with default "all" in eww-monitoring-panel.nix
- [ ] T033 [P] [US2] Add Eww variable event_filter_search with default "" in eww-monitoring-panel.nix
- [ ] T034 [US2] Implement filter-controls Yuck widget with buttons for "All", "Window", "Workspace", "Output" event types
- [ ] T035 [US2] Add search input box to filter-controls widget with onchange handler updating event_filter_search
- [ ] T036 [US2] Implement event_filter_matches() Yuck helper function (checks event.category matches filter_type AND searchable_text contains filter_search)
- [ ] T037 [US2] Add :visible conditional to event-card in logs-view (only show if event_filter_matches() returns true)
- [ ] T038 [US2] Add event count display showing "X events" or "X filtered / Y total" in logs-view header
- [ ] T039 [US2] Add "Clear Filters" button to reset event_filter_type="all" and event_filter_search=""

**Checkpoint**: User Stories 1 AND 2 complete - can view events and filter/search effectively

---

## Phase 5: User Story 3 - View Enriched Event Metadata (Priority: P3)

**Goal**: Display project associations, scope classification, app registry names alongside raw events for enhanced debugging context

**Independent Test**: Launch a scoped window (e.g., terminal in a project), view its creation event, verify enrichment shows project name, scope="scoped", and app registry name

### Tests for User Story 3

- [ ] T040 [P] [US3] Create test_event_enrichment.py with integration tests for enrich_window_event() querying i3pm daemon
- [ ] T041 [P] [US3] Create fixtures/sample_event_data.py with enriched event examples (scoped windows, global windows, PWAs)

### Implementation for User Story 3

- [ ] T042 [US3] Implement enrich_window_event() async function in monitoring_data.py (queries DaemonClient.get_window_tree(), matches window ID, extracts project/scope/app_name)
- [ ] T043 [US3] Add enrichment call in on_window_event() handler for window::new, window::focus events (with <20ms timeout)
- [ ] T044 [US3] Add graceful degradation: if daemon unavailable, set enrichment=None and daemon_available=False in Event
- [ ] T045 [US3] Extend event-card widget to display enrichment.project_name with teal border if scope="scoped"
- [ ] T046 [US3] Add enrichment.app_name display in event-card (use registry name if available, fallback to raw app_id)
- [ ] T047 [US3] Add PWA badge (is_pwa=true) indicator for workspace 50+ windows in event-card
- [ ] T048 [US3] Add visual distinction for project-scoped events: different background color or border style
- [ ] T049 [US3] Add daemon unavailability warning at top of logs-view if events_data.daemon_available=false

**Checkpoint**: All enrichment features working - events show full context (project, scope, app names)

---

## Phase 6: User Story 4 - Control Event Stream Performance (Priority: P3)

**Goal**: Provide pause/resume and clear controls to prevent performance degradation during long monitoring sessions

**Independent Test**: Click "Pause", perform 10 window operations, verify events don't appear in UI; click "Resume", verify buffered events appear immediately

### Tests for User Story 4

- [ ] T050 [P] [US4] Create integration test for event batching (send 20 events in 50ms, verify UI receives batched update within 100ms)
- [ ] T051 [P] [US4] Create unit test for EventBuffer.clear() method

### Implementation for User Story 4

- [ ] T052 [US4] Implement event batching in stream_events() with 100ms debounce window (collect events in batch, emit once per window)
- [ ] T053 [US4] Add Eww variable events_paused with default false in eww-monitoring-panel.nix
- [ ] T054 [US4] Implement pause/resume toggle button in logs-view header (updates events_paused variable)
- [ ] T055 [US4] Modify deflisten to respect events_paused (backend continues streaming, frontend stops updating UI when paused)
- [ ] T056 [US4] Implement "Clear" button in logs-view header (calls backend to clear EventBuffer or clears frontend event list)
- [ ] T057 [US4] Add EventBuffer.clear() method in monitoring_data.py
- [ ] T058 [US4] Add visual indicator showing "PAUSED" status when events_paused=true
- [ ] T059 [US4] Add event count tracking and display current buffer size (e.g., "127 / 500 events")

**Checkpoint**: All performance controls working - can pause, resume, clear event stream

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final integration, documentation, and validation

- [ ] T060 [P] Add error handling for Sway IPC disconnection in stream_events() (exponential backoff reconnection per Feature 085 pattern)
- [ ] T061 [P] Add signal handlers (SIGTERM, SIGINT, SIGPIPE) for graceful shutdown in monitoring_data.py
- [ ] T062 [P] Implement sticky scroll behavior: track scroll_at_bottom variable, only auto-scroll when true
- [ ] T063 [P] Add output::unspecified event handling for monitor configuration changes
- [ ] T064 [P] Add binding::run and mode::change event handling for keybinding/mode events
- [ ] T065 Add heartbeat mechanism (emit JSON every 5s if no events) to detect stale connections
- [ ] T066 [P] Add comprehensive docstrings to all new functions in monitoring_data.py
- [ ] T067 [P] Add inline comments explaining event enrichment and batching logic
- [ ] T068 Update quickstart.md with final keyboard shortcuts and troubleshooting steps (already complete, verify accuracy)
- [ ] T069 Run pytest test suite: `pytest tests/092-logs-events-tab/ -v` and ensure all tests pass
- [ ] T070 Manual UI testing: Follow quickstart.md test scenarios (view events, filter, search, pause/resume, clear)
- [ ] T071 Verify performance targets: <100ms event latency, <200ms filter response, 30fps @ 50+ events/sec
- [ ] T072 NixOS rebuild dry-build: `sudo nixos-rebuild dry-build --flake .#<target>` to validate configuration
- [ ] T073 Deploy to test environment and verify end-to-end functionality

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories CAN proceed in parallel (if team capacity allows)
  - Or sequentially in priority order: US1 (P1) → US2 (P2) → US3 (P3) → US4 (P3)
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (View Real-Time Events)**: Can start after Foundational - No dependencies on other stories ✓ INDEPENDENT
- **US2 (Filter and Search)**: Can start after Foundational - Requires US1 event display for testing, but filtering logic is independent
- **US3 (Enriched Metadata)**: Can start after Foundational - Enrichment is additive to US1 events, can develop in parallel
- **US4 (Performance Controls)**: Can start after Foundational - Pause/resume/clear are independent of event display

### Within Each User Story

- Tests MUST be written and FAIL before implementation (TDD)
- Models before services
- Backend event handling before frontend display
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

**Setup Phase (Phase 1)**:
- T002 and T003 can run in parallel (independent verification tasks)

**Foundational Phase (Phase 2)**:
- T006 and T007 can run in parallel (independent Pydantic models)
- T010 and T011 can run in parallel (independent helpers)

**User Story 1 (Phase 3)**:
- Tests (T012-T015) can all run in parallel (independent test files)
- T022-T027 frontend tasks can run in parallel with T016-T021 backend tasks (different developers)

**User Story 2 (Phase 4)**:
- T028 and T029 can run in parallel (independent test files)
- T030 and T031 can run in parallel with T032-T034 (backend vs frontend)

**User Story 3 (Phase 5)**:
- T040 and T041 can run in parallel (independent test files)
- T045-T048 frontend tasks can run in parallel (different widget elements)

**User Story 4 (Phase 6)**:
- T050 and T051 can run in parallel (independent test files)
- T053-T055 can run in parallel (different Eww variables and handlers)

**Polish Phase (Phase 7)**:
- T060-T067 can all run in parallel (independent concerns: error handling, signals, events, docs)

**Cross-Story Parallelization**:
- Once Foundational phase completes, US1, US2, US3, US4 can ALL be developed in parallel by different developers
- Backend tasks (monitoring_data.py) can proceed independently of frontend tasks (eww-monitoring-panel.nix)

---

## Parallel Example: User Story 1

```bash
# Terminal 1: Backend developer - Event handling
claude-code "Implement T016-T021: Event streaming backend"

# Terminal 2: Frontend developer - UI display
claude-code "Implement T022-T027: Logs tab UI widgets"

# Terminal 3: Test developer - Test infrastructure
claude-code "Implement T012-T015: Event model and buffer tests"

# All three can work simultaneously with minimal coordination
```

## Parallel Example: Across User Stories

```bash
# Developer A: User Story 1 (MVP)
claude-code "Implement Phase 3 (US1): View Real-Time Events"

# Developer B: User Story 2 (Filtering)
claude-code "Implement Phase 4 (US2): Filter and Search"

# Developer C: User Story 3 (Enrichment)
claude-code "Implement Phase 5 (US3): Enriched Metadata"

# Developer D: User Story 4 (Performance)
claude-code "Implement Phase 6 (US4): Performance Controls"

# All four user stories can proceed in parallel after Foundational phase
```

---

## MVP Scope Recommendation

**Minimum Viable Product**: User Story 1 only (Phase 1, 2, 3)

**Delivers**:
- ✅ Real-time event streaming (window, workspace events)
- ✅ Event display with icons and timestamps
- ✅ Sub-100ms event latency
- ✅ Logs tab in monitoring panel

**Does NOT include** (defer to future iterations):
- ❌ Filtering/search (US2)
- ❌ Event enrichment (US3)
- ❌ Pause/resume/clear controls (US4)

**Why this MVP?**:
- Validates core deflisten architecture works for event streaming
- Provides immediate debugging value (see events in real-time)
- Independently testable (acceptance scenario: open panel, see events appear)
- Low risk (extends proven Feature 085 patterns)
- Quick delivery (estimated 1-1.5 days with tests)

**Incremental Delivery Path**:
1. **v0.1 (MVP)**: US1 only - Basic event streaming and display
2. **v0.2**: Add US2 - Filtering and search capabilities
3. **v0.3**: Add US3 - Event enrichment with daemon metadata
4. **v0.4**: Add US4 - Performance controls (pause/resume/clear)
5. **v1.0**: Polish phase - Error handling, docs, full validation

---

## Task Summary

**Total Tasks**: 73
- Setup (Phase 1): 3 tasks
- Foundational (Phase 2): 8 tasks
- User Story 1 (Phase 3): 16 tasks (12 tests + 12 implementation)
- User Story 2 (Phase 4): 12 tasks (2 tests + 10 implementation)
- User Story 3 (Phase 5): 10 tasks (2 tests + 8 implementation)
- User Story 4 (Phase 6): 10 tasks (2 tests + 8 implementation)
- Polish (Phase 7): 14 tasks

**Parallel Opportunities**: 28 tasks marked [P] (38% of total)

**Independent Test Criteria**:
- ✅ US1: Open panel → create window → event appears within 100ms
- ✅ US2: Apply filter → only matching events shown within 200ms
- ✅ US3: Launch scoped window → enrichment shows project/scope/app name
- ✅ US4: Pause → perform actions → resume → buffered events appear

**Format Validation**: ✅ All tasks follow checklist format with checkbox, ID, optional [P], optional [Story], description, and file paths

---

## Implementation Strategy

1. **TDD Approach**: Write tests first (marked in each phase), ensure FAIL, then implement
2. **MVP First**: Implement Phase 1 → 2 → 3 (US1 only) for rapid validation
3. **Incremental Delivery**: Add US2, US3, US4 sequentially based on user feedback
4. **Parallel Execution**: Leverage [P] tasks and cross-story parallelization for speed
5. **Constitution Compliance**: All tasks align with Principles I, VI, X, XI, XIV per plan.md

**Ready for implementation** - All tasks are actionable with specific file paths and clear acceptance criteria.
