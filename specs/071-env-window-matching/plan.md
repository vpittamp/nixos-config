# Implementation Plan: Environment Variable-Based Window Matching

**Branch**: `057-env-window-matching` | **Date**: 2025-11-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/etc/nixos/specs/057-env-window-matching/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Replace multi-level fallback window matching logic (app_id → window class → title) with deterministic environment variable-based identification using I3PM_* variables injected at application launch. This feature validates 100% environment variable coverage, benchmarks /proc filesystem query performance (<10ms target), and simplifies window identification logic by reading I3PM_APP_ID, I3PM_APP_NAME, I3PM_PROJECT_NAME, I3PM_SCOPE from process environment instead of window properties. Enables reliable multi-instance tracking, deterministic project association, and layout restoration without race conditions from non-deterministic window properties.

**Test-Driven Approach**: Following **Principle XIV: Test-Driven Development & Autonomous Testing**, all tests are written BEFORE implementation with autonomous execution via pytest-asyncio, Sway IPC state verification, and /proc filesystem validation.

---

## Technical Context

**Language/Version**: Python 3.11+ (existing i3pm daemon runtime)
**Primary Dependencies**: i3ipc-python (i3ipc.aio for async Sway IPC), asyncio, existing i3pm daemon infrastructure
**Storage**: In-memory event tracking with persistent assignment configuration in JSON
**Testing**: pytest with pytest-asyncio for async testing, benchmark scripts for latency validation, autonomous test execution via Sway IPC + /proc verification
**Target Platform**: NixOS with Sway/Wayland compositor (Hetzner Cloud, M1 MacBook Pro)
**Project Type**: System daemon enhancement - single project with modular services
**Performance Goals**: <10ms average latency for /proc/<pid>/environ reads, <100ms for 50-window filtering, <20ms with parent traversal
**Constraints**: Must maintain 100% environment variable coverage, zero regression in window management, backward incompatible (no legacy support required)
**Scale/Scope**: Support 100+ concurrent windows, handle rapid window creation (<100ms between launches), parent process traversal up to 3 levels

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Principle I: Modular Composition
**Status**: COMPLIANT
**Rationale**: Feature enhances existing i3pm daemon module with focused responsibility (environment-based window identification). Changes isolated to window matching service layer, no duplication across configurations.

### ✅ Principle II: Reference Implementation Flexibility
**Status**: COMPLIANT
**Rationale**: Implementation targets Sway/Wayland reference configuration (hetzner-sway.nix). Testing on M1 MacBook Pro validates cross-platform compatibility within Sway ecosystem.

### ✅ Principle III: Test-Before-Apply
**Status**: COMPLIANT
**Rationale**: pytest-based automated tests for environment variable parsing, performance benchmarks for validation, manual testing via i3pm windows and daemon commands.

### ✅ Principle X: Python Development & Testing Standards
**Status**: COMPLIANT
**Rationale**: Python 3.11+ async/await patterns via i3ipc.aio, pytest with pytest-asyncio for testing, type hints for window environment models, performance benchmarking with latency metrics.

### ✅ Principle XI: i3 IPC Alignment & State Authority
**Status**: COMPLIANT
**Rationale**: Uses Sway IPC (i3-compatible protocol) for window tree queries, validates PID availability via window properties, maintains event-driven architecture for window lifecycle.

### ✅ Principle XII: Forward-Only Development & Legacy Elimination
**Status**: COMPLIANT - **KEY PRINCIPLE FOR THIS FEATURE**
**Rationale**: Explicitly removes all legacy window matching code (app_id, window class, title fallbacks) without backward compatibility. Replaces suboptimal multi-level fallback logic with optimal environment-based identification. No feature flags or dual code paths.

### ✅ Principle XIV: Test-Driven Development & Autonomous Testing
**Status**: COMPLIANT - **NEW CONSTITUTIONAL REQUIREMENT**
**Rationale**: All tests written BEFORE implementation (test-first approach). Comprehensive test pyramid: unit tests (70% - environment parsing, data models), integration tests (20% - Sway IPC + /proc), end-to-end tests (10% - full workflows). Autonomous test execution via pytest with Sway IPC state verification and /proc filesystem validation. No manual testing required - tests run headlessly in CI/CD. Test iteration loop: spec → write tests → implement → run tests → fix → repeat until passing.

