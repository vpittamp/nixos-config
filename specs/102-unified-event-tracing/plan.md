# Implementation Plan: Unified Event Tracing System

**Branch**: `102-unified-event-tracing` | **Date**: 2025-11-30 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/102-unified-event-tracing/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Unify the event tracing system by publishing i3pm internal events (project::switch, visibility::*, command::*, launch::*) to the Log tab alongside raw Sway events, enabling cross-referencing between Log and Trace views, causality chain visualization, enhanced output event distinction, and trace templates for common debugging scenarios. Implementation extends the existing EventBuffer and WindowTracer services while adding correlation_id propagation via `contextvars.ContextVar` for causality tracking.

## Technical Context

**Language/Version**: Python 3.11+ (i3pm daemon, monitoring data backend), Yuck/GTK3 (Eww widgets), Nix (module configuration)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Pydantic 2.x (data models), asyncio (event handling), contextvars (correlation propagation), Eww 0.4+ (GTK3 widgets)
**Storage**: In-memory circular buffer (500 events), JSON files for trace persistence (~/.local/share/i3pm/event-history/)
**Testing**: pytest with pytest-asyncio (daemon), sway-test framework (widget integration)
**Target Platform**: Linux with Sway compositor (Hetzner headless, M1 hybrid)
**Project Type**: Single - daemon extensions + widget updates
**Performance Goals**: <100ms Log tab UI update latency, handle 100+ events/sec without loss, <1s trace template startup
**Constraints**: 500-event buffer limit (requires copy-on-evict), 10 concurrent traces max, 1000 events per trace max
**Scale/Scope**: ~30 new event types visible in Log tab, 3 trace templates, 4 filter categories

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate (Phase 0)

| Principle | Requirement | Status | Notes |
|-----------|-------------|--------|-------|
| **I. Modular Composition** | No code duplication, composable modules | ✅ PASS | Extends existing EventBuffer, WindowTracer services |
| **III. Test-Before-Apply** | dry-build before switch | ✅ PASS | Standard workflow |
| **VI. Declarative Configuration** | No imperative scripts | ✅ PASS | Nix modules, Eww widget definitions |
| **X. Python Standards** | Python 3.11+, async/await, pytest, Pydantic | ✅ PASS | Extends existing daemon architecture |
| **XI. i3 IPC Alignment** | Sway IPC as source of truth, event-driven | ✅ PASS | Enhances existing event handlers |
| **XII. Forward-Only Development** | No legacy compatibility layers | ✅ PASS | Adds new features, no backwards compat needed |
| **XIV. Test-Driven Development** | Tests before implementation | ✅ PASS | Will define tests in spec acceptance scenarios |
| **XV. Sway Test Framework** | Declarative JSON tests for Sway state | ✅ PASS | Can test cross-reference navigation |

**Pre-Research Gate Result**: ✅ PASS - Proceed to Phase 0

### Post-Design Gate (Phase 1)

| Principle | Requirement | Status | Notes |
|-----------|-------------|--------|-------|
| **I. Modular Composition** | No code duplication | ✅ PASS | UnifiedEventType enum shared by buffer and tracer |
| **X. Python Standards** | Pydantic models, type hints | ✅ PASS | All entities use dataclass/Pydantic with full typing |
| **XI. i3 IPC Alignment** | Sway IPC as authority | ✅ PASS | Output diffing uses swaymsg get_outputs, not custom state |
| **XIII. Deno Standards** | N/A | ✅ N/A | No CLI changes in this feature |
| **XIV. Test-Driven** | Tests defined before impl | ✅ PASS | Test files outlined in project structure |
| **XV. Sway Test Framework** | Declarative JSON tests | ✅ PASS | Can test cross-ref navigation via sway-test |

**Post-Design Gate Result**: ✅ PASS - Ready for /speckit.tasks

## Project Structure

### Documentation (this feature)

```text
specs/102-unified-event-tracing/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── ipc-methods.md   # New IPC methods for cross-referencing
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/desktop/i3-project-event-daemon/
├── event_buffer.py              # MODIFY: Add correlation_id, copy-on-evict
├── handlers.py                  # MODIFY: Publish i3pm events to buffer
├── models/
│   ├── legacy.py                # MODIFY: Extend EventEntry with correlation_id, trace_id
│   └── events.py                # NEW: Unified event type definitions (30+ types)
├── services/
│   ├── window_tracer.py         # MODIFY: Cross-reference APIs, template support
│   ├── correlation_service.py   # NEW: ContextVar-based correlation tracking
│   └── output_event_service.py  # NEW: State diffing for output event distinction
└── daemon.py                    # MODIFY: Initialize correlation service

home-modules/tools/i3_project_manager/cli/
└── monitoring_data.py           # MODIFY: Publish i3pm events in --mode events --listen

home-modules/desktop/
└── eww-monitoring-panel.nix     # MODIFY: Add i3pm filter category, cross-ref UI, templates

tests/102-unified-event-tracing/
├── unit/
│   ├── test_correlation_service.py
│   ├── test_output_event_detection.py
│   └── test_event_filter_categories.py
├── integration/
│   ├── test_i3pm_event_publishing.py
│   ├── test_cross_reference_navigation.py
│   └── test_causality_chain_tracking.py
└── fixtures/
    ├── mock_sway_events.py
    └── sample_trace_data.py
```

**Structure Decision**: Extends existing i3pm daemon architecture (single project pattern). New services are added for correlation tracking and output event detection. Eww widget definitions are modified in place. Test suite follows existing pattern in tests/ directory.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations - all Constitution principles satisfied. Implementation extends existing services rather than adding new layers.
