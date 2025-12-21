# Grafana Correlation: Claude Code (Traces, Metrics, Logs, Profiles)

This repo collects Claude Code telemetry via Grafana Alloy and exports to an LGTM stack (Tempo/Mimir/Loki).

## 1) The join key: `session.id`

Claude Code native OpenTelemetry telemetry uses `session.id` (UUID per conversation).

The Node interceptor (`scripts/minimal-otel-interceptor.js`) now hydrates the same UUID via a SessionStart hook, so:

- **Metrics/logs** (native Claude Code) and **traces** (interceptor) correlate by `session.id`
- You can search Tempo traces by the same UUID you see in Loki/Mimir

## 2) Tempo: find the logical trace

In Grafana → Explore → Tempo:

- Filter: `service.name = "claude-code"`
- Add: `session.id = "<uuid>"`

Expected hierarchy:

- `Claude Code Session` (root)
  - `Turn #N: ...`
    - `LLM Call: ...`
    - `Tool: ...`

Notes:

- Turn spans are created from hooks (`UserPromptSubmit` + `Stop`) when those hook events fire.
- If hooks are unavailable, the interceptor falls back to heuristic turn boundaries and uses an idle “debounce” to group multiple API calls into one logical Turn.
- Background/preflight API calls may appear with `turn.number = 0` (LLM spans parented to the session root).

Subagents:

- Parent trace includes a `Task` Tool span.
- Subagent trace’s root span includes:
  - a span **link** to the parent Task span
  - `claude.parent_session_id = "<parent uuid>"`

## 3) Metrics → Traces: exemplars via spanmetrics

Alloy config includes an `otelcol.connector.spanmetrics` pipeline which derives RED metrics from traces and (optionally) attaches exemplars.

This enables “click from a metric sample to the originating trace” in Grafana (Explore → Mimir → exemplars).

Notes:

- The connector excludes `span.name` to prevent high-cardinality series from Turn/tool naming.
- Metrics are exported to Mimir via `otelcol.exporter.prometheus`.
- `prometheus.remote_write` is configured with `send_exemplars = true` to forward trace exemplars.
- If you use tail-based sampling in the trace pipeline, exemplars can reference trace IDs that are later dropped (Grafana will show 404s for those exemplars). Align sampling policies with exemplar usage (see `https://grafana.com/docs/grafana/latest/fundamentals/exemplars/`).

## 4) Logs ↔ Traces

Claude Code exports structured events via OTLP logs (for example: `claude_code.api_request`, `claude_code.tool_result`).

Recommended workflow:

- Find a slow/failed event in Loki (filter by `session.id`)
- Jump to Tempo traces (same `session.id`) to view causality + timing across tool loops

## 5) Profiles ↔ Traces (future)

To enable “traces to profiles” in Grafana:

1. Collect continuous profiles for the `claude-code` process (Pyroscope eBPF profiler or NodeJS SDK)
2. Ensure profiles include consistent labels (at minimum `service.name=claude-code`, `host.name`)
3. Configure Grafana correlations to use span time range + `service.name`/`host.name` to fetch profiles

Grafana’s “Traces to profiles” feature uses configured span/resource tags to build profile queries, and (for span-profiles) looks for the `pyroscope.profile.id` attribute on spans (see `https://grafana.com/docs/grafana/latest/datasources/tempo/traces-in-grafana/link-trace-id/`).

## 6) eBPF tracing (Beyla) and correlation

Beyla can add low-level HTTP/gRPC traces and process-level telemetry.

If you instrument `claude-code` with Beyla, keep:

- `service.name` stable (or use an explicit mapping)
- trace context propagation in mind (Beyla won’t automatically join to logical AI spans unless trace context is propagated)

To enable correlation for outgoing Anthropic calls, the interceptor can optionally inject a W3C `traceparent` header:

- Set `OTEL_INTERCEPTOR_INJECT_TRACEPARENT=1` for `claude` (sends trace IDs to the upstream endpoint; enable only if you want this behavior).

Note: Beyla will prefer an existing `traceparent` header value if your application already sets one (see `https://grafana.com/docs/beyla/latest/configure/context-propagation/`).

## 7) Useful interceptor knobs

All are optional (defaults are chosen to be safe and low-cardinality):

- `OTEL_INTERCEPTOR_TURN_BOUNDARY_MODE` = `auto|hooks|heuristic`
- `OTEL_INTERCEPTOR_TURN_IDLE_END_MS` = debounce window for heuristic mode (default: `1500`)
- `OTEL_INTERCEPTOR_SESSION_ID_POLICY` = `buffer|eager` (default: `buffer`)
- `OTEL_INTERCEPTOR_SESSION_ID_BUFFER_MAX_MS` / `OTEL_INTERCEPTOR_SESSION_ID_BUFFER_MAX_SPANS` = safety caps for buffering
