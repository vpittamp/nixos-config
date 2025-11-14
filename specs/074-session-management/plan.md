# Implementation Plan: Comprehensive Session Management

**Branch**: `074-session-management` | **Date**: 2025-01-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/074-session-management/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Extends existing i3pm project management system with comprehensive session management capabilities: workspace focus restoration per project, terminal working directory tracking, focused window restoration, auto-save/restore functionality, and Sway-compatible window restoration using mark-based correlation to replace broken swallow mechanism.

## Technical Context

**Language/Version**: Python 3.11+ (existing daemon standard per Constitution Principle X)
**Primary Dependencies**:
  - i3ipc.aio (async Sway/i3 IPC client)
  - Pydantic v2 (data validation, existing in layout system)
  - asyncio (event-driven architecture)
  - psutil (process introspection for terminal cwd via `/proc/{pid}/cwd`)

**Storage**:
  - In-memory daemon state (StateManager) - existing
  - JSON persistence files in `~/.config/i3/` (existing: `window-workspace-map.json`, `active-project.json`)
  - Layout snapshots in `~/.local/share/i3pm/layouts/{project}/{snapshot-name}.json` (existing infrastructure)

**Testing**:
  - pytest with pytest-asyncio (async test support per Constitution Principle X)
  - sway-test framework for end-to-end window manager testing (Constitution Principle XV)
  - Unit tests for Pydantic models, state management, correlation logic
  - Integration tests for Sway IPC interaction and event handling

**Target Platform**:
  - NixOS with Sway/Wayland compositor (primary)
  - i3/X11 backward compatibility (optional, can use existing swallow mechanism)
  - Hetzner Cloud (headless Sway with VNC)
  - M1 Mac (native Sway on Asahi Linux)

**Project Type**: Single project (extension to existing i3pm daemon in `home-modules/desktop/i3-project-event-daemon/`)

**Performance Goals**:
  - Workspace focus switch: <100ms latency
  - Auto-save capture: <200ms (imperceptible during project switch)
  - Mark-based window correlation: >95% accuracy, <30s timeout
  - Full 10-window layout restore: <15s total
  - Event processing: <100ms per window::new or workspace::focus event

