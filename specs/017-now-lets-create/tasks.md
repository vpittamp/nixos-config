# Tasks: i3 Project System Monitor

**Input**: Design documents from `/etc/nixos/specs/017-now-lets-create/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/jsonrpc-api.md

**Tests**: Not requested in feature specification - testing will be manual verification against acceptance scenarios

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Following NixOS home-manager structure from plan.md:
- **Monitor tool**: `home-modules/tools/i3-project-monitor/`
- **Daemon extensions**: `home-modules/desktop/i3-project-event-daemon/`
- **Scripts**: `scripts/`
- **NixOS modules**: `home-modules/tools/`, `home-modules/desktop/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create project structure and install dependencies

- [X] **T001** Create monitor tool directory structure at `home-modules/tools/i3-project-monitor/` with subdirectories: `displays/`, `__init__.py`, `__main__.py`
- [X] **T002** [P] Create empty Python module files: `home-modules/tools/i3-project-monitor/{__init__.py,__main__.py,models.py,daemon_client.py}`
- [X] **T003** [P] Create display mode module files: `home-modules/tools/i3-project-monitor/displays/{__init__.py,base.py,live.py,events.py,history.py,tree.py}`
- [X] **T004** [P] Create home-manager module file: `home-modules/tools/i3-project-monitor.nix` (empty, will be filled in Polish phase)
- [X] **T005** Create bash wrapper script: `scripts/i3-project-monitor` with argparse placeholder and execution boilerplate

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure and daemon extensions that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Daemon Extensions (Required by ALL Monitor Modes)

- [X] **T006** [P] [Foundation] Add EventEntry dataclass to `home-modules/desktop/i3-project-event-daemon/models.py` (event_id, event_type, timestamp, window_id, window_class, workspace_name, project_name, tick_payload, processing_duration_ms, error fields)
- [X] **T007** [Foundation] Create EventBuffer class in `home-modules/desktop/i3-project-event-daemon/event_buffer.py` (circular deque with maxlen=500, add_event, get_events methods)
- [X] **T008** [Foundation] Update daemon __main__ to instantiate EventBuffer and pass to handlers (modify `home-modules/desktop/i3-project-event-daemon/__main__.py`)

### Event Storage Integration (Required by US2 and US3)

- [X] **T009** [Foundation] Update `on_tick` handler in `home-modules/desktop/i3-project-event-daemon/handlers.py` to create EventEntry and add to EventBuffer after processing
- [X] **T010** [Foundation] Update `on_window_new` handler to create EventEntry and add to EventBuffer after marking window
- [X] **T011** [Foundation] Update `on_window_close` handler to create EventEntry and add to EventBuffer
- [X] **T012** [Foundation] Update `on_window_mark` handler to create EventEntry and add to EventBuffer
- [X] **T013** [Foundation] Update `on_window_focus` handler to create EventEntry and add to EventBuffer

### JSON-RPC API Extensions (Required by ALL Monitor Modes)

- [X] **T014** [Foundation] Implement `list_monitors` JSON-RPC method in `home-modules/desktop/i3-project-event-daemon/ipc_server.py` (query i3 outputs and workspaces, return monitor list with workspace assignments)
- [X] **T015** [Foundation] Update `get_events` JSON-RPC method in `home-modules/desktop/i3-project-event-daemon/ipc_server.py` to query EventBuffer with limit and event_type filtering
- [X] **T016** [Foundation] Add `subscribed_clients` set to IPCServer class in `home-modules/desktop/i3-project-event-daemon/ipc_server.py` (tracks SubscribedClient instances)
- [X] **T017** [Foundation] Implement `subscribe_events` JSON-RPC method in `home-modules/desktop/i3-project-event-daemon/ipc_server.py` (add client to subscribed_clients, return subscription_id)
- [X] **T018** [Foundation] Implement `broadcast_event` method in IPCServer to send JSON-RPC notifications to all subscribed clients
- [X] **T019** [Foundation] Update EventBuffer integration to call broadcast_event after adding each event (modify T007 or create hook in handlers)