**Test Automation Details**:
- **State verification strategy**: Sway IPC GET_TREE queries for window validation, /proc/<pid>/environ reads for environment verification
- **No UI simulation needed**: All tests use programmatic application launch + state verification
- **Autonomous execution**: Tests create/cleanup resources (launch apps, query state, validate coverage)
- **Performance validation**: Benchmark tests with statistical assertions (p95 < 10ms)
- **Coverage validation**: Parametrized tests across all registered applications (100% coverage target)

### Constitution Compliance: **PASS** ✅
All relevant principles satisfied. Feature aligns with forward-only development mandate by completely replacing legacy matching logic. Test-driven development ensures correctness before deployment.

---

## Project Structure

### Documentation (this feature)

```text
specs/057-env-window-matching/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/tools/i3pm/
├── __init__.py                          # Package initialization
├── __main__.py                          # CLI entry point
├── daemon/
│   ├── __init__.py
│   ├── event_listener.py                # Main daemon with i3 IPC subscriptions
│   ├── window_environment.py            # NEW: Environment variable parser
│   ├── window_matcher.py                # MODIFIED: Environment-based matching logic
│   ├── window_filter.py                 # MODIFIED: Use env vars for filtering
│   ├── workspace_assigner.py            # MODIFIED: Use env vars for assignment
│   └── models.py                        # MODIFIED: Add WindowEnvironment model
├── cli/
│   ├── windows.py                       # MODIFIED: Display I3PM_* env vars
│   ├── diagnose.py                      # MODIFIED: Validate env var coverage
│   └── benchmark.py                     # NEW: Performance benchmark tool
└── tests/
    ├── unit/
    │   ├── test_window_environment.py   # NEW: Test env var parsing
    │   └── test_window_matcher.py       # MODIFIED: Test env-based matching
    ├── integration/
    │   ├── test_proc_filesystem.py      # NEW: Test /proc reads
    │   └── test_coverage_validation.py  # NEW: Test 100% coverage
    ├── performance/
    │   ├── test_env_query_benchmark.py  # NEW: Benchmark /proc latency
    │   └── test_batch_query_benchmark.py # NEW: Benchmark bulk queries
    └── scenarios/
        ├── test_env_window_matching.py  # NEW: End-to-end env matching tests
        ├── test_coverage_validation_e2e.py # NEW: Full coverage test
        └── test_project_association_e2e.py # NEW: Project switching tests

scripts/
└── i3pm/
    ├── app-launcher-wrapper.sh          # EXISTING: Already injects I3PM_* vars
    └── firefoxpwa-wrapper.sh            # EXISTING: Already injects I3PM_* for PWAs

home-modules/desktop/
└── app-registry-data.nix                # EXISTING: App definitions with metadata
```

**Structure Decision**: Single project (i3pm daemon enhancement) with focused changes to window matching subsystem. New modules for environment variable parsing and performance benchmarking, modifications to existing matcher/filter/assigner modules to use environment variables instead of window properties. Tests organized by unit (models, parsing), integration (/proc access, coverage), performance (benchmarks), and scenarios (end-to-end workflows). Test-first approach per Principle XIV.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No complexity violations** - Feature follows all constitutional principles without exceptions.

---

## Post-Design Constitution Re-Evaluation

*Re-checked after Phase 1 design completion (2025-11-03)*

### ✅ Principle I: Modular Composition
**Status**: COMPLIANT
**Post-Design Rationale**: Design adds focused `window_environment.py` module (80 lines) and removes `window_identifier.py` (280 lines). Net reduction in code complexity while maintaining single-responsibility principle. No duplication across configurations.

### ✅ Principle III: Test-Before-Apply
**Status**: COMPLIANT
**Post-Design Rationale**: Comprehensive test suite designed across unit (environment parsing), integration (/proc filesystem access), performance (latency benchmarks), and scenarios (end-to-end matching). Benchmark tools validate performance requirements before deployment.

### ✅ Principle X: Python Development & Testing Standards
**Status**: COMPLIANT
**Post-Design Rationale**: Data models use dataclasses with validation (__post_init__), type hints on all public APIs (WindowEnvironment, EnvironmentQueryResult, CoverageReport, PerformanceBenchmark), pytest-asyncio for async testing. Follows existing i3pm daemon patterns.

