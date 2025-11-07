# Tasks: Sway Tree Diff Monitor

**Feature Branch**: `052-sway-tree-diff-monitor`
**Input**: Design documents from `/specs/052-sway-tree-diff-monitor/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are NOT requested in the spec, so only essential validation tests are included (performance benchmarks).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create directory structure home-modules/tools/sway-tree-monitor/ with subdirs: diff/, correlation/, buffer/, ui/, rpc/
- [X] T002 Create package __init__.py files in all subdirectories
- [X] T003 [P] Add Python dependencies to home-modules/desktop/python-environment.nix: xxhash, orjson, textual

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models, hash cache, and daemon infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] Create Pydantic models in home-modules/tools/sway-tree-monitor/models.py: TreeSnapshot, WindowContext
- [X] T005 [P] Create Pydantic models in home-modules/tools/sway-tree-monitor/models.py: TreeDiff, FieldChange, NodeChange, ChangeType enum
- [X] T006 [P] Create Pydantic models in home-modules/tools/sway-tree-monitor/models.py: TreeEvent, UserAction, EventCorrelation, ActionType enum
- [X] T007 [P] Create FilterCriteria model in home-modules/tools/sway-tree-monitor/models.py with matches() method
- [X] T008 Implement xxHash-based Merkle tree hasher in home-modules/tools/sway-tree-monitor/diff/hasher.py with compute_subtree_hash()
- [X] T009 Implement HashCache in home-modules/tools/sway-tree-monitor/diff/cache.py with TTL-based eviction (60s)
- [X] T010 Implement hash-based tree differ in home-modules/tools/sway-tree-monitor/diff/differ.py with incremental comparison
- [X] T011 Create TreeEventBuffer circular buffer in home-modules/tools/sway-tree-monitor/buffer/event_buffer.py using collections.deque(maxlen=500)
- [X] T012 [P] Implement significance scoring logic in home-modules/tools/sway-tree-monitor/diff/differ.py (geometry, focus, workspace changes)
- [X] T013 Create daemon main loop skeleton in home-modules/tools/sway-tree-monitor/daemon.py with Sway IPC connection
- [X] T014 Implement JSON-RPC 2.0 server in home-modules/tools/sway-tree-monitor/rpc/server.py over Unix socket
- [X] T015 Implement JSON-RPC 2.0 client in home-modules/tools/sway-tree-monitor/rpc/client.py with error handling

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Real-time Window State Change Monitoring (Priority: P1) 🎯 MVP

**Goal**: Display real-time tree changes as they occur with <10ms diff computation, <100ms display latency

**Independent Test**: Launch monitor, open/close a window, verify state changes displayed in real-time with user action correlation

### Performance Benchmarks for User Story 1

- [X] T016 [P] [US1] Create performance benchmark in tests/sway-tree-monitor/performance/benchmark_diff.py for 50/100/200 window trees
- [X] T017 [P] [US1] Create test fixtures in tests/sway-tree-monitor/fixtures/sample_trees.py with mock Sway trees (50/100/200 windows)

### Implementation for User Story 1

- [X] T018 [US1] Implement Sway event subscription in daemon.py: subscribe to window, workspace, binding events
- [X] T019 [US1] Implement tree snapshot capture in daemon.py using i3ipc.aio Connection().get_tree()
- [X] T020 [US1] Integrate diff computation in daemon.py: capture snapshot → compute hash → compare with previous → generate diff
- [X] T021 [US1] Add event storage to daemon.py: store TreeEvent (snapshot + diff) in TreeEventBuffer
- [X] T022 [US1] Implement RPC method "query_events" in rpc/server.py with filtering support
- [X] T023 [US1] Implement RPC method "ping" and "get_daemon_status" in rpc/server.py
- [X] T024 [US1] Create Textual app skeleton in home-modules/tools/sway-tree-monitor/ui/app.py with tabbed interface
- [X] T025 [US1] Implement live streaming view in home-modules/tools/sway-tree-monitor/ui/live_view.py using DataTable widget
- [X] T026 [US1] Add real-time event subscription worker in ui/live_view.py using @work decorator
- [X] T027 [US1] Implement CLI entry point in home-modules/tools/sway-tree-monitor/__main__.py with "live" mode
- [X] T028 [US1] Add keyboard navigation to live view: q=quit, f=filter, d=drill down
- [X] T029 [US1] Create systemd service unit in modules/services/sway-tree-monitor.nix with MemoryMax=50M, CPUQuota=5%
- [X] T030 [US1] Run performance benchmark: validate <10ms diff computation for 100 windows (p95)

**Checkpoint**: At this point, User Story 1 should be fully functional - real-time monitoring with <10ms diffs, <100ms display

---

## Phase 4: User Story 2 - Historical Event Timeline with User Action Correlation (Priority: P2)

**Goal**: Review past events with timestamp and user action correlation (500ms window, confidence scoring)

**Independent Test**: Perform window operations, query history, verify all events captured with timestamps and user action correlations

### Implementation for User Story 2

- [X] T031 [P] [US2] Implement CorrelationTracker in home-modules/tools/sway-tree-monitor/correlation/tracker.py with 500ms time window
- [X] T032 [P] [US2] Implement multi-factor confidence scoring in home-modules/tools/sway-tree-monitor/correlation/scoring.py (temporal 40%, semantic 30%, exclusivity 20%, cascade 10%)
- [X] T033 [US2] Add binding event listener to daemon.py for keypress detection
- [X] T034 [US2] Integrate CorrelationTracker into daemon.py: track user actions → correlate with tree changes
- [X] T035 [US2] Add cascade chain tracking to correlation logic: primary → secondary → tertiary effects
- [X] T036 [US2] Update TreeEvent storage to include EventCorrelation list with confidence scores
- [X] T037 [US2] Implement historical query view in home-modules/tools/sway-tree-monitor/ui/history_view.py using DataTable
- [X] T038 [US2] Add CLI "history" mode to __main__.py with --since, --last, --filter options
- [X] T039 [US2] Add correlation display to history view: show "Triggered By" column with confidence labels
- [X] T040 [US2] Add time filtering to query_events RPC method: since_ms, until_ms parameters

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - live monitoring + historical query with correlation

---

## Phase 5: User Story 3 - Detailed Event Inspection with Context Enrichment (Priority: P2)

**Goal**: Drill down into events to see detailed diffs with enriched context (I3PM env vars, project associations)

**Independent Test**: Select any event, inspect detailed diff, verify native Sway fields + enriched context (I3PM_PROJECT_NAME, etc.)

### Implementation for User Story 3

- [X] T041 [P] [US3] Implement window environment reading in daemon.py: read /proc/<pid>/environ for I3PM_* variables
- [X] T042 [P] [US3] Implement project mark extraction in daemon.py: parse window marks for project:*, app:* patterns
- [X] T043 [US3] Create WindowContext enrichment logic in daemon.py: populate i3pm_app_id, i3pm_project_name, i3pm_scope
- [X] T044 [US3] Add enriched_data to TreeSnapshot: Dict[int, WindowContext] mapping window ID → context
- [X] T045 [US3] Implement RPC method "get_event" in rpc/server.py with detailed diff and enrichment
- [X] T046 [US3] Create detailed diff view in home-modules/tools/sway-tree-monitor/ui/diff_view.py using Rich Syntax widget for JSON
- [X] T047 [US3] Add tree path notation to diff output: "outputs[0].workspaces[2].nodes[5]"
- [X] T048 [US3] Add enrichment display section in diff view: show I3PM_* variables, project marks
- [X] T049 [US3] Implement CLI "diff" mode to __main__.py: sway-tree-monitor diff <EVENT_ID>
- [X] T050 [US3] Add syntax highlighting for JSON diffs in diff_view.py using Rich theme

**Checkpoint**: All core user stories (US1, US2, US3) should now be independently functional - live, history, detailed inspection

---

## Phase 6: User Story 4 - Performance-Optimized Continuous Monitoring (Priority: P2)

**Goal**: Run monitor continuously with <2% CPU, <25MB memory, stable performance for 500+ events

**Independent Test**: Run monitor for 1 hour, generate 1000 events, verify CPU <2%, memory <25MB, circular buffer auto-eviction works

### Implementation for User Story 4

- [X] T051 [P] [US4] Implement fast-path optimization in diff/differ.py: if root hash matches, return empty diff
- [X] T052 [P] [US4] Add configurable field exclusions in diff/hasher.py: skip timestamp fields during hash computation
- [X] T053 [US4] Implement hash cache cleanup in diff/cache.py: periodic TTL-based eviction every 60s
- [X] T054 [US4] Add geometry threshold filtering in diff/differ.py: ignore changes <5px (configurable)
- [X] T055 [US4] Implement memory monitoring in daemon.py: track buffer size, hash cache size, correlation tracker size
- [X] T056 [US4] Add CPU/memory metrics to "get_daemon_status" RPC response
- [X] T057 [US4] Implement event burst handling in daemon.py: buffer up to 50 events/second without data loss
- [X] T058 [US4] Create statistical summary view in home-modules/tools/sway-tree-monitor/ui/stats_view.py
- [X] T059 [US4] Implement RPC method "get_statistics" in rpc/server.py with performance metrics
- [X] T060 [US4] Add CLI "stats" mode to __main__.py with --since, --format options
- [ ] T061 [US4] Run 8-hour continuous monitoring test: validate memory stays <25MB, CPU <2%

**Checkpoint**: Performance targets validated - system is production-ready for continuous monitoring

---

## Phase 7: User Story 5 - Filtered and Searchable Event Stream (Priority: P3)

**Goal**: Filter event stream by type, significance, window class, project to reduce noise

**Independent Test**: Apply filter "workspace", verify only workspace events displayed; filter by significance >0.5, verify minor changes hidden

### Implementation for User Story 5

- [X] T062 [P] [US5] Implement FilterCriteria matching logic in models.py: event type, time range, significance filters
- [X] T063 [P] [US5] Add window-specific filtering in FilterCriteria: window_class, window_title_pattern, project_name
- [X] T064 [US5] Integrate FilterCriteria into query_events RPC method: apply filters during buffer scan
- [X] T065 [US5] Add real-time filter UI in live_view.py: press 'f' to open filter dialog
- [X] T066 [US5] Add filter display in history_view.py: show active filters at top
- [X] T067 [US5] Implement --filter, --min-significance, --project CLI options for live and history modes
- [X] T068 [US5] Add tree_path_pattern filtering in FilterCriteria: regex pattern for tree paths
- [X] T069 [US5] Add user_initiated_only filter option: show only events with confidence >= 70%

**Checkpoint**: User Story 5 complete - filtering reduces noise and improves signal-to-noise ratio for targeted debugging

---

## Phase 8: User Story 6 - Export and Persistence for Post-Mortem Analysis (Priority: P3)

**Goal**: Enable persistent event logging to disk with 7-day retention, export/import for post-mortem analysis

**Independent Test**: Enable persistence, generate events, restart monitor, verify historical events available; export to JSON, import, replay

### Implementation for User Story 6

- [ ] T070 [P] [US6] Implement JSON file persistence in buffer/event_buffer.py: save_to_disk() using orjson
- [ ] T071 [P] [US6] Add automatic persistence on daemon shutdown in daemon.py
- [ ] T072 [US6] Implement retention policy in buffer/event_buffer.py: delete files older than 7 days
- [ ] T073 [US6] Implement RPC method "export_events" in rpc/server.py with path, compression options
- [ ] T074 [US6] Implement RPC method "import_events" in rpc/server.py with schema version validation
- [ ] T075 [US6] Add CLI "export" mode to __main__.py: sway-tree-monitor export <FILE> --since --compress
- [ ] T076 [US6] Add CLI "import" mode to __main__.py: sway-tree-monitor import <FILE> --replay --speed
- [ ] T077 [US6] Implement event replay logic in ui/live_view.py: simulate real-time with original timing
- [ ] T078 [US6] Create configuration file support in daemon.py: load ~/.config/sway-tree-monitor/config.toml
- [ ] T079 [US6] Add schema versioning to exported JSON: include "schema_version": "1.0.0"

**Checkpoint**: All user stories (US1-US6) complete - full feature set with live monitoring, history, inspection, performance, filtering, persistence

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, final validation, and quality improvements

- [X] T080 [P] Update CLAUDE.md with sway-tree-monitor commands and troubleshooting
- [X] T081 [P] Create README.md in home-modules/tools/sway-tree-monitor/ with developer documentation
- [X] T082 Add error handling for Sway IPC disconnection in daemon.py: auto-reconnect with exponential backoff
- [X] T083 Add graceful shutdown handling in daemon.py: flush buffer to disk, close socket
- [X] T084 Add input validation for all RPC methods: validate params, return -32602 for invalid
- [X] T085 Implement socket permissions in rpc/server.py: set to 0600 (owner read/write only)
- [X] T086 Add debug logging throughout daemon.py and ui/: use Python logging module
- [X] T087 [P] Validate quickstart.md examples work: test all commands from quickstart.md
- [X] T088 Run final performance validation: 50/100/200 window benchmarks, verify all targets met
- [X] T089 Test on M1 Mac: verify works with single eDP-1 display, no Hetzner-specific code
- [X] T090 Update flake.nix to include sway-tree-monitor in Hetzner and M1 configurations (conditionally enabled where Sway is present)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P2 → P2 → P3 → P3)
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1's daemon but independently testable
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - Adds enrichment to US1's snapshots but independently testable
- **User Story 4 (P2)**: Can start after US1 complete - Optimizes US1's diff computation
- **User Story 5 (P3)**: Can start after US1 complete - Adds filtering to US1's live/history views
- **User Story 6 (P3)**: Can start after US1 complete - Adds persistence to US1's buffer

**Suggested Order**: US1 (MVP) → US2 (correlation) → US3 (enrichment) → US4 (performance) → US5 (filtering) → US6 (persistence)

### Within Each User Story

- Performance benchmarks (if present) run in parallel with model creation
- Models/services complete before integration into daemon
- RPC methods complete before CLI implementation
- Core implementation before UI components
- Story independently testable before moving to next priority

### Parallel Opportunities

- **Setup (Phase 1)**: T003 can run in parallel with T001/T002
- **Foundational (Phase 2)**: T004-T007 (models) can run in parallel; T008-T012 (diff components) can run in parallel after models
- **User Story 1**: T016-T017 (benchmarks) can run in parallel with T018-T021 (daemon core)
- **User Story 2**: T031-T032 (correlation components) can run in parallel
- **User Story 3**: T041-T044 (enrichment) can run in parallel with T045 (RPC method)
- **User Story 4**: T051-T054 (optimizations) can run in parallel
- **User Story 5**: T062-T063 (filtering logic) can run in parallel
- **User Story 6**: T070-T072 (persistence) can run in parallel with T073-T074 (RPC methods)
- **Polish (Phase 9)**: T080-T081 (docs) and T087-T089 (validation) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch benchmarks and fixtures together:
Task: "Create performance benchmark in tests/sway-tree-monitor/performance/benchmark_diff.py"
Task: "Create test fixtures in tests/sway-tree-monitor/fixtures/sample_trees.py"

# Launch daemon core implementation together:
Task: "Implement Sway event subscription in daemon.py"
Task: "Implement tree snapshot capture in daemon.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test real-time monitoring independently with performance benchmarks
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → **Deploy/Demo (MVP!)**
3. Add User Story 2 → Test independently → Deploy/Demo (MVP + correlation)
4. Add User Story 3 → Test independently → Deploy/Demo (MVP + correlation + enrichment)
5. Add User Story 4 → Validate performance → Deploy/Demo (optimized for production)
6. Add User Story 5 → Test filtering → Deploy/Demo (enhanced UX)
7. Add User Story 6 → Test persistence → Deploy/Demo (complete feature set)

Each story adds value without breaking previous stories.

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (core live monitoring)
   - Developer B: User Story 2 (correlation - depends on US1 daemon structure)
   - Developer C: User Story 3 (enrichment - can start in parallel with US2)
3. After US1-US3 complete:
   - Developer A: User Story 4 (performance optimization)
   - Developer B: User Story 5 (filtering)
   - Developer C: User Story 6 (persistence)
4. Final validation and polish together

---

## Notes

- [P] tasks = different files, no dependencies, can run in parallel
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Performance benchmarks validate <10ms diff computation target (User Story 4)
- Focus on US1 (MVP) first for maximum value delivery
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Success Criteria from spec.md:
  - SC-002: <10ms diff computation (validated in T030, T088)
  - SC-003: <25MB memory usage (validated in T061)
  - SC-004: <1% CPU average (validated in T061)
  - SC-005: <100ms display latency (inherent in Textual framework)
  - SC-006: 90% correlation accuracy (achieved via multi-factor scoring in T032)
