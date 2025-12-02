# Implementation Plan: Enhanced Worktree User Experience

**Branch**: `109-enhance-worktree-user-experience` | **Date**: 2025-12-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/109-enhance-worktree-user-experience/spec.md`

## Summary

Enhance the Eww monitoring panel's worktree management capabilities to provide an exceptional parallel development experience. This includes:

1. **Worktree Navigation**: Fast switching (<500ms) between worktrees with comprehensive status visibility
2. **Lazygit Integration**: Deep integration using `--path` and view positional arguments to open lazygit in the correct context
3. **CRUD Operations**: Streamlined create/delete workflows with safety guardrails
4. **Keyboard-First UX**: Full keyboard navigation for power users
5. **Status Indicators**: Real-time visibility into dirty, sync, stale, merged, and conflict states

## Technical Context

**Language/Version**: Python 3.11+ (daemon/backend), Yuck/GTK3 (Eww widgets), Bash 5.0+ (scripts), Nix (module configuration)
**Primary Dependencies**: i3ipc.aio (Sway IPC), Pydantic 2.x (data models), Eww 0.4+ (GTK3 widgets), asyncio (event handling), lazygit 0.40+ (git TUI)
**Storage**: JSON files (`~/.config/i3/projects/*.json`), in-memory daemon state
**Testing**: pytest (Python), sway-test framework (Sway IPC state verification)
**Target Platform**: NixOS with Sway Wayland compositor (Hetzner reference, M1 secondary)
**Project Type**: NixOS home-manager module with Python backend and Eww widget frontend
**Performance Goals**: <500ms worktree switch, <2s status update, <100ms panel interaction latency
**Constraints**: Event-driven architecture (no polling), Sway IPC as authoritative state source
**Scale/Scope**: 10-20 worktrees per repository, 3-5 concurrent repositories

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Extends existing eww-monitoring-panel.nix module |
| III. Test-Before-Apply | ✅ PASS | Will use dry-build before switch |
| VI. Declarative Configuration | ✅ PASS | All config via Nix modules and JSON |
| X. Python Development Standards | ✅ PASS | Python 3.11+, asyncio, Pydantic, pytest |
| XI. i3 IPC Alignment | ✅ PASS | Sway IPC as authoritative state source |
| XII. Forward-Only Development | ✅ PASS | Enhancing existing implementation, no legacy compat needed |
| XIII. Deno CLI Standards | ⚠️ N/A | No new Deno CLI tools in this feature |
| XIV. Test-Driven Development | ✅ PASS | Will create sway-test cases for worktree operations |
| XV. Sway Test Framework | ✅ PASS | Will use declarative JSON tests for Eww panel state |

**Gate Result**: ✅ PASS - All applicable principles satisfied

## Project Structure

### Documentation (this feature)

```text
specs/109-enhance-worktree-user-experience/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (IPC contracts)
│   └── lazygit-context.json
└── tasks.md             # Phase 2 output (not created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/desktop/
├── eww-monitoring-panel.nix      # Main Eww panel configuration (MODIFY)
│   ├── projects_tab widget       # Worktree list display (ENHANCE)
│   ├── worktree_card widget      # Individual worktree card (ENHANCE)
│   ├── worktree_actions widget   # Action buttons/menu (NEW)
│   └── keyboard handlers         # Focus mode keybindings (ADD)
└── i3-project-event-daemon/
    ├── services/
    │   └── worktree_service.py   # Worktree operations (ENHANCE)
    ├── models/
    │   └── worktree.py           # Worktree data model (EXISTS)
    └── handlers/
        └── lazygit_handler.py    # Lazygit context launch (NEW)

home-modules/tools/
├── monitoring-panel/
│   └── project_crud_handler.py   # CRUD operations (ENHANCE)
└── i3_project_manager/
    └── cli/
        └── monitoring_data.py    # Backend data (EXISTS)

scripts/
└── worktree-lazygit.sh           # Lazygit launcher script (NEW)

tests/
├── 109-enhance-worktree-ux/
│   ├── test_worktree_switch.json      # sway-test: worktree switching
│   ├── test_lazygit_context.json      # sway-test: lazygit launch
│   └── test_keyboard_navigation.json  # sway-test: keyboard shortcuts
└── i3_project_manager/
    └── unit/
        └── test_lazygit_context.py    # pytest: context generation
```

**Structure Decision**: Extends existing home-modules structure following Constitution Principle I (Modular Composition). No new top-level directories needed - enhancements integrate into existing eww-monitoring-panel.nix and i3-project-event-daemon modules.

## Complexity Tracking

> No violations to justify - implementation follows existing patterns.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | - | - |
