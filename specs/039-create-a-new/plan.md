# Implementation Plan: i3 Window Management System Diagnostic & Optimization

**Branch**: `039-create-a-new` | **Date**: 2025-10-26 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/etc/nixos/specs/039-create-a-new/spec.md`

## Summary

This feature provides systematic diagnosis and optimization of the i3 window management pipeline, eliminating duplicate/conflicting implementations while establishing a pure event-driven architecture. The implementation validates each component independently (event detection, subscription, window identification, rule matching, command execution), consolidates code to a single optimal implementation, and provides comprehensive diagnostic tooling for troubleshooting.

**Key Technical Approach**:
- Event-driven architecture using i3 IPC subscriptions (no polling)
- Python 3.11+ with async/await patterns via i3ipc.aio
- Code audit to identify and eliminate all duplicate implementations
- Diagnostic CLI tools using Rich library for terminal UI
- Comprehensive test coverage (90%+) before legacy code removal
- Window class normalization with alias support
- Process environment variable reading for window context

## Technical Context

**Language/Version**: Python 3.13 (current i3-project-daemon standard)
**Primary Dependencies**:
- i3ipc-python (async i3 IPC communication via i3ipc.aio)
- asyncio (event loop and async patterns)
- Rich (terminal UI for diagnostic tools)
- pytest + pytest-asyncio (testing framework)
- Pydantic (data validation and models)

**Storage**:
- JSON configuration files (~/.config/i3/)
- /proc/{pid}/environ (process environment variable reading)
- Window marks (persistent metadata via i3 IPC)

**Testing**: pytest with async support (pytest-asyncio), integration tests with mock i3 IPC

**Target Platform**: NixOS Linux with i3 window manager (Hetzner reference configuration)

**Project Type**: Single project - Python daemon + CLI tools

**Performance Goals**:
- <50ms window::new event detection
- <100ms workspace assignment execution
- <100ms event processing latency (20+ concurrent windows)
- <5 seconds diagnostic command execution
- <1% CPU usage during steady state

**Constraints**:
- Must read /proc/{pid}/environ for window context
- Must not use polling (event-driven only)
- Must eliminate all duplicate implementations
- Must maintain 99.9% uptime during operation
- Must support daemon restart without losing state

**Scale/Scope**:
- 50+ concurrent window creations (stress test)
- 20+ application types with workspace rules
- 10+ documented misconfiguration scenarios
- 500 event circular buffer for diagnostics

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Modular Composition (Principle I)
- **Status**: PASS
- **Rationale**: Feature consolidates existing i3-project-daemon modules, eliminating duplication. Diagnostic tools will be separate modules in `home-modules/tools/`.

### ✅ Reference Implementation Flexibility (Principle II)
- **Status**: PASS - Using Hetzner i3wm configuration
- **Rationale**: Feature validates on reference Hetzner configuration with i3wm before applying to other platforms.

### ✅ Test-Before-Apply (Principle III)
- **Status**: PASS
- **Rationale**: Implementation includes comprehensive pytest test suite (90%+ coverage) before any legacy code removal. All changes will be tested with `nixos-rebuild dry-build`.

### ✅ Override Priority Discipline (Principle IV)
- **Status**: PASS (N/A for this feature)
- **Rationale**: Feature modifies Python code and configuration files, not NixOS module options.

### ✅ Platform Flexibility Through Conditional Features (Principle V)
- **Status**: PASS
- **Rationale**: Daemon and diagnostic tools work on all platforms with i3 installed. Conditional logic based on `config.services.xserver.enable` already exists.

### ✅ Declarative Configuration Over Imperative (Principle VI)
- **Status**: PASS
- **Rationale**: All configuration remains declarative in NixOS modules and JSON files. No imperative scripts.

### ✅ Documentation as Code (Principle VII)
- **Status**: PASS
- **Rationale**: Feature includes quickstart.md, research.md, data-model.md, and contracts documentation. CLAUDE.md will be updated with new diagnostic commands.

### ✅ Remote Desktop & Multi-Session Standards (Principle VIII)
- **Status**: PASS
- **Rationale**: Feature maintains compatibility with xrdp multi-session setup. Event-driven architecture reduces per-session overhead.

### ✅ Tiling Window Manager & Productivity Standards (Principle IX)
- **Status**: PASS
- **Rationale**: Feature optimizes i3wm workflow with reliable workspace assignment and diagnostic tools.

### ✅ Python Development & Testing Standards (Principle X)
- **Status**: PASS
- **Rationale**: Python 3.13, async/await via i3ipc.aio, pytest with pytest-asyncio, type hints, Pydantic models, Rich terminal UI. Follows established patterns from Feature 017/018.

### ✅ i3 IPC Alignment & State Authority (Principle XI)
- **Status**: PASS
- **Rationale**: All state queries use i3 IPC as authoritative source. Event-driven architecture via i3 IPC subscriptions. Diagnostic tools validate daemon state against i3 IPC.

### ✅ Forward-Only Development & Legacy Elimination (Principle XII)
- **Status**: PASS - **CRITICAL FOR THIS FEATURE**
- **Rationale**: Feature explicitly eliminates duplicate implementations, conflicting APIs, and legacy code. No backwards compatibility, no dual code paths. Complete replacement of suboptimal patterns.

### ⚠️ Deno CLI Development Standards (Principle XIII)
- **Status**: PARTIAL - Using Python instead of Deno
- **Justification**: Daemon requires i3ipc-python library (Python-specific), async integration with existing Python codebase, and pytest testing framework. Diagnostic CLI tools use Rich library (Python). Migration to Deno would require rewriting entire daemon ecosystem.
- **Future Consideration**: New standalone CLI tools (not requiring i3ipc integration) could use Deno.

### Overall Constitution Compliance: ✅ PASS

**Key Strength**: Feature exemplifies Principle XII (Forward-Only Development) by explicitly eliminating technical debt and duplicate implementations.

## Project Structure

### Documentation (this feature)

```
specs/039-create-a-new/
├── plan.md              # This file
├── research.md          # Phase 0: Technical research findings
├── data-model.md        # Phase 1: Entity and state models
├── quickstart.md        # Phase 1: User quickstart guide
├── contracts/           # Phase 1: API contracts
│   ├── daemon-ipc-api.md           # JSON-RPC daemon API spec
│   ├── diagnostic-cli-api.md       # CLI command interface
│   ├── window-identity-schema.json # Window identity data model
│   └── event-schema.json           # Event data structures
├── checklists/
│   └── requirements.md  # Specification quality checklist
└── tasks.md             # Phase 2: NOT created by /speckit.plan
```

### Source Code (repository root)

```
home-modules/desktop/i3-project-event-daemon/
├── __init__.py
├── __main__.py          # Daemon entry point
├── connection.py        # i3 IPC connection and event subscription
├── handlers.py          # Event handlers (window::new, workspace, etc.)
├── state.py             # Daemon state management
├── ipc_server.py        # JSON-RPC IPC server
├── models.py            # Pydantic data models
├── services/
│   ├── window_identifier.py    # Window class normalization (NEW)
│   ├── env_reader.py            # /proc environment reading (ENHANCED)
│   ├── workspace_assigner.py   # Workspace assignment logic (CONSOLIDATED)
│   └── event_processor.py      # Event processing pipeline (NEW)
└── README.md

home-modules/tools/i3pm-diagnostic/
├── __init__.py
├── __main__.py          # CLI entry point
├── models.py            # Diagnostic data models
├── commands/
│   ├── health_check.py          # Daemon health validation
│   ├── window_inspect.py        # Window property inspection
│   ├── event_trace.py           # Event processing trace
│   └── state_validate.py        # State consistency validation
├── displays/
│   ├── health_display.py
│   ├── window_display.py
│   └── event_display.py
└── README.md

tests/i3-project-daemon/
├── unit/
│   ├── test_window_identifier.py
│   ├── test_env_reader.py
│   ├── test_workspace_assigner.py
│   └── test_event_processor.py
├── integration/
│   ├── test_daemon_ipc.py
│   ├── test_i3_connection.py
│   └── test_event_subscription.py
├── scenarios/
│   ├── test_workspace_assignment.py
│   ├── test_window_filtering.py
│   └── test_code_consolidation.py
└── fixtures/
    ├── mock_i3.py
    ├── mock_daemon.py
    └── sample_windows.json
```

**Structure Decision**: Single project structure with separate daemon and diagnostic tool packages. Daemon code lives in `home-modules/desktop/i3-project-event-daemon/` (existing), new diagnostic tools in `home-modules/tools/i3pm-diagnostic/`. Tests organized by type (unit, integration, scenarios) under `tests/`.

## Complexity Tracking

*No Constitution violations requiring justification.*

This feature aligns perfectly with Constitution principles, especially Principle XII (Forward-Only Development) which mandates elimination of duplicate implementations and legacy code without backwards compatibility.

## Phase 0: Outline & Research

### Research Tasks

1. **Window Class Normalization Patterns**
   - Research common window class naming conventions (reverse-domain, simple names)
   - Investigate alias mapping strategies (exact match, substring, regex)
   - Analyze i3ass project's approach to window class matching
   - Document best practices for fuzzy matching vs exact matching

2. **Process Environment Variable Reading**
   - Research /proc/{pid}/environ reading patterns in Python
   - Investigate error handling for missing PIDs, permission denied
   - Document child process vs parent process environment inheritance
   - Best practices for caching environment data vs re-reading

3. **Event-Driven Architecture Patterns**
   - Research i3 IPC subscription reliability and timing
   - Investigate event ordering guarantees and race condition patterns
   - Document best practices for handling rapid event streams
   - Analyze i3ass project's defensive programming strategies

4. **Code Duplication Detection**
   - Research Python AST parsing for duplicate function detection
   - Investigate semantic similarity analysis vs syntactic matching
   - Document strategies for identifying conflicting APIs
   - Best practices for automated code audit tooling

5. **Diagnostic Tool Design**
   - Research Rich library patterns for live displays and tables
   - Investigate best practices for terminal UI error handling
   - Document patterns for JSON output vs human-readable output
   - Analyze diagnostic command patterns from existing tools

**Output**: `research.md` with findings from all research tasks

### Research Questions to Resolve

- **Q1**: What window class normalization strategy provides best UX (exact + substring vs regex)?
- **Q2**: How to handle window PID resolution failures (xprop fallback vs error)?
- **Q3**: What level of code similarity constitutes "duplicate" (AST vs semantic)?
- **Q4**: Should diagnostic tools be integrated into main CLI or separate commands?

## Phase 1: Design & Contracts

### Data Model (`data-model.md`)

**Entities**:

1. **WindowIdentity**
   - window_id: int
   - window_class: str
   - window_class_normalized: str
   - window_instance: str | None
   - window_title: str
   - window_pid: int
   - i3pm_env: I3PMEnvironment | None

2. **I3PMEnvironment**
   - app_id: str
   - app_name: str
   - project_name: str | None
   - project_dir: str | None
   - scope: "scoped" | "global"
   - launch_time: int
   - launcher_pid: int

3. **WorkspaceRule**
   - app_identifier: str  # Can be normalized class or exact class
   - target_workspace: int
   - matching_strategy: "exact" | "normalized" | "alias"
   - aliases: list[str]

4. **DiagnosticReport**
   - timestamp: datetime
   - event_subscriptions: list[EventSubscription]
   - tracked_windows: list[WindowIdentity]
   - recent_events: list[WindowEvent]
   - state_validation: StateValidation
   - i3_ipc_state: I3IPCState

5. **EventSubscription**
   - subscription_type: "window" | "workspace" | "output" | "tick"
   - is_active: bool
   - event_count: int
   - last_event_time: datetime | None

### API Contracts (`contracts/`)

1. **daemon-ipc-api.md**: JSON-RPC methods for diagnostic tools
   - `health_check()` → HealthStatus
   - `get_window_identity(window_id)` → WindowIdentity
   - `get_workspace_rule(app_name)` → WorkspaceRule | None
   - `validate_state()` → StateValidation
   - `get_recent_events(limit, type)` → list[WindowEvent]

2. **diagnostic-cli-api.md**: CLI command specifications
   - `i3pm diagnose health` - daemon health check
   - `i3pm diagnose window <window_id>` - window property inspection
   - `i3pm diagnose events [--limit N] [--type TYPE]` - event trace
   - `i3pm diagnose validate` - state consistency validation

3. **window-identity-schema.json**: Pydantic model JSON schema
4. **event-schema.json**: Event data structures

### Quickstart Guide (`quickstart.md`)

User-facing guide covering:
- How to run diagnostic health check
- How to inspect window properties when workspace assignment fails
- How to trace event processing for debugging
- How to validate daemon state consistency
- Common troubleshooting scenarios with commands

### Agent Context Update

Run `.specify/scripts/bash/update-agent-context.sh claude` to add:
- Python 3.13 with i3ipc.aio
- Rich library for terminal UI
- pytest + pytest-asyncio testing framework
- Pydantic for data models
- Window class normalization patterns
- /proc filesystem environment reading

## Phase 2: Tasks Generation

**NOT created by /speckit.plan** - Will be generated by `/speckit.tasks` command.

Tasks will be ordered by dependency:
1. Code Audit: Identify duplicate implementations
2. Research: Window class normalization, environment reading
3. Core Services: Consolidate workspace assignment, event processing
4. Diagnostic Tools: CLI commands with Rich UI
5. Testing: Unit, integration, scenario tests
6. Legacy Removal: Delete duplicate code after test coverage
7. Documentation: Update CLAUDE.md with new commands

## Success Validation

Implementation will be validated against spec success criteria:

- **SC-001**: 100% window::new events detected (integration tests + stress tests)
- **SC-002**: 95% workspace assignments succeed within 200ms (automated tests)
- **SC-016-022**: Code consolidation metrics (zero duplicates/conflicts after completion)
- **SC-011-015**: Test coverage and validation metrics (90%+ coverage target)

## Notes

- Feature explicitly implements Principle XII (Forward-Only Development) by eliminating all duplicate implementations
- Diagnostic tooling is critical for validating event-driven architecture
- Code consolidation must happen AFTER comprehensive test coverage
- Window class normalization will significantly reduce configuration errors
- /proc environment reading provides deterministic window-to-project association