### Monitor Tool Core (Required by ALL Display Modes)

- [X] **T020** [P] [Foundation] Implement data models in `home-modules/tools/i3-project-monitor/models.py`: MonitorState, WindowEntry, MonitorEntry, EventEntry, TreeNode dataclasses (from data-model.md)
- [X] **T021** [Foundation] Implement DaemonClient class in `home-modules/tools/i3-project-monitor/daemon_client.py` with methods: connect, send_request (JSON-RPC helper), get_status, get_windows, list_monitors, get_events, subscribe_events
- [X] **T022** [Foundation] Implement reconnection logic in DaemonClient: connect_with_retry (exponential backoff 1s, 2s, 4s, 8s, 16s, max 5 retries)
- [X] **T023** [Foundation] Implement BaseDisplay class in `home-modules/tools/i3-project-monitor/displays/base.py` with Rich console setup, render method stub, error display helpers
- [X] **T024** [Foundation] Implement CLI entry point in `home-modules/tools/i3-project-monitor/__main__.py`: argparse for --mode, --filter, --limit, --format flags, mode dispatcher to display classes

**Checkpoint**: Foundation ready - daemon has event storage and extended API, monitor tool has core client and models

---

## Phase 3: User Story 1 - Real-time System State Visibility (Priority: P1) 🎯 MVP

**Goal**: Display current daemon status, active project, tracked windows, and monitors in a live-updating terminal UI

**Independent Test**: Run `i3-project-monitor --mode=live`, verify display shows active project, window list with project assignments, monitor list with workspace assignments, daemon connection status. Acceptance scenarios AS1.1-AS1.4 from spec.md.

### Implementation for User Story 1

- [X] **T025** [US1] Implement LiveDisplay class in `home-modules/tools/i3-project-monitor/displays/live.py`: render method creates Rich layout with 4 panels (connection status, active project, windows table, monitors table)
- [X] **T026** [US1] Implement connection status panel rendering in LiveDisplay: daemon uptime, events processed, error count (uses DaemonClient.get_status)
- [X] **T027** [US1] Implement active project panel rendering in LiveDisplay: project name or "None", tracked windows count (uses DaemonClient.get_status)
- [X] **T028** [US1] Implement windows table rendering in LiveDisplay: columns for ID, Class, Title, Project, Workspace (uses DaemonClient.get_windows)
- [X] **T029** [US1] Implement monitors table rendering in LiveDisplay: columns for Monitor, Resolution, Workspaces, Primary, Active (uses DaemonClient.list_monitors)
- [X] **T030** [US1] Integrate Rich Live context manager in LiveDisplay to auto-refresh display every 250ms (4 Hz)
- [X] **T031** [US1] Add "Daemon not running" error state to LiveDisplay (handle ConnectionError from DaemonClient)
- [X] **T032** [US1] Wire LiveDisplay into __main__.py mode dispatcher: `if args.mode == "live": LiveDisplay(client).run()`

**Checkpoint**: User Story 1 (Live Mode) is fully functional - run `i3-project-monitor` to see real-time state

---

## Phase 4: User Story 2 - Event Stream Monitoring (Priority: P2)

**Goal**: Display live stream of events as they occur with timestamps and details

**Independent Test**: Run `i3-project-monitor --mode=events`, perform actions (open window, switch project, close window), verify each action generates visible event in stream with <100ms latency. Acceptance scenarios AS2.1-AS2.4 from spec.md.

### Implementation for User Story 2

