# Implementation Plan: Real-Time Event Log and Activity Stream

**Branch**: `092-logs-events-tab` | **Date**: 2025-11-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/092-logs-events-tab/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Add a fifth "Logs" tab to the existing Eww monitoring panel that streams real-time Sway IPC events (window creation, focus changes, workspace switches) with enriched metadata from the i3pm daemon (project associations, scope classification, registry app names). The event stream uses the existing deflisten architecture from Feature 085, maintains a 500-event circular buffer with FIFO eviction, provides filtering by event type and text search, and displays events with sub-100ms latency. This delivers comprehensive observability into window management operations for debugging and understanding system state changes.

## Technical Context

**Language/Version**: Python 3.11+ (backend event streaming), Yuck/GTK (Eww widget UI), Nix (module configuration)
**Primary Dependencies**: i3ipc.aio (Sway IPC event subscriptions), asyncio (event loop), Eww 0.4+ (GTK3), Sway 1.8+
**Storage**: In-memory circular buffer (500 events max, FIFO eviction), no persistent storage
**Testing**: pytest with async support (pytest-asyncio) for backend, manual UI testing for Eww widgets
**Target Platform**: NixOS with Sway compositor (Hetzner Sway, M1 hybrid configs)
**Project Type**: Desktop UI extension (GTK widget) with Python backend streaming service
**Performance Goals**: <100ms event display latency, <200ms filter response, 30fps UI @ 50+ events/second
**Constraints**: <50MB memory for event buffer, auto-reconnect on IPC disconnection (<5s recovery), sticky scroll behavior
**Scale/Scope**: 5 tabs total (Windows/Projects/Apps/Health/Logs), 500 event history, 8-10 event types (window::*, workspace::*, output::*, etc.)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Principle X: Python Development & Testing Standards

- **Compliance**: ✅ PASS - Python 3.11+ with async/await patterns (i3ipc.aio, asyncio)
- **Testing**: pytest with pytest-asyncio for backend event stream logic
- **Data Models**: Will use Pydantic models for event schemas and filter state
- **Error Handling**: Explicit error handling with clear user messages for IPC disconnection, daemon unavailability

**Validation**: Follows existing patterns from monitoring_data.py (Feature 085) - same async architecture, same i3ipc.aio library, same event subscription patterns.

### ✅ Principle XI: i3 IPC Alignment & State Authority

- **Compliance**: ✅ PASS - Sway IPC is authoritative source for all events
- **Event Subscriptions**: Uses i3ipc SUBSCRIBE message type for window, workspace, output events
- **Event-Driven**: <100ms latency event handlers (matches Feature 015 requirements)
- **Graceful Degradation**: Auto-reconnection with exponential backoff on IPC disconnection

**Validation**: Feature leverages Sway IPC natively - no custom state tracking, all events sourced from Sway, enrichment queried from i3pm daemon (which itself uses Sway IPC as authority).

### ✅ Principle XIV: Test-Driven Development & Autonomous Testing

- **Compliance**: ✅ PASS - Will follow TDD approach
- **Test Pyramid**: Unit tests for event models/filters (70%), integration tests for IPC subscriptions (20%), end-to-end tests for UI stream rendering (10%)
- **Autonomous Execution**: Backend tests run via pytest with no manual interaction
- **State Verification**: Sway IPC state queries validate event enrichment correctness

**Validation**: Backend Python components fully testable with pytest-asyncio (mock i3ipc events, verify circular buffer behavior, validate enrichment logic). UI tests limited to manual verification (Eww GTK widgets lack headless testing framework).

### ✅ Principle I: Modular Composition

- **Compliance**: ✅ PASS - Extends existing eww-monitoring-panel.nix module
- **Reuse**: Leverages monitoring_data.py backend script (Feature 085) with new `--mode events` flag
- **No Duplication**: Event streaming logic shares deflisten architecture, no new systemd services

**Validation**: Feature adds ~200-300 lines to existing Eww config (new tab, event list widget, filter controls). Backend script extended with event mode. Zero new modules or services.

### ✅ Principle VI: Declarative Configuration Over Imperative

- **Compliance**: ✅ PASS - All configuration via Nix modules
- **Widget Generation**: Eww Yuck code generated via Nix string interpolation in eww-monitoring-panel.nix
- **No Runtime Config**: Filter state and event buffer managed in-memory by backend script (ephemeral)

**Validation**: Follows existing pattern from Features 085, 088 - all UI declaratively defined in Nix, backend spawned by systemd service definition.

### 🟡 Principle XII: Forward-Only Development & Legacy Elimination

- **Compliance**: ⚠️ CONSIDERATION - Adding 5th tab to existing panel
- **Assessment**: No legacy code to replace - this is pure addition to existing monitoring panel
- **Justification**: No backwards compatibility concerns - existing tabs unchanged, new tab adds capability without legacy cruft

**Validation**: N/A - additive feature with no legacy to eliminate.

### Gate Summary

**Status**: ✅ **PASS** - All applicable principles satisfied

