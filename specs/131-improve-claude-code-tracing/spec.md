# Feature Specification: Improve Claude Code Tracing (v131)

**Feature Branch**: `131-improve-claude-code-tracing`  
**Created**: 2025-12-20  
**Status**: Implemented ✅

## Goal

Improve the Claude Code logical tracing so that:

1. **Turns are correct** (a single user prompt produces one Turn span, even across tool loops).
2. **Causality is explicit** (LLM spans ↔ Tool spans are linked, not just inferred from timing).
3. **Subagents are robustly linked** (multiple concurrent `Task` subagents don’t all link to the last Task).
4. **Correlation works in Grafana** across:
   - Claude Code native metrics/logs (`session.id` UUID)
   - Interceptor traces (`session.id`, `gen_ai.conversation.id`)
   - Derived “span metrics” with exemplars (metrics → traces navigation)

## What Was Wrong (Key Findings)

### 1) Turn boundary bug

Anthropic `tool_result` payloads are encoded as `role: "user"` messages.  
The prior “new turn if last message role == user” heuristic created extra Turn spans per tool loop.

### 2) `session.id` mismatch (no correlation)

Claude Code native telemetry uses `session.id` as a **UUID per conversation**.  
The interceptor generated `session.id = claude-${pid}-${timestamp}`, so:

- Logs/metrics and traces could not be joined by `session.id`
- Local `otel-ai-monitor` saw two “sessions” for the same conversation

### 3) Multi-Task subagent correlation race

When a single LLM response contains multiple `Task` tool calls, writing a single “current Task” traceparent
causes “last Task wins”: multiple subagents link to the same parent Task span.

## Implementation Summary

### A) Fix turn boundary detection

Treat a request as a new turn only if the last message is a **user prompt** (not a `tool_result` message).

### B) Hydrate `session.id` from hooks

Use a lightweight `SessionStart` hook to write Claude Code’s `session_id` (UUID) to:

`$XDG_RUNTIME_DIR/claude-session-${PID}.json`

The Node interceptor reads this before emitting spans so its `session.id` matches Claude Code native telemetry.

### C) Add explicit causality (span links)

- **Tool spans** include a span link to the **LLM span** that produced the `tool_use`.
- **LLM spans** include span links to **Tool spans** whose `tool_result` blocks are included in the request.

This improves “why did this happen?” analysis without relying on naming heuristics.

### D) Robust subagent linking for concurrent Tasks

For each `Task` tool call, the parent writes a per-Task context file:

`$XDG_RUNTIME_DIR/claude-task-context-${parentPid}-${tool_use_id}.json`

Subagents atomically “claim” one context file (rename) to link to the correct parent Task span.

Additionally, subagent root spans record `claude.parent_session_id` to correlate back to the parent conversation.

### E) Span→Metrics exemplars (Grafana)

Alloy now includes an `otelcol.connector.spanmetrics` pipeline to derive RED metrics from spans and attach exemplars.
To avoid cardinality explosions, `span.name` is excluded.

### F) Local verification harness

Added `scripts/test-otel-interceptor-harness.js` to validate turn boundaries, `session.id` hydration, and causal links without hitting the real Anthropic API.

## Files Changed

- `scripts/minimal-otel-interceptor.js` (v3.5.0)
- `scripts/claude-hooks/otel-session-start.sh`
- `scripts/claude-hooks/otel-session-end.sh`
- `home-modules/ai-assistants/claude-code.nix`
- `modules/services/grafana-alloy.nix`
- `scripts/test-otel-interceptor-harness.js`

## Open Questions / Future Improvements

1. **True trace context exemplars on Claude Code native metrics**: requires in-process tracing context (OTel SDK)
   or emitting custom metrics from the interceptor.
2. **Profiles ↔ traces**: adopt Pyroscope eBPF profiling or NodeJS SDK, then configure Grafana “traces to profiles”
   using `service.name`, `host.name`, and time-range correlations.
3. **Permission wait visibility**: consider emitting spans/events for PermissionRequest/Notification hooks to show
   time spent awaiting user approval.
