# Implementation Plan: Workspace Navigation Event Broadcasting

**Branch**: `059-workspace-nav-events` | **Date**: 2025-11-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/059-workspace-nav-events/spec.md`

## Summary

Add navigation event broadcasting methods (`nav()`, `delete()`) to the i3pm daemon's WorkspaceModeManager class, connecting existing Sway keybindings to existing workspace-preview-daemon handlers. This "glue code" feature enables arrow key navigation through workspace preview without requiring new UI components or keybinding changes.

**Primary Requirement**: Broadcast navigation events (Up/Down/Left/Right/Home/End/Delete) from i3pm daemon to workspace-preview-daemon subscribers within 50ms of CLI command receipt.

**Technical Approach**: Add two async methods to WorkspaceModeManager class following the existing `add_digit()` pattern - both methods will call `_emit_workspace_mode_event()` with appropriate event_type and direction payload.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon - Constitution Principle X)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Pydantic (event data models), orjson (fast JSON serialization for IPC)
**Storage**: N/A (in-memory state only, consumed by workspace-preview-daemon subscribers via JSON-RPC IPC)
**Testing**: pytest with pytest-asyncio for async tests, sway-test framework for end-to-end navigation workflow
**Target Platform**: Linux with Sway Wayland compositor (hetzner-sway reference, M1 secondary)
**Project Type**: Single project (daemon extension)
**Performance Goals**: <50ms event broadcast latency, <1% CPU overhead, non-blocking IPC emission
**Constraints**: Must not block main daemon event loop, graceful handling when no subscribers, event delivery within 50ms (human perception threshold)
**Scale/Scope**: 4 user stories (P1: arrow nav, P2: window nav, P3: home/end, P3: delete), 10 functional requirements, 2 new methods in WorkspaceModeManager

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards ✅
- **Requirement**: Python 3.11+, async/await patterns, pytest, Pydantic models
- **Compliance**: Uses existing Python 3.11 daemon, follows async patterns from `add_digit()`, Pydantic models for events
- **Gate**: PASS - Extends existing codebase with consistent patterns

### Principle XI: i3 IPC Alignment & State Authority ✅
- **Requirement**: Sway IPC as authoritative source, event-driven architecture, <100ms latency
- **Compliance**: Navigation events broadcast via existing IPC server infrastructure, non-blocking async emission
- **Gate**: PASS - Follows existing event broadcasting pattern from Features 042/058

### Principle XII: Forward-Only Development & Legacy Elimination ✅
- **Requirement**: No backwards compatibility, complete replacement of suboptimal code
- **Compliance**: No legacy code - this is net-new functionality connecting existing infrastructure
- **Gate**: PASS - Pure addition, no legacy compatibility concerns

### Principle XIV: Test-Driven Development & Autonomous Testing ✅
- **Requirement**: Test-first approach, autonomous execution, comprehensive test pyramid
- **Compliance**: Will write pytest unit tests before implementation, sway-test for end-to-end
- **Gate**: PASS - TDD workflow required (tests written in Phase 2)

### Principle XV: Sway Test Framework Standards ✅
- **Requirement**: Declarative JSON tests for window manager interactions
- **Compliance**: Will use sway-test for end-to-end navigation workflow validation
- **Gate**: PASS - Framework exists, will add navigation test cases

**Constitution Check Status**: ✅ PASS - All relevant principles satisfied, no violations

## Project Structure

### Documentation (this feature)

```text
specs/059-workspace-nav-events/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── navigation-events.json  # JSON-RPC event schema
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/desktop/i3-project-event-daemon/
├── workspace_mode.py           # MODIFY: Add nav() and delete() methods (lines ~350-400)
├── models.py                   # VERIFY: NavigationEvent model already exists (Feature 059 prep)
└── handlers.py                 # VERIFY: JSON-RPC handlers call new methods

home-modules/tools/sway-workspace-panel/
├── workspace-preview-daemon    # VERIFY: Event handlers already exist (lines 922-939)
├── selection_models/
│   ├── selection_manager.py    # VERIFY: SelectionManager already exists
│   └── navigation_handler.py   # VERIFY: NavigationHandler already exists

