# Verification Checklist (v131)

## Local correctness (no real Anthropic calls)

- Run `node scripts/test-otel-interceptor-harness.js`
  - Expect: **PASS**
  - Ensures: 1 Turn span across tool loop, `session.id` hydration, LLM↔Tool causal links

## On-host integration (after nixos/home-manager rebuild)

- Run `claude --version`
  - Expect stderr includes `[OTEL-Interceptor v3.5.0] Active`
- Start a real Claude Code session and capture the UUID `session.id` from OTLP metrics/logs.
- In Grafana Tempo, search traces with `service.name="claude-code"` and `session.id="<uuid>"`
  - Expect: `Claude Code Session` → `Turn #N` → `LLM Call ...` + `Tool: ...`

## Metrics ↔ traces (exemplars)

- In Grafana Mimir Explore, query spanmetrics-derived series (for example: request duration histogram)
- Confirm exemplars appear and link to Tempo traces

## Optional: Beyla correlation for HTTP spans

- Enable `OTEL_INTERCEPTOR_INJECT_TRACEPARENT=1` for `claude` runs
  - This sends W3C `traceparent` on outgoing Anthropic calls (enable only when desired).
- Confirm Beyla spans share trace IDs with logical traces (Tempo trace view should show both).

## Optional: Profiles ↔ traces (design)

- Prefer a dedicated privileged profiler (eBPF) separate from the unprivileged `grafana-alloy` service.
- Use `process.pid`, `service.name`, `host.name`, and span time range to configure “Traces to profiles” in Grafana.

