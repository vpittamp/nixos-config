# Implementation Plan: IPC Launch Context for Multi-Instance App Tracking

**Branch**: `041-ipc-launch-context` | **Date**: 2025-10-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/041-ipc-launch-context/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Replace environment variable-based window tracking with an IPC launch notification system where the launcher notifies the daemon before executing applications. The daemon correlates new windows to launch events using application class, timing, and workspace location to achieve correct project assignment for multi-instance applications like VS Code that share processes.

## Technical Context

**Language/Version**: Python 3.11+ (existing i3-project daemon runtime)
**Primary Dependencies**: i3ipc.aio (async i3 IPC), asyncio (event loop), Pydantic (data models)
**Storage**: In-memory pending launch registry (no persistent storage required)
**Testing**: pytest with pytest-asyncio for async tests, tmux integration for interactive testing
**Target Platform**: NixOS Linux with i3 window manager and systemd user services
**Project Type**: System daemon extension (single project)
**Performance Goals**: <10ms correlation per window, <100ms total latency from window event to project assignment
**Constraints**: <5MB memory for pending launch registry (<1000 entries), 5-second launch timeout, zero fallback mechanisms
**Scale/Scope**: 10 simultaneous pending launches supported without degradation, 100% pure IPC correlation (no environment variable fallbacks)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards
- ✅ **Python 3.11+ with async/await**: Using i3ipc.aio for async i3 IPC, asyncio event loop
- ✅ **pytest with pytest-asyncio**: Test framework specified for async tests
- ✅ **Type hints**: Pydantic models specified for data validation
- ✅ **Testing scenarios**: Spec includes comprehensive test scenarios for project lifecycle, rapid launches, timeout handling
- ⚠️ **Test coverage requirement**: Must achieve unit tests (models, correlation algorithm), integration tests (IPC), scenario tests (user stories 1-5)

### Principle XI: i3 IPC Alignment & State Authority
- ✅ **Event-driven architecture**: Extends existing i3 IPC window event subscription system
- ✅ **i3ipc.aio library**: Specified in dependencies for i3 IPC communication
- ✅ **Daemon state validation**: Correlation must query i3 IPC for window properties (class, workspace)
- ✅ **Event subscriptions**: Uses existing window::new event subscription

### Principle XII: Forward-Only Development & Legacy Elimination
- ✅ **No backwards compatibility**: Spec explicitly states "don't worry about backwards compatibility" and "we want to replace the current logic"
- ✅ **No fallback mechanisms**: FR-008 mandates no fallbacks (no title parsing, no process environment, no active project default)
- ✅ **Complete replacement**: Will completely replace environment variable-based tracking with IPC launch context
- ✅ **Explicit failure mode**: FR-009 requires explicit logging of correlation failures for testing validation

### Principle III: Test-Before-Apply
- ✅ **Comprehensive testing**: Spec includes 5 prioritized user stories with acceptance scenarios
- ✅ **Edge case coverage**: Spec documents 7 edge cases with expected behaviors
- ⚠️ **Automated test suite**: Must create pytest test suite achieving 100% edge case coverage (SC-010)

### Principle VI: Declarative Configuration Over Imperative
- ✅ **Daemon extension**: Extends existing declarative systemd user service
- ✅ **No manual configuration**: Launch notification happens via existing IPC infrastructure
- ✅ **State in memory**: Pending launches are ephemeral, not requiring persistent configuration

**Gate Status**: ✅ PASS - All constitutional requirements aligned, no violations requiring justification.

**Post-Design Re-Check**: Must validate after Phase 1 that:
1. Data models use Pydantic for validation
2. Test scenarios cover all 5 user stories and 7 edge cases
3. No fallback mechanisms introduced during implementation
4. All state queries use i3 IPC as authoritative source

## Project Structure

### Documentation (this feature)

```
specs/041-ipc-launch-context/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
home-modules/desktop/i3-project-event-daemon/
├── daemon.py                    # Main daemon event loop (MODIFY)
├── handlers.py                  # Event handlers for window/workspace/output (MODIFY)
├── ipc_server.py                # JSON-RPC IPC server (ADD launch notification endpoint)
├── models.py                    # Pydantic data models (ADD launch notification models)
├── services/
│   ├── launch_registry.py       # NEW: Pending launch management
│   └── window_correlator.py     # NEW: Window-to-launch correlation engine
├── window_filtering.py          # Window filtering logic (MINIMAL CHANGES)
└── state.py                     # Daemon state management (ADD registry state)

home-modules/tools/i3-project-test/
├── scenarios/
│   ├── launch_context/          # NEW: IPC launch context test scenarios
│   │   ├── sequential_launches.py    # User Story 1: Sequential launches
│   │   ├── rapid_launches.py         # User Story 2: Rapid launches
│   │   ├── timeout_handling.py       # User Story 3: Launch timeout
│   │   ├── multi_app_types.py        # User Story 4: Multiple app types
│   │   └── workspace_disambiguation.py # User Story 5: Workspace correlation
│   └── ... (existing scenarios)
├── assertions/
│   └── launch_assertions.py     # NEW: Launch correlation validation
└── test_runner.py               # Existing test runner (EXTEND)

home-modules/tools/i3pm/          # CLI tool (existing)
└── (NO CHANGES - launch notification via existing wrapper)
```

**Structure Decision**: Single project (daemon extension). This feature extends the existing i3-project-event-daemon rather than creating a new project. New modules will be added to the `services/` directory for launch registry and correlation logic. The IPC server will gain a new endpoint for launch notifications. Testing follows existing pytest patterns with new scenario modules for the 5 user stories.

## Phase 0: Research & Architecture Decisions

### Research Tasks

Based on Technical Context unknowns and feature requirements, no clarifications are needed - the specification is complete and all technical context is defined:

✅ **Language/Runtime**: Python 3.11+ (established by existing daemon)
✅ **IPC Communication**: i3ipc.aio async library (existing dependency)
✅ **Data Models**: Pydantic for validation (specified)
✅ **Testing Framework**: pytest with pytest-asyncio (specified)
✅ **Storage**: In-memory registry (specified - no persistent storage)
✅ **Correlation Algorithm**: Multi-signal approach defined in spec (FR-015 to FR-018)

### Architecture Decisions

All architecture decisions and design patterns documented in [research.md](./research.md).

**Key Decisions**:
1. **Launch Notification Protocol**: JSON-RPC endpoint on existing daemon IPC server
2. **Correlation Algorithm**: Multi-signal confidence scoring (class + time + workspace)
3. **Pending Launch Registry**: In-memory dictionary with automatic 5-second expiration
4. **Window Event Integration**: Extend existing `handlers.py` window::new handler
5. **Testing Strategy**: Scenario-based pytest with daemon mock and state validation

**Output**: ✅ `research.md` complete

---

## Phase 1: Data Model & Contracts

### Deliverables

**Output Files**:
1. ✅ `data-model.md` - Complete with Pydantic models and validation rules
2. ✅ `contracts/ipc-endpoints.md` - JSON-RPC API specifications
3. ✅ `quickstart.md` - User workflows and debugging procedures
4. ✅ `CLAUDE.md` - Updated with Python 3.11+, i3ipc.aio, asyncio, Pydantic

**Data Models Created** (in `data-model.md`):
- `PendingLaunch` - Launch awaiting window correlation
- `WindowInfo` - Newly created window from i3 event
- `CorrelationResult` - Match outcome with confidence scoring
- `LaunchRegistryStats` - Diagnostic statistics
- `ConfidenceLevel` - Enum for categorical confidence (EXACT/HIGH/MEDIUM/LOW/NONE)

**API Contracts Created** (in `contracts/ipc-endpoints.md`):
- `notify_launch` - Pre-launch notification endpoint (NEW)
- `get_launch_stats` - Registry statistics query (NEW)
- `get_pending_launches` - Debug endpoint for pending list (NEW)
- `get_window_state` - Extended with correlation info (MODIFIED)

**Quickstart Workflows** (in `quickstart.md`):
- Sequential application launches (User Story 1)
- Rapid application launches (User Story 2)
- Launch timeout testing (User Story 3)
- Debugging procedures and troubleshooting
- Performance benchmarking commands

---

## Phase 2: Implementation Planning

**NOT INCLUDED IN THIS COMMAND** - Use `/speckit.tasks` to generate `tasks.md` with:
- Dependency-ordered implementation tasks
- Test scenario implementation details
- Acceptance criteria validation steps

---

## Post-Design Constitution Re-Check

### ✅ Constitution Validation (Phase 1 Complete)

**Principle X: Python Development & Testing Standards**
- ✅ Pydantic models with validation (`PendingLaunch`, `WindowInfo`, `CorrelationResult`)
- ✅ Type hints on all models (BaseModel with Field descriptors)
- ✅ Data validation via Pydantic validators
- ✅ Clear module structure planned (services/launch_registry.py, services/window_correlator.py)

**Principle XI: i3 IPC Alignment & State Authority**
- ✅ Event-driven architecture (extends existing window::new subscription)
- ✅ i3ipc.aio for async communication
- ✅ State queries defined (get_window_state with correlation info)

**Principle XII: Forward-Only Development & Legacy Elimination**
- ✅ Zero fallback mechanisms (FR-008 enforced in design)
- ✅ Explicit failure logging for testing (CorrelationResult.no_match factory)
- ✅ Complete replacement approach (no environment variable fallbacks)

**Principle III: Test-Before-Apply**
- ✅ Test scenarios defined in quickstart.md
- ✅ Automated test structure planned (scenarios/launch_context/)
- ✅ Mock patterns identified (MockIPCServer in contracts doc)

**Gate Status**: ✅ PASS - Design maintains constitutional alignment

---

## Summary

**Feature**: IPC Launch Context for Multi-Instance App Tracking
**Branch**: `041-ipc-launch-context`
**Status**: Phase 0 & Phase 1 Complete

**Deliverables**:
- ✅ `research.md` - Architecture decisions and patterns
- ✅ `data-model.md` - Pydantic models and entity relationships
- ✅ `contracts/ipc-endpoints.md` - JSON-RPC API specifications
- ✅ `quickstart.md` - User workflows and debugging guide
- ✅ `CLAUDE.md` - Updated agent context

**Next Steps**:
1. Run `/speckit.tasks` to generate dependency-ordered implementation tasks
2. Begin implementation following tasks.md
3. Validate against acceptance criteria in spec.md

**Key Technical Decisions**:
- Launch notification via JSON-RPC on existing daemon IPC server
- Multi-signal correlation (class + time + workspace) with confidence scoring
- In-memory registry with 5-second auto-expiration
- Zero fallback mechanisms for clean failure testing