**Constraints**:
  - Must maintain backward compatibility with existing layout JSON files (Pydantic optional fields)
  - Must work on Sway (no i3 swallow mechanism available - swaywm/sway#1005)
  - Must not block project switching (async auto-save)
  - Must handle missing directories gracefully (deleted terminal cwd, missing project root)
  - Must persist across daemon restarts (JSON serialization of focus state)

**Scale/Scope**:
  - 1-70 workspaces per session
  - 1-20 projects per user
  - 5-50 windows per project
  - 10-100 auto-saved layouts per project (auto-pruned to 10 most recent)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Applicable Constitutional Principles

**Principle I: Modular Composition** ✅ PASS
- Feature extends existing `i3-project-event-daemon` module
- New session management code will be in `layout/` subdirectory (existing)
- State tracking extends existing `StateManager` class
- No code duplication - builds on existing infrastructure

**Principle III: Test-Before-Apply (NON-NEGOTIABLE)** ✅ PASS
- Will use `nixos-rebuild dry-build --flake .#hetzner-sway` before deployment
- Will test on M1 Mac with `--impure` flag before production use

**Principle VI: Declarative Configuration Over Imperative** ✅ PASS
- All configuration in Nix modules and home-manager
- Session data stored in declarative JSON files
- No imperative post-install scripts

**Principle X: Python Development & Testing Standards** ✅ PASS
- Python 3.11+ with async/await patterns (i3ipc.aio)
- Pydantic v2 for data models (already used in layout system)
- pytest with pytest-asyncio for testing
- Rich library for CLI output (if adding diagnostic commands)

**Principle XI: i3 IPC Alignment & State Authority** ✅ PASS
- Sway IPC is authoritative source for workspace focus state
- Event-driven architecture via workspace::focus and window::focus subscriptions
- Mark-based correlation uses Sway IPC GET_TREE for validation

**Principle XII: Forward-Only Development & Legacy Elimination** ✅ PASS
- Mark-based correlation REPLACES broken swallow mechanism (no dual support)
- No backward compatibility for old layout format - Pydantic handles graceful defaults
- Clean replacement of layout/restore.py's `_swallow_window()` method

**Principle XIV: Test-Driven Development & Autonomous Testing** ✅ PASS
- Will write pytest tests before implementing focus tracking
- sway-test framework for end-to-end workspace restoration validation
- Unit tests for correlation logic, integration tests for Sway IPC interaction

**Principle XV: Sway Test Framework Standards** ✅ PASS
- Declarative JSON test definitions for workspace focus restoration scenarios
- Partial mode for focused state assertions (focusedWorkspace, windowCount)
- Sway IPC GET_TREE as authoritative source for state verification

### Gates Summary

**PASS** - No constitutional violations. Feature aligns with existing architecture:
- Extends existing i3pm daemon (modular composition)
- Uses standard Python/async patterns (Principle X)
- Replaces broken swallow with mark-based correlation (forward-only development)
- Test-driven with pytest and sway-test framework (Principles XIV, XV)

## Project Structure

### Documentation (this feature)

```text
specs/074-session-management/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (mark-based correlation strategy)
├── data-model.md        # Phase 1 output (extended Pydantic models)
├── quickstart.md        # Phase 1 output (user guide)
├── checklists/
│   └── requirements.md  # Quality validation (already completed)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created yet)
```

### Source Code (repository root)

```text
home-modules/desktop/i3-project-event-daemon/
├── models/
│   └── legacy.py                      # EXTEND: DaemonState with project_focused_workspace
├── state.py                           # EXTEND: StateManager with focus tracking methods
├── handlers.py                        # MODIFY: _switch_project() to restore workspace focus
├── services/
│   ├── focus_tracker.py              # NEW: Per-project workspace/window focus tracking
│   └── terminal_cwd.py               # NEW: Terminal working directory extraction
├── layout/
│   ├── models.py                     # EXTEND: WindowPlaceholder (cwd, focused), LayoutSnapshot (focused_workspace)
│   ├── capture.py                    # EXTEND: Capture terminal cwd and focused window
│   ├── restore.py                    # REPLACE: _swallow_window() with mark-based correlation
│   ├── correlation.py                # NEW: Mark-based window correlation for Sway
│   └── persistence.py                # EXTEND: Auto-save/restore logic, layout pruning
└── event_handlers/
    ├── workspace.py                  # EXTEND: Track workspace::focus events
    └── window.py                     # EXTEND: Track window::focus events

tests/i3pm-session-management/
├── unit/
│   ├── test_focus_tracker.py         # Focus state tracking logic
│   ├── test_terminal_cwd.py          # Terminal cwd extraction
│   ├── test_correlation.py           # Mark-based correlation algorithm
│   └── test_models.py                # Extended Pydantic model validation
├── integration/
│   ├── test_focus_restoration.py     # Workspace focus restoration on project switch
│   ├── test_auto_save.py             # Auto-save on project switch
│   └── test_layout_restore.py        # Layout restoration with mark-based correlation
└── sway-tests/
    ├── workspace_focus_restoration.json  # Declarative sway-test for US1
    ├── terminal_cwd_tracking.json        # Declarative sway-test for US2
    └── window_correlation.json           # Declarative sway-test for US3
```

**Structure Decision**: Single project extension to existing i3pm daemon. This feature builds on existing layout infrastructure (capture.py, restore.py, persistence.py, models.py) and extends the state manager for focus tracking. No new top-level directories required - all code lives within the established daemon structure.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*No violations - this section is intentionally empty.*

---

## Phase 0: Research Complete ✅

See [research.md](./research.md) for detailed technical decisions:

- **Mark-based correlation** strategy for Sway compatibility
- **`/proc/{pid}/cwd`** for terminal working directory extraction
- **Dictionary-based focus tracking** in DaemonState
- **Per-project configuration** in Nix registry
- **Auto-save pruning** based on `max_auto_saves` count

All NEEDS CLARIFICATION items resolved.

---

## Phase 1: Design Complete ✅

### Generated Artifacts

1. **[data-model.md](./data-model.md)** - Extended Pydantic models
   - WindowPlaceholder: `cwd`, `focused`, `restoration_mark` fields
   - LayoutSnapshot: `focused_workspace` field
   - DaemonState: `project_focused_workspace`, `workspace_focused_window` dictionaries
   - RestoreCorrelation: New model for tracking mark-based correlation
   - ProjectConfiguration: New model for per-project settings

2. **[contracts/ipc-api.md](./contracts/ipc-api.md)** - JSON-RPC API specification
   - 9 IPC methods (layout.*, project.*, config.*, state.*)
   - Event notifications for auto-save/restore
   - Error codes and performance guarantees
   - CLI integration mappings

3. **[quickstart.md](./quickstart.md)** - User guide
   - Basic usage examples
   - Configuration instructions
   - Workflow scenarios
   - Troubleshooting guide

### Constitution Re-Check (Post-Design)

**Principle I: Modular Composition** ✅ PASS
- Design extends existing modules (layout/, models/, state.py)
- New services (focus_tracker.py, terminal_cwd.py, correlation.py) follow single-responsibility
- No code duplication - reuses existing Pydantic infrastructure

**Principle VI: Declarative Configuration Over Imperative** ✅ PASS
- Per-project config in Nix registry (app-registry-data.nix)
- Session state in declarative JSON files
- No imperative scripts

**Principle X: Python Development & Testing Standards** ✅ PASS
- Pydantic v2 models with validation
- Async/await patterns throughout (i3ipc.aio)
- pytest test structure defined

**Principle XI: i3 IPC Alignment & State Authority** ✅ PASS
- Sway IPC GET_TREE is authoritative for correlation
- Event-driven focus tracking via workspace::focus and window::focus
- Mark-based correlation polls Sway tree

**Principle XII: Forward-Only Development** ✅ PASS
- Mark-based correlation completely replaces swallow mechanism
- No dual code paths or backward compatibility shims
- Clean replacement in layout/restore.py

**Principle XIV & XV: Test-Driven Development** ✅ PASS
- Test structure defined (unit/, integration/, sway-tests/)
- sway-test JSON definitions for declarative validation
- Tests will be written before implementation

**FINAL VERDICT**: All constitutional principles satisfied. Ready for implementation phase.

---

## Next Steps

Run `/speckit.tasks` to generate actionable task breakdown (`tasks.md`) based on this plan.

Implementation will proceed in priority order:
1. **P1**: Workspace focus restoration, terminal cwd tracking, mark-based correlation
2. **P2**: Focused window tracking, auto-save
3. **P3**: Auto-restore

---

## Summary

**Branch**: `074-session-management`
**Spec**: [spec.md](./spec.md)
**Plan**: This file
**Research**: [research.md](./research.md)
**Data Model**: [data-model.md](./data-model.md)
**API Contract**: [contracts/ipc-api.md](./contracts/ipc-api.md)
**User Guide**: [quickstart.md](./quickstart.md)

**Status**: Planning phase complete. All design artifacts generated. Constitution check passed. Ready for task generation and implementation.