home-modules/desktop/sway-keybindings.nix
└── (lines 674-678)             # VERIFY: Arrow key bindings already call i3pm-workspace-mode nav

tests/
└── i3pm/
    ├── test_workspace_mode_nav.py        # NEW: Unit tests for nav() and delete() methods
    └── integration/
        └── test_nav_event_broadcast.py  # NEW: Integration test for end-to-end event flow

home-modules/tools/sway-test/tests/sway-tests/
└── integration/
    └── test_navigation_workflow.json    # NEW: End-to-end navigation test with sync
```

**Structure Decision**: Single project extension - modifying existing daemon (`workspace_mode.py`) with two new methods. No new services or daemons required. Testing uses existing pytest framework plus sway-test for end-to-end validation.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

N/A - No constitution violations. This feature follows all established patterns:
- Python 3.11+ with async/await (Principle X)
- Event-driven architecture via Sway IPC (Principle XI)
- Test-driven development (Principle XIV)
- Declarative sway-test for window manager testing (Principle XV)

## Phase 0: Research

### Research Questions

**Q1**: How does the existing `add_digit()` method emit events to subscribers?
- **Finding**: Calls `await self._emit_workspace_mode_event("digit")` which broadcasts via `self._ipc_server`
- **Pattern**: All event emission goes through `_emit_workspace_mode_event(event_type, **kwargs)`
- **Implication**: Nav events should follow same pattern for consistency

**Q2**: What payload structure is expected by workspace-preview-daemon navigation handlers?
- **Finding**: Handlers expect `event_type` (string) and `direction` (string) fields
- **Code**: `direction = payload.get("direction")` in workspace-preview-daemon line 927
- **Implication**: Payload must include `{"event_type": "nav", "direction": "up|down|left|right|home|end"}`

**Q3**: What are the performance constraints for event broadcasting?
- **Finding**: Target <50ms latency (human perception threshold from spec)
- **Measurement**: `add_digit()` achieves <20ms typical latency via async non-blocking IPC
- **Implication**: Same async pattern will meet <50ms requirement

**Q4**: Should navigation state be tracked in WorkspaceModeState?
- **Finding**: Not required - SelectionManager in workspace-preview-daemon owns navigation state
- **Decision**: i3pm daemon is stateless broadcaster, preview daemon is stateful consumer
- **Rationale**: Separation of concerns - daemon broadcasts, preview manages selection

**Q5**: What error handling is needed when no subscribers exist?
- **Finding**: `_emit_workspace_mode_event()` already handles gracefully: `if not self._ipc_server: return`
- **Pattern**: Logged at DEBUG level, no exceptions raised
- **Implication**: No additional error handling needed

See [research.md](research.md) for detailed findings and architectural patterns.

## Phase 1: Design & API Contracts

### Data Models

See [data-model.md](data-model.md) for complete entity definitions.

**Key Entities**:
1. **NavigationEvent**: Event payload with `direction` field (up/down/left/right/home/end)
2. **SelectionState**: Managed by workspace-preview-daemon, tracks current highlight
3. **EventBroadcast**: JSON-RPC IPC message with navigation event payload

### API Contracts

See [contracts/navigation-events.json](contracts/navigation-events.json) for JSON-RPC schema.

**New Methods**:
1. `workspace_mode.nav(direction: str)` - JSON-RPC method
2. `workspace_mode.delete()` - JSON-RPC method

**Event Schema**:
```json
{
  "type": "workspace_mode",
  "payload": {
    "event_type": "nav",
    "direction": "up",
    "mode": "all_windows",
    "timestamp": "2025-11-12T14:30:00Z"
  }
}
```

### Quickstart Guide

See [quickstart.md](quickstart.md) for user-facing navigation instructions.

## Phase 2: Implementation Tasks

*Detailed in `/speckit.tasks` command output - NOT created by `/speckit.plan`*

**Task Preview** (will be refined in tasks.md):

1. **Write unit tests for nav() method** (TDD - before implementation)
   - Test valid directions (up/down/left/right/home/end)
   - Test invalid direction raises ValueError
   - Test inactive mode raises RuntimeError
   - Test event emission payload structure

2. **Write unit tests for delete() method** (TDD - before implementation)
   - Test delete in active mode
   - Test delete in inactive mode raises RuntimeError
   - Test event emission payload structure

3. **Implement nav() method in WorkspaceModeManager**
   - Add async method following `add_digit()` pattern
   - Validate direction parameter
   - Call `_emit_workspace_mode_event("nav", direction=direction)`
   - Add docstring with Feature 059 reference

4. **Implement delete() method in WorkspaceModeManager**
   - Add async method following `cancel()` pattern
   - Validate mode is active
   - Call `_emit_workspace_mode_event("delete")`
   - Add docstring with Feature 059 reference

5. **Add JSON-RPC handlers in daemon handlers.py**
   - Register `workspace_mode.nav` JSON-RPC method
   - Register `workspace_mode.delete` JSON-RPC method
   - Wire to WorkspaceModeManager instance

6. **Write integration test for event broadcasting**
   - Mock IPC server
   - Call nav() and delete()
   - Verify correct event payloads emitted

7. **Write sway-test end-to-end navigation test**
   - Enter workspace mode via IPC
   - Send nav commands via CLI
   - Verify preview state changes (via daemon inspection)

8. **Run all tests until passing**
   - Execute pytest test suite
   - Execute sway-test navigation workflow
   - Fix any failures

9. **Update CLAUDE.md with navigation keybindings**
   - Document arrow key behavior in workspace mode
   - Add troubleshooting section for navigation

10. **Rebuild NixOS configuration and test on hetzner-sway**
    - `sudo nixos-rebuild switch --flake .#hetzner-sway`
    - Manual testing: Enter workspace mode, test arrow keys
    - Verify <50ms visual feedback

