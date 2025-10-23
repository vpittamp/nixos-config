# Implementation Plan: Automated Window Rules Discovery and Validation

**Branch**: `031-create-a-new` | **Date**: 2025-10-23 | **Spec**: /etc/nixos/specs/031-create-a-new/spec.md
**Input**: Feature specification from `/specs/031-create-a-new/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature implements an automated system to discover, validate, and migrate window matching patterns for i3's workspace mapping system. The current 65 configured patterns in window-rules.json are untested and causing windows to appear on incorrect workspaces. This tool automates the discovery of correct WM_CLASS/title patterns by launching applications, capturing their window properties via i3 IPC, generating verified patterns, validating them against real windows, and migrating configuration files with automatic backups.

## Technical Context

**Architecture**: Hybrid Deno CLI (frontend) + Python services (backend) architecture
**Frontend Language**: Deno + TypeScript (Constitution Principle XIII - Deno CLI Development Standards)
**Backend Language**: Python 3.11+ (Constitution Principle X - Python for i3 IPC integration)
**Primary Dependencies**:
- **Deno**: @std/cli/parse-args (CLI parsing), @std/fmt/colors (terminal formatting)
- **Python**: i3ipc-python (async), xdotool (rofi simulation), pytest (testing), Rich (terminal UI)
**IPC Communication**: JSON-RPC over Unix sockets or stdin/stdout between Deno CLI and Python services
**Storage**: JSON files (window-rules.json, app-classes.json, application-registry.json) with timestamped backups
**Testing**:
- **Deno**: Deno.test() for CLI interface testing
- **Python**: pytest with pytest-asyncio for backend service testing
**Target Platform**: NixOS with i3 window manager, X11 display server (Hetzner reference configuration)
**Project Type**: Unified i3pm CLI (Deno) with Python backend services for i3 IPC integration
**Performance Goals**:
- CLI startup: <100ms (Deno fast startup)
- Discovery: <15s per application, <20min for 70 applications
- Migration: <2min for 65+ patterns
- Status dashboard: <500ms load time
**Constraints**: Must not disrupt running i3 session, configurable timeout (10s default), zero config corruption
**Scale/Scope**: 70+ applications to discover/validate, 65+ existing patterns to migrate, unified CLI interface for all i3pm operations

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I - Modular Composition: ✅ PASS
- Tool will be created as reusable module in `home-modules/tools/i3-window-rules/`
- Follows existing Python tool patterns from i3-project-monitor and i3-project-test
- Single responsibility: window pattern discovery, validation, and migration

### Principle III - Test-Before-Apply: ✅ PASS
- Dry-run mode for pattern testing without daemon reload (FR-033)
- Timestamped backups before configuration modifications (FR-026)
- JSON validation with automatic rollback on corruption (FR-028)

### Principle VI - Declarative Configuration: ✅ PASS
- Tool generates declarative configuration (window-rules.json, app-classes.json)
- Desktop file customizations documented for NixOS integration (FR-030C)
- No imperative post-install scripts - all configuration managed via JSON

### Principle X - Python Development Standards: ✅ PASS
- Python 3.11+ with async/await patterns for i3 IPC communication
- pytest with pytest-asyncio for automated testing
- Type hints for function signatures and public APIs
- Rich library for terminal UI tables and live displays
- Follows established module structure pattern from i3-project tools

### Principle XI - i3 IPC Alignment: ✅ PASS
- Uses i3ipc-python library for all window property queries
- Queries i3's GET_TREE for authoritative window data
- Validates patterns against i3's actual window state
- Event-driven pattern matching via existing daemon integration

### Principle XII - Forward-Only Development: ⚠️ REQUIRES DECISION
- **Key Decision Required**: FR-012 asks whether to use native i3 `for_window` rules or current event-driven Python daemon
- **Current Implementation**: Event-driven Python daemon (window::new handler)
- **Trade-off**: Need to research if native i3 rules can support:
  - Project context awareness (scoped vs global apps)
  - Parameterized commands ($PROJECT_DIR substitution)
  - Runtime pattern updates without i3 reload
- **Principle Compliance**: Once decision made, implement optimal solution and completely remove alternative approach - no dual support

### Principle XIII - Deno CLI Standards: ✅ PASS - Hybrid Architecture
- **Decision**: Use Deno for user-facing CLI interface, Python for backend i3 IPC services
- **Rationale**:
  - Deno CLI provides fast startup (<100ms), excellent CLI parsing (@std/cli/parse-args), unified interface
  - Python services handle complex i3 IPC integration (i3ipc-python library proven), async event handling
  - Hybrid architecture follows Constitution Principle XIII: "Deno for new CLI tools"
  - Maintains Principle X compliance: "Python for i3-integrated tools"
- **Communication**: Deno CLI ↔ Python services via JSON-RPC (Unix sockets or stdin/stdout)
- **User Experience**: Single `i3pm` command for all operations (rules discover, daemon status, windows list, logs)

### Testing & Validation Standards: ✅ PASS
- Automated pytest test suites required (Constitution Testing Standards)
- Test scenarios for discovery, validation, migration workflows
- Mock implementations for daemon and i3 IPC
- JSON output format for CI/CD integration

### GATE RESULT: ⚠️ CONDITIONAL PASS - Research Required

Two architectural decisions must be resolved in Phase 0 (research.md):

1. **Window Rule Mechanism (FR-012)**: Native i3 `for_window` vs Event-driven daemon
   - Research i3's built-in capabilities for project context awareness
   - Evaluate if parameterized commands compatible with native rules
   - Document decision with rationale

2. **Pattern Matching Complexity (FR-013)**: Simple precedence vs i3king-style scoring
   - Research modern i3 version (4.20+) built-in matching improvements
   - Evaluate if multi-criteria scoring still necessary
   - Document decision with rationale

**These are NOT violations** - they are explicit research questions from the spec that align with Principle XII (forward-only development). The research phase will determine optimal architecture without legacy compatibility constraints.

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
# Deno CLI (user-facing interface)
home-modules/tools/i3pm/
├── deno.json                # Deno configuration, imports, tasks
├── main.ts                  # Entry point with parseArgs() CLI routing
├── mod.ts                   # Public API exports
├── src/
│   ├── commands/
│   │   ├── rules.ts         # Rules subcommand: discover, validate, migrate, interactive
│   │   ├── status.ts        # System status dashboard
│   │   ├── logs.ts          # Log viewing with filtering
│   │   ├── daemon.ts        # Daemon management (existing)
│   │   ├── windows.ts       # Window listing (existing)
│   │   └── project.ts       # Project management (existing)
│   ├── client/
│   │   └── python_service_client.ts  # JSON-RPC client for Python services
│   ├── ui/
│   │   ├── tables.ts        # Table formatting utilities
│   │   ├── colors.ts        # ANSI color utilities (@std/fmt/colors)
│   │   └── progress.ts      # Progress indicators
│   └── types.ts             # TypeScript interfaces for API contracts
├── tests/
│   └── commands_test.ts     # Deno.test() CLI testing
└── README.md

# Python Backend Services (i3 IPC integration)
home-modules/tools/i3-window-rules-service/
├── __init__.py              # Package initialization
├── __main__.py              # JSON-RPC server entry point
├── models.py                # Pydantic models: Window, Pattern, WindowRule, etc.
├── discovery.py             # Discovery service: launch apps, capture properties
├── validation.py            # Validation service: test patterns against windows
├── migration.py             # Migration service: update configs, backups
├── config_manager.py        # Configuration I/O: window-rules.json, app-classes.json
├── i3_client.py             # i3 IPC wrapper via i3ipc-python
├── rofi_launcher.py         # Rofi simulation via xdotool
├── json_rpc_server.py       # JSON-RPC server for Deno CLI communication
└── README.md

# Tests
tests/i3pm-cli/              # Deno CLI tests
├── rules_command_test.ts    # Test CLI argument parsing and output formatting
├── service_client_test.ts   # Test JSON-RPC client communication
└── integration_test.ts      # End-to-end CLI + service tests

tests/i3-window-rules/       # Python service tests
├── unit/
│   ├── test_models.py       # Pydantic models validation
│   ├── test_pattern_generation.py
│   └── test_config_manager.py
├── integration/
│   ├── test_i3_client.py    # i3 IPC communication (mocked)
│   ├── test_discovery_flow.py
│   └── test_validation_flow.py
├── scenarios/
│   ├── test_bulk_discovery.py
│   └── test_migration.py
└── fixtures/
    ├── mock_i3_tree.py
    ├── mock_rofi.py
    └── sample_configs.py

# Configuration files (existing)
~/.config/i3/
├── window-rules.json        # Modified by migration.py
├── app-classes.json         # Modified by migration.py
└── projects/                # Existing project configurations

# Backup directory (created by tool)
~/.config/i3/backups/
└── window-rules-YYYYMMDD-HHMMSS.json  # Timestamped backups
```

