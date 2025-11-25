# Implementation Plan: Optimize i3pm Project Switching Performance

**Branch**: `091-optimize-i3pm-project` | **Date**: 2025-11-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/091-optimize-i3pm-project/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Optimize i3pm project switching from 5.3 seconds to under 200ms by parallelizing Sway IPC commands using `asyncio.gather()`, eliminating duplicate tree queries via caching, and implementing async command batching in the window filter daemon. This 96% performance improvement enables Feature 090's notification callback sleep time to be reduced from 6 seconds to 1 second, improving cross-project navigation responsiveness.

## Technical Context

**Language/Version**: Python 3.11+ (existing daemon standard per Constitution Principle X)
**Primary Dependencies**: i3ipc.aio (async Sway IPC client), asyncio (parallelization), Pydantic (data validation)
**Storage**: In-memory daemon state (no persistence changes required)
**Testing**: pytest with pytest-asyncio for async test support, benchmark scripts for performance validation
**Target Platform**: Linux with Sway 1.8+ window manager, NixOS deployment
**Project Type**: Single project (Python daemon modification in existing i3pm system)
**Performance Goals**: <200ms average project switch (5 windows), <300ms (40 windows), 96% improvement from 5.3s baseline
**Constraints**: Zero regression in window filtering accuracy, maintain existing scoped/global semantics, <100ms latency overhead per window operation
**Scale/Scope**: 10-40 windows per project (typical usage), support for up to 100 windows (upper bound)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Compliance Review

✅ **Principle X (Python Development & Testing Standards)**:
- Uses Python 3.11+ with async/await patterns (i3ipc.aio, asyncio)
- Testing framework: pytest with pytest-asyncio
- Uses existing daemon architecture (no new daemon required)
- Type hints and Pydantic models for data validation
- Follows single-responsibility principle (window_filter.py focused on window visibility logic)

✅ **Principle XI (i3 IPC Alignment & State Authority)**:
- Sway IPC is authoritative source of truth (no custom state tracking changes)
- Event-driven architecture via i3 IPC subscriptions (preserved)
- Uses GET_TREE, GET_WORKSPACES, GET_OUTPUTS for state queries
- All window commands use Sway IPC COMMAND message type

✅ **Principle XII (Forward-Only Development & Legacy Elimination)**:
- Complete replacement of sequential command pattern with parallel pattern
- No backwards compatibility layers or feature flags
- Old sequential code will be removed when parallel version is implemented
- Clean break to optimal solution

✅ **Principle XIV (Test-Driven Development & Autonomous Testing)**:
- Benchmark suite will validate performance targets (5 window, 10 window, 20 window, 40 window scenarios)
- Integration tests will verify zero regression in window filtering accuracy
- State verification via Sway IPC tree queries
- Automated test execution in headless environment

### Gates

- ✅ **Gate 1**: No new daemon process required (modifies existing i3-project-event-daemon)
- ✅ **Gate 2**: No new storage mechanism required (in-memory state only)
- ✅ **Gate 3**: Test framework already established (pytest, i3ipc.aio)
- ✅ **Gate 4**: Performance improvement aligns with Feature 090 (notification callback)

## Project Structure

###  Documentation (this feature)

```text
specs/091-optimize-i3pm-project/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/desktop/i3-project-event-daemon/
├── services/
│   ├── window_filter.py           # MODIFIED: Parallel command execution (lines 325-541)
│   ├── command_batch.py            # NEW: Async command batching service
│   └── tree_cache.py               # NEW: Tree query cache with TTL
├── models/
│   ├── window_command.py           # NEW: Window command data models
│   └── performance_metrics.py      # NEW: Performance tracking models
└── __init__.py

tests/091-optimize-i3pm-project/
├── unit/
│   ├── test_command_batch.py      # Unit tests for command batching logic
│   ├── test_tree_cache.py         # Unit tests for tree caching
│   └── test_window_command.py     # Unit tests for command models
├── integration/
│   ├── test_parallel_commands.py  # Integration test for asyncio.gather() parallelization
│   └── test_window_filter.py      # Regression tests for window filtering accuracy
├── benchmarks/
│   ├── benchmark_project_switch.sh  # Benchmark script (5/10/20/40 window scenarios)
│   └── benchmark_results.json       # Baseline and target performance data
└── fixtures/
    └── mock_sway_tree.py           # Mock Sway tree structures for testing
```

