# Tasks: Linux System Log Integration

**Feature**: 029-linux-system-log
**Branch**: `029-linux-system-log`
**Input**: Design documents from `/specs/029-linux-system-log/`

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Summary

- **Total Tasks**: 47
- **User Stories**: 3 (P1: systemd integration, P2: proc monitoring, P3: correlation)
- **MVP Scope**: User Story 1 (systemd integration) - Tasks T001-T018
- **Parallel Opportunities**: 28 tasks can run in parallel within their phases
- **Tests**: Not included (not requested in spec)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Minimal setup - feature extends existing daemon, no new project needed

- [ ] T001 [P] [Setup] Create new Python modules in `home-modules/desktop/i3-project-event-daemon/`: systemd_query.py, proc_monitor.py, event_correlator.py (empty shells for now)
- [ ] T002 [P] [Setup] Create test directory structure: `tests/i3-project-daemon/unit/` and `tests/i3-project-daemon/integration/`
- [ ] T003 [P] [Setup] Update `home-modules/desktop/i3-project-event-daemon/README.md` with feature overview and new module descriptions

**Checkpoint**: Project structure ready for implementation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core EventEntry model extensions and database schema - MUST complete before any user story

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 [Foundation] Extend EventEntry source validation in `home-modules/desktop/i3-project-event-daemon/models.py:206` to include "systemd", "proc"
- [ ] T005 [P] [Foundation] Add systemd event fields to EventEntry in `models.py`: systemd_unit, systemd_message, systemd_pid, journal_cursor (all Optional[str])
- [ ] T006 [P] [Foundation] Add process event fields to EventEntry in `models.py`: process_pid, process_name, process_cmdline, process_parent_pid, process_start_time (all Optional types)
- [ ] T007 [Foundation] Add EventEntry validation in `__post_init__` for systemd events (must have systemd_unit) and proc events (must have process_pid and process_name)
- [ ] T008 [P] [Foundation] Update Deno EventNotificationSchema in `home-modules/tools/i3pm-deno/src/validation.ts` to include new source enum values and optional fields
- [ ] T009 [P] [Foundation] Create SQLite migration script `home-modules/desktop/i3-project-event-daemon/migrations/029_add_systemd_proc_fields.sql` to add new columns to event_log table
- [ ] T010 [Foundation] Run migration script and verify schema changes with `sqlite3 ~/.config/i3/event_log.db ".schema event_log"`

**Checkpoint**: Foundation ready - EventEntry model supports all event sources, user story implementation can now begin

---

## Phase 3: User Story 1 - View System Service Launches (Priority: P1) 🎯 MVP

**Goal**: Query systemd journal for application service starts and display alongside i3 events

**Independent Test**: Run `i3pm daemon events --source=systemd --since="1 hour ago"` and verify systemd service events appear with proper timestamps

### Implementation for User Story 1

