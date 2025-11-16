# Implementation Plan: Enhanced Project Selection in Eww Preview Dialog

**Branch**: `078-eww-preview-improvement` | **Date**: 2025-11-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/078-eww-preview-improvement/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance the Eww preview dialog's project selection mode to provide fuzzy filtering, visual worktree relationship display, and rich project metadata. Users activate project mode via ":" prefix, type to filter projects with real-time fuzzy matching, navigate with arrow keys, and switch projects via Enter. The implementation extends the existing workspace mode architecture (Python daemon + Eww widget) with new IPC events, enhanced project data models, and improved UI rendering.

## Technical Context

**Language/Version**: Python 3.11+ (i3pm daemon, workspace-preview-daemon), Nix (Eww widget generation)
**Primary Dependencies**: i3ipc.aio, Pydantic, Eww (GTK widgets), asyncio
**Storage**: JSON project files (`~/.config/i3/projects/*.json`), in-memory daemon state
**Testing**: pytest with pytest-asyncio for daemon logic, sway-test framework for end-to-end window manager validation
**Target Platform**: NixOS with Sway/Wayland compositor (Hetzner Cloud, M1 Mac)
**Project Type**: Single project - extends existing i3pm daemon and Eww workspace panel
**Performance Goals**: <50ms filter response time for 100 projects, <16ms arrow key navigation latency
**Constraints**: Must integrate with existing workspace mode architecture, maintain <100ms event propagation latency
**Scale/Scope**: Up to 100 projects per user, 3-5 concurrent Sway sessions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition ✅
- Feature extends existing modular architecture (workspace_mode.py, preview_renderer.py, eww-workspace-bar.nix)
- New functionality added to existing modules, not new monolithic files
- Follows Base → Services → Desktop inheritance

### Principle III: Test-Before-Apply ✅
- All configuration changes validated via `nixos-rebuild dry-build`
- Python daemon changes require pytest test suite

### Principle X: Python Development Standards ✅
- Python 3.11+ with async/await patterns via i3ipc.aio and asyncio
- Pydantic models for data validation (project metadata, filter state)
- Type hints for all new functions and public APIs

### Principle XI: i3 IPC Alignment ✅
- N/A for this feature - focuses on project management, not window state
- Project list comes from filesystem, not Sway IPC

### Principle XII: Forward-Only Development ✅
- Enhances existing project mode, does not add legacy compatibility layers
- Complete replacement of single-match display with full project list

### Principle XIII: Deno CLI Development Standards ✅
- N/A - Feature uses Python daemon, not Deno CLI tool

### Principle XIV: Test-Driven Development ✅
- Acceptance scenarios from spec translate to pytest async tests
- End-to-end tests via sway-test framework for keyboard input simulation

### Principle XV: Sway Test Framework Standards ✅
- Keyboard navigation tests use sway-test declarative JSON definitions
- Partial mode for focused assertions (project switch result, focused workspace)

## Project Structure

### Documentation (this feature)

```text
specs/078-eww-preview-improvement/
├── spec.md              # Feature specification (completed)
├── plan.md              # This file
├── research.md          # Phase 0 output (fuzzy matching algorithms, project data enrichment)
├── data-model.md        # Phase 1 output (ProjectMetadata, FilterState, ProjectListItem)
├── quickstart.md        # Phase 1 output (user guide for enhanced project selection)
├── contracts/           # Phase 1 output (IPC event schemas, Eww data contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Existing files to modify
home-modules/desktop/i3-project-event-daemon/
├── workspace_mode.py              # Add project list loading, fuzzy filtering, arrow navigation
├── project_service.py             # Add project metadata enrichment (worktree detection, git status)
└── models.py                      # Add ProjectListItem, FilterState Pydantic models

home-modules/tools/sway-workspace-panel/
├── workspace-preview-daemon       # Handle project_mode events, render project list
├── preview_renderer.py            # Add render_project_list() method
├── models.py                      # Add ProjectPreviewData, ProjectListEntry models
└── selection_models/
    └── selection_state.py         # Extend for project list selection (index-based)

home-modules/desktop/
└── eww-workspace-bar.nix          # Add project list widget (yuck), styling (scss)

# Test files
tests/078-eww-preview-improvement/
├── test_fuzzy_matching.py         # Unit tests for fuzzy matching algorithm
├── test_project_metadata.py       # Unit tests for worktree detection, git status
├── test_project_list_selection.py # Integration tests for arrow navigation
└── sway-tests/
    └── test_project_switch.json   # End-to-end sway-test for keyboard workflow
```

**Structure Decision**: Single project extending existing workspace-preview architecture. Modifications localized to workspace_mode.py (daemon), preview_renderer.py (rendering), and eww-workspace-bar.nix (UI). No new top-level directories required.

## Complexity Tracking

> No Constitution violations - implementation follows existing patterns
