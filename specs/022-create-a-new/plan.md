# Implementation Plan: Enhanced i3pm TUI with Comprehensive Management & Automated Testing

**Branch**: `022-create-a-new` | **Date**: 2025-10-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/022-create-a-new/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance the i3pm TUI application to provide complete project lifecycle management through intuitive interfaces for layout operations (save/restore/close-all with application relaunching), workspace-to-monitor configuration, window classification, auto-launch management, and pattern-based matching. Implement automated testing framework using Textual Pilot API to simulate user interactions and verify state changes, event triggers, and UI behavior. Leverage i3's native IPC (RUN_COMMAND, GET_TREE, GET_OUTPUTS) for all operations, following established Python async patterns with i3ipc.aio library.

## Technical Context

**Language/Version**: Python 3.11+ (established by Constitution Principle X for i3-project system tooling)
**Primary Dependencies**:
- Textual Framework (Python TUI, already in use for existing screens)
- i3ipc.aio (async i3 IPC library, already in use for daemon communication)
- pytest & pytest-asyncio (testing framework per Constitution Principle X)
- Rich (terminal UI library for formatting, already in use)

**Storage**:
- JSON files for project configurations (`~/.config/i3/projects/*.json`)
- JSON files for saved layouts (`~/.config/i3/layouts/*.json`)
- JSON files for app classifications (`~/.config/i3/app-classes.json`)
- JSON files for pattern rules (`~/.config/i3/pattern-rules.json`)

**Testing**: pytest with pytest-asyncio for async tests, Textual Pilot API for TUI interaction simulation, mock implementations for daemon/i3 IPC

**Target Platform**: NixOS/Linux with i3 window manager, X11 display server (per Constitution Principle VIII for RDP compatibility)

**Project Type**: Single Python project extending existing i3pm TUI application

**Performance Goals**:
- All TUI operations complete within 2 seconds (per spec SC-001, constraint)
- Layout restoration within 2 seconds including application relaunching (per spec FR-002)
- Pattern rule testing shows results within 500ms (per spec SC-006)
- Monitor configuration updates within 1 second of physical changes (per spec SC-010)

**Constraints**:
- Must use i3 native IPC API as authoritative state source (Constitution Principle XI)
- Backward compatibility with existing project JSON files required (per spec constraints)
- Daemon must be running and connected for layout/workspace operations (per spec constraints)
- Test isolation required to prevent cross-test interference (per spec FR-032)
- Configuration saves must be atomic to prevent corruption (per spec constraints)

**Scale/Scope**:
- Support 10+ projects per user with multiple layouts per project
- Handle 100 windows per layout maximum (per spec constraints)
- Support 10 workspaces across up to 10 monitors (per spec constraints)
- Test suite execution under 5 minutes for complete coverage (per spec SC-007)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards ✅ PASS

**Evaluation**:
- Python 3.11+ requirement: ✅ Specified in Technical Context
- Async/await patterns: ✅ Required for i3ipc.aio and daemon communication per spec
- pytest framework: ✅ FR-029 through FR-033 require pytest with pytest-asyncio
- Type hints: ✅ Constitution requires type hints for function signatures
- Data validation: ✅ Pydantic/dataclasses already in use per dependencies
- Rich library: ✅ Already in use for TUI, specified in dependencies
- Error handling: ✅ Edge cases document error messages and remediation
- Test coverage: ✅ SC-007 requires test suite execution under 5 minutes, SC-008 requires 100% regression detection accuracy

**Alignment**: Full compliance. Spec explicitly requires automated testing framework (FR-029 through FR-033, User Story 7) with pytest, async patterns for i3 IPC communication, and comprehensive test coverage across all user workflows.

### Principle XI: i3 IPC Alignment & State Authority ✅ PASS

