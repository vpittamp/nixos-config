# Implementation Plan: Synchronization-Based Test Framework

**Branch**: `069-sync-test-framework` | **Date**: 2025-11-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/069-sync-test-framework/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance the sway-test framework with synchronization primitives inspired by i3 testsuite to eliminate race conditions in window manager testing. The core issue: test code queries X11 state before Sway IPC commands have completed X11 processing, causing ~10% flaky test failures. Solution: Implement `sync()` method using Sway's mark/unmark IPC commands as synchronization barriers, guaranteeing X11 state consistency before assertions. Expected impact: 50% faster test runtime (50s → 25s), <1% flakiness (from 5-10%), and <10ms sync overhead per operation.

## Technical Context

**Language/Version**: TypeScript (matching existing sway-test framework), Deno 1.40+
**Primary Dependencies**:
- `@std/cli` (parseArgs for CLI), `@std/fs` (file operations), `@std/path` (path utilities)
- `i3ipc` (Sway IPC - note: may need Node.js binding research or native Deno implementation)
- Existing sway-test framework services (SwayClient, ActionExecutor, StateComparator)

**Storage**: N/A (test framework operates in-memory with JSON test files)
**Testing**: Deno.test() for unit tests, self-hosting test validation (test the tests)
**Target Platform**: NixOS/Linux with Sway Wayland compositor, headless test environments
**Project Type**: Single project (enhancement to existing `home-modules/tools/sway-test/`)
**Performance Goals**:
- Sync operation: <10ms under normal conditions (95th percentile)
- Test suite total runtime: 50s → 25s (50% reduction)
- Individual test speedup: 5-10x faster than timeout-based equivalents
- Zero test hangs (all syncs timeout within 5 seconds if Sway unresponsive)

**Constraints**:
- **Development strategy**: Existing tests continue working during implementation (allows incremental testing)
- **Final product**: ALL timeout-based tests replaced with sync - zero legacy code preserved (Principle XII)
- Sway IPC mark/unmark commands only (no X11 ClientMessage protocol needed - Sway native approach)
- Must work in headless Xvfb/Xephyr environments for CI/CD
- Sync timeout: 5 seconds max (prevents hanging tests)

**Scale/Scope**:
- Target: 50-100 test files in sway-test suite
- Expected usage: 100% of tests use sync actions (final state - no timeout-based tests remain)
- Migration strategy: Convert tests incrementally during development, then **DELETE all wait_event timeout code**

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle XIII: Deno CLI Development Standards ✅ PASS
- Using TypeScript/Deno 1.40+ (matches existing sway-test framework)
- Using @std/cli for parseArgs, @std/fs, @std/path (standard library modules)
- Compiled standalone executable distribution via `deno compile`
- Strict type checking enabled
- Error messages will provide actionable guidance (e.g., "Sync timeout - Sway may be unresponsive")

### Principle XIV: Test-Driven Development & Autonomous Testing ✅ PASS
- Feature enhances autonomous testing capability (eliminates manual timeouts)
- Sync mechanism enables deterministic state verification via Sway IPC
- Tests will be self-validating (test the sync mechanism with sync-based tests)
- Unit tests for sync logic, integration tests for Sway IPC communication
- Follows test pyramid: 70% unit (sync utilities), 20% integration (IPC), 10% e2e (full test scenarios)

### Principle XV: Sway Test Framework Standards ✅ PASS
- Enhances declarative JSON test definitions with new action types (sync, launch_app_sync, send_ipc_sync)
- Maintains Sway IPC as authoritative source (mark/unmark commands for sync)
- Preserves multi-mode state comparison (exact, partial, assertions, empty)
- Undefined semantics remain unchanged (undefined = "don't check")
- TypeScript/Deno implementation (matches framework standards)
- Adds performance-critical feature (50% faster tests, <1% flakiness)

### Principle XII: Forward-Only Development & Legacy Elimination ✅ PASS
**Development strategy**: Existing tests continue working during implementation (pragmatic - allows incremental development/testing)

**Final product** (what ships):
- ✅ ALL timeout-based tests converted to sync-based
- ✅ `wait_event` timeout code DELETED entirely (except for app-specific state, see quickstart.md FAQ)
- ✅ Zero dual code paths (sync is the only way)
- ✅ No "deprecated but supported" patterns
- ✅ Migration complete within feature scope (not left for "someday")

**Justification**: Gradual conversion is a development tactic to maintain working tests during implementation. Final commit MUST delete all legacy timeout patterns - no preservation of old approaches.

### Principle III: Test-Before-Apply ✅ PASS
- Implementation will include unit tests for sync mechanism
- Integration tests for Sway IPC mark/unmark commands
- Performance benchmarks for <10ms sync latency target
- All tests must pass before merging to main

### Complexity Justification
**No violations** - This feature reduces complexity by eliminating arbitrary timeouts and race conditions. Sync mechanism is simpler than timeout tuning.

---

## Post-Design Constitution Re-Evaluation

### Principle XIII: Deno CLI Development Standards ✅ PASS (CONFIRMED)
- ✅ TypeScript implementation with strict types defined (SyncMarker, SyncResult, SyncConfig)
- ✅ Deno standard library usage confirmed (@std/cli, @std/fs, @std/path)
- ✅ Native `Deno.Command` for subprocess (swaymsg wrapper)
- ✅ Comprehensive error handling (timeout errors, IPC errors)
- ✅ Performance tracking built-in (SyncStats with latency metrics)