## Phase 3: Validation & Documentation

*Post-implementation validation checklist*

- [ ] All pytest tests pass (unit + integration)
- [ ] sway-test end-to-end navigation test passes
- [ ] Manual testing on hetzner-sway confirms <50ms latency
- [ ] Manual testing on M1 confirms navigation works (if applicable)
- [ ] CLAUDE.md updated with navigation documentation
- [ ] quickstart.md provides clear user instructions
- [ ] No performance regression (<1% CPU overhead verified)
- [ ] Code follows existing patterns (`add_digit()` as reference)
- [ ] Docstrings reference Feature 059
- [ ] Constitution compliance re-validated (all gates still PASS)

## Success Criteria Mapping

**From spec.md Success Criteria**:

1. **SC-001**: Users can navigate through entire workspace list with visual feedback <50ms
   - **Implementation**: `nav()` method broadcasts events, preview daemon updates UI
   - **Validation**: sway-test measures latency, manual testing confirms visual feedback

2. **SC-002**: 100% of navigation key presses result in correct preview state changes
   - **Implementation**: Event-driven architecture ensures deterministic state updates
   - **Validation**: Integration tests mock all key combinations, verify state changes

3. **SC-003**: Users can select and switch to any workspace using keyboard navigation
   - **Implementation**: `nav()` for navigation, existing `execute()` for workspace switch
   - **Validation**: sway-test end-to-end test navigates to workspace 23, verifies switch

4. **SC-004**: System handles rapid navigation (10+ key presses/sec) without dropping events
   - **Implementation**: Async non-blocking IPC prevents event queue saturation
   - **Validation**: Integration test sends 20 events in 2 seconds, verifies all processed

5. **SC-005**: Navigation state cleared immediately (<20ms) when workspace mode exits
   - **Implementation**: Preview daemon resets on `cancel` or `execute` events
   - **Validation**: Integration test measures state reset latency

## Agent Context Update

*Placeholder - will be updated by `.specify/scripts/bash/update-agent-context.sh claude`*

**New Technologies Added**:
- None (all technologies already in use from Features 042, 059, 072)

**Existing Technologies Confirmed**:
- Python 3.11+ (i3pm daemon)
- i3ipc.aio (async Sway IPC)
- Pydantic (data models)
- orjson (JSON serialization)
- pytest + pytest-asyncio (testing)
- sway-test framework (end-to-end testing)