**Evaluation**:
- State queries via i3 IPC: ✅ Dependencies list GET_TREE, GET_OUTPUTS, GET_WORKSPACES, GET_MARKS
- Workspace-to-output validation: ✅ FR-010 requires validation against current monitor count
- Monitor configuration via GET_OUTPUTS: ✅ FR-012 requires display of monitor configuration from i3
- Window marking verification: ✅ FR-015 requires immediate effect on window classification
- Event subscriptions: ✅ Existing daemon uses i3 IPC subscriptions per dependencies
- i3ipc.aio library: ✅ Explicitly listed in dependencies with async patterns
- Event-driven architecture: ✅ Clarification session confirmed i3 RUN_COMMAND for launching, GET_TREE for window matching

**Alignment**: Full compliance. Spec explicitly states "Application launching uses i3's native RUN_COMMAND IPC for execution and GET_TREE for window matching" (Assumption 3) and "Window identification for repositioning uses i3 window properties (class, instance, title, role) available via GET_TREE" (Assumption 4).

### Testing & Validation Standards ✅ PASS

**Evaluation**:
- Unit tests required: ✅ FR-031 requires state verification assertions
- Integration tests: ✅ FR-030 requires capturing daemon events and file modifications
- Test scenarios: ✅ User Story 7 (P1 priority) defines automated TUI testing framework
- Headless operation: ✅ Assumption 6 specifies Xvfb for virtual display
- Mock implementations: ✅ FR-032 requires test isolation preventing cross-test interference
- Machine-readable reports: ✅ FR-033 requires test coverage reports
- Test execution time: ✅ SC-007 requires full test suite under 5 minutes
- Expected vs actual state: ✅ FR-031 requires state verification assertions
- tmux integration: ✅ Constitution requires tmux for manual interactive testing

**Alignment**: Full compliance. Entire User Story 7 (Priority P1) is dedicated to automated testing framework with all required capabilities. Success criteria SC-007 (5 minute execution) and SC-008 (100% regression detection) ensure comprehensive coverage.

### Diagnostic & Monitoring Standards ✅ PASS

**Evaluation**:
- Real-time state display: ✅ FR-012 requires monitor configuration display updating within 1 second
- Event streams captured: ✅ FR-030 requires capturing daemon events during tests
- Diagnostic capture: ✅ User Story 7 Acceptance Scenario 3 requires "screenshots, state dumps, and logs for debugging"
- State validation: ✅ FR-010 requires validation against current monitor count (i3 IPC authority)
- Multiple display modes: ✅ Monitor Dashboard (User Story 8) provides interactive monitor status view
- Connection status indication: ✅ Edge case documents daemon connection failures with clear error
- Error guidance: ✅ All edge cases include remediation steps (FR-022 auto-launch status, edge case for missing apps)
- Structured JSON reports: ✅ FR-033 requires test coverage reports (machine-readable format)

**Alignment**: Full compliance. TUI screens provide real-time monitoring, test framework includes diagnostic capture, and all error states provide actionable troubleshooting guidance per edge cases.

### Modular Composition (Principle I) ✅ PASS

**Evaluation**:
- Single Python project extending existing i3pm TUI application per Technical Context
- No new modules being added to NixOS configuration structure
- Extending existing home-modules/tools/i3_project_manager/ structure
- Reusing established dependencies (Textual, i3ipc.aio, pytest)

**Alignment**: No modular composition violations. Feature extends existing Python application without creating new configuration modules or duplicating code.

### Declarative Configuration (Principle VI) ✅ PASS

**Evaluation**:
- Configuration storage: ✅ JSON files in ~/.config/i3/ (existing pattern)
- No imperative scripts: ✅ All operations via TUI and daemon IPC
- Configuration atomicity: ✅ Constraint explicitly requires atomic configuration saves

**Alignment**: Full compliance. All configuration changes persist to JSON files declaratively, no imperative post-install scripts required.

### Documentation as Code (Principle VII) ✅ PASS

**Evaluation**:
- User Story 7 includes automated testing framework as P1 priority
- Phase 1 will generate quickstart.md per /speckit.plan workflow
- Comprehensive edge cases documented (10 scenarios)
- Success criteria are measurable (10 specific metrics)

**Alignment**: Full compliance. Documentation will be generated during planning phase, and comprehensive requirements documentation already created in spec.md.

