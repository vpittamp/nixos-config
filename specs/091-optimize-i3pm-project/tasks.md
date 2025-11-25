# Implementation Tasks: Optimize i3pm Project Switching Performance

**Feature**: 091-optimize-i3pm-project
**Branch**: `091-optimize-i3pm-project`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Overview

This feature optimizes i3pm project switching from 5.3 seconds to under 200ms (96% improvement) by parallelizing Sway IPC commands, eliminating duplicate tree queries, and implementing async command batching.

**Tech Stack**: Python 3.11+, i3ipc.aio, asyncio, Pydantic
**Target**: <200ms average project switch (10-20 windows)

## Implementation Strategy

**MVP Scope** (User Story 1 only):
- Parallel window hide/restore commands
- Basic performance instrumentation
- Validates 96% improvement target

**Incremental Delivery**:
1. **US1** (P1): Instant project switching (<200ms) - Core optimization
2. **US2** (P2): Consistent performance across window counts - Scaling validation
3. **US3** (P3): Notification callback integration - Feature 090 benefit

Each user story is independently testable and deployable.

---

## Phase 1: Setup & Infrastructure

**Goal**: Prepare project structure and dependencies for optimization implementation

- [X] T001 Create test directory structure for Feature 091 in `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/tests/091-optimize-i3pm-project/`
- [X] T002 Create benchmark directory in `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/tests/091-optimize-i3pm-project/benchmarks/`
- [X] T003 Create baseline benchmark script `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/tests/091-optimize-i3pm-project/benchmarks/benchmark_project_switch.sh` to capture current 5.3s baseline
- [X] T004 Run baseline benchmark and save results to `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/tests/091-optimize-i3pm-project/benchmarks/baseline_results.json`

---

## Phase 2: Foundational Components

**Goal**: Implement reusable services and data models required by all user stories

### Data Models (Blocking)

- [X] T005 Create `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/home-modules/desktop/i3-project-event-daemon/models/window_command.py` with WindowCommand and CommandType models
- [X] T006 Create `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/home-modules/desktop/i3-project-event-daemon/models/performance_metrics.py` with PerformanceMetrics model
- [X] T007 Add CommandBatch model to `window_command.py` with batching logic

### Core Services (Blocking)

- [X] T008 Create `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/home-modules/desktop/i3-project-event-daemon/services/command_batch.py` with CommandBatchService class
- [X] T009 Implement `execute_parallel()` method in CommandBatchService using asyncio.gather()
- [X] T010 Implement `execute_batch()` method in CommandBatchService for semicolon-chained commands
- [X] T011 Create `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/home-modules/desktop/i3-project-event-daemon/services/tree_cache.py` with TreeCacheService class
- [X] T012 Implement tree caching with 100ms TTL and event-driven invalidation in TreeCacheService
- [X] T013 Create `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/home-modules/desktop/i3-project-event-daemon/services/performance_tracker.py` with PerformanceTrackerService class

---

## Phase 3: User Story 1 - Instant Project Switching (P1)

**Goal**: Achieve <200ms project switch time for typical workloads (10-20 windows)

**Independent Test**: Switch between two projects with 10-15 windows each and measure time from command initiation to completion. Success = average <200ms over 10 runs.

**Why MVP**: This is the core performance optimization. Completing just this story delivers immediate 96% improvement and validates the parallelization approach.

### Implementation Tasks

- [X] T014 [US1] Backup current `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/home-modules/desktop/i3-project-event-daemon/services/window_filter.py` to `window_filter.py.backup`
- [X] T015 [US1] Refactor `filter_windows_for_project()` in `window_filter.py` to use TreeCacheService for tree queries
- [X] T016 [US1] Replace sequential hide commands (lines 455-461) with parallel execution using CommandBatchService.execute_parallel()
- [X] T017 [US1] Group window restore operations (lines 380-452) into CommandBatch instances
- [X] T018 [US1] Replace sequential restore commands with parallel batch execution using asyncio.gather()
- [X] T019 [US1] Add PerformanceTrackerService instrumentation to `filter_windows_for_project()`
- [X] T020 [US1] Update daemon event handler to invalidate TreeCache on window/workspace events

### Validation Tasks

- [X] T021 [US1] Run benchmark script and verify average switch time <200ms for 10-window projects
- [X] T022 [US1] Run integration tests in `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/tests/091-optimize-i3pm-project/integration/test_window_filter.py` to verify zero regression in window filtering accuracy
- [X] T023 [US1] Check daemon logs for performance metrics showing parallelization active (2+ parallel batches)
- [X] T024 [US1] Verify scoped/global window semantics preserved (manual test with 2 projects)

---

## Phase 4: User Story 2 - Consistent Scaling Performance (P2)

**Goal**: Maintain sub-300ms performance for projects with up to 40 windows

**Independent Test**: Create test projects with 5, 10, 20, and 40 windows. Benchmark switching to each project. Success = all scenarios meet performance targets (5w:<150ms, 10w:<180ms, 20w:<200ms, 40w:<300ms).

**Dependency**: Requires US1 (parallel execution infrastructure)

### Implementation Tasks

- [X] T025 [US2] Create test projects with varying window counts (5, 10, 20, 40 windows) in `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/tests/091-optimize-i3pm-project/fixtures/`
- [X] T026 [US2] Enhance benchmark script to test all window count scenarios and generate performance report
- [X] T027 [US2] Add window count detection to PerformanceMetrics for per-scenario tracking
- [X] T028 [US2] Implement adaptive batching strategy in CommandBatchService for large window counts (>30 windows)

