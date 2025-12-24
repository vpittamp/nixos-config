# Implementation Plan: Multiple AI Indicators Per Terminal Window

**Branch**: `136-multiple-indicators` | **Date**: 2025-12-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/136-multiple-indicators/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable the EWW monitoring panel to display multiple AI session indicators per terminal window, supporting scenarios where users run multiple AI CLIs (Claude Code, Codex, Gemini) in different tmux panes of the same terminal. The current architecture tracks sessions correctly but aggregates them to a single badge per window—this feature exposes all sessions for each window with overflow handling (3 visible + "+N more" badge for additional sessions).

## Technical Context

**Language/Version**: Python 3.11+ (otel-ai-monitor), Nix (configuration), Yuck/SCSS (EWW widgets)
**Primary Dependencies**: Pydantic, aiohttp, EWW 0.4+, i3ipc.aio
**Storage**: In-memory session state in otel-ai-monitor (no persistence changes needed)
**Testing**: pytest with async support, manual verification via tmux + multiple AI CLIs
**Target Platform**: NixOS with Sway/Wayland (hetzner-sway configuration)
**Project Type**: Single (modifications to existing otel-ai-monitor service + EWW widgets)
**Performance Goals**: Indicator updates within 2 seconds of session state changes (per FR-008)
**Constraints**: Support at least 5 concurrent AI sessions per window (FR-006), UI remains functional
**Scale/Scope**: 2-5 concurrent sessions per window typical, 10+ for power users

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Changes scoped to otel-ai-monitor + EWW panel modules |
| III. Test-Before-Apply | ✅ PASS | Will verify with dry-build before switch |
| VI. Declarative Configuration | ✅ PASS | EWW widgets defined in Nix, no imperative scripts |
| X. Python Development Standards | ✅ PASS | Pydantic models, async patterns, type hints |
| XI. Sway/i3 IPC Alignment | ✅ PASS | Window correlation already uses IPC as authoritative source |
| XII. Forward-Only Development | ✅ PASS | Replacing single-badge model with multi-badge, no backward compat |
| XIV. Test-Driven Development | ✅ PASS | Will add tests for multi-session scenarios |
| XVI. Observability Standards | ✅ PASS | Extends existing OTEL session tracking without breaking pipeline |

### Post-Design Check (Phase 1 Complete)

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Data model changes isolated to session_tracker.py, monitoring_data.py, windows-view.yuck.nix |
| VI. Declarative Configuration | ✅ PASS | New `otel_badges` array generated declaratively in Python |
| X. Python Development Standards | ✅ PASS | Extended Pydantic models with proper typing (List[Dict]) |
| XI. Sway/i3 IPC Alignment | ✅ PASS | No changes to IPC layer; window_id correlation unchanged |
| XII. Forward-Only Development | ✅ PASS | Breaking change from `badge.otel_*` to `otel_badges[]`; no compat layer |
| XVI. Observability Standards | ✅ PASS | `sessions_by_window` grouping enables per-window telemetry aggregation |

**All gates passed.** Ready to proceed to Phase 2 (task generation).

## Project Structure

### Documentation (this feature)

```text
specs/136-multiple-indicators/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Modified Files (existing)
scripts/otel-ai-monitor/
├── models.py                    # Extend SessionListItem model with pane context
├── session_tracker.py           # Remove deduplication, group by window_id
└── output_writer.py             # Emit window-grouped session arrays

home-modules/desktop/eww-monitoring-panel/
├── yuck/
│   └── windows-view.yuck.nix    # Render multiple badges per window
└── scss/
    └── components.scss          # Add badge overflow styling

# Test Files (new/modified)
tests/otel-ai-monitor/
├── test_multi_session.py        # Multi-session tracking tests (new)
└── test_window_grouping.py      # Window grouping logic tests (new)
```

**Structure Decision**: Modifications to existing otel-ai-monitor Python service and EWW widget definitions. No new directories needed—changes are scoped to existing module boundaries per Constitution Principle I (Modular Composition).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
