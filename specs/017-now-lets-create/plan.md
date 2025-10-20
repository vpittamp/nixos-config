# Implementation Plan: i3 Project System Monitor

**Branch**: `017-now-lets-create` | **Date**: 2025-10-20 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/017-now-lets-create/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Create a terminal-based monitoring tool for the i3 project management system that provides real-time visibility into system state (active project, tracked windows, monitors), live event streaming (window open/close, project switches), historical event review, and i3 tree inspection. The tool uses Python with the Rich library for terminal UI, connects to the daemon via JSON-RPC over Unix socket, supports multiple concurrent display modes (live/events/history/tree), and enables developers to quickly debug and understand the event-driven i3 project system without manually parsing logs.

## Technical Context

**Language/Version**: Python 3.11 (matches existing i3-project daemon)
**Primary Dependencies**: Rich (terminal UI with tables/live displays), i3ipc.aio (i3 tree inspection), existing daemon JSON-RPC client library
**Storage**: In-memory circular buffer for last 500 events, no persistent storage
**Testing**: pytest with unit tests for display formatters, integration tests for daemon communication
**Target Platform**: NixOS Linux with i3 window manager, runs as standalone CLI tool
**Project Type**: Single project (standalone monitoring CLI tool)
**Performance Goals**: Display new events within 100ms of occurrence, handle 1000+ events without degradation, startup time under 1 second
**Constraints**: Minimal complexity (reuse existing daemon IPC patterns), no dependencies on external monitoring frameworks, terminal-only UI (no web/GUI)
**Scale/Scope**: Single-user debugging tool, 4 display modes, ~500 LOC expected, extend daemon with 3-5 new JSON-RPC methods

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Modular Composition (Principle I)
✅ **PASS** - Monitor tool follows modular design:
- Standalone Python module in `home-modules/tools/i3-project-monitor/`
- Reuses existing daemon IPC client library (no duplication)
- Display modes isolated as separate classes (live/events/history/tree)
- Each display mode has single responsibility

### Declarative Configuration (Principle VI)
✅ **PASS** - Configuration is fully declarative:
- Monitor tool installed via home-manager package
- No imperative post-install scripts required
- CLI flags for mode selection (--mode=live|events|history|tree)
- Daemon JSON-RPC methods declared in daemon module

### Documentation as Code (Principle VII)
✅ **PASS** - Documentation included:
- Module header comments explaining purpose and usage
- Quickstart.md will document all display modes and CLI flags
- Integration with existing i3 project documentation
- CLI --help output provides usage guidance

### Package Organization
✅ **PASS** - Follows package standards:
- Monitor tool added to user packages (development profile)
- Rich library added as Python dependency
- No new system-wide packages required
- Tool-specific dependencies scoped to module

### Platform Compatibility
✅ **PASS** - Single platform target:
- Linux with i3 window manager only (matches existing i3-project system)
- Not applicable to WSL/Hetzner/M1 platform differences
- Container deployment not required (debugging tool)

### Testing Requirements
⚠️ **ADVISORY** - Testing strategy defined:
- Unit tests for display formatters
- Integration tests for daemon communication
- Manual testing on Hetzner i3 environment
- Note: Testing relies on daemon running, may need mock daemon for CI

### Complexity Justification
✅ **NO VIOLATIONS** - Feature adds reasonable complexity:
- Extends existing i3-project system with debugging tool
- Reuses established patterns (JSON-RPC, asyncio, Rich UI)
- No new abstraction layers or deep inheritance
- 4 display modes justified by distinct debugging needs (P1-P4 priorities)

**GATE STATUS**: ✅ **APPROVED** - No constitutional violations, proceed to Phase 0

---

## Post-Design Constitution Re-evaluation

*Re-checked after Phase 1 design completion*

### Modular Composition (Principle I)
✅ **PASS** - Design maintains modular structure:
- Monitor tool as standalone Python module with clear separation of concerns
- Display modes (live/events/history/tree) as separate classes
- Daemon extensions (EventBuffer, list_monitors, subscribe_events) cleanly integrate into existing architecture
- No duplication - reuses existing IPC patterns, data models, and connection handling

### Declarative Configuration (Principle VI)
✅ **PASS** - All configuration remains declarative:
- Monitor tool packaged via home-manager (Python package with CLI wrapper)
- Daemon extensions declared in existing daemon module
- No runtime configuration files or imperative setup required
- CLI flags for mode selection are runtime behavior, not configuration

