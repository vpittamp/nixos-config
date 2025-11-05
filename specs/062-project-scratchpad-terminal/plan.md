# Implementation Plan: Project-Scoped Scratchpad Terminal

**Branch**: `062-project-scratchpad-terminal` | **Date**: 2025-11-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/062-project-scratchpad-terminal/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable users to access a project-scoped, persistent floating terminal via keybinding (Mod+Shift+Return) that opens in the project's root directory, maintains independent state per project, and toggles show/hide without affecting other windows. The terminal leverages Sway's scratchpad mechanism for hiding while keeping the process running, with the i3pm daemon tracking project-to-terminal associations and managing lifecycle events.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), asyncio (event loop), psutil (process validation)
**Storage**: In-memory daemon state (project → terminal PID/window ID mapping), Sway window marks for persistence
**Testing**: pytest with pytest-asyncio, ydotool for Wayland input simulation, Sway IPC state verification
**Target Platform**: NixOS with Sway Wayland compositor (hetzner-sway, m1 configurations)
**Project Type**: System daemon extension with CLI integration
**Performance Goals**: <500ms terminal toggle for existing terminals, <2s for initial launch, <100ms daemon event processing
**Constraints**: Single terminal per project, Alacritty only, must not interfere with existing project window filtering, terminals don't persist across Sway restarts
**Scale/Scope**: 5-10 concurrent projects typical, 20-30 projects maximum, single-user system

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards ✅ PASS
- **Requirement**: Python 3.11+, async/await for i3 IPC, pytest with pytest-asyncio, type hints, Pydantic models
- **Compliance**: Feature will use Python 3.11+ matching i3pm daemon, i3ipc.aio for async IPC, pytest-asyncio for testing
- **Notes**: Extends existing i3pm daemon architecture consistently

### Principle XI: i3 IPC Alignment & State Authority ✅ PASS
- **Requirement**: i3 IPC as authoritative source, event-driven architecture, GET_TREE/GET_MARKS for state queries
- **Compliance**: Feature will query Sway IPC for window state, use window marks for terminal identification, subscribe to window events
- **Notes**: Daemon will validate terminal existence via Sway IPC GET_TREE rather than relying solely on internal state

### Principle XII: Forward-Only Development & Legacy Elimination ✅ PASS
- **Requirement**: Optimal solution without backwards compatibility constraints, replace legacy code completely
- **Compliance**: Spec explicitly states "prioritizes optimal solution over backwards compatibility" and allows replacing existing scratchpad patterns
- **Notes**: Will replace any legacy scratchpad terminal approaches with unified project-scoped implementation

### Principle XIV: Test-Driven Development & Autonomous Testing ✅ PASS
- **Requirement**: Test-first development, comprehensive test pyramid, autonomous user flow testing via ydotool/Sway IPC
- **Compliance**: Will write tests before implementation, use ydotool for keybinding simulation, verify state via Sway IPC
- **Notes**: Test scenarios from spec translate directly to automated test cases (terminal launch, toggle, multi-project isolation)

### Principle I: Modular Composition ✅ PASS
- **Requirement**: Composable modules, single responsibility, proper NixOS option patterns
- **Compliance**: Feature extends i3pm daemon module, adds keybinding to Sway configuration module
- **Notes**: No new top-level modules needed, integrates into existing architecture

### Principle III: Test-Before-Apply ✅ PASS
- **Requirement**: Always dry-build before applying configuration changes
- **Compliance**: Standard NixOS development workflow will be followed
- **Notes**: Required for all configuration changes during implementation

### Gate Evaluation: ✅ ALL GATES PASS
No constitution violations identified. Feature aligns with existing architecture patterns and principles. Proceeding to Phase 0 research.

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
home-modules/tools/i3pm-deno/
├── src/
│   ├── commands/
│   │   └── scratchpad.ts        # NEW: CLI commands for scratchpad terminal
│   ├── daemon-client.ts          # EXISTING: JSON-RPC client
│   └── models.ts                 # MODIFY: Add scratchpad types
└── main.ts                       # MODIFY: Add scratchpad subcommand

