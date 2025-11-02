# Implementation Plan: Reliable Event-Driven Workspace Assignment

**Branch**: `053-workspace-assignment-enhancement` | **Date**: 2025-11-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/053-workspace-assignment-enhancement/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature investigates and fixes the root cause of unreliable PWA workspace assignment by ensuring 100% window creation event delivery from the window manager (Sway) to the workspace assignment service. The approach consolidates to a single event-driven assignment mechanism, eliminating conflicting native window manager rules and ensuring sub-second workspace assignment for all window types (PWAs, native apps, floating windows).

## Technical Context

**Language/Version**: Python 3.11+ (existing i3pm daemon runtime), Nix for configuration management
**Primary Dependencies**: i3ipc-python (i3ipc.aio for async Sway IPC), asyncio, existing i3pm daemon infrastructure
**Storage**: In-memory event tracking with persistent assignment configuration in JSON
**Testing**: pytest with pytest-asyncio for async testing, existing i3pm diagnostic framework
**Target Platform**: NixOS with Sway/Wayland (hetzner-sway configuration), compatible with i3/X11 via shared IPC protocol
**Project Type**: System tooling enhancement - event-driven daemon modification + configuration consolidation
**Performance Goals**: <100ms workspace assignment latency, 100% event delivery reliability, <1% CPU overhead
**Constraints**: Must not modify Sway source code, must work within Sway IPC protocol, no polling fallbacks allowed
**Scale/Scope**: Single-user desktop environment, 70 workspaces across 3 monitors, ~50 concurrent windows typical

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle III: Test-Before-Apply ✅
- All configuration changes will be tested with `nixos-rebuild dry-build --flake .#hetzner-sway`
- Event delivery fixes will be validated on test platform before deployment
- Rollback procedures verified for daemon changes

### Principle VI: Declarative Configuration Over Imperative ✅
- Workspace assignment consolidation will use declarative Nix configuration
- Sway window rules migrated to event-driven service configuration
- No imperative scripts for assignment logic

### Principle X: Python Development & Testing Standards ✅
- Using Python 3.11+ with asyncio for daemon enhancements
- pytest with pytest-asyncio for event delivery validation tests
- i3ipc.aio for async Sway IPC communication
- Type hints for all new functions

### Principle XI: i3 IPC Alignment & State Authority ✅
- All event subscriptions via Sway IPC SUBSCRIBE message type
- Window state queried via GET_TREE and GET_WORKSPACES
- Event-driven architecture, no polling mechanisms
- Diagnostic tools will include Sway IPC state validation

### Principle XII: Forward-Only Development & Legacy Elimination ✅ **CRITICAL**
- **Complete replacement of native Sway assignment rules with event-driven service**
- No compatibility layers for old assignment mechanisms
- Legacy `for_window` workspace assignment directives will be REMOVED entirely
- Single consolidated assignment configuration - no dual support
- This aligns with spec requirement FR-015 through FR-018: exactly ONE assignment mechanism

### No Violations Requiring Justification
All constitutional principles are followed. The Forward-Only Development principle explicitly supports the spec's requirement to consolidate assignment mechanisms without backwards compatibility.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/tools/i3pm/
├── daemon/
│   ├── workspace_assigner.py       # NEW: Centralized workspace assignment handler
│   ├── event_monitor.py            # ENHANCED: Event gap detection and logging
│   ├── window_filter.py            # EXISTING: Window filtering (may be affected)
│   └── daemon.py                   # ENHANCED: Event subscription ordering
├── cli/
│   └── diagnostic.py               # ENHANCED: Event delivery diagnostics
└── tests/
    ├── test_workspace_assigner.py  # NEW: Assignment logic tests
    └── test_event_delivery.py      # NEW: Event subscription tests

home-modules/desktop/
├── sway.nix                         # ENHANCED: Remove native assignment rules
└── walker.nix                       # EXISTING: Launch notification integration

.config/i3/
├── workspace-assignments.json       # ENHANCED: Consolidated assignment config
└── app-registry.json               # EXISTING: Application definitions

