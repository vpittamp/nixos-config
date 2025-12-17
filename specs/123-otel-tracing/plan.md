# Implementation Plan: OpenTelemetry AI Assistant Monitoring

**Branch**: `123-otel-tracing` | **Date**: 2025-12-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/123-otel-tracing/spec.md`

## Summary

Implement native OpenTelemetry-based AI assistant monitoring that replaces all legacy detection mechanisms (tmux polling, badge files, Claude hooks). A single OTLP HTTP receiver service will accept telemetry from Claude Code and Codex CLI, process session lifecycle events, and output JSON streams directly to EWW via deflisten for fully event-driven UI updates.

## Technical Context

**Language/Version**: Python 3.11+ (OTLP receiver), Nix (configuration), Yuck/SCSS (EWW widgets)
**Primary Dependencies**: opentelemetry-proto (parsing), aiohttp/uvicorn (HTTP server), EWW deflisten
**Storage**: N/A (in-memory session state only, no persistence)
**Testing**: pytest-asyncio (unit/integration), sway-test (UI validation)
**Target Platform**: NixOS/Linux with Sway (Wayland), systemd user services
**Project Type**: Single service + configuration modules
**Performance Goals**: <1 second latency from AI event to UI update (SC-001, SC-002)
**Constraints**: <30MB memory (SC-004), fully event-driven/no polling (SC-005), 10+ concurrent sessions (SC-003)
**Scale/Scope**: 2 AI tools (Claude Code, Codex CLI), single-user desktop

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | New `otel-ai-monitor` service module + modified EWW modules |
| II. Reference Implementation | ✅ PASS | Hetzner Sway is reference; feature validated there first |
| III. Test-Before-Apply | ✅ PASS | All changes tested via `dry-build` before apply |
| IV. Override Priority Discipline | ✅ PASS | Standard options, no `mkForce` needed |
| V. Conditional Features | ✅ PASS | Service enables conditionally via `services.otel-ai-monitor.enable` |
| VI. Declarative Configuration | ✅ PASS | All config in Nix modules; no imperative scripts |
| VII. Documentation as Code | ✅ PASS | Spec, plan, quickstart included |
| X. Python Standards | ✅ PASS | Python 3.11+, async/await, pytest, type hints |
| XII. Forward-Only Development | ✅ PASS | **KEY**: Clean replacement of legacy code, no backward compat |
| XIV. Test-Driven Development | ✅ PASS | Tests before implementation, autonomous execution |

**Gate Result**: ✅ ALL GATES PASS - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/123-otel-tracing/
├── plan.md              # This file
├── research.md          # Phase 0: OTLP protocol research
├── data-model.md        # Phase 1: Session/event entities
├── quickstart.md        # Phase 1: User quick start guide
└── tasks.md             # Phase 2: Implementation tasks
```

### Source Code (repository root)

```text
# New files to create
scripts/otel-ai-monitor/
├── __init__.py
├── __main__.py              # CLI entry point (systemd ExecStart)
├── models.py                # Session, TelemetryEvent Pydantic models
├── receiver.py              # OTLP HTTP receiver (aiohttp)
├── session_tracker.py       # Session state machine
├── notifier.py              # Desktop notification sender
└── output.py                # JSON stream writer (stdout)

home-modules/services/
└── otel-ai-monitor.nix      # New service module

# Files to modify
home-modules/ai-assistants/
└── claude-code.nix          # Add OTEL_* env vars, remove state hooks

home-modules/desktop/eww-top-bar/
├── eww.yuck.nix             # Replace defpoll with deflisten for AI sessions
└── scripts/ai-sessions-status.sh  # REMOVE (replaced by deflisten)

home-modules/desktop/
└── eww-monitoring-panel.nix # Replace badge consumption with stream

# Files to remove
scripts/tmux-ai-monitor/     # Entire directory
scripts/claude-hooks/
├── prompt-submit-notification.sh
├── stop-notification.sh
├── stop-notification-handler.sh
└── swaync-action-callback.sh
home-modules/services/
└── tmux-ai-monitor.nix

tests/otel-ai-monitor/
├── test_models.py           # Unit tests for Pydantic models
├── test_receiver.py         # OTLP parsing tests
├── test_session_tracker.py  # State machine tests
└── fixtures/
    └── sample_otlp.py       # Sample OTLP payloads
```

**Structure Decision**: Single Python service (`scripts/otel-ai-monitor/`) following Constitution Principle X (Python Standards). Service runs as systemd user unit, outputs to stdout for EWW deflisten consumption. No web frontend; all UI via existing EWW widgets.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. Design follows simplest approach:
- Single Python service (no microservices)
- In-memory state (no database)
- Stdout streaming (no message queue)
- Native OTLP protocol (no custom instrumentation)

## Constitution Re-Check (Post-Design)

*Re-evaluated after Phase 1 design artifacts created.*

| Principle | Status | Post-Design Notes |
|-----------|--------|-------------------|
| I. Modular Composition | ✅ PASS | data-model.md shows clean entity separation |
| VI. Declarative Configuration | ✅ PASS | quickstart.md shows Nix-only config |
| X. Python Standards | ✅ PASS | Pydantic models, async patterns confirmed |
| XII. Forward-Only Development | ✅ PASS | research.md R1-R10 all use optimal approaches |
| XIV. Test-Driven Development | ✅ PASS | Test files in project structure |

**Post-Design Gate Result**: ✅ ALL GATES PASS - Ready for Phase 2 (tasks.md)

## Generated Artifacts

| Artifact | Path | Purpose |
|----------|------|---------|
| Plan | `specs/123-otel-tracing/plan.md` | This file |
| Research | `specs/123-otel-tracing/research.md` | OTLP protocol, Claude/Codex telemetry |
| Data Model | `specs/123-otel-tracing/data-model.md` | Session, Event, Output entities |
| Quick Start | `specs/123-otel-tracing/quickstart.md` | User documentation |

## Next Steps

Run `/speckit.tasks` to generate implementation tasks from this plan.