home-modules/tools/i3pm/
├── src/
│   ├── daemon/
│   │   ├── event_handlers.py    # MODIFY: Add window event handling for terminals
│   │   ├── scratchpad_manager.py # NEW: Scratchpad terminal lifecycle management
│   │   └── state.py             # MODIFY: Add scratchpad terminal tracking
│   ├── models/
│   │   └── scratchpad.py        # NEW: Pydantic models for scratchpad state
│   └── services/
│       └── terminal_launcher.py  # NEW: Alacritty launch with env vars
└── tests/
    ├── unit/
    │   └── test_scratchpad_manager.py    # NEW: Unit tests
    ├── integration/
    │   └── test_terminal_lifecycle.py     # NEW: Integration tests
    └── scenarios/
        └── test_user_workflows.py         # NEW: E2E user flow tests

home-modules/desktop/sway.nix     # MODIFY: Add scratchpad keybinding
```

**Structure Decision**: Extends existing i3pm daemon (Python) and i3pm CLI (TypeScript/Deno) with scratchpad functionality. Python daemon handles terminal lifecycle and state management via async event handlers. Deno CLI provides user-facing commands. Sway keybinding configuration integrates via existing NixOS module structure.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No complexity violations identified. Feature integrates cleanly into existing architecture.

---

## Phase 0 Output: Research (COMPLETED)

✅ **File**: `research.md`

**Key Decisions**:
1. **Terminal Identification**: Sway marks (`scratchpad:{project_name}`) + I3PM_* environment variables
2. **Launch Mechanism**: `asyncio.create_subprocess_exec()` with env var injection
3. **State Sync**: In-memory daemon state validated against Sway IPC GET_TREE
4. **Scratchpad Commands**: Native Sway `move scratchpad`, `scratchpad show` with mark criteria
5. **Event Filtering**: Mark prefix + env var validation for window event handling

**Technology Stack**: Python 3.11+, i3ipc.aio, Pydantic, pytest-asyncio, ydotool, TypeScript/Deno CLI

---

## Phase 1 Output: Design (COMPLETED)

✅ **File**: `data-model.md`
- **Entities**: `ScratchpadTerminal` (Pydantic model), `ScratchpadManager` (lifecycle manager)
- **State Model**: In-memory dict with Sway IPC validation
- **Lifecycle**: Created → Visible ↔ Hidden → Terminated

✅ **File**: `contracts/scratchpad-rpc.json`
- **Methods**: `scratchpad.toggle`, `scratchpad.launch`, `scratchpad.status`, `scratchpad.close`, `scratchpad.cleanup`
- **Transport**: Unix socket JSON-RPC
- **Error Handling**: Standard JSON-RPC error codes with application-specific codes

✅ **File**: `quickstart.md`
- **Workflows**: Basic toggle, multi-project isolation, state persistence, global terminal
- **Troubleshooting**: Launch failures, toggle issues, working directory problems
- **Diagnostics**: Status queries, validation, cleanup

✅ **Context Update**: CLAUDE.md updated with scratchpad architecture patterns

---

## Re-evaluated Constitution Check (POST-DESIGN)

### Principle XIV: Test-Driven Development ✅ PASS
- **Design compliance**: `quickstart.md` includes manual test procedures, `research.md` documents E2E test strategy with ydotool
- **Implementation readiness**: Test scenarios map directly to acceptance criteria, pytest structure defined

### Principle XI: i3 IPC Alignment ✅ PASS
- **Design compliance**: Sway IPC is authoritative source, validation on every operation, event-driven architecture
- **Implementation readiness**: `ScratchpadManager.validate_terminal()` queries Sway GET_TREE before operations

### All Other Principles ✅ PASS
- No design changes introduced constitution violations
- Architecture remains modular, forward-only, properly tested

**Final Gate Evaluation**: ✅ ALL GATES PASS (POST-DESIGN)

---

## Next Steps (Phase 2 - NOT executed by this command)

**Command**: `/speckit.tasks` (generates `tasks.md` from plan and spec)

**Expected Tasks**:
1. Implement `ScratchpadTerminal` Pydantic model with validation
2. Implement `ScratchpadManager` lifecycle methods
3. Add window event handlers to i3pm daemon for terminal tracking
4. Implement JSON-RPC handlers for scratchpad methods
5. Add Deno CLI commands for scratchpad operations
6. Add Sway keybinding configuration
7. Write unit tests for models and manager
8. Write integration tests for daemon IPC
9. Write E2E tests for user workflows with ydotool
10. Update documentation and rebuild NixOS configuration

**Implementation Branch**: `062-project-scratchpad-terminal` (already created)
