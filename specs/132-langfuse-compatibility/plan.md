# Implementation Plan: Langfuse-Compatible AI CLI Tracing

**Branch**: `132-langfuse-compatibility` | **Date**: 2025-12-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/132-langfuse-compatibility/spec.md`

## Summary

Enhance the existing AI CLI tracing infrastructure to be optimized for Langfuse observability. The system will:
1. Transform existing OTEL spans into Langfuse-compatible format with proper run types (`chain`, `llm`, `tool`)
2. Export to Langfuse's OTEL endpoint alongside existing local monitoring
3. Apply LangSmith SDK patterns for trace hierarchy, content serialization, and usage extraction
4. Support all three AI CLIs (Claude Code, Codex, Gemini) with unified semantic conventions

## Technical Context

**Language/Version**: Python 3.11+ (otel-ai-monitor), JavaScript/Node.js (interceptors)
**Primary Dependencies**: opentelemetry-proto, aiohttp, Grafana Alloy, existing interceptor scripts
**Storage**: N/A (in-memory session state, remote Langfuse storage)
**Testing**: pytest (Python), manual integration testing with Langfuse UI
**Target Platform**: NixOS (Hetzner/ThinkPad), Linux x86_64
**Project Type**: Single project (extension of existing telemetry stack)
**Performance Goals**: <60s trace delivery to Langfuse, <100ms local processing overhead
**Constraints**: Maintain backward compatibility with EWW panel, no disruption to existing Alloy pipeline
**Scale/Scope**: 3 AI CLIs, single-user workstation, ~100 sessions/day

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Extends existing modules (grafana-alloy.nix, otel-ai-monitor) |
| III. Test-Before-Apply | ✅ PASS | NixOS dry-build required before deployment |
| VI. Declarative Configuration | ✅ PASS | All Langfuse config via NixOS module options |
| XII. Forward-Only Development | ✅ PASS | No legacy compatibility layers needed |
| XIV. Test-Driven Development | ✅ PASS | Integration tests verify trace structure in Langfuse |
| XVI. Observability Standards | ✅ PASS | Aligns with OTEL/Alloy patterns in constitution |

**Gate Result**: PASSED - No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/132-langfuse-compatibility/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── langfuse-otel-mapping.md
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Existing files to modify:
scripts/
├── otel-ai-monitor/
│   ├── models.py              # Add Langfuse attribute mappings
│   ├── receiver.py            # Add Langfuse-specific span enrichment
│   ├── langfuse_exporter.py   # NEW: Langfuse OTLP exporter
│   └── session_tracker.py     # Add usage_metadata aggregation
├── minimal-otel-interceptor.js    # Add Langfuse attributes
├── codex-otel-interceptor.js      # Add Langfuse attributes
└── gemini-otel-interceptor.js     # Add Langfuse attributes

modules/services/
└── grafana-alloy.nix          # Add Langfuse export destination

home-modules/tools/
└── claude-code/
    └── otel-config.nix        # Add Langfuse env vars
```

**Structure Decision**: Single project extending existing telemetry stack. No new directories needed - modifications to existing interceptors, otel-ai-monitor service, and Alloy configuration.

## Complexity Tracking

> No Constitution Check violations requiring justification.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |
