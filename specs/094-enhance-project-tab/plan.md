# Implementation Plan: Enhanced Projects & Applications CRUD Interface

**Branch**: `094-enhance-project-tab` | **Date**: 2025-11-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/094-enhance-project-tab/spec.md`

## Summary

Add comprehensive CRUD (Create, Read, Update, Delete) operations to the monitoring panel's Projects and Applications tabs. Projects tab will support editing local and remote projects, managing Git worktrees with parent-child hierarchy visualization, and handling JSON configuration files. Applications tab will support editing regular apps, terminal apps, and PWAs with type-specific form fields, ULID auto-generation for new PWAs, and Nix rebuild workflow integration. Both tabs will feature inline forms, conflict detection for concurrent edits, CLI error handling, and visual consistency with existing Tab 1 (Windows) and Tab 5 (Events) using Catppuccin Mocha theme.

## Technical Context

**Language/Version**:
- Python 3.11+ (existing daemon standard per Constitution Principle X)
- TypeScript/Deno 1.40+ (CLI tools per Constitution Principle XIII)
- Nix 2.18+ (configuration and build system)
- Yuck/GTK3 (Eww widget language)

**Primary Dependencies**:
- Existing: `i3ipc.aio`, `asyncio`, `Pydantic` (Python backend)
- Existing: `Eww 0.4+`, `GTK3` (widget UI)
- Existing: `i3pm` CLI (TypeScript/Deno)
- New: Nix expression parser/editor for `app-registry-data.nix` modifications
- New: Form validation library for inline forms (Yuck expressions or Python backend validation)

**Storage**:
- **Projects**: `~/.config/i3/projects/*.json` (one file per project, read/write via Python)
- **Worktrees**: `~/.config/i3/projects/*.json` (same as projects, distinguished by `parent_project` field)
- **Applications**: `home-modules/desktop/app-registry-data.nix` (Nix expression, requires parsing and generation)
- **PWAs**: Implicit in `app-registry-data.nix` (ULID generation via `/etc/nixos/scripts/generate-ulid.sh`)

**Testing**:
- Python: `pytest` with `pytest-asyncio` for backend services and data models (Constitution Principle X)
- TypeScript/Deno: `Deno.test()` for CLI validation logic (Constitution Principle XIII)
- Window Manager: `sway-test` framework for UI interaction testing (Constitution Principle XV)

**Target Platform**:
- Linux NixOS with Sway window manager (Wayland compositor)
- Multi-monitor support (3 headless displays on Hetzner, local + VNC on M1)
- Eww-based GTK3 widgets (declarative UI)

**Project Type**:
- Single project (widget extension to existing monitoring panel)
- No separate backend/frontend split (Python backend script + Yuck UI definition)

**Performance Goals**:
- Form validation feedback: <300ms debounced response to user input
- Save operations: <500ms for project JSON writes, <2s for Nix file edits
- List updates: <500ms after CRUD operation without page reload
- CLI command execution: <3s for `i3pm worktree create`, <10s for Git operations

**Constraints**:
- UI must not steal focus from active window (non-disruptive overlay)
- Nix rebuilds NOT executed from UI (clipboard copy only for security)
- All JSON/Nix file modifications must preserve formatting where possible
- Conflict detection must compare file modification timestamps before save
- CLI error handling must parse stderr/exit codes for actionable messages

**Scale/Scope**:
- Typical workload: 5-10 projects, 3-5 worktrees per main project, 30-50 applications
- Maximum tested: 20 projects, 10 worktrees per project, 100 applications
- Form complexity: 4-8 fields for projects, 10-15 fields for applications (varies by type)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards ✅
- **Language**: Python 3.11+ for backend validation and file editing
- **Async**: Uses `asyncio` for deflisten streaming (existing pattern)
- **Testing**: pytest with pytest-asyncio for unit/integration tests
- **Data validation**: Pydantic models for form validation and project/app configs
- **Module structure**: Follows single-responsibility (models, services, validators)
- **Compliance**: PASS - matches existing monitoring panel architecture

### Principle XIII: Deno CLI Development Standards ✅
- **CLI tools**: No new CLI tools required (extends existing `i3pm` CLI)
- **Integration**: May add TypeScript/Deno validators if CLI-level validation needed
- **Compliance**: PASS - not creating new standalone CLI tools

### Principle XIV: Test-Driven Development & Autonomous Testing ⚠️
- **TDD workflow**: MUST write tests before implementation
- **Test pyramid**: Unit tests (form validation), integration tests (file editing), E2E tests (UI interaction)
- **Sway testing**: Will use sway-test framework for UI interaction validation
- **Autonomous execution**: Tests must run without manual intervention
- **Compliance**: CONDITIONAL PASS - requires commitment to TDD workflow during implementation

### Principle XV: Sway Test Framework Standards ✅
- **Test definitions**: Will create JSON test definitions for form validation workflows
- **Multi-mode comparison**: Will use partial mode for form state validation
- **Declarative tests**: E.g., "create project" test validates focused tab, form visibility, validation state
- **Compliance**: PASS - will use sway-test for E2E UI testing

### Principle VI: Declarative Configuration Over Imperative ✅
- **JSON editing**: Projects stored as declarative JSON configs
- **Nix editing**: Applications stored in declarative Nix expressions
- **No imperative scripts**: All file modifications preserve declarative nature
- **Compliance**: PASS - maintains declarative philosophy

### Principle XI: i3 IPC Alignment & State Authority ✅
- **Monitoring panel**: Uses existing i3pm daemon as authoritative source
- **Event-driven**: Uses deflisten for real-time form validation feedback
- **No custom state**: Form state derived from file reads, not parallel tracking
- **Compliance**: PASS - respects daemon authority

### Principle XII: Forward-Only Development & Legacy Elimination ✅
- **No backwards compatibility**: This is a new feature, no legacy code to preserve
- **Clean implementation**: Will not add feature flags or dual code paths
- **Compliance**: PASS - new feature with no legacy constraints

### Complexity Justification

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Text-based Nix editing (not AST-based) | Must programmatically edit `app-registry-data.nix` from Python backend | AST-based parsing requires Rust FFI (rnix-parser), adds complexity and violates Principle X (Python 3.11+ standard). Text manipulation with templates is pragmatic for well-structured list append/edit/delete operations. |
| Hybrid validation (backend + frontend) | Real-time validation feedback with authoritative business logic enforcement | Pure frontend validation cannot check filesystem/uniqueness; pure backend validation requires form submission to see errors. Hybrid matches existing monitoring panel architecture (Health tab, project list patterns). |

**Constitution Check Result**: ✅ **PASS** (with TDD commitment required during implementation)

## Project Structure

### Documentation (this feature)

```text
specs/094-enhance-project-tab/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── form-validation-api.md
│   ├── project-crud-api.md
│   └── app-crud-api.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

**Structure Decision**: Single project structure extending existing monitoring panel infrastructure. Backend components integrate with existing Python daemon tools, frontend extends Eww widget definitions in Nix.

```text
home-modules/
├── desktop/
│   ├── eww-monitoring-panel.nix          # MODIFY: Add Projects/Apps tab UI widgets
│   ├── app-registry-data.nix             # TARGET: Applications CRUD edits this file
│   └── app-registry.nix                  # REFERENCE: Generates JSON from Nix data
│
└── tools/
    ├── i3_project_manager/
    │   ├── cli/
    │   │   └── monitoring_data.py        # MODIFY: Add --mode projects/apps handlers
    │   ├── models/
    │   │   ├── project_config.py         # NEW: Project Pydantic models
    │   │   └── app_config.py             # NEW: Application Pydantic models
    │   ├── services/
    │   │   ├── project_editor.py         # NEW: Project JSON CRUD service
    │   │   ├── app_registry_editor.py    # NEW: Nix file editing service
    │   │   └── form_validator.py         # NEW: Real-time validation service
    │   └── validators/
    │       ├── project_validator.py      # MODIFY: Add CRUD-specific validation
    │       └── app_validator.py          # NEW: Application field validation
    │
    └── monitoring-panel/                  # NEW DIRECTORY: Feature 094 tooling
        ├── __init__.py
        ├── project_crud_handler.py        # Project CRUD request handlers
        ├── app_crud_handler.py            # Application CRUD request handlers
        ├── conflict_detector.py           # File modification conflict detection
        └── cli_executor.py                # CLI command execution with error parsing

tests/
├── 094-enhance-project-tab/
│   ├── unit/
│   │   ├── test_project_editor.py       # Project JSON editing tests
│   │   ├── test_app_registry_editor.py  # Nix file editing tests
│   │   ├── test_form_validator.py       # Validation logic tests
│   │   ├── test_project_models.py       # Pydantic model tests
│   │   └── test_app_models.py           # Application model tests
│   ├── integration/
│   │   ├── test_project_crud_workflow.py  # End-to-end project CRUD
│   │   ├── test_app_crud_workflow.py      # End-to-end app CRUD
│   │   ├── test_worktree_crud.py          # Worktree creation via i3pm CLI
│   │   ├── test_conflict_detection.py     # Concurrent edit conflict handling
│   │   └── test_cli_error_handling.py     # CLI failure parsing and recovery
│   └── sway-tests/
│       ├── test_project_form_validation.json    # UI validation interaction
│       ├── test_app_form_validation.json        # Application form UI
│       ├── test_inline_edit_workflow.json       # Edit → Save → List update
│       └── test_conflict_resolution_ui.json     # Conflict dialog interaction

scripts/
└── generate-ulid.sh                      # REFERENCE: ULID generation for PWAs

shared/
└── pwa-sites.nix                         # TARGET: PWA CRUD may edit this file
```

### File Modification Summary

**New Files (11)**:
1. `home-modules/tools/i3_project_manager/models/project_config.py` - Pydantic models for projects
2. `home-modules/tools/i3_project_manager/models/app_config.py` - Pydantic models for applications
3. `home-modules/tools/i3_project_manager/services/project_editor.py` - Project JSON CRUD
4. `home-modules/tools/i3_project_manager/services/app_registry_editor.py` - Nix file editing
5. `home-modules/tools/i3_project_manager/services/form_validator.py` - Real-time validation
6. `home-modules/tools/i3_project_manager/validators/app_validator.py` - App field validation
7. `home-modules/tools/monitoring-panel/project_crud_handler.py` - Project CRUD handlers
8. `home-modules/tools/monitoring-panel/app_crud_handler.py` - App CRUD handlers
9. `home-modules/tools/monitoring-panel/conflict_detector.py` - Conflict detection
10. `home-modules/tools/monitoring-panel/cli_executor.py` - CLI execution with error parsing
11. `tests/094-enhance-project-tab/` - Complete test suite (14 test files)

**Modified Files (3)**:
1. `home-modules/desktop/eww-monitoring-panel.nix` - Add Projects/Apps tab UI widgets
2. `home-modules/tools/i3_project_manager/cli/monitoring_data.py` - Add `--mode projects/apps` handlers
3. `home-modules/tools/i3_project_manager/validators/project_validator.py` - Add CRUD validation

**Target Files (edited by feature, not by implementation)**:
1. `~/.config/i3/projects/*.json` - Project configurations (created/edited/deleted by CRUD)
2. `home-modules/desktop/app-registry-data.nix` - Application registry (edited via `app_registry_editor.py`)
3. `shared/pwa-sites.nix` - PWA definitions (edited for PWA CRUD)
