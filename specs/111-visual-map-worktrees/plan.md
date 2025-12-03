# Implementation Plan: Visual Worktree Relationship Map

**Branch**: `111-visual-map-worktrees` | **Date**: 2025-12-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/111-visual-map-worktrees/spec.md`

## Summary

Add a visual graph representation to the monitoring panel's Projects tab showing worktree relationships, branch lineage, and merge status. The map displays worktrees as nodes with edges indicating parent-child relationships, ahead/behind commit counts, and merge flow status. Implementation uses server-side SVG generation in Python with existing monitoring panel infrastructure for display.

## Technical Context

**Language/Version**: Python 3.11+ (backend), Yuck/GTK3 CSS (Eww widgets), Bash (scripts)
**Primary Dependencies**: i3ipc.aio (Sway IPC), Pydantic 2.x (data models), Eww 0.4+ (GTK3 widgets), drawsvg (SVG generation)
**Storage**: In-memory cache with TTL, SVG files in `/tmp/worktree-map-*.svg`
**Testing**: pytest (Python), sway-test (Sway IPC state verification)
**Target Platform**: NixOS with Sway, Hetzner and M1 configurations
**Project Type**: Single project extension (monitoring panel)
**Performance Goals**: <2s map render for 20 worktrees, <500ms project switch from map click
**Constraints**: <100ms SVG generation, 5-minute cache TTL for branch relationships
**Scale/Scope**: Support 10-20 worktrees per repository, 5-level branch depth hierarchy

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Extends existing monitoring panel module, no code duplication |
| II. Reference Implementation | ✅ PASS | Hetzner-Sway reference platform, validated first |
| III. Test-Before-Apply | ✅ PASS | dry-build required, sway-test validation |
| VI. Declarative Configuration | ✅ PASS | Nix module configuration, generated widgets |
| X. Python Standards | ✅ PASS | Python 3.11+, async/await, Pydantic models, pytest |
| XI. i3 IPC Alignment | ✅ PASS | Sway IPC authoritative for window/workspace state |
| XII. Forward-Only Development | ✅ PASS | New feature, no legacy compatibility needed |
| XIII. Deno CLI Standards | N/A | No CLI changes, backend-only |
| XIV. Test-Driven Development | ✅ PASS | Tests for SVG generation, relationship detection |
| XV. Sway Test Framework | ✅ PASS | Declarative JSON tests for panel interactions |

**Gate Status**: ✅ ALL GATES PASS - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/111-visual-map-worktrees/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0: Technical research findings
├── data-model.md        # Phase 1: Data model definitions
├── quickstart.md        # Phase 1: User guide
├── contracts/           # Phase 1: API contracts
│   └── relationship-cache.schema.json
└── tasks.md             # Phase 2: Implementation tasks
```

### Source Code (repository root)

```text
home-modules/tools/i3_project_manager/
├── services/
│   ├── git_utils.py              # Extended: merge-base, branch relationships
│   └── worktree_map_service.py   # NEW: SVG generation, layout algorithm
├── models/
│   └── worktree_relationship.py  # NEW: Relationship data models
└── cli/
    └── monitoring_data.py        # Extended: map data output

home-modules/desktop/
└── eww-monitoring-panel.nix      # Extended: map widget, tab integration

tests/111-visual-map-worktrees/
├── unit/
│   ├── test_merge_base.py
│   ├── test_svg_generation.py
│   └── test_layout_algorithm.py
├── integration/
│   └── test_relationship_cache.py
└── sway-tests/
    └── test_map_interaction.json
```

**Structure Decision**: Single project extension - extends existing monitoring panel infrastructure with new Python services and Eww widgets. No new top-level directories.

## Complexity Tracking

> No violations requiring justification - all gates pass.
