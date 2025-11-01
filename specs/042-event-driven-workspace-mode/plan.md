# Implementation Plan: Event-Driven Workspace Mode Navigation

**Branch**: `042-event-driven-workspace-mode` | **Date**: 2025-10-31 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/042-event-driven-workspace-mode/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Migrate workspace mode navigation from bash script-based implementation (70ms latency) to event-driven Python daemon architecture (target <20ms latency). The feature replaces external bash processes spawned on each keypress with in-daemon state management and Sway IPC integration. Key improvements include real-time status bar feedback via daemon events, workspace navigation history tracking, and native Sway binding_mode_indicator support for visual mode state display.

## Technical Context

**Language/Version**: Python 3.11+ (existing i3pm daemon runtime)
**Primary Dependencies**: i3ipc-python (i3ipc.aio for async), asyncio, Rich (terminal UI), pytest/pytest-asyncio (testing)
**Storage**: In-memory state only (no persistence) - workspace mode state and history stored in daemon memory, cleared on restart
**Testing**: pytest with pytest-asyncio for async event handling tests
**Target Platform**: NixOS with Sway/Wayland (Hetzner Cloud reference) and i3/X11 compatibility (M1 MacBook Pro)
**Project Type**: Single daemon extension with CLI tools (extends existing i3pm daemon)
**Performance Goals**: <10ms digit accumulation, <20ms workspace switch execution, <5ms status bar event broadcast
**Constraints**: <100ms total navigation latency (mode entry → digit input → execution → focus change), zero file I/O on hot path, async-safe state management
**Scale/Scope**: Single-user system (1 daemon instance), supports 1-3 monitors, tracks last 100 workspace switches, handles 50+ rapid switches per minute

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle III: Test-Before-Apply
✅ **PASS** - Feature follows existing testing patterns (pytest-based testing for daemon extensions, manual testing with automated test framework)

### Principle X: Python Development & Testing Standards
✅ **PASS** - Uses Python 3.11+, async/await with i3ipc.aio, pytest/pytest-asyncio for testing, type hints for APIs, Pydantic for data models, event-driven architecture via i3 IPC subscriptions

### Principle XI: i3 IPC Alignment & State Authority
✅ **PASS** - All workspace state queries use i3 IPC (GET_WORKSPACES, GET_OUTPUTS), output cache refreshed via output events, workspace switch commands via i3 IPC COMMAND, event-driven via SUBSCRIBE

### Principle XII: Forward-Only Development & Legacy Elimination
✅ **PASS** - Completely replaces bash script-based workspace mode with daemon-based architecture, no backwards compatibility with old bash scripts, legacy bash files will be removed

### Principle VI: Declarative Configuration Over Imperative
✅ **PASS** - Sway mode configuration declared in Nix (modes.conf generated via home-manager), CLI commands declared in Nix packages, daemon service configuration declared in NixOS module

### Complexity Justification
**Not Required** - No constitution violations. Feature extends existing i3pm daemon (established pattern), uses proven async patterns from Feature 015, follows Python standards from Features 017-018, maintains i3 IPC alignment from Principle XI.

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
# Daemon Extension (extends existing i3pm daemon)
home-modules/tools/i3pm/
├── daemon/
│   ├── workspace_mode.py      # NEW - Workspace mode state manager
│   ├── workspace_mode_handler.py  # NEW - Event handler for mode events
│   └── main.py                # MODIFIED - Register workspace_mode IPC methods
├── cli/
│   └── workspace_mode.py      # NEW - CLI commands (digit, execute, cancel, state, history)
└── models/
    └── workspace_mode.py      # NEW - Pydantic models (WorkspaceModeState, WorkspaceSwitch, WorkspaceModeEvent)

# Sway Configuration (declarative mode definitions)
home-modules/desktop/sway/
├── modes.conf.nix            # MODIFIED - Add goto_workspace and move_workspace modes
└── keybindings.nix           # MODIFIED - Add CapsLock/Ctrl+0 mode entry bindings

# Status Bar Integration
home-modules/desktop/i3bar/
└── workspace_mode_block.py   # NEW - Status bar script for workspace mode display

# Testing
tests/i3pm/workspace_mode/
├── test_models.py            # NEW - Pydantic model validation tests
├── test_workspace_mode_manager.py  # NEW - State management unit tests
├── test_workspace_mode_ipc.py      # NEW - IPC contract tests
└── scenarios/
    └── test_navigation_workflow.py # NEW - End-to-end navigation scenario tests
```

**Structure Decision**: Feature extends existing i3pm daemon infrastructure (established in Feature 015). Workspace mode logic lives in daemon as a new module with dedicated state manager and event handler. CLI tool delegates to daemon via JSON-RPC IPC (consistent with existing i3pm commands). Sway configuration is declaratively generated via Nix. Testing follows pytest patterns from Features 017-018.

## Complexity Tracking

**Not Applicable** - No constitution violations requiring justification.