- [X] **T033** [US2] Implement EventsDisplay class in `home-modules/tools/i3-project-monitor/displays/events.py`: async subscribe to daemon events via DaemonClient.subscribe_events
- [X] **T034** [US2] Implement event stream rendering in EventsDisplay: Rich table with columns for TIME, TYPE, WINDOW, PROJECT, DETAILS
- [X] **T035** [US2] Implement async event listener loop in EventsDisplay: read JSON-RPC notifications from daemon socket, parse event, add to display buffer
- [X] **T036** [US2] Add local event buffer (deque maxlen=100) to EventsDisplay to smooth display updates and prevent freezing
- [X] **T037** [US2] Implement event type filtering in EventsDisplay based on --filter CLI flag (filter by "window", "workspace", "tick")
- [X] **T038** [US2] Add event statistics footer to EventsDisplay: events received count, errors count, duration timer
- [X] **T039** [US2] Implement graceful handling of connection loss in EventsDisplay: show "Connection lost, retrying..." status during reconnection
- [X] **T040** [US2] Wire EventsDisplay into __main__.py mode dispatcher: `if args.mode == "events": EventsDisplay(client).run()`

**Checkpoint**: User Story 2 (Event Stream) is fully functional - run `i3-project-monitor --mode=events` to see live events

---

## Phase 5: User Story 3 - Historical Event Log Review (Priority: P3)

**Goal**: Display timestamped log of recent events with filtering and search capabilities

**Independent Test**: Run `i3-project-monitor --mode=history --limit=50`, verify display shows last 50 events with timestamps in chronological order. Test filtering with `--filter=window`. Acceptance scenarios AS3.1-AS3.3 from spec.md.

### Implementation for User Story 3

- [X] **T041** [US3] Implement HistoryDisplay class in `home-modules/tools/i3-project-monitor/displays/history.py`: query daemon via DaemonClient.get_events with limit parameter
- [X] **T042** [US3] Implement event log rendering in HistoryDisplay: format each event as `[timestamp] event_type | details` with syntax highlighting
- [X] **T043** [US3] Add event type filtering to HistoryDisplay based on --filter CLI flag (pass event_type to get_events)
- [X] **T044** [US3] Implement --limit parameter handling in HistoryDisplay (default 20, max 500)
- [X] **T045** [US3] Add event count summary to HistoryDisplay: "Showing N events (filtered by type)" footer
- [X] **T046** [US3] Wire HistoryDisplay into __main__.py mode dispatcher: `if args.mode == "history": HistoryDisplay(client, args.limit, args.filter).run()`

**Checkpoint**: User Story 3 (History Mode) is fully functional - run `i3-project-monitor --mode=history` to review past events

---

## Phase 6: User Story 4 - i3 Tree Inspection (Priority: P4)

**Goal**: Display hierarchical i3 window tree with marks and properties

**Independent Test**: Run `i3-project-monitor --mode=tree`, verify display shows workspace hierarchy, window marks (including project marks), window properties. Acceptance scenarios AS4.1-AS4.3 from spec.md.

### Implementation for User Story 4

- [X] **T047** [US4] Implement TreeDisplay class in `home-modules/tools/i3-project-monitor/displays/tree.py`: query i3 tree directly via i3ipc.aio.Connection (no daemon mediation)
- [X] **T048** [US4] Implement i3 tree query in TreeDisplay: async connect to i3, call get_tree(), disconnect
- [X] **T049** [US4] Implement recursive tree rendering in TreeDisplay: Rich table with TYPE, ID, MARKS, NAME/TITLE columns, indent based on depth
- [X] **T050** [US4] Add tree node filtering by marks in TreeDisplay: support --marks CLI flag to show only nodes with matching marks (e.g., `--marks=project:`)
- [X] **T051** [US4] Implement window property detail view in TreeDisplay: when window node displayed, show window_class, window_title, window_role, floating status, layout
- [X] **T052** [US4] Add scratchpad workspace highlighting in TreeDisplay: clearly mark `__i3_scratch` workspace and floating windows
- [X] **T053** [US4] Wire TreeDisplay into __main__.py mode dispatcher: `if args.mode == "tree": TreeDisplay().run()`

**Checkpoint**: User Story 4 (Tree Inspector) is fully functional - run `i3-project-monitor --mode=tree` to inspect window hierarchy

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: NixOS integration, documentation, and improvements affecting multiple user stories

