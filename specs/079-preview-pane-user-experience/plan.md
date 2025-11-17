# Implementation Plan: Preview Pane User Experience

**Branch**: `079-preview-pane-user-experience` | **Date**: 2025-11-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/079-preview-pane-user-experience/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Optimize git worktree user experience through enhanced preview pane navigation (arrow keys, backspace exit, numeric prefix filtering), improved visual hierarchy (worktree grouping, branch numbers), and cross-component integration (top bar labels, environment variables, notification navigation).

## Technical Context

**Language/Version**: Python 3.11+ (i3-project-event-daemon), TypeScript/Deno 1.40+ (i3pm CLI), Nix (Eww widget generation)
**Primary Dependencies**: i3ipc.aio (Sway IPC), Pydantic (data models), Eww (GTK widgets), asyncio (event handling), SwayNC (notifications)
**Storage**: JSON project files (`~/.config/i3/projects/`), in-memory daemon state
**Testing**: pytest-asyncio (Python daemon), Deno.test (TypeScript CLI), sway-test framework (window manager)
**Target Platform**: NixOS with Sway compositor (Hetzner, M1)
**Project Type**: Multi-component (daemon + CLI + widgets)
**Performance Goals**: <50ms arrow key response, <500ms project switch, <1s CLI command execution
**Constraints**: Event-driven architecture, Sway IPC as authoritative state source, keyboard-first workflows
**Scale/Scope**: 10-50 concurrent projects, 1-70 workspaces, single user workstation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle Compliance

| Principle | Status | Justification |
|-----------|--------|---------------|
| I. Modular Composition | ✅ PASS | Extends existing modules: workspace_mode.py, project_filter_service.py, eww-workspace-bar.nix |
| III. Test-Before-Apply | ✅ PASS | Will use nixos-rebuild dry-build before switch |
| IX. Tiling WM Standards | ✅ PASS | Keyboard-first navigation (arrow keys, backspace, prefix filtering) |
| X. Python Dev Standards | ✅ PASS | Async/await via i3ipc.aio, Pydantic models, pytest testing |
| XI. i3 IPC Alignment | ✅ PASS | Sway IPC as authoritative state (workspace focus, window marks) |
| XII. Forward-Only Development | ✅ PASS | Complete replacement of current navigation (no legacy mode) |
| XIII. Deno CLI Standards | ✅ PASS | TypeScript i3pm worktree list with Zod validation |
| XIV. Test-Driven Development | ✅ PASS | Tests before implementation, autonomous execution |
| XV. Sway Test Framework | ✅ PASS | Declarative JSON tests for project switching validation |

### Gate Status: **PASS** - All constitutional principles satisfied

## Project Structure

### Documentation (this feature)

```text
specs/079-preview-pane-user-experience/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Python Daemon (workspace_mode, project_filter_service)
home-modules/desktop/i3-project-event-daemon/
├── workspace_mode.py              # Arrow key navigation handler (extend for project list)
├── project_filter_service.py      # Fuzzy matching logic (add numeric prefix scoring)
├── models/
│   └── project_filter.py          # Pydantic models (add branch_number, hierarchy fields)
└── window_environment_bridge.py   # Environment variable injection (add worktree metadata)

# Eww Widgets (preview pane, top bar)
home-modules/desktop/
├── eww-workspace-bar.nix          # Project list widget (add branch numbers, hierarchy view)
└── eww-top-bar/
    ├── eww.yuck.nix               # Top bar project label (add icon, accent styling)
    └── scripts/
        └── active-project.py      # Project monitor (include branch number, worktree status)

# TypeScript CLI (i3pm worktree commands)
home-modules/tools/i3pm/
├── src/
│   ├── commands/
│   │   └── worktree.ts            # Implement worktree list command
│   └── services/
│       └── worktree-metadata.ts   # Git metadata extraction (already exists)
└── deno.json

# Notification Integration
home-modules/tools/
└── claude-code-hooks/
    └── stop-hook.sh               # Include tmux window identifier in notifications

# Sway Keybindings
home-modules/desktop/
└── sway.nix                       # Arrow key bindings (route to project list navigation)

# Workspace Preview Daemon
home-modules/tools/sway-workspace-panel/
└── workspace-preview-daemon       # Handle project list navigation events

tests/
├── 079-preview-pane-user-experience/
│   ├── test_arrow_navigation.py      # Arrow key navigation unit tests
│   ├── test_numeric_prefix_filter.py # Prefix matching logic tests
│   ├── test_worktree_hierarchy.py    # Hierarchy display tests
│   ├── test_environment_injection.py # I3PM_IS_WORKTREE env var tests
│   └── test_notification_click.py    # Notification action tests
└── sway-tests/
    └── 079-project-selection.json    # End-to-end project switching tests
```

**Structure Decision**: Multi-component architecture extending existing modules. Python daemon handles event processing and state management (workspace_mode.py, project_filter_service.py). Nix generates Eww widgets for visual rendering. TypeScript/Deno CLI provides user commands. No new services created - all functionality integrates into existing architecture per Constitution Principle I (Modular Composition).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
