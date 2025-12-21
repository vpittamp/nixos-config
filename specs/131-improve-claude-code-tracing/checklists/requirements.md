# Verification Checklist (v131)

## Phase 1: Core Tracing

### Local correctness (no real Anthropic calls)

- Run `node scripts/test-otel-interceptor-harness.js`
  - Expect: **PASS** (6/6 tests)
  - Ensures: Turn boundaries, session.id hydration, LLM↔Tool causal links

### On-host integration (after nixos/home-manager rebuild)

- Run `claude --version`
  - Expect stderr includes `[OTEL-Interceptor v3.8.0] Active`
- Start a real Claude Code session and capture the UUID `session.id` from OTLP metrics/logs.
- In Grafana Tempo, search traces with `service.name="claude-code"` and `session.id="<uuid>"`
  - Expect: `Claude Code Session` → `Turn #N` → `LLM Call ...` + `Tool: ...`

### Metrics ↔ traces (exemplars)

- In Grafana Mimir Explore, query spanmetrics-derived series (for example: request duration histogram)
- Confirm exemplars appear and link to Tempo traces

---

## Phase 2: Enhanced Observability

### Cost Metrics

- Run `node scripts/test-otel-interceptor-harness.js --test=cost`
  - Expect: **PASS**
  - Validates: `gen_ai.usage.cost_usd` calculation and aggregation

- In Grafana Tempo, inspect LLM spans:
  - Expect: `gen_ai.usage.cost_usd` attribute with calculated USD value
  - Expect: Turn spans have aggregated cost
  - Expect: Session spans have total cost

### Error Handling

- Run `node scripts/test-otel-interceptor-harness.js --test=error`
  - Expect: **PASS**
  - Validates: `error.type` classification, `turn.error_count`

- In Grafana Tempo, inspect error LLM spans:
  - Expect: `error.type` attribute (rate_limit, auth, server, etc.)
  - Expect: Turn spans have `turn.error_count`

### Permission Visibility

- Run `node scripts/test-otel-interceptor-harness.js --test=permission`
  - Expect: **PASS**
  - Validates: PERMISSION spans with correct attributes

- During real Claude Code session requiring permission:
  - Trigger a Write or Bash command that requires approval
  - Approve or deny the permission
  - In Grafana Tempo, search for `openinference.span.kind="PERMISSION"`
  - Expect: PERMISSION span with:
    - `permission.tool` (e.g., "Write")
    - `permission.result` ("approved" or "denied")
    - `permission.wait_ms` (user wait time in milliseconds)

### Streaming Response

- Run `node scripts/test-otel-interceptor-harness.js --test=streaming`
  - Expect: **PASS**
  - Validates: SSE event stream parsing, token extraction

### Concurrent Tasks

- Run `node scripts/test-otel-interceptor-harness.js --test=concurrent`
  - Expect: **PASS**
  - Validates: Multiple Task context files, proper subagent linking

---

## Optional: Advanced Features

### Beyla correlation for HTTP spans

- Enable `OTEL_INTERCEPTOR_INJECT_TRACEPARENT=1` for `claude` runs
  - This sends W3C `traceparent` on outgoing Anthropic calls (enable only when desired).
- Confirm Beyla spans share trace IDs with logical traces (Tempo trace view should show both).

### Profiles ↔ traces (design)

- Prefer a dedicated privileged profiler (eBPF) separate from the unprivileged `grafana-alloy` service.
- Use `process.pid`, `service.name`, `host.name`, and span time range to configure "Traces to profiles" in Grafana.

---

## Quick Test Commands

```bash
# Run all tests
node scripts/test-otel-interceptor-harness.js

# Run specific test
node scripts/test-otel-interceptor-harness.js --test=basic
node scripts/test-otel-interceptor-harness.js --test=streaming
node scripts/test-otel-interceptor-harness.js --test=concurrent
node scripts/test-otel-interceptor-harness.js --test=error
node scripts/test-otel-interceptor-harness.js --test=permission
node scripts/test-otel-interceptor-harness.js --test=cost

# Debug mode
OTEL_INTERCEPTOR_DEBUG=1 claude "test prompt" 2>&1 | grep OTEL
```