Configuration files (generated by Nix):
~/.config/sway/config               # MODIFIED: Remove `for_window` workspace assignments
~/.config/i3/workspace-assignments.json  # MODIFIED: Migrate PWA assignments
```

**Structure Decision**: This is a system tooling enhancement that modifies the existing i3pm daemon and Sway configuration. The primary changes are:
1. **New workspace_assigner.py module** - Centralized event-driven assignment logic
2. **Enhanced event_monitor.py** - Event gap detection between emitted and received events
3. **Sway configuration cleanup** - Remove native `for_window` workspace assignment rules
4. **Consolidated assignment config** - Single JSON source of truth for all workspace assignments

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No complexity violations - all constitutional principles followed without justification needed.

---

## Phase 0: Research Complete ✅

**Output**: [research.md](./research.md)

**Key Findings**:
1. **Root Cause #1 (CRITICAL)**: Native Sway `assign` rules suppress window creation events
   - Solution: Remove all native assignment rules, consolidate to daemon-only mechanism
2. **Root Cause #2 (HIGH)**: Native Wayland property timing - `app_id` populated asynchronously
   - Solution: Add 100ms delayed property re-check for incomplete properties
3. **Root Cause #3 (MEDIUM)**: Launch notification workspace not integrated
   - Solution: Add Priority 0 tier using `matched_launch.workspace_number`

**Technology Decisions**:
- Use Sway IPC event subscription for 100% event delivery (remove conflicting native rules)
- Add launch notification as Priority 0 in workspace assignment
- Implement delayed property re-check for native Wayland apps

---

## Phase 1: Design & Contracts Complete ✅

**Outputs**:
- [data-model.md](./data-model.md) - Entity definitions, relationships, validation rules
- [quickstart.md](./quickstart.md) - User guide with commands and troubleshooting
- Agent context updated - New technologies added to CLAUDE.md

**Data Model Entities**:
1. `WindowCreationEvent` - Sway IPC window::new event payload
2. `EventSubscription` - Active event type subscriptions with health tracking
3. `PWAWindow` - Progressive Web App properties and identifiers
4. `LaunchNotification` - Pre-launch message for window correlation (Priority 0 source)
5. `AssignmentRecord` - Historical workspace assignment with timing metrics
6. `EventGap` - Detected missed events for diagnostic purposes
7. `AssignmentConfiguration` - Consolidated workspace assignment rules

**Key Relationships**:
- `LaunchNotification` → `WindowCreationEvent` → `AssignmentRecord` (Priority 0 path)
- `EventSubscription` → `WindowCreationEvent` → `EventGap` (health monitoring)
- `AssignmentConfiguration` → `PWAWindow` → `AssignmentRecord` (configuration to execution)

**Workspace Assignment Priority System**:
0. Launch notification workspace (NEW - highest priority, ~80% of PWA launches)
1. App-specific handlers (VS Code title parsing)
2. `I3PM_TARGET_WORKSPACE` environment variable
3. `I3PM_APP_NAME` registry lookup
4. Window class matching (exact → instance → normalized)

---

## Phase 2: Task Planning (NOT YET COMPLETE)

**Next Step**: Run `/speckit.tasks` command to generate implementation tasks

**Expected Tasks**:
- T001-T010: Remove native Sway assignment rules and migrate configuration
- T011-T020: Add Priority 0 launch notification workspace integration
- T021-T030: Implement delayed property re-check for native Wayland apps
- T031-T040: Add event gap detection and subscription health monitoring
- T041-T050: Testing and validation (event delivery, assignment latency, PWA reliability)

---

## Summary

**Planning Complete**: Research and design phases finished successfully

**Branch**: `053-workspace-assignment-enhancement`

**Generated Artifacts**:
- ✅ `plan.md` - This file (implementation plan with technical context and constitution check)
- ✅ `research.md` - Root cause analysis and technology decisions
- ✅ `data-model.md` - Entity definitions and data structures
- ✅ `quickstart.md` - User guide and troubleshooting
- ⏳ `tasks.md` - NOT YET CREATED (run `/speckit.tasks` to generate)

**Ready for Implementation**: Yes - all design artifacts complete, constitution validated

**Next Command**: `/speckit.tasks` (generates actionable implementation tasks from this plan)