### Documentation as Code (Principle VII)
✅ **PASS** - Comprehensive documentation generated:
- research.md - technology decisions and best practices
- data-model.md - all data structures and validation rules
- contracts/jsonrpc-api.md - complete API specification
- quickstart.md - user guide with examples and troubleshooting
- Plan includes inline documentation requirements for code

### Testing Requirements
✅ **PASS** - Testing strategy defined in contracts:
- Unit tests for display formatters (Rich table generation)
- Integration tests for daemon communication (JSON-RPC calls)
- Manual testing checklist in contracts/jsonrpc-api.md
- Mock daemon pattern for CI environment testing

### Complexity Justification
✅ **NO NEW VIOLATIONS** - Design complexity justified:
- 4 display modes justified by P1-P4 priority user stories
- EventBuffer (500 events) justified by debugging requirement (FR-006)
- Event streaming via JSON-RPC notifications justified by <100ms latency requirement (SC-002)
- No unnecessary abstractions added - all patterns reused from existing daemon

**RE-EVALUATION RESULT**: ✅ **APPROVED** - Design adheres to all constitutional principles

---

## Project Structure

### Documentation (this feature)

```
specs/017-now-lets-create/
├── plan.md                      # This file (implementation plan)
├── spec.md                      # Feature specification (input)
├── research.md                  # Phase 0: Technology decisions
├── data-model.md                # Phase 1: Data structures and validation
├── quickstart.md                # Phase 1: User guide
├── contracts/                   # Phase 1: API contracts
│   └── jsonrpc-api.md          # Extended daemon JSON-RPC API
└── tasks.md                     # Phase 2: Task breakdown (generated by /speckit.tasks)
```

### Source Code (repository root)

**Monitor Tool** (new standalone Python module):
```
home-modules/tools/i3-project-monitor/
├── __init__.py                  # Package initialization
├── __main__.py                  # CLI entry point (argparse)
├── models.py                    # Data models (MonitorState, WindowEntry, etc.)
├── daemon_client.py             # JSON-RPC client for daemon communication
├── displays/
│   ├── __init__.py
│   ├── base.py                 # Base display class with Rich helpers
│   ├── live.py                 # Live state display mode
│   ├── events.py               # Event stream display mode
│   ├── history.py              # Historical event log display mode
│   └── tree.py                 # i3 tree inspector display mode
└── README.md                    # Module documentation

tests/i3-project-monitor/
├── test_models.py               # Data model validation tests
├── test_daemon_client.py        # IPC client tests (mock daemon)
├── test_displays.py             # Display formatter tests
└── fixtures/
    └── mock_daemon.py          # Mock daemon for integration tests
```

**Daemon Extensions** (existing daemon, extended):
```
home-modules/desktop/i3-project-event-daemon/
├── __init__.py
├── __main__.py
├── daemon.py
├── connection.py
├── config.py
├── state.py
├── models.py                    # Extended with EventEntry model
├── ipc_server.py                # Extended with list_monitors, subscribe_events
├── handlers.py                  # Extended to populate EventBuffer
└── event_buffer.py              # NEW: Circular buffer for event storage
```

**NixOS Integration**:
```
home-modules/tools/
└── i3-project-monitor.nix       # NEW: Home-manager module for monitor tool

home-modules/desktop/
└── i3-project-daemon.nix        # Updated: Add monitor tool to packages

scripts/
└── i3-project-monitor           # NEW: Bash wrapper for CLI tool
```

**Structure Decision**:

This implementation follows the **single project** pattern with a clear separation between:

1. **Monitor Tool** (`home-modules/tools/i3-project-monitor/`): Standalone Python module with display modes as subpackages. Packaged via home-manager, installed as user-level tool.

2. **Daemon Extensions** (`home-modules/desktop/i3-project-event-daemon/`): Extends existing daemon with EventBuffer and new JSON-RPC methods. Maintains existing architecture.

3. **Tests** (`tests/i3-project-monitor/`): Isolated test suite with mock daemon for integration testing without requiring live i3 instance.

The structure reuses existing daemon patterns (models.py, ipc_server.py) and follows NixOS home-manager conventions (tool modules in `home-modules/tools/`).

**Key Design Decisions**:
- Display modes separated into `displays/` subpackage for modularity
- Daemon client abstraction (`daemon_client.py`) enables easy mocking for tests
- EventBuffer as separate module in daemon for clean separation of concerns
- Bash wrapper script for convenient CLI invocation (follows i3-project-* naming)

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