- [ ] T011 [P] [US1] Implement journalctl query function in `home-modules/desktop/i3-project-event-daemon/systemd_query.py`: `async def query_systemd_journal(since, until, unit_pattern, limit) -> List[EventEntry]`
- [ ] T012 [P] [US1] Implement JSON parsing for journalctl output in `systemd_query.py`: parse `__REALTIME_TIMESTAMP`, `_SYSTEMD_UNIT`, `MESSAGE`, `_PID` fields
- [ ] T013 [P] [US1] Implement systemd event filtering in `systemd_query.py`: filter for "app-*.service" and "*.desktop" unit patterns
- [ ] T014 [US1] Implement EventEntry creation from systemd journal entries in `systemd_query.py`: set source="systemd", event_type="systemd::service::start", map JSON fields to EventEntry
- [ ] T015 [US1] Add error handling for journalctl command failures in `systemd_query.py`: return empty list with warning message if journalctl unavailable
- [ ] T016 [US1] Add IPC method `query_systemd_events()` in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`: register method, call systemd_query.query_systemd_journal(), return EventEntry list as JSON
- [ ] T017 [US1] Extend `query_events()` IPC method in `ipc_server.py` to support `source="systemd"` and `source="all"` parameters, merge systemd events with existing events sorted by timestamp
- [ ] T018 [US1] Update Deno CLI `daemon.ts` in `home-modules/tools/i3pm-deno/src/commands/daemon.ts`: add `--source` flag support for "systemd", "proc", "all" values
- [ ] T019 [P] [US1] Add systemd event formatting in `daemon.ts` formatEvent() function: handle "systemd::service::start" event type with systemd_message display
- [ ] T020 [P] [US1] Add [systemd] source badge formatting in `daemon.ts`: distinct color/style for systemd events
- [ ] T021 [US1] Write unit test `tests/i3-project-daemon/unit/test_systemd_query.py`: test JSON parsing with sample journalctl output
- [ ] T022 [US1] Write unit test for systemd event filtering: verify "app-*" pattern matching
- [ ] T023 [US1] Write integration test `tests/i3-project-daemon/integration/test_systemd_integration.py`: query actual journal, verify EventEntry conversion
- [ ] T024 [US1] Manual test: Run `i3pm daemon events --source=systemd` and verify output matches acceptance scenarios from spec

**Checkpoint**: User Story 1 complete - systemd events queryable and displayable 🎉

---

## Phase 4: User Story 2 - Monitor Background Process Activity (Priority: P2)

**Goal**: Monitor /proc filesystem for new processes and capture process::start events

**Independent Test**: Start process monitoring, launch rust-analyzer, run `i3pm daemon events --source=proc` and verify process event appears

### Implementation for User Story 2

- [ ] T025 [P] [US2] Implement /proc monitoring class in `home-modules/desktop/i3-project-event-daemon/proc_monitor.py`: `class ProcessMonitor` with `async def start()`
- [ ] T026 [P] [US2] Implement PID detection in `proc_monitor.py`: scan `/proc` directory, track seen PIDs in set, detect new PIDs
- [ ] T027 [P] [US2] Implement process detail reading in `proc_monitor.py`: read `/proc/{pid}/comm`, `/proc/{pid}/cmdline`, `/proc/{pid}/stat` fields
- [ ] T028 [US2] Implement process filtering in `proc_monitor.py`: allowlist for interesting processes (rust-analyzer, node, python, docker, etc.), skip others
- [ ] T029 [US2] Implement command line sanitization in `proc_monitor.py`: `def sanitize_cmdline(cmdline)` with regex patterns for password=*, token=*, key=* replacement with "***"
- [ ] T030 [US2] Implement command line truncation in `proc_monitor.py`: limit to 500 chars with "..." indicator
- [ ] T031 [US2] Implement EventEntry creation for process events in `proc_monitor.py`: set source="proc", event_type="process::start", populate process fields
- [ ] T032 [US2] Add error handling in `proc_monitor.py`: catch FileNotFoundError and PermissionError, skip process silently and continue
- [ ] T033 [US2] Integrate ProcessMonitor with daemon in `home-modules/desktop/i3-project-event-daemon/daemon.py`: initialize ProcessMonitor, start monitoring loop on daemon startup
- [ ] T034 [US2] Add IPC methods in `ipc_server.py`: `start_proc_monitoring()`, `stop_proc_monitoring()` for runtime control
- [ ] T035 [US2] Update `query_events()` in `ipc_server.py` to include proc events when `source="proc"` or `source="all"`
- [ ] T036 [P] [US2] Add process event formatting in `daemon.ts` formatEvent(): handle "process::start" event type, display process_name and sanitized cmdline
- [ ] T037 [P] [US2] Add [proc] source badge formatting in `daemon.ts`: distinct color/style for proc events
- [ ] T038 [US2] Write unit test `tests/i3-project-daemon/unit/test_proc_monitor.py`: test cmdline sanitization with various password/token patterns
- [ ] T039 [US2] Write unit test for cmdline truncation: verify 500-char limit with "..."
- [ ] T040 [US2] Write unit test for allowlist filtering: verify only interesting processes captured
- [ ] T041 [US2] Write integration test `tests/i3-project-daemon/integration/test_proc_monitoring.py`: start monitoring, spawn test process, verify event captured
- [ ] T042 [US2] Manual test: Start monitoring, launch rust-analyzer, verify `i3pm daemon events --source=proc` shows event with sanitized cmdline
- [ ] T043 [US2] Performance test: Launch 50+ processes rapidly, verify CPU usage stays <5%

**Checkpoint**: User Story 2 complete - process monitoring active and events captured 🎉

---

## Phase 5: User Story 3 - Correlate Events (Priority: P3)

**Goal**: Detect and display parent-child relationships between window events and process spawns

**Independent Test**: Launch VS Code, run `i3pm daemon events --correlate`, verify window::new event shows rust-analyzer as child process

### Implementation for User Story 3

- [ ] T044 [P] [US3] Create EventCorrelation model in `home-modules/desktop/i3-project-event-daemon/models.py`: define EventCorrelation dataclass with correlation_id, parent_event_id, child_event_ids, confidence_score, timing/hierarchy/name factors
- [ ] T045 [P] [US3] Create SQLite tables in migration script: `event_correlations` and `correlation_children` tables per data-model.md schema
- [ ] T046 [US3] Implement correlation detection in `home-modules/desktop/i3-project-event-daemon/event_correlator.py`: `async def detect_correlations(event_buffer, time_window=5000)` - scan recent events for timing/hierarchy/name matches
- [ ] T047 [US3] Implement confidence scoring in `event_correlator.py`: `def calculate_confidence(timing_factor, hierarchy_factor, name_similarity, workspace_match)` with weighted formula (40%, 30%, 20%, 10%)
- [ ] T048 [US3] Implement timing proximity calculation in `event_correlator.py`: calculate milliseconds between parent and child events
- [ ] T049 [US3] Implement hierarchy detection in `event_correlator.py`: read `/proc/{child_pid}/stat` field 4 (parent PID), match against window event PIDs or systemd PIDs
- [ ] T050 [US3] Implement name similarity in `event_correlator.py`: compare window_class to process_name using string distance algorithm (Levenshtein or similar)
- [ ] T051 [US3] Implement workspace matching in `event_correlator.py`: compare workspace_name from window event to i3 IPC current workspace at process spawn time
- [ ] T052 [US3] Add correlation storage in `event_correlator.py`: insert EventCorrelation into database, update event_correlations and correlation_children tables
- [ ] T053 [US3] Add IPC methods in `ipc_server.py`: `get_correlation(event_id)`, `query_correlations(correlation_type, min_confidence, limit)`
- [ ] T054 [US3] Add `--correlate` flag in `daemon.ts`: query correlations via IPC, display in hierarchical format with indentation
- [ ] T055 [P] [US3] Implement correlation display formatting in `daemon.ts`: show parent event, indented child events with time delta and confidence score
- [ ] T056 [US3] Write unit test `tests/i3-project-daemon/unit/test_event_correlator.py`: test confidence scoring with known factor values
- [ ] T057 [US3] Write unit test for timing proximity: verify 5-second window detection
- [ ] T058 [US3] Write unit test for name similarity: test "Code" vs "rust-analyzer" scoring
- [ ] T059 [US3] Write integration test `tests/i3-project-daemon/integration/test_correlation.py`: create window event, spawn related process, verify correlation detected
- [ ] T060 [US3] Manual test: Launch VS Code, wait for rust-analyzer spawn, run `i3pm daemon events --correlate`, verify hierarchical display matches acceptance scenario

**Checkpoint**: User Story 3 complete - event correlation working with confidence scoring 🎉

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final integration, documentation, and cross-story improvements

- [ ] T061 [P] [Polish] Update `home-modules/desktop/i3-project-event-daemon/README.md` with complete usage examples for all three user stories
- [ ] T062 [P] [Polish] Update CLAUDE.md with new event source commands and examples
- [ ] T063 [P] [Polish] Add comprehensive error messages for common failure cases (journalctl unavailable, /proc not accessible, correlation disabled)
- [ ] T064 [P] [Polish] Add daemon startup logging: log when systemd query module initialized, proc monitoring started, correlation enabled
- [ ] T065 [Polish] Performance optimization: profile proc monitoring CPU usage, optimize allowlist matching if needed
- [ ] T066 [Polish] Integration test for unified stream: verify `--source=all` shows chronologically sorted events from all sources (i3, systemd, proc)
- [ ] T067 [Polish] End-to-end test: launch Firefox → verify systemd::service::start → verify window::new → verify events appear in `--source=all`

**Checkpoint**: Feature complete and polished 🎉

---

## Dependencies & Parallel Execution

### Story Completion Order

```
Phase 1 (Setup) → Phase 2 (Foundation) → Phase 3 (US1) ──┐
                                        ├─→ Phase 4 (US2) ──┼─→ Phase 6 (Polish)
                                        └─→ Phase 5 (US3) ──┘