### Validation Tasks

- [X] T029 [US2] Run multi-scenario benchmark and verify all targets met (see performance table in spec.md)
- [X] T030 [US2] Calculate standard deviation of switch times and verify <50ms across all scenarios
- [X] T031 [US2] Generate performance report showing p95 latency <250ms for 20-window scenario

---

## Phase 5: User Story 3 - Notification Callback Reliability (P3)

**Goal**: Enable Feature 090 callback sleep reduction from 6s to 1s while maintaining 100% reliability

**Independent Test**: Send Claude Code notification from project A, switch to project B, click "Return to Window" button. Success = return to project A completes in <1.5s total (1s sleep + <500ms switch).

**Dependency**: Requires US1 (sub-200ms switching) and US2 (validated scaling)

### Implementation Tasks

- [X] T032 [US3] Update `/etc/nixos/scripts/claude-hooks/swaync-action-callback.sh` line 50 to reduce sleep from 6s to 1s
- [X] T033 [US3] Add logging to callback script to measure actual project switch completion time

### Validation Tasks

- [X] T034 [US3] Test cross-project notification callback workflow (project A → B → notification → A)
- [X] T035 [US3] Verify 100% success rate over 20 callback test runs
- [X] T036 [US3] Measure total callback time and verify <1.5s average (1s sleep + switching overhead)

---

## Phase 6: Polish & Optimization

**Goal**: Final performance tuning and documentation updates

- [X] T037 Run full benchmark suite across all user stories and generate final performance report
- [X] T038 Update `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/CLAUDE.md` with Feature 091 quickstart commands
- [X] T039 Document performance improvements in commit message for Feature 091 merge
- [X] T040 Clean up backup files (`window_filter.py.backup`) and temporary test fixtures
- [X] T041 Verify daemon restart doesn't break optimizations (systemctl --user restart i3-project-event-listener)

---

## Task Dependencies

```
Setup (T001-T004)
        ↓
Foundational (T005-T013) ← BLOCKING: Required by all user stories
        ↓
    ┌───┴───┐
    ↓       ↓
   US1   Parallel
(T014-T024)  Opportunity
    ↓       ↑
   US2   (Independent,
(T025-T031) can start
    ↓      after US1)
   US3
(T032-T036)
    ↓
  Polish
(T037-T041)
```

**Critical Path**: Setup → Foundational → US1 → US2 → US3 → Polish

**Parallel Opportunities**:
- Within US1: T016, T017 can be developed in parallel (different code sections)
- Within US2: T027, T028 can be developed in parallel (independent enhancements)
- US1 validation (T021-T024) can run in parallel with US2 planning

---

## Parallel Execution Examples

### US1 Parallel Development

**Session 1** (Core Parallelization):
- T016: Parallelize hide commands
- T018: Parallelize restore commands

**Session 2** (Infrastructure):
- T015: Tree cache integration
- T019: Performance instrumentation

**Session 3** (Validation):
- T021: Benchmark validation
- T022: Integration tests

### US2 Parallel Development

**Session 1** (Test Infrastructure):
- T025: Create test projects
- T026: Enhance benchmark script

**Session 2** (Optimization):
- T027: Window count tracking
- T028: Adaptive batching

---

## Validation Criteria

### US1 Success Criteria
- ✅ Average switch time <200ms (10-window projects)
- ✅ Zero regression in window filtering (scoped/global semantics preserved)
- ✅ Performance logs show parallelization active (>1 parallel batches)
- ✅ Tree cache hit rate >80%

### US2 Success Criteria
- ✅ Performance targets met for all window counts (see spec.md table)
- ✅ Standard deviation <50ms
- ✅ P95 latency <250ms

### US3 Success Criteria
- ✅ Feature 090 callback completes in <1.5s total
- ✅ 100% success rate over 20 test runs
- ✅ No regression in notification functionality

---

## Testing Strategy

**Integration Tests** (Zero Regression):
- `/tests/091-optimize-i3pm-project/integration/test_window_filter.py`
  - Test scoped window filtering
  - Test global window filtering
  - Test window state restoration (workspace, floating, geometry)

**Performance Tests** (Benchmark Validation):
- `/tests/091-optimize-i3pm-project/benchmarks/benchmark_project_switch.sh`
  - Baseline: 5.3s (captured in T004)
  - Target: <200ms average
  - Multi-scenario: 5w, 10w, 20w, 40w window counts

**Manual Tests** (Feature 090 Integration):
- Cross-project notification callback (T034-T036)
- Daemon restart validation (T041)

---

## Summary

**Total Tasks**: 41
- Setup: 4 tasks
- Foundational: 9 tasks
- US1 (P1): 11 tasks
- US2 (P2): 7 tasks
- US3 (P3): 5 tasks
- Polish: 5 tasks

**MVP Scope**: Setup + Foundational + US1 = 24 tasks (59% of total)
**Parallel Opportunities**: 8 tasks marked [P], 3 parallel development sessions per story

**Estimated Timeline**:
- MVP (US1): ~6-8 hours (core optimization + validation)
- US2: ~3-4 hours (scaling validation + adaptive batching)
- US3: ~1-2 hours (callback integration)
- Total: ~10-14 hours

**Risk Mitigation**:
- Early benchmark baseline (T003-T004) validates optimization approach
- Integration tests (T022) ensure zero regression
- Incremental delivery enables rollback if issues arise
