# Implementation Plan: Enhanced Git Worktree Status Indicators

**Branch**: `120-improve-git-changes` | **Date**: 2025-12-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/120-improve-git-changes/spec.md`

## Summary

Enhance the eww monitoring panel to display comprehensive git worktree status information in both the Windows view project headers and Worktree cards. Users will see at-a-glance status indicators showing dirty/clean state, sync status (ahead/behind), merge status, conflicts, staleness, and a visual diff bar showing line additions/deletions. Status indicators are displayed in priority order (conflicts > dirty > sync > stale > merged) with all applicable states visible.

## Technical Context

**Language/Version**: Python 3.11+ (monitoring_data.py, git_utils.py), Yuck/GTK (eww widgets), SCSS (styling)
**Primary Dependencies**: eww 0.4+, i3ipc.aio, Pydantic, existing i3_project_manager infrastructure
**Storage**: N/A (data computed on demand from git commands)
**Testing**: pytest for Python, visual inspection for eww widgets, sway-test for integration
**Target Platform**: Hetzner Sway (primary), NixOS with Sway/eww
**Project Type**: Single project - extends existing monitoring panel
**Performance Goals**: <50ms git status computation per worktree, 10-second polling interval
**Constraints**: 2-second timeout for git commands, no blocking of UI rendering
**Scale/Scope**: 10-20 concurrent worktrees typical usage

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Extends existing modules (monitoring_data.py, eww-monitoring-panel.nix) |
| II. Reference Implementation | ✅ PASS | Hetzner Sway is current reference, this feature targets it |
| III. Test-Before-Apply | ✅ PASS | Will run dry-build before deployment |
| V. Platform Flexibility | ✅ PASS | Git status works on all platforms with worktrees |
| VI. Declarative Configuration | ✅ PASS | All config in Nix modules, no imperative scripts |
| X. Python Development Standards | ✅ PASS | Python 3.11+, Pydantic models, type hints |
| XI. i3 IPC Alignment | ✅ PASS | Uses existing daemon infrastructure, Sway IPC for window state |
| XII. Forward-Only Development | ✅ PASS | Replacing/enhancing existing indicators, no legacy compat needed |
| XIV. Test-Driven Development | ✅ PASS | Unit tests for data transforms, visual tests for eww |
| XV. Sway Test Framework | ⚠️ PARTIAL | Integration tests recommended but not blocking for UI feature |

## Project Structure

### Documentation (this feature)

```text
specs/120-improve-git-changes/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
home-modules/tools/i3_project_manager/
├── services/
│   └── git_utils.py                    # MODIFY: Add diff stats extraction
├── cli/
│   └── monitoring_data.py              # MODIFY: Add diff bar computation, enhance status fields
└── models/
    └── worktree.py                     # MODIFY: Add diff stats to model (if not present)

home-modules/desktop/
└── eww-monitoring-panel.nix            # MODIFY: Add status to project headers, enhance worktree cards

tests/120-improve-git-changes/
├── unit/
│   ├── test_git_diff_stats.py          # NEW: Test diff stats parsing
│   └── test_status_indicator_logic.py  # NEW: Test priority ordering, bar calculation
└── fixtures/
    └── sample_git_outputs.py           # NEW: Mock git command outputs
```

**Structure Decision**: Single project extending existing monitoring panel infrastructure. No new directories needed - modifications to existing files.

## Complexity Tracking

> No complexity violations identified. Feature extends existing infrastructure without adding new abstractions or platform targets.