- [X] **T054** [P] [Polish] Implement home-manager module in `home-modules/tools/i3-project-monitor.nix`: create Python package with setuptools, include rich and i3ipc dependencies, export package
- [X] **T055** [P] [Polish] Update `home-modules/profiles/base-home.nix` to add i3-project-monitor module to imports
- [X] **T056** [Polish] Complete bash wrapper script `scripts/i3-project-monitor`: add shebang, pass all args to Python module via `python3 -m i3_project_monitor "$@"`
- [X] **T057** [P] [Polish] Add module docstrings to all Python files: __init__.py, __main__.py, models.py, daemon_client.py, displays/*.py
- [X] **T058** [P] [Polish] Add CLI --help documentation in __main__.py: document all modes, flags, examples
- [X] **T059** [P] [Polish] Add error handling for missing dependencies in __main__.py: check for Rich library, i3ipc library, provide helpful error messages
- [X] **T060** [Polish] Test monitor tool against quickstart.md examples: verify all command examples work (live mode, event stream, history with --limit, tree with --marks)
- [X] **T061** [Polish] Add connection timeout handling to DaemonClient: if daemon doesn't respond in 5 seconds, show clear error message
- [X] **T062** [P] [Polish] Add --version flag to CLI in __main__.py: display monitor tool version
- [X] **T063** [P] [Polish] Update CLAUDE.md with monitor tool usage in "Project Management Workflow" section: add troubleshooting command examples

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-6)**: All depend on Foundational phase completion
  - US1 (P1) can start after Foundational
  - US2 (P2) can start after Foundational (requires EventBuffer from T007)
  - US3 (P3) can start after Foundational (requires EventBuffer from T007)
  - US4 (P4) can start after Foundational (independent of other stories)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Foundation only - no dependencies on other stories
- **User Story 2 (P2)**: Foundation only - no dependencies on other stories
- **User Story 3 (P3)**: Foundation only - no dependencies on other stories
- **User Story 4 (P4)**: Foundation only - completely independent (queries i3 directly)

### Within Each Phase

**Phase 2 (Foundational)**:
- T006-T008: EventBuffer creation (sequential)
- T009-T013: Event handler updates (all parallel after T007-T008)
- T014-T019: JSON-RPC extensions (T016-T019 sequential for subscribe logic, T014-T015 parallel)
- T020-T024: Monitor tool core (T020-T021 parallel, T022 after T021, T023-T024 parallel after T020)

**Phase 3 (US1)**:
- T025: Class skeleton (prerequisite for all)
- T026-T029: Panel rendering (all parallel after T025)
- T030-T032: Integration (sequential after T026-T029)

**Phase 4 (US2)**:
- T033: Class skeleton (prerequisite for all)
- T034-T037: Core features (all parallel after T033)
- T038-T040: Polish and integration (sequential after T034-T037)

**Phase 5 (US3)**:
- T041-T045: All parallel (simple query-and-display)
- T046: Integration (after T041-T045)

**Phase 6 (US4)**:
- T047-T051: All parallel (different rendering concerns)
- T052-T053: Finalization (sequential after T047-T051)

**Phase 7 (Polish)**:
- T054-T055: NixOS packaging (parallel)
- T056: Script wrapper (after T054)
- T057-T059: Documentation (parallel)
- T060-T063: Final polish (sequential after all previous)

### Parallel Opportunities

**Setup (Phase 1)**:
- T002, T003, T004, T005 can all run in parallel after T001

**Foundational (Phase 2)**:
- T009-T013 (event handlers) can all run in parallel
- T020-T021 (models and client) can run in parallel
- T023-T024 (base display and CLI) can run in parallel

**User Stories (Phases 3-6)**:
- Once Foundational is complete, all 4 user stories can be developed in parallel by different developers

**Polish (Phase 7)**:
- T054-T055 (packaging) parallel
- T057-T059 (documentation) parallel

---

## Parallel Example: User Story 1

```bash
# After T025 is complete, launch panel rendering tasks in parallel:
Task: "Implement connection status panel rendering in LiveDisplay"
Task: "Implement active project panel rendering in LiveDisplay"
Task: "Implement windows table rendering in LiveDisplay"
Task: "Implement monitors table rendering in LiveDisplay"
```

---

## Parallel Example: User Story 2

```bash
# After T033 is complete, launch core features in parallel:
Task: "Implement event stream rendering in EventsDisplay"
Task: "Implement async event listener loop in EventsDisplay"
Task: "Add local event buffer to EventsDisplay"
Task: "Implement event type filtering in EventsDisplay"
```

---

## Parallel Example: All User Stories After Foundation

```bash
# After Phase 2 (Foundational) is complete, all user stories can start in parallel:
Task: "Implement LiveDisplay class (US1)"
Task: "Implement EventsDisplay class (US2)"
Task: "Implement HistoryDisplay class (US3)"
Task: "Implement TreeDisplay class (US4)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete **Phase 1: Setup** (T001-T005)
2. Complete **Phase 2: Foundational** (T006-T024) - CRITICAL, blocks everything
3. Complete **Phase 3: User Story 1** (T025-T032)
4. **STOP and VALIDATE**: Run `i3-project-monitor --mode=live` and verify all acceptance scenarios
5. If validated, consider deploying/demoing MVP before continuing

**MVP Scope**: 32 tasks (Setup + Foundational + US1)

**Value Delivered**: Developers can see current system state (active project, windows, monitors) in real-time

### Incremental Delivery

1. **Foundation** (T001-T024) → Core infrastructure ready
2. **+US1 (P1)** (T025-T032) → Live state monitoring (MVP!)
3. **+US2 (P2)** (T033-T040) → Event stream debugging capability
4. **+US3 (P3)** (T041-T046) → Historical event analysis
5. **+US4 (P4)** (T047-T053) → Advanced tree inspection
6. **+Polish** (T054-T063) → Production-ready NixOS integration

Each increment is independently testable and adds value without breaking previous stories.

### Parallel Team Strategy

With multiple developers:

1. **Week 1**: Team completes Setup + Foundational together (T001-T024)
2. **Week 2** (once Foundational is done):
   - Developer A: User Story 1 (T025-T032)
   - Developer B: User Story 2 (T033-T040)
   - Developer C: User Story 3 (T041-T046)
   - Developer D: User Story 4 (T047-T053)
3. **Week 3**: Team completes Polish together (T054-T063)

Stories integrate seamlessly since they share the Foundation but are otherwise independent.

---

## Task Summary

- **Total Tasks**: 63
- **Setup Tasks**: 5 (T001-T005)
- **Foundational Tasks**: 19 (T006-T024) - BLOCKS all user stories
- **User Story 1 (P1) Tasks**: 8 (T025-T032)
- **User Story 2 (P2) Tasks**: 8 (T033-T040)
- **User Story 3 (P3) Tasks**: 6 (T041-T046)
- **User Story 4 (P4) Tasks**: 7 (T047-T053)
- **Polish Tasks**: 10 (T054-T063)

**Parallel Opportunities**: 27 tasks marked [P] can run in parallel with other tasks

**MVP Scope** (US1 only): 32 tasks (51% of total)

**Critical Path**: Setup → Foundational → US1 → Polish (minimum for production deployment)

---

## Notes

- **[P]** tasks work on different files and can run in parallel
- **[Story]** labels map tasks to user stories for traceability
- Each user story is independently completable and testable
- Tests are NOT included (not requested in spec) - manual verification via acceptance scenarios
- Commit after each task or logical group (e.g., all panel renderers for US1)
- Stop at any checkpoint to validate story works independently
- Daemon extensions (Phase 2) are critical - all monitor modes depend on them

---

**Tasks Status**: ✅ Complete - 63 tasks generated, organized by user story, ready for implementation