**Structure Decision**: Hybrid architecture with Deno CLI frontend and Python backend services. Deno CLI (`i3pm`) provides unified user interface following Constitution Principle XIII (Deno CLI Development Standards). Python services handle i3 IPC integration following Principle X (Python for i3-integrated tools). Communication via JSON-RPC for clean separation. Testing structure supports both Deno CLI tests (Deno.test()) and Python service tests (pytest) as required by Constitution Testing Standards. This architecture enables fast CLI startup (<100ms) while maintaining robust i3 IPC integration.

## Complexity Tracking

*No complexity violations identified. Architecture follows established patterns from i3-project-monitor and i3-project-test tools.*

## Post-Design Constitution Re-Evaluation

**Status**: ✅ ALL GATES PASSED

### Architectural Decisions Finalized (Phase 0)

1. **Window Rule Mechanism (FR-012)**: ✅ RESOLVED
   - **Decision**: Event-driven Python daemon (NOT native i3 for_window)
   - **Rationale**: Supports project context awareness, parameterized commands, runtime updates
   - **Compliance**: Aligns with Principle XII (Forward-Only Development) - optimal solution selected

2. **Pattern Matching Complexity (FR-013)**: ✅ RESOLVED
   - **Decision**: Simple precedence order (NOT i3king-style scoring)
   - **Rationale**: Adequate for distinct application patterns, simpler implementation
   - **Compliance**: Aligns with Principle XII - simpler alternative is sufficient

