# Implementation Plan: Unified Workspace/Window/Project Switcher

**Branch**: `072-unified-workspace-switcher` | **Date**: 2025-11-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/072-unified-workspace-switcher/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance workspace mode to show a visual list of ALL windows across all workspaces when entering workspace mode (CapsLock/Ctrl+0). Users can filter the list by typing workspace digits (e.g., "23" shows only workspace 23) or switch to project search mode by typing ":" prefix. The preview card displays within 150ms with <50ms updates, using Eww for rendering and extending the existing workspace-preview-daemon (Feature 057) for state queries.

## Technical Context

**Language/Version**: Python 3.11+ (matches existing workspace-preview-daemon)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Eww 0.4+ (preview card rendering), orjson (fast JSON serialization), pyxdg (desktop entry icon resolution)
**Storage**: N/A (in-memory state only, consumed by Eww deflisten)
**Testing**: sway-test framework (TypeScript/Deno, Feature 069 sync-based testing)
**Target Platform**: NixOS with Sway/Wayland compositor (Hetzner, M1 configurations)
**Project Type**: Single (extending existing workspace-preview-daemon)
**Performance Goals**: <150ms initial preview render, <50ms keystroke-to-update latency, <100ms project fuzzy match
**Constraints**: Preview card max height 600px with GTK scrolling, support 100+ windows across 70 workspaces, <10ms GET_TREE query overhead
**Scale/Scope**: 100+ windows, 70 workspaces, 20-50 projects (typical developer workstation)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards ✅

- **Python 3.11+**: ✅ Matches existing workspace-preview-daemon
- **Async/await patterns**: ✅ Uses i3ipc.aio for Sway IPC (existing pattern)
- **Testing framework**: ✅ sway-test framework (Feature 069) for window manager testing
- **Type hints**: ✅ Required for all function signatures
- **Data validation**: ✅ Pydantic models for event payloads (existing pattern)
- **Rich UI**: N/A (daemon outputs JSON, no terminal UI)
- **Module structure**: ✅ Extending existing `PreviewRenderer` class

### Principle XI: i3 IPC Alignment & State Authority ✅

- **Sway IPC as authority**: ✅ Uses GET_TREE, GET_WORKSPACES for window queries
- **Event-driven architecture**: ✅ Extends existing workspace_mode event subscriptions
- **State validation**: ✅ No custom state tracking - queries Sway IPC on demand
- **i3ipc.aio library**: ✅ Used for all async Sway IPC communication
- **Event latency**: ✅ <100ms target aligns with existing daemon (<20ms measured)

### Principle XII: Forward-Only Development & Legacy Elimination ✅

- **Optimal architecture**: ✅ Extends existing daemon, no compatibility shims needed
- **Legacy code**: N/A (new feature, no legacy to replace)
- **Backwards compatibility**: ✅ Preserves existing workspace navigation behavior (FR-009)
- **Complete replacement**: ✅ Enhances (not replaces) existing preview card system

### Principle XIV: Test-Driven Development & Autonomous Testing ✅

- **Test-first approach**: ✅ Will write sway-test JSON definitions before implementation
- **Test pyramid**: ✅ Unit tests (PreviewRenderer), integration (IPC queries), E2E (sway-test)
- **Autonomous execution**: ✅ sway-test framework provides autonomous UI testing
- **Sway IPC state verification**: ✅ Test validates window list via GET_TREE queries
- **Headless CI/CD**: ✅ sway-test supports headless Sway session

### Principle XV: Sway Test Framework Standards ✅

- **Declarative JSON tests**: ✅ Will use sway-test for all window manager validation
- **Partial mode**: ✅ Will test focusedWorkspace, windowCount, workspace structure
- **Sway IPC authority**: ✅ GET_TREE provides authoritative window list state
- **TypeScript/Deno**: ✅ Tests use existing sway-test framework
- **Test failures block commits**: ✅ All tests must pass before merging

### ❌ No Constitutional Violations

All implementation decisions align with existing constitution principles. No complexity justification required.

## Project Structure

### Documentation (this feature)

```text
specs/072-unified-workspace-switcher/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (COMPLETED)
├── data-model.md        # Phase 1 output (pending)
├── quickstart.md        # Phase 1 output (pending)
├── contracts/           # Phase 1 output (pending - JSON schemas for preview card)
│   └── preview-card-all-windows.schema.json
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (extends existing workspace-preview-daemon)

```text
home-modules/tools/sway-workspace-panel/
├── workspace-preview-daemon         # Main daemon (extend emit_preview function)
├── preview_renderer.py              # Add render_all_windows() method
├── models.py                        # Pydantic models for events (existing)
└── icon_resolver.py                 # Desktop icon resolution (existing)

home-modules/desktop/
├── eww-workspace-bar.nix            # Add all-windows preview card widget
└── unified-bar-theme.nix            # Styling for grouped workspace view

