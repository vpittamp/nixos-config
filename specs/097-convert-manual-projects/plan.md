# Implementation Plan: Git-Centric Project and Worktree Management

**Branch**: `097-convert-manual-projects` | **Date**: 2025-11-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/097-convert-manual-projects/spec.md`

## Summary

Redesign i3pm project management to use git's native architecture as the single source of truth. Use `bare_repo_path` (GIT_COMMON_DIR) as the canonical identifier for grouping all worktrees. Implement a unified project model with three types: `repository` (primary entry point, one per bare repo), `worktree` (linked to parent repository), and `standalone` (no worktrees). Provide full worktree CRUD operations via monitoring panel UI with hierarchical display.

## Technical Context

**Language/Version**: Python 3.11+ (daemon, services), TypeScript/Deno 1.40+ (CLI)
**Primary Dependencies**: i3ipc.aio (Sway IPC), Pydantic 2.x (validation), Zod 3.22+ (TypeScript schemas), Eww (GTK widgets)
**Storage**: JSON files in `~/.config/i3/projects/*.json`
**Testing**: pytest (Python), Deno.test (TypeScript), sway-test framework (window manager)
**Target Platform**: NixOS with Sway/Wayland (Hetzner, M1)
**Project Type**: Single (extends existing i3pm codebase)
**Performance Goals**: <10s worktree creation, <5s worktree deletion, <2s git metadata refresh, <3 clicks to switch worktrees
**Constraints**: <200ms panel update latency, event-driven (not polling)
**Scale/Scope**: ~10-50 projects per user, ~1-20 worktrees per repository

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Extends existing `project_editor.py`, `monitoring_data.py`, and i3pm-deno CLI modules |
| II. Reference Implementation | ✅ PASS | Features validated against Hetzner Sway reference |
| III. Test-Before-Apply | ✅ PASS | Will use `nixos-rebuild dry-build` before deployment |
| X. Python Standards | ✅ PASS | Python 3.11+, async/await, Pydantic, pytest |
| XI. i3 IPC Alignment | ✅ PASS | Git is source of truth (not daemon state), events via IPC subscriptions |
| XII. Forward-Only | ✅ PASS | No backwards compatibility - fresh implementation, old projects recreated via discovery |
| XIII. Deno CLI Standards | ✅ PASS | TypeScript/Deno 1.40+, `@std/cli/parse-args`, Zod validation |
| XIV. Test-Driven Development | ✅ PASS | Tests before implementation, sway-test for window manager |
| XV. Sway Test Framework | ✅ PASS | Declarative JSON tests for panel interactions |

**Gate Status**: ✅ ALL PASS - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/097-convert-manual-projects/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (CLI commands, IPC messages)
├── checklists/
│   └── requirements.md  # Specification quality checklist
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Python Backend (daemon/services)
home-modules/tools/i3_project_manager/
├── models/
│   └── project_config.py    # MODIFY: Add source_type, bare_repo_path, parent_project fields
├── services/
│   └── project_editor.py    # MODIFY: Update list_projects() for new model
└── cli/
    └── monitoring_data.py   # MODIFY: Update project display for hierarchy

# TypeScript CLI (i3pm-deno)
home-modules/tools/i3pm-deno/
├── src/
│   ├── models/
│   │   └── project.ts       # MODIFY: Add unified project schema
│   ├── commands/
│   │   ├── project/
│   │   │   └── discover.ts  # NEW: Discovery command
│   │   └── worktree/
│   │       ├── create.ts    # EXISTS: Update to use bare_repo_path
│   │       ├── remove.ts    # EXISTS: Verify correct deletion
│   │       └── list.ts      # EXISTS: Update for hierarchy
│   └── services/
│       ├── project-manager.ts    # MODIFY: Add discovery service
│       └── git-worktree.ts       # EXISTS: Core git operations
└── tests/
    └── project/
        └── discover_test.ts # NEW: Discovery tests

# Eww Panel (monitoring widget)
home-modules/desktop/eww-monitoring-panel/
├── eww.yuck              # MODIFY: Add hierarchy display, CRUD buttons
└── eww.scss              # MODIFY: Style for worktree nesting

# sway-test (window manager testing)
tests/097-convert-manual-projects/
├── test_project_hierarchy.json   # NEW: Panel hierarchy tests
├── test_worktree_create.json     # NEW: Creation workflow tests
└── test_worktree_delete.json     # NEW: Deletion workflow tests
```

**Structure Decision**: Extends existing i3pm codebase (single project pattern). Python for daemon/services following Constitution X, TypeScript/Deno for CLI following Constitution XIII. Eww for panel UI. No new top-level directories - all code integrates into existing module structure.

## Complexity Tracking

> No Constitution violations - all checks passed.

| Aspect | Complexity Level | Justification |
|--------|-----------------|---------------|
| Unified Project Model | Low | Single schema with discriminator simplifies code vs separate types |
| Git as Source of Truth | Low | Eliminates state synchronization bugs - git is always authoritative |
| No Backwards Compatibility | Reduces complexity | Constitution XII allows forward-only development |
