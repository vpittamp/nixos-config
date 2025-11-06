# Implementation Plan: i3run-Inspired Application Launch UX Enhancement

**Branch**: `051-i3run-enhanced-launch` | **Date**: 2025-11-06 | **Spec**: [spec.md](spec.md)

## Summary

This feature adopts i3run's superior **UX patterns** for application launching (run-raise-hide state machine, summon mode, scratchpad state preservation) while **rejecting** its window matching approach. Our existing I3PM_* environment variable system provides objectively better window identification than i3run's class/instance/title matching.

**Core Implementation**: Extend existing i3pm daemon with 5-state machine logic, add `i3pm run` CLI command, generalize Feature 062's scratchpad state preservation to all applications.

**Key Integration Points**:
- Feature 041 (launch notification) - no changes needed
- Feature 057 (unified launcher + I3PM_* injection) - no changes needed
- Feature 062 (scratchpad terminal) - generalize state preservation pattern
- Feature 058 (Python daemon) - add `get_window_state()` RPC method

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), asyncio (event loop), psutil (process validation), Pydantic (state models)
**Storage**: In-memory daemon state (window states, scratchpad geometry), persistent config in `~/.config/i3/scratchpad-states.json` (v1.0)
**Testing**: pytest with pytest-asyncio, mock Sway IPC, Wayland input simulation (ydotool), Sway IPC state verification
**Target Platform**: NixOS with Sway compositor (Hetzner headless, M1 physical display)
**Project Type**: Single project (daemon extension + CLI tool)
**Performance Goals**:
- <500ms toggle latency for existing windows (P95)
- <2s launch latency for new applications (P95)
- <10px geometry preservation accuracy (P95)
- 100% unique instance ID generation
- <20MB additional daemon memory footprint

**Constraints**:
- Must integrate with existing i3pm daemon (Feature 058)
- Must use existing app-launcher-wrapper.sh (Feature 057)
- Must preserve Feature 062 scratchpad terminal functionality
- Must work on both headless (Hetzner) and physical (M1) displays
- Must handle multi-monitor configurations (Feature 049)

**Scale/Scope**:
- Support 50+ registered applications
- Handle 10+ concurrent scratchpad windows
- Track state for 100+ windows simultaneously
- Store geometry for up to 50 hidden windows

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition
✅ **PASS** - Extends existing modular architecture:
- Reuses `home-modules/tools/i3pm/daemon/` for Python implementation
- Extends daemon with new RPC methods (no duplication)
- CLI command added to existing `i3pm` tool (Deno TypeScript)
- No monolithic files created

### Principle III: Test-Before-Apply
✅ **PASS** - Test strategy defined:
- Unit tests for 5-state machine logic
- Integration tests for Sway IPC state queries
- End-to-end tests for run-raise-hide workflow
- Scratchpad state preservation validation tests

### Principle X: Python Development & Testing Standards
✅ **PASS** - Follows established patterns:
- Python 3.11+ with async/await patterns
- pytest with pytest-asyncio for async tests
- Pydantic models for state validation
- Follows existing daemon architecture (Feature 058)

### Principle XI: i3 IPC Alignment & State Authority
✅ **PASS** - Sway IPC is authoritative:
- All state queries via Sway IPC GET_TREE, GET_WORKSPACES
- No custom state tracking that contradicts Sway state
- Scratchpad states derived from Sway window properties
- Event-driven updates via Sway IPC subscriptions

### Principle XII: Forward-Only Development & Legacy Elimination
✅ **PASS** - Optimal solution without backwards compatibility:
- No legacy i3run patterns preserved (window matching rejected)
- Adopts only UX patterns that enhance existing system
- Generalizes Feature 062 logic instead of duplicating
- No feature flags or compatibility shims