**Structure Decision**: Single project structure (Option 1) because this feature modifies an existing daemon service (`window_filter.py`) and adds supporting services (`command_batch.py`, `tree_cache.py`). No separate frontend/backend or multi-platform components required.

## Complexity Tracking

> **No complexity violations detected** - this feature operates within existing daemon architecture and follows established patterns.

---

## Phase 0: Outline & Research (Generated Below)

Research tasks will investigate:
1. **asyncio.gather() patterns** for parallel Sway IPC command execution
2. **i3ipc.aio concurrency limits** and race condition handling
3. **Tree caching strategies** with TTL (time-to-live) expiration
4. **Command batching** for independent operations (move, resize, floating enable/disable)
5. **Performance instrumentation** for sub-200ms validation

## Phase 1: Design & Contracts (Generated Below)

Design artifacts will include:
1. **data-model.md**: WindowCommand, CommandBatch, TreeCache, PerformanceMetrics models
2. **contracts/**: Internal service APIs (CommandBatchService, TreeCacheService)
3. **quickstart.md**: User-facing guide for validating performance improvements

## Key Implementation Highlights

### Primary Bottleneck (Identified)

**File**: `home-modules/desktop/i3-project-event-daemon/services/window_filter.py`
**Lines**: 325-541
**Issue**: Sequential `await conn.command()` calls execute 60+ Sway IPC commands one-at-a-time

**Example Sequential Pattern** (Current):
```python
for window in windows:
    await conn.command(f'[con_id={window_id}] move workspace number {workspace_num}')
    await conn.command(f'[con_id={window_id}] floating enable')
    await conn.command(f'[con_id={window_id}] resize set {width} px {height} px')
```

**Optimized Parallel Pattern** (Target):
```python
commands = [
    conn.command(f'[con_id={w.id}] move workspace number {w.workspace}')
    for w in windows_to_restore
]
await asyncio.gather(*commands)
```

### Optimization Strategies

1. **Parallelization** (Primary - 50-65% improvement):
   - Use `asyncio.gather()` to execute independent window commands concurrently
   - Group commands by operation type (move, resize, floating, focus)
   - Maintain order-dependency where required (e.g., floating enable before resize)

2. **Tree Query Caching** (Secondary - 10-15% improvement):
   - Cache Sway tree snapshots with 100ms TTL
   - Eliminate duplicate `get_tree()` calls within single switch operation
   - Invalidate cache on relevant Sway events (window close, workspace change)

3. **Command Batching** (Tertiary - 5-10% improvement):
   - Batch multiple commands into single Sway IPC message where possible
   - Example: `move workspace 5; floating enable; resize set 800 600`
   - Reduce round-trip latency for multi-step window operations

### Feature 090 Integration

**Benefit**: Reduced project switch time enables Feature 090 notification callback to use 1-second sleep instead of 6 seconds.

**File**: `/etc/nixos/scripts/claude-hooks/swaync-action-callback.sh`
**Line**: 50
**Change**: `sleep 6` → `sleep 1` (after Feature 091 implementation)

---

## Next Steps

1. **Phase 0**: Run research agents to investigate asyncio.gather() patterns and i3ipc.aio concurrency
2. **Phase 1**: Generate data models, service contracts, and quickstart documentation
3. **Phase 2**: Generate tasks.md with dependency-ordered implementation steps (via `/speckit.tasks`)
4. **Implementation**: Execute tasks, run benchmarks, validate performance targets
5. **Validation**: Reduce Feature 090 sleep time and verify notification callback reliability