home-modules/tools/sway-test/tests/
└── sway-tests/
    ├── basic/
    │   └── test_unified_switcher_all_windows.json  # P1: All windows view
    ├── integration/
    │   ├── test_unified_switcher_filter.json       # P2: Digit filtering
    │   └── test_unified_switcher_project_mode.json # P3: Project mode
    └── regression/
        └── test_preview_card_performance.json      # Performance validation
```

**Structure Decision**: Single project extension - modifying existing workspace-preview-daemon (Python 3.11+) and Eww workspace bar configuration. No new daemons required. Tests use sway-test framework (Feature 069) for autonomous window manager validation.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No violations** - This feature extends existing infrastructure without adding complexity.

## Phase 0: Research (COMPLETED)

**Status**: ✅ Complete
**Output**: [research.md](research.md)

**Key Findings**:
- **Window Query Performance**: Sway IPC GET_TREE takes ~15-30ms for 100 windows (within 50ms budget)
- **Preview Architecture**: Extend existing workspace-preview-daemon (80% code reuse)
- **Project Integration**: Reuse existing project_mode event system (no new code needed)
- **Event Flow**: Leverage Sway keybinding routing (digits vs letters handled by Sway)
- **Eww Rendering**: GTK scroll widget handles 500+ items smoothly (no virtual scrolling needed)

## Phase 1: Design & Contracts (COMPLETED)

**Status**: ✅ Complete

**Outputs**:
- [data-model.md](data-model.md) - Pydantic models for AllWindowsPreview, WorkspaceGroup, WindowPreviewEntry
- [contracts/preview-card-all-windows.schema.json](contracts/preview-card-all-windows.schema.json) - JSON Schema for Eww integration
- [quickstart.md](quickstart.md) - User-facing documentation with keybindings and troubleshooting

**Key Decisions**:
- **Data Model**: `AllWindowsPreview` extends existing preview system with `workspace_groups` array
- **Performance**: <150ms initial render (50ms Sway IPC + 50ms construction + 50ms Eww render)
- **Edge Cases**: Max 20 initial workspace groups, scrollable GTK widget, instructional state
- **Testing**: sway-test framework (Feature 069) for autonomous window manager validation

**Agent Context**: Updated CLAUDE.md with Python 3.11+, i3ipc.aio, Eww 0.4+, orjson dependencies

## Phase 2: Task Generation (COMPLETED)

**Status**: ✅ Complete
**Command**: `/speckit.tasks`
**Output**: [tasks.md](tasks.md)

**Generated Tasks**: 57 total tasks organized by user story
- **Phase 1 - Setup**: 5 tasks (review existing architecture)
- **Phase 2 - Foundational**: 6 tasks (data models + daemon IPC client)
- **Phase 3 - User Story 1 (P1)**: 14 tasks (all-windows preview + 3 tests)
- **Phase 4 - User Story 2 (P2)**: 12 tasks (workspace filtering + 4 tests)
- **Phase 5 - User Story 3 (P3)**: 11 tasks (project mode + 4 tests)
- **Phase 6 - Polish**: 9 tasks (performance, docs, validation)

**Task Breakdown**:
1. Setup tasks (T001-T005): Review existing infrastructure
2. Foundational tasks (T006-T011): AllWindowsPreview/WorkspaceGroup/WindowPreviewEntry models, daemon IPC client
3. US1 tasks (T012-T025): render_all_windows() method, Eww widget, GTK scrolling, instructional/empty states
4. US2 tasks (T026-T037): Digit filtering, workspace validation, <50ms update latency
5. US3 tasks (T038-T048): ":" prefix detection, project mode transition, <100ms fuzzy match
6. Polish tasks (T049-T057): Performance logging, debouncing, edge cases, documentation

**Parallel Opportunities**: 15 tasks marked [P] for parallel execution
- Setup phase: 3 parallel tasks
- User story tests: 11 parallel test creation tasks
- Polish phase: 6 parallel tasks

**MVP Scope**: User Story 1 only (T001-T025) = 25 tasks
**Incremental Delivery**: US1 → US2 → US3 → Polish

## Planning Summary

**Branch**: `072-unified-workspace-switcher`
**Research Duration**: ~1 hour (agent-driven)
**Design Duration**: ~30 minutes
**Total Planning Time**: ~1.5 hours

**Constitutional Compliance**:
- ✅ Principle X: Python 3.11+, i3ipc.aio, sway-test framework
- ✅ Principle XI: Sway IPC as authority (GET_TREE, GET_WORKSPACES)
- ✅ Principle XII: Forward-only (no legacy compatibility)
- ✅ Principle XIV: Test-driven (sway-test before implementation)
- ✅ Principle XV: Declarative JSON tests (partial mode)

**Risk Assessment**: **LOW**
- Extends proven infrastructure (Feature 057 workspace-preview-daemon)
- 80% code reuse from existing preview system
- Performance validated via research (15-30ms GET_TREE)
- All edge cases identified and handled

**Ready for**: `/speckit.tasks` to generate implementation tasks

---

**Last Updated**: 2025-11-12
**Phase**: Planning Complete (Phase 0 + Phase 1)
**Next**: Task Generation (Phase 2)