- ✅ Python/Testing standards aligned with constitution
- ✅ Sway IPC authority maintained
- ✅ TDD approach with autonomous backend testing
- ✅ Modular extension of existing feature
- ✅ Declarative Nix configuration
- ⚠️ Forward-only principle N/A (additive feature, no legacy)

**Proceed to Phase 0 research**

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Backend - Python event streaming service
home-modules/tools/i3_project_manager/cli/
└── monitoring_data.py        # EXTENDED - Add --mode events support
                               # New functions: query_events_data(), stream_events()
                               # Event enrichment via i3pm daemon client

# Frontend - Eww GTK widget
home-modules/desktop/
└── eww-monitoring-panel.nix  # EXTENDED - Add Logs tab UI
                               # New widgets: logs-view, event-card, filter-controls
                               # New variables: events_data, event_filter_state

# Tests - Backend event logic
tests/092-logs-events-tab/
├── unit/
│   ├── test_event_models.py          # Event schema validation
│   ├── test_event_buffer.py          # Circular buffer FIFO eviction
│   └── test_event_enrichment.py      # i3pm daemon metadata augmentation
├── integration/
│   ├── test_sway_ipc_subscriptions.py  # i3ipc event subscriptions
│   └── test_event_filtering.py         # Filter logic (type, search text)
└── fixtures/
    ├── mock_sway_events.py             # Mock Sway IPC event payloads
    └── sample_event_data.py            # Sample enriched event data
```

**Structure Decision**: This is an **extension feature** (not new project). We extend two existing files:
1. **Backend**: `monitoring_data.py` adds new event streaming mode (similar to existing windows/projects/apps/health modes)
2. **Frontend**: `eww-monitoring-panel.nix` adds new Logs tab widget (5th tab alongside Windows/Projects/Apps/Health)

No new files required in `home-modules/` - all changes are additive to existing Feature 085/088 codebase. Test structure follows existing pattern from Feature 085.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**Status**: ✅ No violations - complexity tracking not required

All constitution principles are satisfied. This is a straightforward extension of existing Feature 085 monitoring panel using established patterns.

---

## Phase 1 Design Review

### Constitution Re-Check (Post-Design)

After completing Phase 1 design (research, data model, contracts):

**✅ All gates still satisfied**

- ✅ **Python Standards (X)**: Event buffer uses `collections.deque`, Pydantic models for validation, async/await with i3ipc.aio
- ✅ **i3 IPC Authority (XI)**: All events sourced from Sway IPC, no parallel state tracking
- ✅ **TDD (XIV)**: Test structure defined in plan (unit/integration/fixtures), pytest-asyncio ready
- ✅ **Modular Composition (I)**: Extends monitoring_data.py and eww-monitoring-panel.nix (no new modules)
- ✅ **Declarative Config (VI)**: All UI in Nix-generated Yuck, no imperative scripts
- ✅ **Forward-Only (XII)**: N/A - additive feature

**Design Quality**:
- Event enrichment architecture is clean (on-demand daemon queries, graceful degradation)
- Circular buffer implementation uses stdlib (no custom ring buffer logic)
- Frontend filtering avoids backend complexity (Eww conditional rendering)
- Performance characteristics meet all success criteria (<100ms latency, 30fps @ 50 events/sec)

**Ready for Phase 2**: Task breakdown via `/speckit.tasks`

---

## Artifacts Generated

### Documentation

- ✅ `plan.md` - This file (implementation plan)
- ✅ `research.md` - Technical research and decisions
- ✅ `data-model.md` - Data structures and schemas
- ✅ `contracts/backend-frontend-api.md` - API specification
- ✅ `quickstart.md` - User guide and troubleshooting

### Context Updates

- ✅ `CLAUDE.md` - Agent context updated with new technologies

### Next Steps

Run `/speckit.tasks` to generate task breakdown (`tasks.md`) with dependency-ordered implementation steps.

---

## Implementation Guidance

### Backend Changes (monitoring_data.py)

1. Add `--mode events` argument handling
2. Implement `query_events_data()` function (one-shot mode)
3. Implement `stream_events()` function (deflisten mode)
4. Add event enrichment via DaemonClient
5. Implement event buffer with `collections.deque(maxlen=500)`
6. Add event batching logic (100ms debounce window)
7. Add icon/color mapping for event types
8. Generate searchable_text field for filtering

### Frontend Changes (eww-monitoring-panel.nix)

1. Add "Logs" tab button to header
2. Add `events_data` deflisten variable
3. Add `event_filter_state`, `scroll_at_bottom`, `events_paused` variables
4. Implement `logs-view` widget (main container)
5. Implement `event-card` widget (individual event display)
6. Implement `filter-controls` widget (type buttons, search box)
7. Add keyboard handler for tab 5 (`5` or `Alt+5`)
8. Add Catppuccin Mocha styling for event cards

### Test Implementation

1. Unit tests: Event models, buffer FIFO eviction, icon mapping
2. Integration tests: Sway IPC subscriptions, event enrichment, filtering
3. Manual UI tests: Tab switching, filtering, search, scroll behavior

**Estimated Effort**: 2-3 days (backend 1 day, frontend 1 day, testing 0.5 day, polish 0.5 day)