### Principle XIV: Test-Driven Development & Autonomous Testing
⚠️ **ATTENTION** - Test-first approach required:
- Tests MUST be written before implementation (see Phase 1)
- User flow tests via Wayland input simulation (ydotool)
- State verification via Sway IPC tree queries
- Autonomous test execution without manual intervention

**Gate Status**: ✅ **PASSED** - Proceed to Phase 0 research

**Re-evaluation Required**: After Phase 1 design to verify:
- State model design doesn't violate IPC authority principle
- Test strategy covers all acceptance criteria
- Integration points don't duplicate existing logic

## Project Structure

### Documentation (this feature)

```text
specs/051-i3run-enhanced-launch/
├── plan.md              # This file
├── research.md          # Phase 0 output (technology decisions, patterns)
├── data-model.md        # Phase 1 output (state models, entities)
├── quickstart.md        # Phase 1 output (user guide)
├── contracts/           # Phase 1 output (RPC API contracts)
│   ├── daemon-rpc.json  # JSON-RPC method signatures
│   └── state-schema.json # Scratchpad state storage schema
└── tasks.md             # Phase 2 output (/speckit.tasks - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/tools/i3pm/
├── daemon/
│   ├── scratchpad_manager.py          # Existing (Feature 062) - generalize
│   ├── window_state_manager.py        # NEW - run-raise-hide logic
│   ├── rpc_handlers.py                # EXTEND - add get_window_state() method
│   └── models/
│       ├── scratchpad.py              # Existing - extend with geometry
│       └── window_state.py            # NEW - Pydantic model for window states
│
├── cli/                                # Deno TypeScript CLI
│   ├── commands/
│   │   └── run.ts                     # NEW - i3pm run <app> implementation
│   └── main.ts                        # EXTEND - add run command
│
└── tests/                              # Test suite
    ├── unit/
    │   ├── test_window_state_machine.py
    │   └── test_scratchpad_preservation.py
    ├── integration/
    │   ├── test_sway_ipc_queries.py
    │   └── test_daemon_rpc.py
    └── e2e/
        ├── test_run_raise_hide.py
        └── test_summon_mode.py
```

**Structure Decision**: Extends existing single-project structure (`home-modules/tools/i3pm/`). Python daemon extensions in `daemon/`, Deno TypeScript CLI in `cli/`, tests in `tests/`. No new top-level directories needed - leverages modular composition principle.

## Complexity Tracking

> **No violations** - This feature aligns with all constitution principles and doesn't introduce new complexity requiring justification.

## Phase 0: Research & Technical Decisions

**Status**: ✅ **COMPLETE**

### Research Findings

All technical unknowns resolved. See [research.md](research.md) for detailed analysis.

**Key Decisions**:

1. **Scratchpad State Storage**: Reuse existing `window-workspace-map.json` (Feature 038 pattern)
   - Schema: v1.1 (already exists, no migration needed)
   - Storage: `~/.config/i3/window-workspace-map.json`
   - Rationale: Proven pattern, <10ms latency, atomic writes, schema versioning

2. **5-State Machine**: State class with transition methods (`RunRaiseManager`)
   - Pattern: Service class like `ScratchpadManager`
   - Methods: `detect_window_state()`, `execute_transition()`, `_transition_*()`
   - Rationale: Testability, readability, matches existing daemon architecture

3. **Geometry Preservation**: Floating state + geometry (x, y, width, height)
   - Properties: `floating` (bool), `geometry` (dict with x/y/width/height)
   - Rationale: Feature 038 pattern, user expectations, <10px accuracy requirement

4. **CLI Integration**: New subcommand in `main.ts` using `parseArgs()`
   - File: `src/commands/run.ts`
   - Flags: `--summon`, `--hide`, `--nohide`, `--force`, `--json`
   - Rationale: Consistency with existing commands, code reuse, Deno CLI standards

5. **Sway IPC Queries**: Daemon state + direct ID lookup
   - Performance: ~20-22ms (well under 500ms target)
   - Method: Lookup window_id from daemon, then `tree.find_by_id()`
   - Rationale: Fast, accurate, leverages existing Feature 041 tracking

### Deliverable

✅ **Complete**: [research.md](research.md) with all decisions documented, rationale provided, alternatives considered, and implementation patterns defined.

---

---

## Phase 1: Design & Contracts

**Status**: ✅ **COMPLETE**

### Design Artifacts Generated

1. **`data-model.md`** - Complete data model specification
   - 7 core entities: WindowState, WindowStateInfo, WindowGeometry, ScratchpadState, RunMode, RunRequest, RunResponse
   - State transition diagrams and validation rules
   - Integration with Features 038/041/057/062
   - Performance characteristics and testing strategy

2. **`contracts/daemon-rpc.json`** - JSON-RPC API contract
   - `app.run` method: Main entry point for run-raise-hide
   - `window.get_state` method: Internal state query
   - Complete request/response schemas with examples
   - Error codes and handling patterns

3. **`quickstart.md`** - User documentation and examples
   - CLI reference with all flags and modes
   - Common workflows and use cases
   - Keybinding recommendations
   - Troubleshooting guide
   - Integration examples

### Key Design Decisions

**Data Models**:
- Reuses existing `window-workspace-map.json` schema v1.1 (Feature 038)
- Pydantic models for validation (WindowGeometry, ScratchpadState)
- Python enums for state machine (WindowState, RunMode)
- Immutable data structures (frozen=True)

**API Contract**:
- JSON-RPC 2.0 over Unix socket (/run/i3-project-daemon/ipc.sock)
- Single `app.run` method with mode parameter
- Standard error codes (-32xxx for protocol, custom for app errors)
- JSON output support for scripting

**User Experience**:
- Default summon mode (bring window to me)
- Hide mode for toggle behavior (like i3run)
- NoHide mode for idempotent show
- Force flag for multi-instance apps

### Constitution Re-Check

Re-evaluating gates after design phase:

#### Principle XI: i3 IPC Alignment & State Authority ✅
- ✅ All state queries via Sway IPC GET_TREE
- ✅ No custom state contradicts Sway authority
- ✅ Scratchpad states derived from Sway properties
- ✅ Event-driven updates via Sway IPC subscriptions

#### Principle XIV: Test-Driven Development ✅
- ✅ Test strategy defined in data-model.md
- ✅ Unit tests for each data model
- ✅ Integration tests for state machine
- ✅ End-to-end tests for full workflow
- ✅ Autonomous execution planned (pytest, Sway IPC mocks)

**Gate Status**: ✅ **RE-VALIDATION PASSED** - Design adheres to all constitution principles

---

## Planning Command Complete

**Status**: ✅ **Phase 0 & Phase 1 Complete** - Ready for task generation

**Note**: Per `/speckit.plan` command specification, planning command ends after Phase 2 planning. This feature has completed Phase 0 (Research) and Phase 1 (Design & Contracts).

**Generated Artifacts**:
- ✅ `plan.md` - Implementation plan with technical context and constitution check
- ✅ `research.md` - Technology decisions and implementation patterns
- ✅ `data-model.md` - Complete data model with 7 entities, validation, integration
- ✅ `contracts/daemon-rpc.json` - JSON-RPC API contract with examples
- ✅ `quickstart.md` - User guide with workflows and troubleshooting

**Next Steps**:
- Run `/speckit.tasks` to generate implementation tasks
- Follow test-driven development: write tests → implement → verify
- Phases 2-4 as defined in spec.md (P1: run-raise-hide + summon, P2: scratchpad + force, P3: hide/nohide)

**Branch**: `051-i3run-enhanced-launch` (active)
**Documentation**:
- [spec.md](spec.md) - Feature specification (validated)
- [analysis-window-matching.md](analysis-window-matching.md) - Critical evaluation of i3run patterns
- [checklists/requirements.md](checklists/requirements.md) - Quality checklist (passed)
