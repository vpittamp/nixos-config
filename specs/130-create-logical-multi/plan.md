# Implementation Plan: Logical Multi-Span Trace Hierarchy for Claude Code

**Branch**: `130-create-logical-multi` | **Date**: 2025-12-20 | **Spec**: [spec.md](./spec.md)
**Status**: ✅ Implementation Complete | **Validated**: 2025-12-20
**Input**: Feature specification from `/specs/130-create-logical-multi/spec.md`

## Summary

Replace the existing two-level trace hierarchy (Session → API Calls) with a comprehensive multi-level structure (Session → Turns → LLM/Tool spans) that follows OpenTelemetry GenAI semantic conventions. The new implementation will capture user turns as logical groupings, individual tool executions, subagent correlation via span links, and token cost attribution - enabling meaningful trace visualization in Grafana Tempo.

## Technical Context

**Language/Version**: JavaScript (Node.js, Claude Code runtime)
**Primary Dependencies**: Node.js `http` module (built-in), `node:buffer`
**Storage**: N/A (stateless interceptor, memory-only during session)
**Testing**: Manual verification via Grafana Tempo trace visualization
**Target Platform**: Linux (NixOS), works on all platforms supporting Claude Code
**Project Type**: Single script (fetch interceptor injected via NODE_OPTIONS)
**Performance Goals**: <5ms overhead per API call, <1KB memory per span
**Constraints**: No external dependencies, must work within Claude Code's Node.js runtime
**Scale/Scope**: Single file replacement (~500 lines), supports sessions with 500+ API calls

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|------------|-------|
| III. Test-Before-Apply | ✅ PASS | Will test with dry-build and verify traces in Tempo |
| VI. Declarative Configuration | ✅ PASS | Interceptor configured via Nix wrapper in claude-code.nix |
| XII. Forward-Only Development | ✅ PASS | Complete replacement of minimal-otel-interceptor.js |
| XIII. Deno CLI Standards | N/A | This is Node.js (Claude Code runtime), not Deno CLI |
| XIV. Test-Driven Development | ⚠️ PARTIAL | Manual testing via Tempo; automated tests not feasible for interceptor |

**Gate Status**: PASS - No blocking violations. Partial TDD compliance is acceptable for trace interceptors where automated testing requires complex infrastructure.

## Project Structure

### Documentation (this feature)

```text
specs/130-create-logical-multi/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (OTLP span schemas)
├── checklists/
│   └── requirements.md  # Specification quality checklist
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
scripts/
├── minimal-otel-interceptor.js     # REPLACE with new implementation
└── claude-hooks/
    └── bash-history.sh             # Unaffected (separate hook)

home-modules/ai-assistants/
└── claude-code.nix                 # Node wrapper configuration (minimal changes)

modules/services/
└── grafana-alloy.nix               # Trace enrichment rules (may need updates)
```

**Structure Decision**: Single-file replacement pattern. The new interceptor replaces `scripts/minimal-otel-interceptor.js` with no new files required. The Alloy configuration may need minor updates to handle new span types.

## Complexity Tracking

No Constitution violations requiring justification. Implementation is straightforward single-file replacement.

## Implementation Summary

### Components Delivered

| Component | File | Description |
|-----------|------|-------------|
| Interceptor v3.4.0 | `scripts/minimal-otel-interceptor.js` | Multi-span hierarchy with hybrid trace context lookup |
| SessionStart hook | `scripts/claude-hooks/otel-session-start.sh` | Creates trace context, sets OTEL_* env vars |
| PreToolUse hook | `scripts/claude-hooks/otel-pretool-task.sh` | Propagates context to Task tool subagents |
| SessionEnd hook | `scripts/claude-hooks/otel-session-end.sh` | Finalizes session span on exit |
| NixOS integration | `home-modules/ai-assistants/claude-code.nix` | Wires hooks and NODE_OPTIONS |

### Validation Results (2025-12-20)

**Trace Context Propagation Test**:
- ✅ SessionStart creates `$XDG_RUNTIME_DIR/claude-otel-*.json`
- ✅ SessionStart creates `.claude-trace-context.json` in working dir
- ✅ Environment variables set: `OTEL_TRACE_PARENT`, `OTEL_SESSION_TRACE_ID`, `OTEL_SESSION_SPAN_ID`
- ✅ Subagent inherits same trace ID (`b3540f524bb42d1b86bc0d8eda61ece4`)
- ✅ W3C Trace Context format valid
- ✅ Parent-child span relationships established

### Remaining Work

- [ ] T056: Remove backup file after 1 week stable operation (2025-12-27)