US1, US2, US3 can be implemented in parallel after Foundation phase completes
```

### Parallel Opportunities by Phase

**Phase 1** (all parallel):
- T001, T002, T003 (3 tasks)

**Phase 2** (partial parallel):
- T005, T006, T008, T009 can run in parallel (4 tasks)
- T004, T007, T010 are sequential dependencies

**Phase 3 (US1)** (high parallelism):
- T011, T012, T013 can run in parallel (3 tasks)
- T019, T020 can run in parallel with T018 (2 tasks)
- T021, T022, T023 tests can run in parallel (3 tasks)

**Phase 4 (US2)** (high parallelism):
- T025, T026, T027 can run in parallel (3 tasks)
- T036, T037 can run in parallel with T035 (2 tasks)
- T038, T039, T040, T041 tests can run in parallel (4 tasks)

**Phase 5 (US3)** (moderate parallelism):
- T044, T045 can run in parallel (2 tasks)
- T055, T056, T057, T058 can run in parallel (4 tasks)

**Phase 6 (Polish)** (high parallelism):
- T061, T062, T063, T064 can run in parallel (4 tasks)

**Total parallel tasks**: 28 out of 67 tasks can run in parallel

---

## File Change Summary

### New Files (8)
1. `home-modules/desktop/i3-project-event-daemon/systemd_query.py`
2. `home-modules/desktop/i3-project-event-daemon/proc_monitor.py`
3. `home-modules/desktop/i3-project-event-daemon/event_correlator.py`
4. `home-modules/desktop/i3-project-event-daemon/migrations/029_add_systemd_proc_fields.sql`
5. `tests/i3-project-daemon/unit/test_systemd_query.py`
6. `tests/i3-project-daemon/unit/test_proc_monitor.py`
7. `tests/i3-project-daemon/unit/test_event_correlator.py`
8. `tests/i3-project-daemon/integration/test_unified_stream.py`

### Modified Files (5)
1. `home-modules/desktop/i3-project-event-daemon/models.py` - EventEntry extensions, EventCorrelation model
2. `home-modules/desktop/i3-project-event-daemon/ipc_server.py` - New IPC methods
3. `home-modules/desktop/i3-project-event-daemon/daemon.py` - ProcessMonitor integration
4. `home-modules/tools/i3pm-deno/src/validation.ts` - Schema extensions
5. `home-modules/tools/i3pm-deno/src/commands/daemon.ts` - CLI flag handling, event formatting

---

## Implementation Strategy

### MVP Delivery (User Story 1 Only)

**Tasks T001-T024** deliver a working MVP:
- systemd journal integration
- Query and display service launches
- Merge with existing i3 events
- Independent test: `i3pm daemon events --source=systemd`

**Time Estimate**: 6-8 hours for MVP

### Incremental Delivery

**After MVP, add US2** (Tasks T025-T043):
- Process monitoring from /proc
- Extends event stream with background processes
- Independent test: `i3pm daemon events --source=proc`

**Time Estimate**: 8-10 hours

**Finally, add US3** (Tasks T044-T060):
- Event correlation
- Advanced debugging capability
- Independent test: `i3pm daemon events --correlate`

**Time Estimate**: 10-12 hours

**Total Estimated Time**: 24-30 hours for complete feature

---

## Validation Criteria

### User Story 1 Acceptance (MVP)
- [ ] systemd events appear with `--source=systemd`
- [ ] Events show proper timestamps and service names
- [ ] Mixed stream with `--source=all` merges chronologically
- [ ] JSON export works with systemd events

### User Story 2 Acceptance
- [ ] Process events appear with `--source=proc`
- [ ] Command lines are sanitized (passwords/tokens hidden)
- [ ] Process monitoring CPU usage <5%
- [ ] Live streaming with `--follow` shows processes in <1s

### User Story 3 Acceptance
- [ ] `--correlate` flag shows parent-child relationships
- [ ] Confidence scores displayed (≥0.5)
- [ ] Time deltas shown between parent and children
- [ ] Correlation accuracy ≥80% for VS Code → rust-analyzer

### Overall Feature Success
- [ ] All three user stories independently testable
- [ ] Performance targets met (CPU <5%, latency <2s)
- [ ] Error handling graceful (missing journalctl, /proc permissions)
- [ ] Documentation complete (README, CLAUDE.md, quickstart.md)

---

## Next Steps

1. **Review tasks**: Ensure all requirements from spec.md are covered
2. **Start with MVP**: Implement Phase 1-3 (Tasks T001-T024) for User Story 1
3. **Test MVP**: Verify acceptance criteria before moving to US2
4. **Iterate**: Add US2, then US3 in sequence
5. **Polish**: Final integration and documentation

**Ready to implement**: Run `/speckit.implement` to begin task-by-task execution
