# Implementation Plan: Eww Interactive Menu Stabilization

**Branch**: `073-eww-menu-stabilization` | **Date**: 2025-11-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/073-eww-menu-stabilization/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Stabilize the Eww workspace preview menu to enable reliable per-window actions (close, move, float toggle, etc.) through keyboard-driven interaction. The primary challenge is that Eww's GTK3 widget system has limited native keyboard support, requiring external keyboard handling via the existing workspace-preview-daemon (Python 3.11+, i3ipc.aio). The feature will fix the critical Delete key issue (windowtype "normal" → "dock" to pass events through to Sway), add multi-action workflow support, provide visual keyboard shortcut hints, and extend window actions beyond basic navigation. Performance target: <20ms state update latency using `defvar` + `eww update` CLI patterns established in Feature 072.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon and workspace-preview-daemon)
**Primary Dependencies**:
- i3ipc.aio (async Sway IPC communication)
- asyncio (event loop, async/await patterns)
- Eww 0.4+ (ElKowar's Wacky Widgets - GTK3 widget system)
- Pydantic (data validation for menu state, action parameters)
- orjson (fast JSON serialization for Eww updates)
- pyxdg (desktop entry icon resolution - existing)

**Storage**: In-memory state in workspace-preview-daemon (selection index, pending action mode, keyboard shortcut hints), no persistent storage required

**Testing**: pytest with pytest-asyncio for async test support, sway-test framework (TypeScript/Deno) for end-to-end window manager testing

**Target Platform**: Linux NixOS with Sway Wayland compositor (Hetzner Cloud, M1 Mac via Asahi Linux)

**Project Type**: Single project - extending existing workspace-preview-daemon in `home-modules/tools/sway-workspace-panel/`

**Performance Goals**:
- <20ms state update latency for Eww UI (via `defvar` + `eww update` CLI pattern)
- <500ms window close operation end-to-end (keypress to window disappearance)
- <100ms keyboard event passthrough (Eww → Sway → daemon → Eww)
- <50ms visual feedback for keyboard shortcut hints

**Constraints**:
- Eww has limited native keyboard support (GTK3 widget focus issues)
- Must use Sway keybindings + daemon IPC for keyboard handling (not GTK event handlers)
- Eww windowtype "dock" required to pass keyboard events through to Sway
- Must maintain compatibility with existing workspace mode navigation (Features 059, 072)
- Must not break multi-monitor workspace preview (Feature 057)

**Scale/Scope**:
- 5 user stories (P1-P3 priority levels)
- 16 functional requirements (FR-001 through FR-016)
- 10 measurable success criteria
- Extends existing workspace-preview-daemon (~1500 lines) with new action handlers
- 7 edge cases to handle (keyboard interception, rapid input, close failures, empty states, monitor disconnect, sub-modes, daemon crashes)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards ✅ PASS
- ✅ **Python 3.11+**: Matches existing i3pm daemon and workspace-preview-daemon
- ✅ **Async/await patterns**: Uses i3ipc.aio for Sway IPC, asyncio for event loop
- ✅ **pytest + pytest-asyncio**: Testing framework for async test support
- ✅ **Pydantic models**: Data validation for menu state, action parameters
- ✅ **Type hints**: Function signatures will include explicit types
- ✅ **Module structure**: Extends existing workspace-preview-daemon with clear separation (models, handlers, services)
- ✅ **CLI tools**: No new CLI tools - daemon extension only
- ✅ **Error handling**: Explicit error messages for close failures, daemon crashes (FR-006, FR-016)

### Principle XI: i3 IPC Alignment & State Authority ✅ PASS
- ✅ **Sway IPC as authoritative source**: All window queries via GET_TREE, workspace queries via GET_WORKSPACES
- ✅ **Event-driven architecture**: Existing workspace-preview-daemon already uses i3 IPC subscriptions
- ✅ **Window marking**: FR-009 maintains visual selection state via Sway marks
- ✅ **i3ipc-python library**: Uses i3ipc.aio for async Sway IPC communication
- ✅ **<100ms latency target**: FR-002 requires 500ms end-to-end, keyboard passthrough <100ms (constraint)

### Principle XII: Forward-Only Development & Legacy Elimination ✅ PASS
- ✅ **Optimal solution**: Uses Eww windowtype "dock" to fix keyboard passthrough issue (no compatibility layers)
- ✅ **No backwards compatibility**: Replaces broken Delete key behavior completely, no gradual migration
- ✅ **Legacy code removal**: Will delete broken windowtype "normal" configuration when implementing "dock" windowtype
- ✅ **No feature flags**: Single solution for keyboard handling (Sway keybindings + daemon IPC)

### Principle XIV: Test-Driven Development & Autonomous Testing ✅ PASS
- ✅ **Test-first approach**: Plan includes pytest unit tests, sway-test end-to-end tests
- ✅ **Test pyramid coverage**: Unit tests (data models, action handlers), integration tests (daemon IPC), end-to-end tests (sway-test framework)
- ✅ **Autonomous execution**: sway-test framework enables declarative JSON test definitions with autonomous execution
- ✅ **State verification**: Tests will verify window close operations via Sway IPC GET_TREE queries
- ✅ **No manual intervention**: Tests run via `pytest tests/` and `sway-test run tests/*.json` without human interaction

### Principle XV: Sway Test Framework Standards ✅ PASS
- ✅ **Declarative JSON tests**: Will create sway-test test cases for window close, multi-action workflows, keyboard shortcuts
- ✅ **Partial mode state comparison**: Tests will check specific properties (focusedWorkspace, windowCount, workspaces[].windows[])
- ✅ **Sway IPC authority**: All tests verify expected state against GET_TREE and GET_WORKSPACES responses
- ✅ **Enhanced error messages**: sway-test framework provides detailed diffs with mode indicators (PARTIAL mode)
- ✅ **Test failure blocking**: All window manager tests must pass before merging (aligns with US1 acceptance criteria)

### Violations Requiring Justification
**None** - All Constitution principles align with feature requirements.

## Project Structure

### Documentation (this feature)

```text
specs/073-eww-menu-stabilization/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── checklists/
│   └── requirements.md  # Already complete - spec validation
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/tools/sway-workspace-panel/  # Existing daemon directory - extend, don't create new
├── workspace-preview-daemon            # Main daemon script - ADD ACTION HANDLERS
├── models.py                           # Existing models - ADD WINDOW ACTION MODELS
├── selection_models/
│   ├── __init__.py
│   └── selection_state.py              # Existing selection tracking - EXTEND WITH SUB-MODES
├── action_handlers.py                  # NEW - Window action execution (close, move, float, etc.)
├── keyboard_hint_manager.py            # NEW - Generate keyboard shortcut help text
├── sub_mode_manager.py                 # NEW - Manage sub-modes (move window, resize, mark)
├── preview_renderer.py                 # Existing - UPDATE TO SHOW KEYBOARD HINTS
├── icon_resolver.py                    # Existing - No changes needed
├── theme_manager.py                    # Existing - No changes needed
├── daemon_client.py                    # Existing - No changes needed
└── workspace_panel.py                  # Existing - No changes needed

home-modules/desktop/                   # Nix configuration changes
├── eww-workspace-bar.nix               # UPDATE - Change windowtype "normal" → "dock"
└── sway-keybindings.nix                # UPDATE - Add Delete key binding in workspace mode

home-modules/tools/sway-test/tests/sway-tests/  # End-to-end tests
├── test_window_close.json              # NEW - US1: Delete key closes window
├── test_multi_action_workflow.json     # NEW - US2: Multiple actions in one session
├── test_keyboard_shortcuts_visible.json # NEW - US3: Keyboard hint display
└── test_extended_window_actions.json   # NEW - US4: Move, float toggle, etc.

tests/workspace-preview-daemon/          # Unit/integration tests (pytest)
├── unit/
│   ├── test_action_handlers.py         # NEW - Test window action logic
│   ├── test_keyboard_hint_manager.py   # NEW - Test hint generation
│   └── test_sub_mode_manager.py        # NEW - Test sub-mode state machine
├── integration/
│   ├── test_daemon_window_close.py     # NEW - Test end-to-end close workflow
│   └── test_daemon_sub_modes.py        # NEW - Test sub-mode workflow
└── fixtures/
    └── mock_sway_connection.py         # Existing or NEW - Mock i3ipc.aio Connection
```

**Structure Decision**: **Single project extension** - This feature extends the existing `workspace-preview-daemon` in `home-modules/tools/sway-workspace-panel/` rather than creating a new daemon or CLI tool. The daemon already handles workspace mode navigation (Feature 072), and this feature adds per-window action capabilities. New modules (`action_handlers.py`, `keyboard_hint_manager.py`, `sub_mode_manager.py`) follow Python module structure standards from Constitution Principle X. Tests use both pytest (unit/integration) and sway-test framework (end-to-end) as mandated by Principles XIV and XV.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No violations to track** - Constitution Check passed all relevant principles without justification requirements.

---

## Phase 1 Complete - Post-Design Constitution Check

**Re-evaluated**: 2025-11-13 after completing research.md, data-model.md, and quickstart.md

### Constitution Check Results: ✅ ALL PRINCIPLES STILL PASS

**Principle X: Python Development & Testing Standards** ✅
- Confirmed: Python 3.11+, i3ipc.aio, Pydantic models, pytest testing
- New modules follow single-responsibility principle (action_handlers.py, keyboard_hint_manager.py, sub_mode_manager.py)
- Data models documented in data-model.md with Pydantic validation
- Testing strategy documented with 3-layer approach (unit/integration/e2e)

**Principle XI: i3 IPC Alignment & State Authority** ✅
- Confirmed: All window queries via Sway IPC GET_TREE
- Action handlers use Sway IPC commands (kill, move, floating toggle)
- No parallel state tracking - Sway IPC is authoritative source
- Debounce tracking is transient optimization, not authoritative state

**Principle XII: Forward-Only Development & Legacy Elimination** ✅
- Confirmed: Eww windowtype "normal" → "dock" replacement (no compatibility layer)
- Delete key fix is complete replacement (no conditional logic for old behavior)
- No feature flags or legacy code preservation

**Principle XIV: Test-Driven Development & Autonomous Testing** ✅
- Confirmed: 3-layer test pyramid documented in research.md
- Unit tests: action_handlers.py, keyboard_hint_manager.py, sub_mode_manager.py
- Integration tests: daemon IPC communication, Eww update commands
- E2E tests: sway-test framework test cases documented (test_window_close.json, etc.)

**Principle XV: Sway Test Framework Standards** ✅
- Confirmed: Declarative JSON test definitions for window close, multi-action workflows
- Partial mode state comparison for focused assertions
- Tests verify Sway IPC authoritative state (GET_TREE, GET_WORKSPACES)

### Final Verdict: ✅ READY FOR /speckit.tasks

All technical decisions align with Constitution principles. Research phase resolved all "NEEDS CLARIFICATION" items. Data model uses Pydantic for validation. Testing strategy includes autonomous execution. No violations requiring justification.

**Next Step**: Run `/speckit.tasks` to generate implementation task breakdown.