### Design Validation (Phase 1)

**Data Model Review**:
- ✅ 7 Pydantic models defined with validation rules
- ✅ All entities from spec (Window, Pattern, WindowRule, ApplicationDefinition, DiscoveryResult, ValidationResult, ConfigurationBackup)
- ✅ Type safety via Pydantic v2 field validators
- ✅ Relationships documented

**Contracts Review**:
- ✅ 3 JSON schemas created (window-rules, app-classes, application-registry)
- ✅ Schemas define validation rules, required fields, examples
- ✅ Compatible with existing daemon configuration format
- ✅ Schema versioning for migration compatibility

**Architecture Review**:
- ✅ Module structure follows home-modules/tools/ pattern
- ✅ Testing structure supports unit/integration/scenario tests
- ✅ Separation of concerns: discovery, validation, migration, config I/O, i3 client
- ✅ Terminal UI using Rich library (consistent with i3-project-monitor)

### Constitution Compliance Post-Design

**Principle I - Modular Composition**: ✅ PASS
- Module created in `home-modules/tools/i3-window-rules/`
- Single responsibility: window pattern discovery/validation/migration
- Reusable services: discovery.py, validation.py, migration.py

**Principle III - Test-Before-Apply**: ✅ PASS
- Dry-run mode implemented for migration (`--dry-run`)
- Timestamped backups before config modifications
- JSON validation with rollback on corruption

**Principle VI - Declarative Configuration**: ✅ PASS
- All configuration via JSON files (window-rules.json, app-classes.json, application-registry.json)
- No imperative scripts
- NixOS integration documented (desktop file paths, nix packages)

**Principle X - Python Development Standards**: ✅ PASS
- Python 3.11+ confirmed
- async/await via i3ipc.aio
- Pydantic models for data validation
- Rich library for terminal UI
- pytest with pytest-asyncio for testing
- Module structure matches i3-project-monitor pattern

**Principle XI - i3 IPC Alignment**: ✅ PASS
- All window queries via i3 IPC GET_TREE
- Event-driven via window::new subscriptions
- i3 state is authoritative source
- No parallel state tracking

**Principle XII - Forward-Only Development**: ✅ PASS
- Event-driven daemon selected as optimal solution
- Native i3 for_window approach rejected (insufficient capabilities)
- No hybrid approach (avoids dual code paths)
- Clean architectural decision without legacy compatibility

**Principle XIII - Deno CLI Standards**: ✅ PASS - Hybrid Architecture
- Deno CLI frontend for user interface (fast startup, unified commands)
- Python backend services for i3 IPC integration (i3ipc-python library)
- **Pattern Established**: Deno for CLI presentation layer, Python for i3-integrated services
- **Communication**: JSON-RPC over Unix sockets or stdin/stdout
- **User Experience**: Single `i3pm` command for all system management

**Testing & Validation Standards**: ✅ PASS
- Test structure defined: unit/integration/scenarios
- pytest-asyncio for async testing
- Mock patterns for i3 IPC and daemon
- JSON output for CI/CD integration

### Final Gate Result: ✅ PASS - Ready for Implementation

All architectural decisions resolved. All constitution principles satisfied. Design artifacts complete:
- ✅ research.md (Phase 0)
- ✅ data-model.md (Phase 1)
- ✅ contracts/ (Phase 1)
- ✅ quickstart.md (Phase 1)
- ✅ Agent context updated

**Next Step**: Run `/speckit.tasks` to generate implementation task breakdown