### ✅ Principle XI: i3 IPC Alignment & State Authority
**Status**: COMPLIANT
**Post-Design Rationale**: Uses Sway IPC to query window.pid for environment lookups. Validates environment variables against I3PM_EXPECTED_CLASS from window properties. Maintains event-driven architecture (window::new triggers environment query).

### ✅ Principle XII: Forward-Only Development & Legacy Elimination
**Status**: COMPLIANT - **FULLY ALIGNED**
**Post-Design Rationale**: Design explicitly removes 280 lines of legacy window_identifier.py without any backward compatibility shims. No feature flags, no dual code paths, no gradual migration. Complete replacement as mandated by Principle XII.

### ✅ Principle XIV: Test-Driven Development & Autonomous Testing
**Status**: COMPLIANT - **FULLY IMPLEMENTED**
**Post-Design Rationale**: Complete test suite designed with autonomous execution strategy:
- **Unit tests (70%)**: WindowEnvironment parsing, validation rules, /proc reader logic - <1s execution
- **Integration tests (20%)**: Sway IPC + /proc integration, app launch coverage, parent traversal - <10s execution
- **Performance tests**: /proc latency benchmarks, batch query benchmarks with statistical assertions - <30s execution
- **End-to-end scenarios (10%)**: Full workflows (window identification, coverage validation, project association) - <60s execution
- **Autonomous execution**: All tests run via `pytest tests/057-env-window-matching/` with zero manual intervention
- **State verification**: Sway IPC GET_TREE queries + /proc/<pid>/environ reads (no UI simulation needed)
- **Test organization**: Clear directory structure (unit/, integration/, performance/, scenarios/)
- **CI/CD ready**: Headless execution, resource cleanup, <2 minute total test suite

### Final Constitution Compliance: **PASS** ✅

**Design Quality Metrics**:
- Lines of code reduced: ~320 lines (280 from window_identifier.py + 40 from simplified handlers)
- Functions removed: 8 major functions (normalize_class, match_window_class, get_window_identity, match_pwa_instance, match_with_registry, etc.)
- Performance improvement: 15-27x faster (0.4ms vs 6-11ms per window)
- Determinism: 100% (environment variables vs fuzzy class matching)
- Test coverage: Comprehensive test pyramid with autonomous execution
- Test execution: <2 minutes for full suite (CI/CD compatible)

**No violations, no complexity justifications required.** Feature exemplifies forward-only development with optimal solution replacing suboptimal legacy code, validated by comprehensive autonomous testing.

---

## Phase 0 & Phase 1 Complete ✅

**Deliverables Generated**:
1. ✅ research.md - Environment variable analysis, technology decisions, performance benchmarks
2. ✅ data-model.md - WindowEnvironment, EnvironmentQueryResult, CoverageReport, PerformanceBenchmark entities
3. ✅ contracts/window_environment_api.md - API specifications for all functions and CLI commands
4. ✅ quickstart.md - User guide with common use cases and troubleshooting
5. ✅ CLAUDE.md updated - Agent context includes new technologies
6. ✅ Constitution re-evaluation - All principles compliant including new Principle XIV
7. ✅ spec.md updated - Test automation strategies, TDD workflow, autonomous execution plan

**Test-Driven Development Plan**:
- **Phase 0 Complete**: Test suite designed with autonomous execution strategy
- **Next Phase**: Write all tests BEFORE implementation (test-first approach)
- **Test Iteration**: spec → write tests → implement → run → fix → repeat until all pass
- **Test Execution**: `pytest tests/057-env-window-matching/` (autonomous, headless)
- **Success Criteria**: All tests pass before feature considered complete

**Next Phase**: Phase 2 - Task Generation
- Command: `/speckit.tasks` (NOT part of /speckit.plan - separate command)
- Output: tasks.md with dependency-ordered implementation tasks
- **Important**: Write tests FIRST before implementation tasks

**Current Status**: Planning phase complete, ready for test-first implementation.

**Branch**: `057-env-window-matching`
**Artifacts Location**: `/etc/nixos/specs/057-env-window-matching/`
