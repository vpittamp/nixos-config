# Implementation Plan: Interactive Workspace Menu with Keyboard Navigation

**Branch**: `059-interactive-workspace-menu` | **Date**: 2025-11-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/059-interactive-workspace-menu/spec.md`

## Summary

Transform the existing Eww workspace preview dialog (Feature 072) from a static visual display into an interactive menu with keyboard navigation. Users can press Up/Down arrow keys to navigate through workspace headings and window items, press Enter to navigate to the selected item, and press Delete to close selected windows. The feature preserves existing numeric navigation (typing digits + Enter) for backward compatibility while adding visual selection feedback using the Catppuccin Mocha theme.

**Primary Requirement**: Add arrow key navigation and window actions to the workspace preview card shown during workspace mode (CapsLock on M1, Ctrl+0 on Hetzner).

**Technical Approach**: Extend the existing `workspace-preview-daemon` Python daemon to manage selection state, add GTK event handlers to the Eww preview card for arrow key events, implement selection rendering with Catppuccin theme colors, and integrate with Sway IPC for navigation and window close operations. Maintain backward compatibility with existing digit-based filtering and project mode switching.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon and workspace-preview-daemon)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Eww 0.4+ (ElKowar's Wacky Widgets with Yuck DSL), GTK3 (event handling, keyboard input), orjson (fast JSON serialization), pyxdg (desktop entry icon resolution)
**Storage**: In-memory selection state in workspace-preview-daemon (selection index, item type, workspace number, window ID), no persistent storage required
**Testing**: pytest with pytest-asyncio for daemon logic, sway-test framework (TypeScript/Deno) for end-to-end keyboard navigation validation
**Target Platform**: Linux with Sway/Wayland compositor (Hetzner Cloud with 3 virtual displays via HEADLESS-1/2/3, M1 Mac with single eDP-1 display)
**Project Type**: Single project - extending existing workspace-preview-daemon with Eww widget modifications
**Performance Goals**: <10ms selection update latency per arrow key press, <100ms window close operation, <50ms preview card auto-scroll to keep selection visible
**Constraints**: Must maintain backward compatibility with Feature 072 digit-based navigation and project mode (`:` prefix), selection state must be scoped per workspace mode session (reset on exit), GTK event handling must not block Eww rendering pipeline
**Scale/Scope**: Support navigation through 50+ items (workspace headings + windows), handle circular navigation (first ↔ last), auto-scroll preview card when selection moves beyond viewport (600px max height constraint)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Compliance

✅ **Principle I - Modular Composition**: Feature extends existing `workspace-preview-daemon` module and `eww-workspace-bar.nix` configuration. No code duplication - reuses Feature 072 infrastructure (daemon IPC, preview card rendering, Catppuccin theme).

✅ **Principle X - Python Development & Testing Standards**: Uses Python 3.11+ with async/await patterns (i3ipc.aio), pytest for testing, Pydantic models for selection state validation. Follows existing daemon architecture from Feature 015 (i3pm event-driven daemon).

✅ **Principle XI - i3 IPC Alignment & State Authority**: Navigation and window close operations use Sway IPC as authoritative source (GET_TREE for window validation, COMMAND for workspace focus and window kill). Selection state validated against Sway IPC on each action.

✅ **Principle XII - Forward-Only Development & Legacy Elimination**: No backward compatibility code added - existing digit navigation and project mode continue to work via existing code paths. Selection state is additive enhancement, not parallel implementation.

✅ **Principle XIII - Deno CLI Development Standards**: N/A - This feature extends Python daemon, not CLI tool. Testing uses sway-test framework (Deno/TypeScript) per Principle XIV.

✅ **Principle XIV - Test-Driven Development & Autonomous Testing**: Tests written first using pytest for daemon selection logic and sway-test framework for end-to-end keyboard navigation validation. All tests autonomous via Sway IPC state verification and keyboard input simulation (ydotool/wtype).

✅ **Principle XV - Sway Test Framework Standards**: End-to-end tests use declarative JSON test definitions with partial state comparison (focusedWorkspace, selected window, windowCount). Tests validate arrow navigation, Enter navigation, Delete close, and selection persistence across filtering.

### Gate Evaluation

**Status**: ✅ PASSED - All applicable constitution principles satisfied. No violations requiring justification.

**Key Compliance Points**:
- Extends existing modular architecture (workspace-preview-daemon + Eww config)
- Uses Python 3.11+ with async Sway IPC patterns (Principle X)
- Sway IPC as authoritative state source (Principle XI)
- Test-first approach with pytest + sway-test (Principles XIV, XV)
- No legacy compatibility code (Principle XII)

**Re-check After Phase 1**: Verify data model uses Pydantic validation, API contracts follow Sway IPC patterns, and test coverage includes all 4 user stories (P1-P3 priorities).

### Phase 1 Re-check Results

✅ **Data Model** (data-model.md):
- Uses Pydantic `BaseModel` for `SelectionState`, `NavigableItem`, `PreviewListModel`
- Field validators: `@field_validator` for index bounds, item type consistency
- Computed fields: `@computed_field` for derived properties

✅ **API Contracts** (contracts/):
- **sway-ipc-commands.md**: Defines `[con_id=N] kill`, `workspace number N`, `[con_id=N] focus`
- **daemon-ipc-events.md**: Defines 5 IPC events (arrow_key_nav, enter_key_select, delete_key_close, digit_typed, mode_exit)
- Follows i3ipc-python async patterns, includes error handling and timeout logic

✅ **Test Coverage** (quickstart.md workflows):
- **US1 (P1)**: Arrow navigation workflow with circular wrap testing
- **US2 (P2)**: Enter navigation workflow (workspace heading vs window)
- **US3 (P3)**: Delete close workflow with timeout edge cases
- **US4 (P2)**: Visual feedback via CSS `.selected` class (documented in quickstart)

**Constitution Compliance - Final**: ✅ PASSED

## Project Structure

### Documentation (this feature)

```text
specs/059-interactive-workspace-menu/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (GTK event handling, Eww keyboard input, circular navigation patterns)
├── data-model.md        # Phase 1 output (SelectionState, NavigableItem, PreviewListModel entities)
├── quickstart.md        # Phase 1 output (User workflows: arrow navigation, Enter navigation, Delete close)
├── contracts/           # Phase 1 output (Sway IPC commands, daemon IPC events)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/tools/sway-workspace-panel/
├── workspace_panel.py                    # Main daemon (existing - Feature 057)
├── workspace_preview_daemon.py           # Preview daemon (existing - Feature 072)
│   ├── [NEW] SelectionManager class      # Manage selection state (index, item type, circular nav)
│   ├── [NEW] NavigationHandler class     # Handle arrow key events, Enter, Delete
│   ├── [MODIFIED] emit_preview()         # Include selection state in JSON output
│   └── [MODIFIED] handle_workspace_mode() # Reset selection on mode entry/exit
├── models/
│   ├── [NEW] selection_state.py          # Pydantic models: SelectionState, NavigableItem
│   └── preview_state.py                  # (existing - Feature 072)
└── tests/
    ├── test_selection_manager.py         # Unit tests: selection logic, circular nav
    ├── test_navigation_handler.py        # Unit tests: keyboard event handling
    └── integration/
        └── test_arrow_navigation.py      # Integration: Sway IPC navigation validation

home-modules/desktop/
├── eww-workspace-bar.nix                 # Eww configuration (existing - Feature 057)
│   └── [MODIFIED] workspace-mode-preview.yuck  # Add GTK keyboard event listeners
└── unified-bar-theme.nix                 # Catppuccin theme (existing - Feature 057)
    └── [MODIFIED] Add .preview-item-selected CSS class

tests/sway-tests/interactive-workspace-menu/
├── test_arrow_navigation.json            # sway-test: Up/Down navigation, circular wrap
├── test_enter_navigation.json            # sway-test: Enter on workspace heading vs window
├── test_delete_close.json                # sway-test: Delete key closes selected window
└── test_digit_filtering_selection.json   # sway-test: Selection resets when typing digits
```

**Structure Decision**: Single project extension - modifies existing workspace-preview-daemon Python daemon and Eww workspace bar configuration. No new services or daemons required. Selection state lives in-memory within workspace-preview-daemon process. GTK keyboard event handling added to Eww Yuck DSL widget definition. Tests split between pytest (daemon logic) and sway-test (end-to-end navigation flows).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations - Constitution Check passed.
