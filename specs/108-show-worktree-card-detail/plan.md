# Implementation Plan: Enhanced Worktree Card Status Display

**Branch**: `108-show-worktree-card-detail` | **Date**: 2025-12-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/108-show-worktree-card-detail/spec.md`

## Summary

Enhance existing Eww worktree cards in the monitoring panel's Projects tab to display comprehensive git status information at-a-glance. This includes dirty/clean indicators, ahead/behind sync status, branch merge status, stale worktree detection, and detailed tooltips. The feature builds on existing infrastructure (monitoring_data.py, git_utils.py) which already provides basic git status (dirty, ahead, behind).

## Technical Context

**Language/Version**: Python 3.11+ (monitoring_data.py backend), Yuck/GTK (Eww widgets), Nix (home-manager module)
**Primary Dependencies**: i3ipc.aio (Sway IPC), Pydantic 2.x (data models), Eww 0.4+ (GTK3 widgets), asyncio
**Storage**: In-memory daemon state, JSON project files (`~/.config/i3/projects/*.json`)
**Testing**: pytest for Python backend, sway-test framework for UI validation
**Target Platform**: NixOS with Sway compositor (Hetzner headless VNC, M1 Mac)
**Project Type**: Single project - enhancing existing monitoring panel module
**Performance Goals**: Status indicators update within 100ms of panel refresh, git queries complete in <50ms per worktree
**Constraints**: Keep widget compact - all indicators in single row, tooltips for details, avoid UI clutter
**Scale/Scope**: Support 20+ worktrees across multiple repositories without performance degradation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Modular Composition** | ✅ PASS | Enhances existing eww-monitoring-panel.nix module, follows existing patterns |
| **III. Test-Before-Apply** | ✅ PASS | Will use pytest for backend, sway-test for UI validation |
| **VI. Declarative Configuration** | ✅ PASS | All configuration via Nix/home-manager |
| **X. Python Standards** | ✅ PASS | Uses existing monitoring_data.py patterns (async, Pydantic) |
| **XI. i3/Sway IPC Alignment** | ✅ PASS | No Sway IPC changes needed - git status is independent |
| **XII. Forward-Only Development** | ✅ PASS | Enhances existing widgets, no legacy compatibility needed |
| **XIV. Test-Driven Development** | ✅ WILL COMPLY | Tests will be written with implementation |
| **XV. Sway Test Framework** | ⚠️ N/A | Feature is pure UI/data - no Sway state changes |

**No violations requiring justification.**

## Project Structure

### Documentation (this feature)

```text
specs/108-show-worktree-card-detail/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── contracts/           # Phase 1 output (IPC contracts)
```

### Source Code (repository root)

```text
# Existing files to enhance:
home-modules/desktop/eww-monitoring-panel.nix    # Eww widget definitions (Yuck), styles (SCSS)
home-modules/tools/i3_project_manager/
├── cli/monitoring_data.py                       # Backend data provider
└── services/git_utils.py                        # Git metadata extraction

# New/enhanced test files:
tests/108-show-worktree-card-detail/
├── unit/
│   ├── test_git_status_enhanced.py             # New git status fields (merge, stale)
│   └── test_status_indicators.py               # Status indicator logic
├── integration/
│   └── test_monitoring_data_enhanced.py        # Enhanced worktree data
└── fixtures/
    └── sample_worktree_states.py               # Mock git states
```

**Structure Decision**: Enhances existing monitoring_data.py + eww-monitoring-panel.nix. No new source directories needed.

## Complexity Tracking

No violations requiring justification - feature follows existing patterns.
