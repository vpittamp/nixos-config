# Implementation Plan: Dynamic Sway Configuration Management Architecture

**Branch**: `047-create-a-new` | **Date**: 2025-10-29 | **Spec**: [spec.md](/etc/nixos/specs/047-create-a-new/spec.md)
**Input**: Feature specification from `/specs/047-create-a-new/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature establishes a dynamic configuration management architecture for Sway window manager that eliminates rebuild friction while maintaining NixOS integration. The primary requirement is hot-reloadable configuration changes (keybindings, window rules, workspace assignments) without requiring `nixos-rebuild` or Sway restart, reducing configuration iteration time from 120 seconds to under 10 seconds. The technical approach uses a hybrid model: Nix modules manage static system-level settings (packages, services, session setup), while the Python daemon provides runtime configuration loading from version-controlled JSON/TOML files with validation, atomicity, and rollback capabilities.

## Technical Context

**Language/Version**: Python 3.11+ (existing i3pm daemon), Nix expressions for home-manager integration
**Primary Dependencies**: i3ipc.aio (Sway IPC communication), Pydantic (data validation), jsonschema (config validation), existing i3pm daemon architecture
**Storage**: JSON/TOML configuration files in `~/.config/sway/` (keybindings, window rules, workspace assignments), git for version control
**Testing**: pytest with pytest-asyncio (existing standard from Constitution Principle X)
**Target Platform**: NixOS on Hetzner Cloud (hetzner-sway) and M1 MacBook Pro (Sway/Wayland), extends existing i3pm daemon
**Project Type**: System configuration enhancement - extends existing Python daemon with new configuration loading subsystem
**Performance Goals**: Configuration reload <2 seconds, validation <500ms, hot-reload without disrupting active user input
**Constraints**: Must preserve 100% backward compatibility with existing i3pm daemon features (project switching, window filtering, workspace management)
**Scale/Scope**: Single-user systems, ~50 keybindings, ~20 window rules, ~10 projects, configuration files <100KB total

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I - Modular Composition ✅ PASS
- Configuration will be structured as composable modules (config loading, validation, keybinding management, window rule engine)
- Extends existing modular architecture (`home-modules/desktop/sway.nix`, i3pm daemon modules)
- No code duplication - reuses existing i3pm daemon patterns for IPC, event handling, state management

### Principle III - Test-Before-Apply ✅ PASS
- All changes will be tested with `dry-build` before applying
- Configuration validation enforces test-before-apply at runtime (SC-006: 100% syntax error detection)
- Rollback mechanism ensures safe experimentation (SC-007: 3-second rollback)

### Principle IV - Override Priority Discipline ✅ PASS
- Nix modules will use `lib.mkDefault` for overrideable base configuration
- Documented precedence: Nix static config → Python runtime overrides (FR-007)
- Clear separation prevents option conflicts

### Principle VI - Declarative Configuration Over Imperative ✅ PASS
- All configuration managed declaratively in version-controlled files (JSON/TOML) (FR-005)
- Nix generates base Sway config, Python daemon extends dynamically
- No imperative post-install scripts - configuration loading via daemon

### Principle X - Python Development & Testing Standards ✅ PASS
- Python 3.11+, async/await patterns, i3ipc.aio for Sway IPC
- pytest with pytest-asyncio for testing framework
- Pydantic for data validation, type hints required
- Module structure follows single-responsibility principle
- Existing i3pm daemon architecture provides reference implementation

### Principle XI - i3 IPC Alignment & State Authority ✅ PASS
- Sway IPC used as authoritative source for window state, workspaces, outputs
- Event-driven architecture via Sway IPC subscriptions (preserves existing i3pm pattern)
- Configuration reload triggers IPC commands, not direct state manipulation
- Validation queries Sway IPC for current state (workspaces, outputs)

### Principle XII - Forward-Only Development & Legacy Elimination ✅ PASS
- Feature extends existing i3pm daemon without legacy compatibility layers
- Configuration architecture is optimal solution without constraints from old patterns
- No feature flags or dual code paths - single coherent configuration system
- Existing i3pm features preserved but not duplicated (FR-010: 100% backward compatibility)

**GATE STATUS**: ✅ **APPROVED** - All applicable constitution principles satisfied. No violations to justify.

---

## Post-Design Constitution Re-Evaluation

*Re-checked after Phase 1 design completion*

### Design Artifacts Review

**Reviewed Artifacts**:
- `research.md` - Technical decisions and technology stack
- `data-model.md` - Pydantic models and validation schemas
- `contracts/daemon-ipc-endpoints.md` - JSON-RPC API specification
- `contracts/cli-commands.md` - CLI command definitions
- `quickstart.md` - User workflows and examples

### Compliance Confirmation

✅ **Principle I - Modular Composition**: Design uses modular architecture
  - Configuration subsystem: loader, validator, merger, rollback (4 focused modules)
  - Rules engine: keybinding_manager, window_rule_engine, workspace_assignments (3 specialized modules)
  - Extends existing i3pm daemon modules without duplication
  - Clear module responsibilities with single-purpose design

✅ **Principle VI - Declarative Configuration**: All config in version-controlled files
  - TOML/JSON configuration files in `~/.config/sway/` (user-editable)
  - Nix modules generate base configuration declaratively
  - Python daemon loads/validates configuration (no imperative scripts)
  - Git provides version control and rollback mechanism

✅ **Principle X - Python Development Standards**: Follows established patterns
  - Python 3.11+ with async/await (i3ipc.aio for Sway IPC)
  - Pydantic models for data validation (6 core entities defined)
  - pytest with pytest-asyncio for testing (mentioned in Technical Context)
  - Type hints required for all function signatures
  - Rich library for terminal UI (CLI commands output)

✅ **Principle XI - i3 IPC Alignment**: Sway IPC as authoritative source
  - Validation queries Sway IPC for semantic checks (workspace numbers, output names)
  - Window rule application via Sway IPC commands
  - Configuration reload triggers Sway IPC `reload` command
  - Event-driven architecture preserved from existing daemon

✅ **Principle XII - Forward-Only Development**: Optimal solution without legacy
  - No compatibility layers for old configuration system
  - Clean extension of existing i3pm daemon architecture
  - Single coherent configuration management system
  - Existing features preserved (FR-010) but not duplicated

**FINAL GATE STATUS**: ✅ **APPROVED FOR IMPLEMENTATION** - Design maintains full constitution compliance. All principles satisfied. Zero violations identified.

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
home-modules/desktop/
├── sway.nix                              # Base Sway configuration (existing)
├── i3-project-event-daemon/              # Existing i3pm daemon (extends to Sway)
│   ├── daemon.py                         # Main daemon (extends with config loading)
│   ├── config/                           # NEW: Configuration subsystem
│   │   ├── __init__.py
│   │   ├── loader.py                     # Load/parse JSON/TOML config files
│   │   ├── validator.py                  # JSON schema validation
│   │   ├── merger.py                     # Merge Nix base + runtime overrides
│   │   └── rollback.py                   # Git-based rollback manager
│   ├── rules/                            # NEW: Dynamic rule engine
│   │   ├── __init__.py
│   │   ├── keybinding_manager.py         # Apply keybindings via Sway IPC
│   │   ├── window_rule_engine.py         # Dynamic window rule application
│   │   └── workspace_assignments.py      # Hot-reload workspace assignments
│   ├── models.py                         # Pydantic models (extend with config models)
│   ├── ipc_server.py                     # JSON-RPC server (add config reload endpoints)
│   └── state.py                          # Daemon state (track config version)
└── swaybar.nix                           # Existing swaybar config

~/.config/sway/                            # Runtime configuration directory
├── keybindings.toml                       # User-editable keybinding config
├── window-rules.json                      # User-editable window rules
├── workspace-assignments.json             # User-editable workspace config
├── projects/                              # Project-specific overrides
│   ├── nixos.json
│   ├── stacks.json
│   └── personal.json
└── .config-version                        # Current active config version (git hash)

home-modules/tools/i3pm/                   # Deno CLI (extend with config commands)
└── src/
    └── commands/
        ├── config_reload.ts               # NEW: Trigger config reload
        ├── config_validate.ts             # NEW: Validate config syntax
        ├── config_rollback.ts             # NEW: Rollback to previous version
        └── config_show.ts                 # NEW: Show current config with sources
```

**Structure Decision**: System configuration enhancement extending existing i3pm daemon. Uses existing Python 3.11+ daemon architecture from `home-modules/desktop/i3-project-event-daemon/` with new configuration subsystem modules. Configuration files stored in `~/.config/sway/` for user editability and git version control. Deno CLI (`i3pm`) extended with configuration management commands. Follows Constitution Principle X (Python Development Standards) and Principle I (Modular Composition).

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**No violations** - All constitution principles satisfied. No complexity justification required.
