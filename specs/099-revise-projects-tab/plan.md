# Implementation Plan: Revise Projects Tab with Full CRUD Capabilities

**Branch**: `099-revise-projects-tab` | **Date**: 2025-11-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/099-revise-projects-tab/spec.md`

## Summary

Revise the Projects tab in the Eww monitoring widget to provide complete CRUD (Create, Read, Update, Delete) functionality for git projects and worktrees. The tab will display a hierarchical view of repositories with nested worktrees, support creating/deleting worktrees via the `i3pm worktree` CLI, and provide inline editing of project properties. This builds on Features 097 (Git-Centric Project Management) and 098 (Worktree-Aware Environment Integration).

## Technical Context

**Language/Version**:
- Yuck/GTK CSS (Eww widget definitions)
- Python 3.11+ (backend data script, CRUD handlers)
- Bash 5.0+ (helper scripts for worktree operations)
- TypeScript/Deno 1.40+ (i3pm CLI enhancements)

**Primary Dependencies**:
- Eww 0.4+ (GTK3 widget framework)
- i3ipc.aio (async Sway IPC for Python)
- Pydantic 2.x (data validation in Python)
- Zod 3.22+ (TypeScript schema validation)
- i3pm CLI (existing project/worktree commands)

**Storage**:
- JSON files in `~/.config/i3/projects/*.json` (project definitions)
- In-memory daemon state (project index, worktree relationships)

**Testing**:
- sway-test framework (declarative JSON tests per Constitution Principle XV)
- pytest (Python unit/integration tests)
- Manual screenshot verification via grim

**Target Platform**: Linux (Sway/Wayland on NixOS)

**Project Type**: Monorepo integration (Eww widget + Python backend + CLI)

**Performance Goals**:
- Discovery and initial display: <3 seconds
- Worktree creation: <30 seconds (form + git operations)
- Project switching: <500ms active indicator update
- Git status refresh: <2 seconds

**Constraints**:
- Must integrate with existing eww-monitoring-panel.nix structure
- Must use existing i3pm daemon IPC for state updates
- Must follow Constitution Principle XII (forward-only, no legacy support)

**Scale/Scope**:
- Support 50+ worktree projects across multiple parent repositories
- Handle 20+ concurrent worktrees for nixos repository

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | Extends existing eww-monitoring-panel module |
| II. Reference Implementation | PASS | Builds on Hetzner-Sway reference |
| III. Test-Before-Apply | PASS | Will use nixos-rebuild dry-build |
| IV. Override Priority | PASS | Uses existing home-manager option patterns |
| V. Platform Flexibility | PASS | Conditional features for Sway detection |
| VI. Declarative Configuration | PASS | All config in Nix expressions |
| VII. Documentation as Code | PASS | Updating CLAUDE.md with new features |
| X. Python Development | PASS | Using Python 3.11+, i3ipc.aio, Pydantic |
| XI. i3 IPC Alignment | PASS | Sway IPC as authoritative state source |
| XII. Forward-Only Development | PASS | Replacing/enhancing existing Projects tab |
| XIII. Deno CLI Standards | PASS | Using existing i3pm CLI patterns |
| XIV. Test-Driven Development | PASS | Will write tests before implementation |
| XV. Sway Test Framework | PASS | Will use declarative JSON tests |

**Gate Status**: PASS - No violations identified.

## Project Structure

### Documentation (this feature)

```text
specs/099-revise-projects-tab/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── project-api.md   # IPC method contracts
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
home-modules/desktop/
├── eww-monitoring-panel.nix      # Main widget module (modify projects-view, project-card, worktree-card)
└── i3-project-event-daemon/
    ├── services/
    │   └── worktree_service.py   # Worktree CRUD operations (enhance)
    └── models/
        └── project.py            # Project/worktree data models (enhance)

home-modules/tools/
├── i3_project_manager/
│   └── cli/
│       ├── monitoring_data.py    # Backend data script (enhance for hierarchical view)
│       └── project_crud_handler.py # CRUD handler (enhance for worktrees)
└── sway-test/                    # Test framework

tests/099-revise-projects-tab/
├── test_worktree_hierarchy.json  # Hierarchical display tests
├── test_worktree_create.json     # Creation workflow tests
├── test_worktree_delete.json     # Deletion workflow tests
└── test_project_switch.json      # Switching behavior tests
```

**Structure Decision**: Monorepo integration - modifying existing modules rather than creating new ones. The eww-monitoring-panel.nix is the primary target, with supporting changes to Python backend and i3pm CLI.

## Complexity Tracking

> No violations requiring justification.
