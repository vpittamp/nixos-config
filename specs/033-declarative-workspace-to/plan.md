# Implementation Plan: Declarative Workspace-to-Monitor Mapping Configuration

**Branch**: `033-declarative-workspace-to` | **Date**: 2025-10-23 | **Spec**: [spec.md](/etc/nixos/specs/033-declarative-workspace-to/spec.md)
**Input**: Feature specification from `/specs/033-declarative-workspace-to/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Replace the hardcoded workspace-to-monitor distribution logic (currently in `workspace_manager.py` and `detect-monitors.sh`) with a declarative JSON configuration system that allows explicit definition of workspace assignments across 1-3 monitor setups. Implement event-driven workspace redistribution via the existing i3 daemon, add comprehensive CLI/TUI interfaces using Deno/TypeScript, and provide intelligent workspace state preservation across monitor configuration changes. This forward-only development approach completely removes the bash script and refactors Python code to be config-driven.

## Technical Context

**Language/Version**: Python 3.11 (daemon/event handling), TypeScript (Deno 1.40+ for CLI)
**Primary Dependencies**: i3ipc-python (async i3 IPC), Deno std library (@std/cli for parseArgs, @std/fs, @std/json)
**Storage**: JSON configuration file at `~/.config/i3/workspace-monitor-mapping.json`
**Testing**: pytest with pytest-asyncio (Python daemon tests), Deno.test (TypeScript CLI tests)
**Target Platform**: NixOS with i3 window manager v4.16+
**Project Type**: System integration (daemon extension + CLI tool)
**Performance Goals**: <3s workspace redistribution on monitor change, <500ms CLI status commands, <100ms TUI updates
**Constraints**: Event-driven architecture (no polling), <15MB daemon memory, zero downtime config reload
**Scale/Scope**: Support 1-70 workspaces across 1-3 monitors, ~12 CLI commands, 4 TUI display modes

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition
**Status**: ✅ PASS

- Configuration file management will be extracted into `MonitorConfigManager` service module
- Daemon integration extends existing `i3-project-event-listener` without duplication
- CLI commands follow existing `i3pm` modular structure (new `monitors` subcommand)
- No duplicate code between Python daemon and Deno CLI - clear separation of concerns

### Principle III: Test-Before-Apply
**Status**: ✅ PASS

- All changes will be tested via `nixos-rebuild dry-build --flake .#hetzner` before applying
- Python daemon changes tested via pytest before integration
- Deno CLI tested via `deno test` before compilation
- Configuration changes validated before daemon reload

### Principle VI: Declarative Configuration Over Imperative
**Status**: ✅ PASS with ACTION REQUIRED

- JSON configuration file replaces hardcoded distribution logic
- Configuration file generated via NixOS module or home-manager on first run
- **ACTION**: Ensure default config generation uses `environment.etc` or `home.file`, not imperative script
- Daemon reads config declaratively, no imperative state mutation

### Principle VII: Documentation as Code
**Status**: ✅ PASS

- This plan.md documents architecture
- quickstart.md will provide user guide (Phase 1 output)
- Module header comments will explain configuration schema
- CLAUDE.md will be updated with new CLI commands

### Principle X: Python Development & Testing Standards
**Status**: ✅ PASS

- Python 3.11 with async/await for i3 IPC subscriptions
- pytest with pytest-asyncio for daemon tests
- Pydantic models for configuration validation
- Type hints for all public APIs
- Module structure follows single-responsibility principle

### Principle XI: i3 IPC Alignment & State Authority
**Status**: ✅ PASS

- All monitor detection via i3 IPC GET_OUTPUTS (authoritative)
- Workspace assignments via i3 IPC COMMAND messages
- Event-driven updates via i3 IPC output event subscriptions
- Configuration state validated against i3 IPC data on reload
- No xrandr dependency except for primary output preference reading

### Principle XII: Forward-Only Development & Legacy Elimination
**Status**: ✅ PASS - CORE PRINCIPLE FOR THIS FEATURE

- `detect-monitors.sh` will be DELETED (no compatibility mode)
- Hardcoded distribution logic in `workspace_manager.py` will be REPLACED
- No fallback to bash script or old logic
- Single config-driven implementation path
- Documentation focuses on new approach only
- Migration: extract current behavior → JSON config → delete old code (same commit)

### Principle XIII: Deno CLI Development Standards
**Status**: ✅ PASS