### Gate Status: ✅ **PASSED - Proceed to Phase 0 Research**

No violations or complexity justifications required. Feature fully aligns with Constitution Principles X (Python Development), XI (i3 IPC Alignment), Testing & Validation Standards, and Diagnostic & Monitoring Standards.

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
home-modules/tools/i3_project_manager/
├── __init__.py
├── __main__.py                      # CLI entry point (existing)
├── core/
│   ├── __init__.py
│   ├── models.py                    # Existing: Project, AutoLaunchApp, SavedLayout models
│   ├── project.py                   # Existing: ProjectManager for daemon communication
│   ├── pattern_matcher.py           # Existing: Pattern matching for window classification
│   └── layout_manager.py            # NEW: Layout save/restore/export operations with app relaunching
├── tui/
│   ├── __init__.py
│   ├── app.py                       # Existing: Main TUI application
│   └── screens/
│       ├── __init__.py
│       ├── browser.py               # Existing: Project browser (home screen)
│       ├── editor.py                # Existing: Project editor
│       ├── wizard.py                # Existing: Project creation wizard
│       ├── monitor.py               # Existing: Monitor dashboard
│       ├── layout_manager.py        # ENHANCE: Add save/restore/delete/export operations
│       ├── workspace_config.py      # NEW: Workspace-to-monitor assignment configuration
│       ├── classification_wizard.py # NEW: Window classification wizard with live inspection
│       ├── auto_launch_config.py    # NEW: Auto-launch entry configuration interface
│       └── pattern_config.py        # NEW: Pattern rule configuration with live testing
└── cli/
    ├── __init__.py
    └── commands.py                  # Existing: CLI commands (16 total)

tests/i3pm/
├── __init__.py
├── unit/
│   ├── test_models.py               # NEW: Data model validation tests
│   ├── test_pattern_matcher.py      # NEW: Pattern matching logic tests
│   └── test_layout_manager.py       # NEW: Layout operations tests
├── integration/
│   ├── test_daemon_client.py        # NEW: Daemon communication tests
│   ├── test_i3_ipc.py               # NEW: i3 IPC integration tests
│   └── test_layout_restore.py       # NEW: Layout restoration with app relaunching
├── tui/
│   ├── test_layout_manager_screen.py      # NEW: Layout Manager TUI tests
│   ├── test_workspace_config_screen.py    # NEW: Workspace Config TUI tests
│   ├── test_classification_wizard.py      # NEW: Classification wizard tests
│   ├── test_auto_launch_config.py         # NEW: Auto-launch config tests
│   └── test_pattern_config.py             # NEW: Pattern config tests
├── scenarios/
│   ├── test_project_lifecycle.py          # NEW: End-to-end project creation/switch/delete
│   ├── test_layout_workflow.py            # NEW: Save/restore/export layout workflow
│   ├── test_window_classification.py      # NEW: Window classification workflow
│   └── test_monitor_redistribution.py     # NEW: Monitor detection and workspace redistribution
└── fixtures/
    ├── __init__.py
    ├── mock_daemon.py                     # NEW: Mock daemon for testing
    ├── mock_i3.py                         # NEW: Mock i3 IPC for testing
    └── sample_projects.py                 # NEW: Sample project data for tests
```

**Structure Decision**: **Option 1 - Single Python Project Extension**

This feature extends the existing `home-modules/tools/i3_project_manager/` Python application structure. We are:

1. **Extending existing screens**: Layout Manager screen exists but has placeholder implementations - we'll complete all operations
2. **Adding new TUI screens**: 4 new screens for workspace config, classification wizard, auto-launch config, and pattern config
3. **Adding core functionality**: New `layout_manager.py` module for layout operations with application relaunching
4. **Creating comprehensive test suite**: New `tests/i3pm/` directory with unit, integration, TUI, and scenario tests (currently no tests exist)

**No new NixOS modules required** - all changes are within the existing Python application. Testing infrastructure (pytest, pytest-asyncio) already available in development profile per `shared/package-lists.nix`.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
