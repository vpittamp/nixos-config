# Implementation Plan: Mark-Based App Identification with Key-Value Storage

**Branch**: `076-mark-based-app-identification` | **Date**: 2025-11-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/etc/nixos/specs/076-mark-based-app-identification/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance layout restoration by injecting Sway marks with app-registry names at launch time, enabling deterministic app identification without /proc environment scanning. Marks will be stored in a structured key-value format for extensibility and persisted in layout files for accurate restoration.

**Technical Approach**:
1. Inject marks (`i3pm_app:terminal`) via app-registry wrapper at launch
2. Save marks in layout files as structured nested objects
3. Restore by reading saved marks directly (no correlation needed)
4. Clean up marks immediately via window::close event handler

## Technical Context

**Language/Version**: Python 3.11+ (existing daemon standard per Constitution Principle X)
**Primary Dependencies**:
- i3ipc.aio (async Sway IPC communication)
- Pydantic 2.x (mark data models and validation)
- asyncio (event-driven mark cleanup)

**Storage**: JSON layout files in `~/.local/share/i3pm/layouts/<project>/<name>.json`
**Testing**:
- pytest + pytest-asyncio (unit/integration tests)
- sway-test framework (end-to-end tests per Constitution Principle XV)

**Target Platform**: NixOS with Sway window manager (Hetzner reference + M1 Mac)
**Project Type**: Single project (daemon extension + CLI integration)
**Performance Goals**:
- Mark injection: <10ms per app launch
- Layout save with marks: <50ms for 10 apps
- Mark cleanup: <5ms per window close
- Restoration with marks: <1ms per window (no correlation delay)

**Constraints**:
- Marks must persist across Sway reloads
- No mark namespace pollution (100% cleanup rate)
- Backward compatible with existing layouts (graceful fallback to /proc detection)
- Idempotent restore (0 duplicates across multiple restores)

**Scale/Scope**:
- 5-10 apps per layout (typical project)
- 10-20 concurrent windows per session
- 3-5 marks per window (app, project, workspace, custom metadata)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Initial Check (Pre-Research) ✅

All principles passed initial validation.

### Final Check (Post-Design) ✅

### ✅ Principle X: Python Development & Testing Standards
- **Initial Status**: PASS - Python 3.11+, async/await, Pydantic, pytest planned
- **Design Validation**:
  - ✅ MarkManager service uses async/await with i3ipc.aio
  - ✅ MarkMetadata Pydantic model with field validation
  - ✅ pytest + pytest-asyncio for unit/integration tests
  - ✅ Type hints on all public APIs (contracts/mark-manager-api.md)
  - ✅ Error handling with explicit ValueError, IPCError types
- **Final Status**: PASS - Full compliance with Python standards

### ✅ Principle XI: i3 IPC Alignment & State Authority
- **Initial Status**: PASS - Sway IPC GET_TREE, COMMAND, event subscription planned
- **Design Validation**:
  - ✅ Mark queries via GET_TREE (MarkManager.get_window_marks)
  - ✅ Mark injection via COMMAND (swaymsg mark)
  - ✅ Mark cleanup via window::close event subscription
  - ✅ Sway marks are authoritative (stored in Sway tree, not daemon state)
  - ✅ No custom state tracking for marks (query Sway IPC on demand)
- **Final Status**: PASS - Sway IPC is single source of truth for marks

### ✅ Principle XIV: Test-Driven Development & Autonomous Testing
- **Initial Status**: PASS - Test pyramid planned (unit, integration, end-to-end)
- **Design Validation**:
  - ✅ Unit tests defined (test_mark_manager.py, test_mark_models.py)
  - ✅ Integration tests defined (test_mark_injection.py, test_mark_persistence.py)
  - ✅ End-to-end tests defined (test_mark_injection.json, test_mark_cleanup.json, test_mark_restore.json)
  - ✅ All tests are autonomous (no manual intervention)
  - ✅ Performance benchmarks specified (contracts/mark-manager-api.md)
- **Final Status**: PASS - Comprehensive autonomous test coverage

### ✅ Principle XV: Sway Test Framework Standards
- **Initial Status**: PASS - sway-test framework planned
- **Design Validation**:
  - ✅ Partial mode tests for mark verification (quickstart.md)
  - ✅ Declarative JSON test definitions (test_mark_injection.json, etc.)
  - ✅ State comparison on focusedWorkspace, windowCount, marks
  - ✅ Autonomous execution via `sway-test run`
- **Final Status**: PASS - sway-test framework properly used

### ✅ Principle XII: Forward-Only Development & Legacy Elimination
- **Initial Status**: PASS - Single code path with graceful fallback planned
- **Design Validation**:
  - ✅ Mark-based detection is primary method (restore.py)
  - ✅ /proc detection is fallback ONLY for backward compatibility (missing marks field)
  - ✅ NOT a dual implementation - single restore_workflow() with conditional fallback
  - ✅ Natural migration path (re-save layouts to get marks)
  - ✅ No feature flags or "legacy mode" support
- **Final Status**: PASS - Forward-only design with graceful degradation

### ⚠️ Complexity Justification Required: None
- No new abstraction layers introduced
- Extends existing app-registry and layout systems
- No additional platform targets
- **Post-Design Validation**:
  - ✅ MarkManager is a single service (not a framework)
  - ✅ Integrates with existing AppLauncher, daemon, layout persistence
  - ✅ No new configuration files or user-facing complexity
  - ✅ Mark format is simple (`i3pm_<key>:<value>`)

### Summary

**All constitution checks PASSED** ✅

**No violations** - Feature fully complies with all principles.

**Ready for implementation** - Proceed to `/speckit.tasks` to generate task list.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
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
│   ├── app_launcher.py          # EXISTING - Extended to inject marks at launch
│   └── mark_manager.py           # NEW - Mark injection, cleanup, query service
├── layout/
│   ├── models.py                 # EXISTING - Extended with MarkMetadata model
│   ├── persistence.py            # EXISTING - Extended to save/load marks
│   └── restore.py                # EXISTING - Extended to use marks for detection
├── daemon.py                     # EXISTING - Extended with window::close event handler
└── ipc_server.py                 # EXISTING - No changes (uses existing layout system)

tests/mark-based-app-identification/
├── unit/
│   ├── test_mark_manager.py     # Mark injection, parsing, cleanup logic
│   └── test_mark_models.py      # Pydantic MarkMetadata model validation
├── integration/
│   ├── test_mark_injection.py   # AppLauncher + MarkManager integration
│   └── test_mark_persistence.py # Save/load marks in layout files
└── sway-tests/
    ├── test_mark_injection.json # End-to-end: Launch app → verify marks
    ├── test_mark_cleanup.json   # End-to-end: Close window → verify mark removed
    └── test_mark_restore.json   # End-to-end: Restore layout using saved marks
```

**Structure Decision**: Single project extending existing i3-project daemon. This feature integrates into the existing app-registry and layout restoration infrastructure without creating new top-level directories. The daemon already has the necessary event-driven architecture via i3ipc.aio subscriptions.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**Status**: No violations - complexity tracking not required.

All Constitution principles are satisfied. This feature extends existing systems without introducing new abstraction layers, platforms, or architectural patterns.
