# Implementation Plan: Scratchpad Terminal Filtering Reliability

**Branch**: `051-scratchpad-filtering` | **Date**: 2025-11-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/063-scratchpad-filtering/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Fix scratchpad terminal filtering reliability through environment variable validation, one-terminal-per-project constraint enforcement, and test-driven development. The feature addresses duplicate code paths in window filtering logic by implementing consistent scratchpad terminal identification via environment variables and window marks across all filtering code paths (ipc_server.py, window_filter.py, handlers.py).

## Technical Context

**Language/Version**: Python 3.11+ (matches existing i3pm daemon)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), asyncio (event loop), psutil (process validation), pytest (testing), Pydantic (data models)
**Storage**: In-memory daemon state (project → terminal PID/window ID mapping), Sway window marks for persistence
**Testing**: pytest with pytest-asyncio for async test support, bash test scripts with automated assertions
**Target Platform**: NixOS with Sway Wayland compositor (hetzner-sway, m1 configurations)
**Project Type**: Single project - system daemon extension (i3pm daemon enhancement)
**Performance Goals**: <200ms visibility change latency, <100ms filtering logic execution, <1% CPU usage for daemon
**Constraints**: One scratchpad terminal per project, 100% filtering reliability across all code paths, zero scratchpad-related errors during normal usage
**Scale/Scope**: ~10-20 concurrent projects, ~3-5 scratchpad terminals active simultaneously, 3 filtering code paths to update

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Modular Composition** | ✅ PASS | Changes are localized to existing i3pm daemon modules. No new modules required. Updates will be made to existing `window_filter.py`, `ipc_server.py`, `handlers.py` with consistent scratchpad filtering logic. |
| **III. Test-Before-Apply** | ✅ PASS | Spec includes comprehensive test protocol with automated bash scripts. TDD approach mandated with test-first development. |
| **VI. Declarative Configuration** | ✅ PASS | Scratchpad terminal configuration remains declarative via app registry. No imperative changes required. |
| **X. Python Development Standards** | ✅ PASS | Python 3.11+, async/await with i3ipc.aio, pytest testing framework, Pydantic models for data validation. Follows all established patterns. |
| **XI. i3 IPC Alignment** | ✅ PASS | Window state validation uses Sway IPC GET_TREE and GET_MARKS as authoritative source. Environment variable inspection via `/proc/{pid}/environ`. |
| **XII. Forward-Only Development** | ✅ PASS | Spec explicitly states "No Backwards Compatibility Constraints" - aims for optimal solution by replacing inconsistent filtering logic entirely. |
| **XIV. Test-Driven Development** | ✅ PASS | Spec includes mandatory test protocol with unit tests (env var validation), integration tests (daemon communication), end-to-end tests (project switching workflow), and automated test script structure. |

**Constitution Gate Result**: ✅ **PASSED** - All applicable principles satisfied. No violations. Feature design aligns with established architecture patterns.

## Project Structure

### Documentation (this feature)

```text
specs/063-scratchpad-filtering/
├── spec.md              # Feature specification (already created)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (next)
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (Python API contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

**Existing codebase - modifications only, no new directories**:

```text
home-modules/services/i3pm/
├── daemon/
│   ├── i3_project_daemon.py        # Main daemon entry point
│   ├── ipc_server.py               # [MODIFY] Add scratchpad filtering to _hide_windows/_restore_windows
│   ├── window_filter.py            # [MODIFY] Add scratchpad filtering to filter_windows_by_project
│   ├── handlers.py                 # [MODIFY] Add scratchpad filtering to TICK event handler
│   ├── scratchpad_manager.py       # [MODIFY] Add duplicate prevention logic
│   ├── models.py                   # [MODIFY] Add WindowEnvironment model with I3PM_* validation
│   └── utils/
│       └── environment.py          # [NEW] Environment variable parsing and validation utilities

tests/i3pm/
├── unit/
│   ├── test_environment.py         # [NEW] Unit tests for environment variable parsing
│   ├── test_scratchpad_manager.py  # [NEW] Unit tests for duplicate prevention
│   └── test_window_filter.py       # [MODIFY] Add scratchpad filtering tests
├── integration/
│   └── test_filtering_consistency.py # [NEW] Integration tests for cross-path filtering
└── scenarios/
    └── test_scratchpad_workflow.sh   # [NEW] Automated bash test script from spec
```

**Structure Decision**: This feature modifies existing i3pm daemon infrastructure. All changes are localized to the daemon directory with new test coverage. No new top-level directories or modules required. The scratchpad filtering logic will be added as helper functions in existing modules and called consistently from all three filtering code paths.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No violations** - Constitution Check passed. No complexity justification required.
