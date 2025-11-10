# Implementation Plan: Declarative Workspace-to-Monitor Assignment with Floating Window Configuration

**Branch**: `001-declarative-workspace-monitor` | **Date**: 2025-11-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-declarative-workspace-monitor/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature adds declarative configuration for assigning workspaces to monitor roles (primary/secondary/tertiary) directly in application and PWA definitions (`app-registry-data.nix`, `pwa-sites.nix`). Users can specify `preferred_monitor_role` for each application, with automatic fallback logic when monitors disconnect (tertiary → secondary → primary). Additionally, applications can declare floating window behavior with `floating` and `floating_size` fields, integrating with existing project filtering for scoped/global visibility control. The system extends Feature 049's automatic workspace distribution with hot-reloadable, version-controlled monitor assignments.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon), Nix configuration language
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Pydantic (data validation), Nix expression evaluation
**Storage**: JSON state files (`~/.config/sway/monitor-state.json` extended from Feature 049), Nix configuration files (`app-registry-data.nix`, `pwa-sites.nix`)
**Testing**: pytest-asyncio (Python integration tests), sway-test framework (declarative JSON tests for window manager behavior)
**Target Platform**: NixOS with Sway/Wayland compositor (hetzner-sway reference, M1 Mac)
**Project Type**: Single project (system configuration extension)
**Performance Goals**: <1 second workspace reassignment on monitor changes, <100ms hot-reload latency for configuration changes, <10ms monitor role resolution overhead
**Constraints**: Must integrate with existing Feature 049 (automatic workspace distribution), Feature 047 (dynamic config management), Feature 062 (scratchpad terminal), and project filtering system (scope field)
**Scale/Scope**: 70 workspaces (1-70), 3 monitor roles (primary/secondary/tertiary), 1-3 monitor configurations, ~30 applications + ~8 PWAs in registry

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Status**: ✅ **PASSED** - All constitution gates satisfied

### Principle I: Modular Composition
✅ **PASS** - Feature extends existing modules (`app-registry-data.nix`, `pwa-sites.nix`) with new fields rather than creating monolithic configuration. Monitor role resolution logic will be extracted into reusable service module within i3pm daemon.

### Principle III: Test-Before-Apply (NON-NEGOTIABLE)
✅ **PASS** - Implementation will require `dry-build` testing before application. Nix configuration validation ensures type safety for new fields.

### Principle IV: Override Priority Discipline
✅ **PASS** - New `preferred_monitor_role` field uses normal assignment in app definitions. Will use `lib.mkDefault` in Nix modules for default monitor role inference rules.

### Principle VI: Declarative Configuration Over Imperative
✅ **PASS** - Core feature requirement: all workspace-to-monitor assignments declared in Nix expressions. Hot-reload mechanism via Feature 047 maintains declarative approach.

### Principle VII: Documentation as Code
✅ **PASS** - Spec, plan, quickstart, and data model docs will be created. Module header comments will explain monitor role resolution and fallback logic.

### Principle X: Python Development & Testing Standards
✅ **PASS** - Python 3.11+ with i3ipc.aio for async IPC. Pydantic models for monitor role data. pytest-asyncio for integration tests. Rich library for diagnostic output.

### Principle XI: i3 IPC Alignment & State Authority
✅ **PASS** - Monitor configuration queried via Sway IPC GET_OUTPUTS. Workspace assignments validated via GET_WORKSPACES. Event-driven architecture via output event subscriptions.

### Principle XII: Forward-Only Development & Legacy Elimination
✅ **PASS** - Feature 049's hardcoded workspace distribution rules will be completely replaced with declarative configuration. No compatibility shims or dual code paths.

### Principle XIV: Test-Driven Development & Autonomous Testing
✅ **PASS** - Will write sway-test JSON definitions for workspace assignment verification. Integration tests for monitor role resolution. State verification via Sway IPC GET_TREE queries.

### Principle XV: Sway Test Framework Standards
✅ **PASS** - Will use declarative JSON test definitions with partial mode state comparison. Tests will verify focusedWorkspace, workspace-to-output assignments, and floating window behavior via Sway IPC authority.

### Critical Risks Identified

**NONE** - No constitution violations or complexity justifications required. Feature aligns with existing architecture patterns (Feature 049 extension, Feature 047 hot-reload, Feature 062 floating windows).

## Project Structure

### Documentation (this feature)

```text
specs/001-declarative-workspace-monitor/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── monitor-role-config.schema.json  # Nix schema for validation
├── spec.md              # Feature specification (already created)
└── checklists/
    └── requirements.md  # Quality validation (already created)
```

### Source Code (repository root)

```text
# Nix Configuration Extensions
home-modules/desktop/
├── app-registry-data.nix          # UPDATED: Add preferred_monitor_role field
└── sway.nix                       # UPDATED: Remove static workspace assignments

shared/
└── pwa-sites.nix                  # UPDATED: Add preferred_monitor_role field

# Python i3pm Daemon Extensions (Feature 049 integration)
home-modules/desktop/i3-project-event-daemon/
├── monitor_role_resolver.py       # NEW: Monitor role resolution & fallback logic
├── workspace_assignment_manager.py # UPDATED: Integrate monitor role resolution
├── floating_window_manager.py     # NEW: Floating window size/position management
├── models/
│   ├── monitor_config.py          # NEW: Pydantic models for monitor roles
│   └── floating_config.py         # NEW: Pydantic models for floating windows
└── state/
    └── monitor_state.json         # UPDATED: Extended state file format

# Sway Dynamic Configuration (Feature 047 integration)
~/.config/sway/
├── window-rules.json              # UPDATED: Add floating window rules
└── workspace-assignments.json     # NEW: Dynamic monitor role assignments

# Tests
tests/001-declarative-workspace-monitor/
├── unit/
│   ├── test_monitor_role_resolver.py    # Unit tests for resolution logic
│   └── test_floating_window_manager.py  # Unit tests for floating config
├── integration/
│   ├── test_workspace_assignment.py     # Integration with Feature 049
│   └── test_monitor_fallback.py         # Fallback logic integration
└── sway-tests/
    ├── test_workspace_monitor_assignment.json  # Declarative workspace tests
    └── test_floating_window_behavior.json      # Declarative floating tests
```

**Structure Decision**: Single project structure extending existing i3pm daemon with new Python modules for monitor role resolution and floating window management. Nix configuration files are extended with new fields (preferred_monitor_role, floating, floating_size). Tests use both pytest (Python unit/integration) and sway-test framework (declarative window manager behavior).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No complexity violations** - Feature aligns with constitution principles.

---

## Planning Phase Complete ✅

**Phase 0 (Research)**: ✅ Complete
- `research.md`: All technology decisions documented
- 8 research questions resolved (monitor role resolution, hot-reload integration, floating presets, etc.)

**Phase 1 (Design & Contracts)**: ✅ Complete
- `data-model.md`: 7 core entities defined with Pydantic models
- `contracts/`: 2 JSON schemas created (monitor-role-config, workspace-assignments)
- `quickstart.md`: User guide with examples and troubleshooting
- Agent context updated: CLAUDE.md synchronized

**Constitution Re-Check**: ✅ PASSED (no changes from initial check)

**Next Step**: Run `/speckit.tasks` to generate task breakdown for implementation
