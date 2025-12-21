# Feature Specification: Improve Claude Code Tracing (v131)

**Feature Branch**: `131-improve-claude-code-tracing`
**Created**: 2025-12-20
**Updated**: 2025-12-21
**Status**: Implemented ✅ (Phase 1 + Phase 2 + Phase 3)

## Goal

Improve the Claude Code logical tracing so that:

1. **Turns are correct** (a single user prompt produces one Turn span, even across tool loops).
2. **Causality is explicit** (LLM spans ↔ Tool spans are linked, not just inferred from timing).
3. **Subagents are robustly linked** (multiple concurrent `Task` subagents don't all link to the last Task).
4. **Correlation works in Grafana** across:
   - Claude Code native metrics/logs (`session.id` UUID)
   - Interceptor traces (`session.id`, `gen_ai.conversation.id`)
   - Derived "span metrics" with exemplars (metrics → traces navigation)
5. **Cost visibility** (USD cost per LLM call, turn, and session)
6. **Error tracking** (error type classification and count)
7. **Permission wait visibility** (spans for user approval time)
8. **Complete tool lifecycle** (exit_code, output_summary from PostToolUse hook)
9. **Subagent completion** (explicit SubagentStop hook with subagent.session_id)
10. **Notification events** (NOTIFICATION spans for permission_prompt, auth_success)
11. **Context compaction** (COMPACTION spans for manual/auto compaction)

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

---

## Phase 2 Implementation (v3.8.0)

### G) Cost Metrics

Added USD cost calculation for LLM calls using Anthropic's pricing:

| Model | Input ($/1M) | Output ($/1M) | Cache Read | Cache Write |
|-------|--------------|---------------|------------|-------------|
| claude-opus-4-5 | 15.00 | 75.00 | 1.50 | 18.75 |
| claude-sonnet-4 | 3.00 | 15.00 | 0.30 | 3.75 |
| claude-3-5-sonnet | 3.00 | 15.00 | 0.30 | 3.75 |
| claude-3-5-haiku | 0.80 | 4.00 | 0.08 | 1.00 |

New span attributes:
- `gen_ai.usage.cost_usd` (double) - USD cost per LLM call, aggregated to turn and session spans
- Configurable via `OTEL_INTERCEPTOR_MODEL_PRICING_JSON` environment variable

### H) Error Handling

Added error classification based on HTTP status codes and API error types:

| Status | Error Type |
|--------|------------|
| 401, 403 | auth |
| 429 | rate_limit |
| 408, 504 | timeout |
| 4xx | validation |
| 5xx | server |

New span attributes:
- `error.type` (string) - Classification of the error
- `turn.error_count` (int) - Number of errors in the turn

Session tracker now accumulates `error_count` and `last_error_type` per session.

### I) Permission Wait Visibility

Added PERMISSION spans to track time spent waiting for user approval:

1. `PermissionRequest` hook writes metadata to `$XDG_RUNTIME_DIR/claude-permission-${pid}-${tool_use_id}.json`
2. Interceptor polls for permission files and tracks pending permissions
3. When `tool_result` arrives, permission span completed as "approved"
4. When turn ends with pending permissions, completed as "denied"

New span attributes:
- `openinference.span.kind: PERMISSION`
- `permission.tool` (string) - Tool requiring permission (e.g., "Write", "Bash")
- `permission.result` (string) - "approved" or "denied"
- `permission.wait_ms` (int) - Duration of user wait
- `permission.prompt` (string) - Truncated tool description

### J) Enhanced Test Coverage

Expanded test harness with 6 comprehensive test suites:
- **Basic** - Turn boundaries, tool loops, session.id hydration
- **Streaming** - SSE event stream parsing with token extraction
- **Concurrent** - Multiple Task tool_use blocks with context files
- **Error** - 429 rate limit, 500 server error with error.type classification
- **Permission** - PERMISSION spans for user approval wait time
- **Cost** - gen_ai.usage.cost_usd calculation and aggregation

---

## Phase 3 Implementation (v3.9.0) - Trace Coherence

Phase 3 enhances trace coherence by aligning the interceptor's span model with Claude Code's native architecture for orchestration, tool lifecycle, and subagent management.

### K) PostToolUse Hook Integration

Enhanced Tool spans with full lifecycle metadata from PostToolUse hook:

1. `PostToolUse` hook writes metadata to `$XDG_RUNTIME_DIR/claude-posttool-${pid}-${tool_use_id}.json`
2. Interceptor caches posttool metadata and integrates into Tool span completion
3. Enriches Tool spans with execution results

New span attributes:
- `tool.execution.exit_code` (int) - Exit code (primarily for Bash tools)
- `tool.output.summary` (string) - Truncated output preview (200 chars)
- `tool.output.lines` (int) - Line count for Read/Bash output
- `tool.error.type` (string) - Error classification (not_found, permission_denied, timeout)

### L) SubagentStop Hook Integration

Added explicit subagent completion tracking via SubagentStop hook:

1. `SubagentStop` hook fires on parent when Task subagent completes
2. Writes metadata to `$XDG_RUNTIME_DIR/claude-subagent-stop-${pid}-${tool_use_id}.json`
3. Interceptor creates `SUBAGENT_COMPLETION` span linking to original Task

New span type: `openinference.span.kind: SUBAGENT_COMPLETION`

New span attributes:
- `subagent.completed` (bool) - Always true when hook fires
- `subagent.completion_source` (string) - "hook" (explicit) vs "inferred"
- `subagent.session_id` (string) - Child session UUID for cross-session correlation

### M) Notification Event Spans

Added NOTIFICATION spans for Claude Code notification events:

1. `Notification` hook captures permission_prompt, auth_success events
2. Writes metadata to `$XDG_RUNTIME_DIR/claude-notification-${pid}-${timestamp}.json`
3. Interceptor creates zero-duration NOTIFICATION spans

New span type: `openinference.span.kind: NOTIFICATION`

New span attributes:
- `notification.type` (string) - Event type (permission_prompt, auth_success)
- `notification.message` (string) - Truncated notification message
- `notification.timestamp_ms` (int) - Event timestamp

### N) Context Compaction Visibility

Added COMPACTION spans for context window compaction events:

1. `PreCompact` hook captures manual (/compact) and auto compaction
2. Writes metadata to `$XDG_RUNTIME_DIR/claude-precompact-${pid}-${timestamp}.json`
3. Interceptor creates zero-duration COMPACTION spans

New span type: `openinference.span.kind: COMPACTION`

New span attributes:
- `compaction.reason` (string) - "manual" or "auto"
- `compaction.trigger` (string) - "/compact command" or "context_full"
- `compaction.messages_before` (int) - Message count before compaction

### O) Enhanced Test Coverage (Phase 3)

Expanded test harness to 10 comprehensive test suites:
- **PostToolUse** - Tool spans with exit_code, output_summary, output_lines
- **SubagentStop** - SUBAGENT_COMPLETION spans with subagent.session_id
- **Notification** - NOTIFICATION spans for permission_prompt, auth_success
- **Compaction** - COMPACTION spans for manual/auto context compaction

## Span Hierarchy (Updated)

```
Claude Code Session (CHAIN)
├── Turn #1: "User prompt..." (AGENT)
│   ├── LLM Call: claude-sonnet-4 (LLM)
│   ├── Notification: permission_prompt (NOTIFICATION)  [Phase 3]
│   ├── Permission: Write (PERMISSION)
│   ├── Tool: Write file.txt (TOOL)
│   │   └── [exit_code, output_summary]  [Phase 3]
│   ├── Tool: Task "Implement X" (TOOL)
│   ├── Subagent Complete: toolu_xxx (SUBAGENT_COMPLETION)  [Phase 3]
│   └── LLM Call: claude-sonnet-4 (LLM)
├── Compaction: auto (COMPACTION)  [Phase 3]
└── Turn #2: "Follow-up..." (AGENT)
```

## Files Changed

### Phase 1 (v3.5.0)
- `scripts/minimal-otel-interceptor.js`
- `scripts/claude-hooks/otel-session-start.sh`
- `scripts/claude-hooks/otel-session-end.sh`
- `home-modules/ai-assistants/claude-code.nix`
- `modules/services/grafana-alloy.nix`
- `scripts/test-otel-interceptor-harness.js`

### Phase 2 (v3.8.0)
- `scripts/minimal-otel-interceptor.js` - Cost metrics, error handling, permission polling
- `scripts/claude-hooks/otel-permission-request.sh` - New hook for permission tracking
- `scripts/claude-hooks/otel-stop.sh` - Turn end signaling
- `scripts/claude-hooks/otel-user-prompt-submit.sh` - Turn start signaling
- `home-modules/ai-assistants/claude-code.nix` - PermissionRequest hook registration
- `scripts/otel-ai-monitor/models.py` - cost_usd, error_count, last_error_type fields
- `scripts/otel-ai-monitor/session_tracker.py` - Parse cost and error metrics
- `scripts/test-otel-interceptor-harness.js` - 6 comprehensive test suites

### Phase 3 (v3.9.0)
- `scripts/minimal-otel-interceptor.js` - PostToolUse, SubagentStop, Notification, Compaction polling
- `scripts/claude-hooks/otel-posttool.sh` - New hook for tool execution metadata
- `scripts/claude-hooks/otel-subagent-stop.sh` - New hook for subagent completion
- `scripts/claude-hooks/otel-notification.sh` - New hook for notification events
- `scripts/claude-hooks/otel-precompact.sh` - New hook for compaction events
- `home-modules/ai-assistants/claude-code.nix` - Register PostToolUse(*), SubagentStop, Notification, PreCompact hooks
- `scripts/test-otel-interceptor-harness.js` - 10 comprehensive test suites

## Open Questions / Future Improvements

1. **True trace context exemplars on Claude Code native metrics**: requires in-process tracing context (OTel SDK)
   or emitting custom metrics from the interceptor.
2. **Profiles ↔ traces**: adopt Pyroscope eBPF profiling or NodeJS SDK, then configure Grafana "traces to profiles"
   using `service.name`, `host.name`, and time-range correlations.
3. ~~**Permission wait visibility**~~: ✅ Implemented in Phase 2
4. **Cost alerts**: Consider adding Grafana alerts for sessions exceeding cost thresholds.
5. **Error rate dashboards**: Create Grafana panels showing error rates by type over time.