- Deno 1.40+ with TypeScript for all CLI commands
- `@std/cli/parse-args` for argument parsing
- `@std/fs` and `@std/json` for file operations
- Compiled to standalone executable via `deno compile`
- Type-safe interfaces for daemon JSON-RPC communication
- Follows existing `i3pm` CLI structure

### Additional Principles (Multi-Monitor, Remote Desktop, Testing)
**Status**: ✅ PASS

- Remote desktop multi-session compatibility maintained (xrdp + X11)
- Tiling window manager integration via i3 IPC event subscriptions
- Automated testing framework for daemon and CLI (pytest + Deno.test)
- Diagnostic commands for troubleshooting (history, debug, diagnose)

### GATE EVALUATION: ✅ PASS - Proceed to Phase 0

No principle violations. No complexity justification required. Forward-only development principle is central to this feature's design.

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
# Python daemon extension
home-modules/tools/i3pm-daemon/
├── workspace_manager.py        # MODIFIED: Load config instead of hardcoded rules
├── monitor_config_manager.py   # NEW: Config file reading and validation
├── models.py                   # NEW: Pydantic models for config schema
└── config_schema.json          # NEW: JSON schema for validation

# Deno/TypeScript CLI
home-modules/tools/i3pm-cli/
├── deno.json                   # Deno configuration
├── main.ts                     # Entry point with subcommand routing
├── mod.ts                      # Public API exports
└── src/
    ├── commands/
    │   ├── monitors_status.ts       # `i3pm monitors status`
    │   ├── monitors_workspaces.ts   # `i3pm monitors workspaces`
    │   ├── monitors_config.ts       # `i3pm monitors config [show|edit|init|validate|reload]`
    │   ├── monitors_move.ts         # `i3pm monitors move`
    │   ├── monitors_reassign.ts     # `i3pm monitors reassign`
    │   ├── monitors_watch.ts        # `i3pm monitors watch` (live TUI)
    │   ├── monitors_tui.ts          # `i3pm monitors tui` (interactive)
    │   ├── monitors_diagnose.ts     # `i3pm monitors diagnose`
    │   ├── monitors_history.ts      # `i3pm monitors history`
    │   └── monitors_debug.ts        # `i3pm monitors debug`
    ├── models.ts               # TypeScript interfaces
    ├── daemon_client.ts        # JSON-RPC client for daemon IPC
    └── ui/
        ├── table_formatter.ts   # Table display utilities
        └── tui_components.ts    # TUI components

# Tests
tests/i3pm-monitors/
├── python/
│   ├── unit/
│   │   ├── test_config_manager.py
│   │   └── test_models.py
│   ├── integration/
│   │   └── test_workspace_redistribution.py
│   └── fixtures/
│       └── mock_i3_outputs.py
└── typescript/
    ├── commands_test.ts
    └── daemon_client_test.ts

# Scripts to be DELETED (forward-only development)
home-modules/desktop/i3/scripts/
└── detect-monitors.sh          # DELETE: Replaced by daemon event-driven system
```

**Structure Decision**: Hybrid Python + TypeScript structure
- **Python daemon extension**: Extends existing `i3-project-event-listener` daemon with monitor config management. Located in `home-modules/tools/i3pm-daemon/` alongside existing daemon code.
- **Deno CLI**: New standalone CLI tool with comprehensive subcommands. Compiled to executable and integrated into `i3pm` command structure.
- **Forward-only deletion**: `detect-monitors.sh` removed completely, no migration path or compatibility mode.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**No violations identified** - All design decisions comply with constitution principles.

## Post-Design Constitution Re-Evaluation

### Re-Check After Phase 1 Design

All principles remain compliant after completing data model, contracts, and quickstart documentation:

**Principle VI: Declarative Configuration Over Imperative** - ✅ CONFIRMED
- Default configuration file will be generated via NixOS home-manager `xdg.configFile` (see data-model.md section 8)
- No imperative scripts required for config generation
- All configuration management declarative via JSON file

**Principle XII: Forward-Only Development** - ✅ CONFIRMED
- API contracts define new JSON-RPC methods without legacy fallbacks
- No compatibility shims for old bash script approach
- Clean data model with no legacy field support

**All Other Principles** - ✅ PASS (no changes from initial evaluation)

### GATE EVALUATION: ✅ PASS - Ready for Implementation

All design artifacts complete:
- ✅ research.md (Phase 0)
- ✅ data-model.md (Phase 1)
- ✅ contracts/jsonrpc-api.md (Phase 1)
- ✅ quickstart.md (Phase 1)
- ✅ Agent context updated (CLAUDE.md)

**Next Command**: `/speckit.tasks` to generate implementation tasks from this plan.
