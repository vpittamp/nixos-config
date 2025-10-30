# Implementation Plan: Intelligent Automatic Workspace-to-Monitor Assignment

**Branch**: `049-intelligent-automatic-workspace` | **Date**: 2025-10-29 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/049-intelligent-automatic-workspace/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement automatic workspace redistribution across active Sway monitors when displays connect or disconnect, with window preservation to prevent data loss. System will detect monitor changes via Sway output events, debounce rapid changes (500ms), calculate workspace distribution using built-in rules based on monitor count, migrate windows from disconnected monitors, and persist state to JSON files. This replaces the manual Win+Shift+M workflow and removes legacy MonitorConfigManager infrastructure.

## Technical Context

**Language/Version**: Python 3.11+ (matches existing i3pm daemon codebase)
**Primary Dependencies**: i3ipc-python (i3ipc.aio for async Sway IPC), asyncio for event handling, Pydantic for data models
**Storage**: JSON files (`~/.config/sway/monitor-state.json` for persistence, `~/.config/sway/workspace-assignments.json` for Sway Config Manager integration)
**Testing**: pytest with pytest-asyncio for async tests, mock i3 IPC responses, scenario-based tests simulating monitor connect/disconnect workflows
**Target Platform**: NixOS (Hetzner Sway configuration), Sway 1.5+ Wayland compositor with i3 IPC protocol
**Project Type**: Single project (extends existing i3pm daemon event handler system)
**Performance Goals**: <1 second total latency from monitor change event to workspace reassignment completion, <100ms per window migration
**Constraints**: 500ms debounce to prevent flapping, must handle 100+ windows across 9 workspaces without degradation, complete reassignment in <2 seconds
**Scale/Scope**: 3-70 workspaces, 1-4 monitors, 100+ windows, single-user Sway session

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition ✅
- **Status**: PASS
- **Analysis**: Feature extends existing i3pm daemon modules (handlers.py, workspace_manager.py) without duplication. New DynamicWorkspaceManager class replaces MonitorConfigManager with simpler logic. Follows existing handler pattern.

### Principle III: Test-Before-Apply ✅
- **Status**: PASS
- **Analysis**: Will use `sudo nixos-rebuild dry-build --flake .#hetzner-sway` before applying changes. No system-level config changes required (pure daemon enhancement).

### Principle VI: Declarative Configuration Over Imperative ✅
- **Status**: PASS
- **Analysis**: Updates Sway Config Manager's workspace-assignments.json (declarative). State persistence via JSON follows existing patterns. No imperative scripts.

### Principle VII: Documentation as Code ✅
- **Status**: PASS
- **Analysis**: Will create quickstart.md with usage examples, update CLAUDE.md with automatic reassignment workflow, document in implementation.

### Principle X: Python Development & Testing Standards ✅
- **Status**: PASS
- **Analysis**: Python 3.11+, async/await patterns with i3ipc.aio, pytest with pytest-asyncio, Pydantic models for state, follows existing daemon patterns.

### Principle XI: i3 IPC Alignment & State Authority ✅
- **Status**: PASS
- **Analysis**: Uses Sway output events (i3 IPC compatible), GET_OUTPUTS for monitor detection, GET_WORKSPACES for state validation, GET_TREE for window detection. Event-driven via subscriptions.

### Principle XII: Forward-Only Development & Legacy Elimination ✅
- **Status**: PASS WITH ACTION
- **Analysis**: Removes MonitorConfigManager class, deletes workspace-monitor-mapping.json, eliminates manual reassignment workflow. Complete replacement, no backwards compatibility.
- **Action**: Must delete `monitor_config_manager.py` and remove all references in same commit.

### Overall Gate Status: ✅ PASS
No violations detected. Feature aligns with modular composition, event-driven architecture, Python standards, and forward-only development principles.

---

## Post-Design Re-Evaluation

**Phase 1 Design Complete**: Data model, API contracts, and quickstart documentation generated.

### Re-check Against Constitution

**Principle I: Modular Composition** ✅ PASS (confirmed)
- DynamicWorkspaceManager class follows existing patterns
- Integration via handlers.py event system (existing architecture)
- No code duplication - replaces legacy MonitorConfigManager cleanly

**Principle VI: Declarative Configuration** ✅ PASS (confirmed)
- monitor-state.json schema defined (file-schemas.json)
- workspace-assignments.json integration documented
- Pydantic models provide validation layer

**Principle VII: Documentation as Code** ✅ PASS (confirmed)
- quickstart.md created with usage examples, troubleshooting, FAQ
- data-model.md documents all entities with validation rules
- contracts/ directory contains API specifications

**Principle X: Python Development & Testing Standards** ✅ PASS (confirmed)
- Pydantic models for MonitorState, WorkspaceDistribution, ReassignmentResult
- pytest test structure defined (unit, integration, scenario)
- Async patterns documented in contracts/sway-ipc-commands.md

**Principle XI: i3 IPC Alignment** ✅ PASS (confirmed)
- All state queries via Sway IPC (GET_OUTPUTS, GET_WORKSPACES, GET_TREE)
- Output event subscription documented
- Sequential IPC commands for reliable workspace assignment

**Principle XII: Forward-Only Development** ✅ PASS (confirmed)
- Legacy code removal documented (monitor_config_manager.py)
- No backwards compatibility layer
- Migration path: delete old files, fresh state generated

**New Design Insights**:
- Performance targets confirmed achievable: <1s reassignment, <100ms per window
- Debounce pattern reuses existing tick event infrastructure
- State persistence aligns with Sway Config Manager (Feature 047)
- No new configuration files beyond monitor-state.json

**Final Gate Status**: ✅✅ PASS - Ready for Phase 2 (Task Generation)

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
home-modules/desktop/i3-project-event-daemon/
├── handlers.py                    # [MODIFY] Add output event handler with debounce
├── workspace_manager.py           # [MODIFY] Add DynamicWorkspaceManager class
├── models.py                      # [MODIFY] Add MonitorState, WorkspaceDistribution models
├── ipc_server.py                  # [MODIFY] Add IPC commands for diagnostics
├── monitor_config_manager.py      # [DELETE] Replaced by DynamicWorkspaceManager
└── README.md                      # [UPDATE] Document automatic reassignment

~/.config/sway/                    # Runtime state (not in repo)
├── monitor-state.json             # [NEW] Persisted monitor configuration
└── workspace-assignments.json     # [UPDATED] Generated by feature

tests/i3-project-daemon/           # [NEW] Test suite for feature
├── unit/
│   ├── test_dynamic_workspace_manager.py
│   └── test_workspace_distribution.py
├── integration/
│   └── test_output_event_handler.py
└── scenarios/
    └── test_monitor_changes.py
```

**Structure Decision**: Single project extending existing i3pm daemon. Feature integrates into existing event handler architecture (handlers.py), adds new workspace management logic (workspace_manager.py), and removes legacy MonitorConfigManager. Tests follow Python Development Standards (Principle X) with unit, integration, and scenario coverage.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

No complexity violations detected - feature simplifies existing architecture by removing MonitorConfigManager.
