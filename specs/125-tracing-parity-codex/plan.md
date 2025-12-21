# Implementation Plan: Tracing Parity for Gemini CLI and Codex CLI

**Branch**: `125-tracing-parity-codex` | **Date**: 2025-12-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/125-tracing-parity-codex/spec.md`

## Summary

Bring Gemini CLI and Codex CLI tracing to parity with Claude Code's observability capabilities. Unlike Claude Code (which required a Node.js interceptor and 10+ hooks), both Gemini and Codex have **native OTEL support**. This feature leverages their native telemetry, adds attribute normalization in Alloy, implements cost calculation, and enhances otel-ai-monitor for multi-CLI session tracking.

Key approach:
1. Configure native OTEL export from both CLIs (already partially done)
2. Add Alloy transform processors for attribute normalization
3. Extend otel-ai-monitor to parse Gemini/Codex events and calculate costs
4. Verify unified querying in Grafana Tempo

## Technical Context

**Language/Version**: Python 3.11+ (otel-ai-monitor), Nix (configuration), Alloy config language
**Primary Dependencies**: Grafana Alloy 1.x, opentelemetry-proto, aiohttp, Pydantic
**Storage**: N/A (in-memory session state in otel-ai-monitor)
**Testing**: Manual verification via CLI runs + Grafana trace inspection
**Target Platform**: NixOS (Linux) with Sway/Wayland desktop
**Project Type**: NixOS configuration modules + Python service enhancements
**Performance Goals**: Telemetry processing latency <100ms, no impact on CLI responsiveness
**Constraints**: Best-effort telemetry (no blocking), 100MB Alloy buffer before drop
**Scale/Scope**: Single user, 3 CLIs, ~1000 spans/session typical

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Extends existing modules (gemini-cli.nix, codex.nix, grafana-alloy.nix, otel-ai-monitor) |
| III. Test-Before-Apply | ✅ PASS | Will use `dry-build` before applying Nix changes |
| VI. Declarative Configuration | ✅ PASS | All config via Nix expressions and JSON settings |
| X. Python Development Standards | ✅ PASS | otel-ai-monitor uses Python 3.11+, Pydantic, async patterns |
| XII. Forward-Only Development | ✅ PASS | Enhancing existing architecture, no legacy compat needed |

**No violations requiring justification.**

## Project Structure

### Documentation (this feature)

```text
specs/125-tracing-parity-codex/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (pricing tables, event mappings)
├── quickstart.md        # Phase 1 output (testing procedures)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Nix configuration modules (existing, to be enhanced)
home-modules/ai-assistants/
├── gemini-cli.nix       # Gemini CLI settings (OTEL config exists)
├── codex.nix            # Codex CLI settings (OTEL config exists)
└── claude-code.nix      # Reference implementation

modules/services/
└── grafana-alloy.nix    # Add transform processors for Gemini/Codex

home-modules/services/
└── otel-ai-monitor.nix  # Service configuration

# Python service (existing, to be enhanced)
scripts/otel-ai-monitor/
├── models.py            # Add Gemini/Codex event names, pricing fields
├── session_tracker.py   # Enhanced cost calculation
├── receiver.py          # Parse Gemini/Codex OTLP formats
└── pricing.py           # NEW: Cost calculation with pricing tables
```

**Structure Decision**: Enhances existing NixOS configuration modules and Python otel-ai-monitor service. No new top-level directories needed.

## Complexity Tracking

> No violations requiring justification.