### Principle XIV: Test-Driven Development ✅ PASS (CONFIRMED)
- ✅ Unit tests planned: sync-manager.test.ts, sync-marker.test.ts
- ✅ Integration tests planned: sway-sync-ipc.test.ts, sync-performance.test.ts
- ✅ Performance benchmarks defined (<10ms p95 latency target)
- ✅ Self-hosting validation (test the sync with sync-based tests)
- ✅ Coverage targets documented (>90% sync-manager, 100% sync-marker)

### Principle XV: Sway Test Framework Standards ✅ PASS (CONFIRMED)
- ✅ Declarative JSON test definitions extended (sync, launch_app_sync, send_ipc_sync)
- ✅ Sway IPC as authoritative source (mark/unmark commands for sync barriers)
- ✅ Multi-mode state comparison preserved (partial, exact, assertions, empty)
- ✅ Undefined semantics unchanged (undefined = "don't check")
- ✅ Enhanced error reporting via existing diff-renderer.ts

### Principle XII: Forward-Only Development ✅ PASS
- ✅ Migration path documented (timeout → sync replacement)
- ✅ **Development tactic**: Tests work during incremental implementation (pragmatic)
- ✅ **Final product**: ALL timeout tests converted, `wait_event` timeout code DELETED
- ✅ **Scope**: Migration completion is PART of this feature (not deferred to future)
- ✅ Zero dual code paths in final state - sync is the only strategy

### Additional Principles Validated

**Principle III: Test-Before-Apply** ✅ PASS
- Implementation plan includes comprehensive test suite
- Unit tests, integration tests, performance benchmarks all specified
- Dry-build required before merging

**Principle I: Modular Composition** ✅ PASS
- Extends existing sway-test framework (no new modules)
- New files: sync-manager.ts (sync logic), sync-marker.ts (model)
- Modified files: sway-client.ts (add sync methods), action-executor.ts (sync actions)
- Single responsibility maintained

**Principle VII: Documentation as Code** ✅ PASS
- ✅ research.md: Protocol analysis, Sway IPC research
- ✅ data-model.md: Complete interface definitions with examples
- ✅ contracts/: Sway IPC sync protocol specification
- ✅ quickstart.md: Migration guide with before/after examples
- ✅ Inline TypeScript documentation with JSDoc comments

### Final Constitution Verdict

**PASS** - All principles satisfied. No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/069-sync-test-framework/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - i3 sync patterns, Sway IPC research
├── data-model.md        # Phase 1 output - SyncMarker, SyncAction models
├── quickstart.md        # Phase 1 output - Migration guide, usage examples
├── contracts/           # Phase 1 output - Sway IPC sync contract
│   └── sway-sync-protocol.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (existing sway-test framework)

```text
home-modules/tools/sway-test/
├── deno.json                          # Deno configuration (tasks, imports, compiler options)
├── main.ts                            # Entry point with parseArgs() CLI handling
├── mod.ts                             # Public API exports
├── src/
│   ├── commands/
│   │   ├── run.ts                     # Test runner - MODIFIED (add sync action support)
│   │   └── validate.ts                # Test validation
│   ├── services/
│   │   ├── sway-client.ts             # Sway IPC client - MODIFIED (add sync() method)
│   │   ├── action-executor.ts         # Test action execution - MODIFIED (sync actions)
│   │   ├── state-extractor.ts         # Feature 068: Partial state extraction
│   │   ├── state-comparator.ts        # Multi-mode comparison
│   │   └── sync-manager.ts            # NEW: Sync mechanism implementation
│   ├── models/
│   │   ├── test-case.ts               # Test definition schema - MODIFIED (new action types)
│   │   ├── test-result.ts             # Test result types
│   │   ├── state-snapshot.ts          # Sway state types
│   │   └── sync-marker.ts             # NEW: SyncMarker model
│   └── ui/
│       ├── diff-renderer.ts           # Feature 068: Enhanced error messages
│       └── reporter.ts                # Test result reporting
└── tests/
    ├── unit/
    │   ├── sync-manager.test.ts       # NEW: Unit tests for sync mechanism
    │   └── sync-marker.test.ts        # NEW: Unit tests for marker generation
    ├── integration/
    │   ├── sway-sync-ipc.test.ts      # NEW: Integration test for Sway IPC sync
    │   └── sync-performance.test.ts   # NEW: Performance benchmarks (<10ms target)
    └── sway-tests/                    # Example test cases
        ├── test_sync_basic.json       # NEW: Basic sync test
        ├── test_firefox_workspace_sync.json  # NEW: Firefox workspace with sync
        └── test_sync_timeout.json     # NEW: Timeout handling test
```

**Structure Decision**: Enhancement to existing sway-test framework (single project). Modified files: `sway-client.ts` (add sync method), `action-executor.ts` (sync actions), `test-case.ts` (action type definitions). New files: `sync-manager.ts` (core sync logic), `sync-marker.ts` (marker model), plus comprehensive tests. No new top-level directories - all changes within existing `home-modules/tools/sway-test/` structure.
