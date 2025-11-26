# Implementation Plan: Bolster Project & Worktree CRUD Operations in Monitoring Widget

**Branch**: `096-bolster-project-and` | **Date**: 2025-11-26 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/096-bolster-project-and/spec.md`

## Summary

This feature fixes and enhances the existing CRUD operations for projects and worktrees in the eww monitoring panel's Projects tab. Feature 094 implemented comprehensive infrastructure (Python handlers, shell scripts, Eww widgets), but users report that CRUD actions cannot be submitted. This feature focuses on debugging end-to-end flows, ensuring form submissions reach Python handlers correctly, adding robust visual feedback for all operation states, and verifying functionality through direct testing.

## Technical Context

**Language/Version**:
- Python 3.11+ (existing daemon standard per Constitution Principle X)
- Bash (shell scripts for Eww button handlers)
- Nix (eww-monitoring-panel.nix widget definitions)
- Yuck (Eww widget language)

**Primary Dependencies**:
- Existing: `i3ipc.aio`, `asyncio`, `Pydantic` (Python backend)
- Existing: `Eww 0.4+`, `GTK3` (widget UI)
- Existing: `jq` (JSON manipulation in shell scripts)
- Existing: `i3pm` CLI (TypeScript/Deno - for project operations reference)

**Storage**:
- Project configs: `~/.config/i3/projects/*.json` (one JSON file per project)
- Application registry: `home-modules/desktop/app-registry-data.nix`
- Eww config: `~/.config/eww-monitoring-panel/`

**Testing**:
- Python: `pytest` with `pytest-asyncio` for backend services
- Sway: `sway-test` framework for UI validation (Constitution Principle XV)
- Manual: Direct UI interaction to verify form submissions

**Target Platform**:
- Linux NixOS with Sway window manager (Wayland compositor)
- Multi-monitor support (Hetzner headless, M1 local + VNC)

**Project Type**: Single project (widget enhancement to existing monitoring panel)

**Performance Goals**:
- Form validation feedback: <300ms debounced response
- Save operations: <500ms for project JSON writes
- List updates: <500ms after CRUD operation
- Success notification: <200ms after operation completion

**Constraints**:
- UI must not steal focus (non-disruptive overlay)
- Shell scripts must correctly pass Eww variables to Python handlers
- All operations must provide visual feedback (loading, success, error states)

**Scale/Scope**:
- Typical: 5-10 projects, 3-5 worktrees per main project
- Form complexity: 4-8 fields for projects, 4 fields for worktrees

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards ✅
- **Language**: Python 3.11+ for backend handlers (existing)
- **Async**: Uses `asyncio` for daemon operations
- **Testing**: pytest with pytest-asyncio for unit/integration tests
- **Data validation**: Pydantic models for form validation
- **Module structure**: Single-responsibility (models, services, handlers)
- **Compliance**: PASS - matches existing monitoring panel architecture

### Principle XIII: Deno CLI Development Standards ✅
- **CLI tools**: No new CLI tools required (uses existing `i3pm` CLI indirectly)
- **Compliance**: PASS - not creating new standalone CLI tools

### Principle XIV: Test-Driven Development & Autonomous Testing ✅
- **TDD workflow**: Tests written before implementation fixes
- **Test pyramid**: Unit tests (Python handlers), integration tests (shell → Python), UI tests (sway-test)
- **Autonomous execution**: sway-test framework for UI validation
- **Compliance**: PASS - will use TDD workflow

### Principle XV: Sway Test Framework Standards ✅
- **Test definitions**: JSON test definitions for form validation workflows
- **Multi-mode comparison**: Partial mode for form state validation
- **Compliance**: PASS - will use sway-test for E2E UI testing

### Principle VI: Declarative Configuration Over Imperative ✅
- **Configuration**: All changes via Nix expressions (eww-monitoring-panel.nix)
- **No imperative scripts**: Shell scripts are invoked declaratively via Eww onclick
- **Compliance**: PASS - maintains declarative philosophy

### Principle XI: i3 IPC Alignment & State Authority ✅
- **State source**: Project list refreshed from filesystem (JSON files)
- **Event-driven**: Eww defpoll for periodic refresh
- **Compliance**: PASS - respects authoritative state sources

### Principle XII: Forward-Only Development & Legacy Elimination ✅
- **No backwards compatibility**: Fixes existing Feature 094 code, no dual paths
- **Clean implementation**: Direct bug fixes and enhancements
- **Compliance**: PASS - forward-only fixes

**Constitution Check Result**: ✅ **PASS**

## Project Structure

### Documentation (this feature)

```text
specs/096-bolster-project-and/
├── plan.md              # This file
├── research.md          # Phase 0 output - debugging findings
├── data-model.md        # Phase 1 output - entity definitions
├── quickstart.md        # Phase 1 output - user guide
├── contracts/           # Phase 1 output - API contracts
│   ├── project-crud-api.md
│   └── form-validation-api.md
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

**Structure Decision**: Enhancing existing Feature 094 infrastructure. No new directories required.

```text
home-modules/
├── desktop/
│   └── eww-monitoring-panel.nix          # MODIFY: Fix shell script bindings, enhance visual feedback
│
└── tools/
    ├── i3_project_manager/
    │   ├── cli/
    │   │   └── monitoring_data.py        # EXISTING: Projects/apps data provider
    │   ├── models/
    │   │   ├── project_config.py         # EXISTING: Project Pydantic models
    │   │   └── validation_state.py       # EXISTING: Form validation state
    │   └── services/
    │       └── project_editor.py         # EXISTING: Project JSON CRUD
    │
    └── monitoring-panel/
        ├── project_crud_handler.py       # MODIFY: Fix handler invocation issues
        ├── cli_executor.py               # EXISTING: CLI command execution
        └── project_form_validator_stream.py  # EXISTING: Form validation stream

tests/
└── 096-bolster-project-and/
    ├── unit/
    │   ├── test_shell_script_execution.py    # NEW: Test shell scripts execute
    │   └── test_form_variable_passing.py     # NEW: Test Eww → Python data flow
    ├── integration/
    │   └── test_crud_end_to_end.py           # NEW: Full CRUD workflow tests
    └── sway-tests/
        ├── test_project_create.json          # NEW: Create project UI test
        ├── test_project_edit.json            # NEW: Edit project UI test
        └── test_worktree_create.json         # NEW: Create worktree UI test
```

### File Modification Summary

**Modified Files (2)**:
1. `home-modules/desktop/eww-monitoring-panel.nix` - Fix onclick bindings, enhance visual feedback
2. `home-modules/tools/monitoring-panel/project_crud_handler.py` - Fix handler execution issues

**New Files (5 test files)**:
1. `tests/096-bolster-project-and/unit/test_shell_script_execution.py`
2. `tests/096-bolster-project-and/unit/test_form_variable_passing.py`
3. `tests/096-bolster-project-and/integration/test_crud_end_to_end.py`
4. `tests/096-bolster-project-and/sway-tests/test_project_create.json`
5. `tests/096-bolster-project-and/sway-tests/test_project_edit.json`
6. `tests/096-bolster-project-and/sway-tests/test_worktree_create.json`

## Complexity Tracking

> No constitution violations requiring justification. This feature fixes existing infrastructure without introducing new complexity.
