# Grafana Correlation: Claude Code (Traces, Metrics, Logs, Profiles)

This repo collects Claude Code telemetry via Grafana Alloy and exports to an LGTM stack (Tempo/Mimir/Loki).

## Codex CLI note (traces are synthesized)

Codex CLI currently emits **OTEL log events** (not spans) via `[otel]` in `~/.codex/config.toml`.

To get Claude-like traces (Session → Turn → LLM/Tool), we:
- Route Codex OTLP logs through `scripts/codex-otel-interceptor.js` (it forwards logs to Alloy and **synthesizes OTLP traces**).
- Use Codex’s `notify` hook to post `agent-turn-complete` to the interceptor for accurate turn end boundaries.
- Normalize the join key by copying `conversation.id` → `session.id` in forwarded Codex logs, and using the same `session.id` on synthesized spans.

## Gemini CLI note (traces are synthesized)

Gemini CLI exports OpenTelemetry telemetry configured via `~/.gemini/settings.json` (`telemetry.*`). We route its telemetry through a local interceptor to synthesize coherent Session → Turn → LLM/Tool traces.

To get Claude-like traces (Session → Turn → LLM/Tool), we:
- Route Gemini OTLP envelopes through `scripts/gemini-otel-interceptor.js` (it forwards logs/metrics to the collector and **synthesizes OTLP traces**).
- Use log events (`gemini_cli.user_prompt`, `gemini_cli.api_*`, `gemini_cli.tool_call`) for span boundaries (Gemini currently has no notify hook like Codex).
  - Note: `OTEL_EXPORTER_OTLP_ENDPOINT` overrides `telemetry.otlpEndpoint`; if set, it can bypass the interceptor and you’ll lose synthesized traces.

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

## 8) Langfuse Integration (Feature 132)

In addition to Grafana LGTM, traces can be exported to [Langfuse](https://langfuse.com) for specialized LLM observability.

### What Langfuse provides

- **LLM-specific trace views**: Hierarchical display of Session → Turn → LLM/Tool with generation-focused UI
- **Token and cost analytics**: Aggregated usage metrics with cost breakdown by model
- **Session grouping**: Related traces grouped by session ID in the Sessions tab
- **Prompt/response visibility**: Full input/output content for debugging and analysis

### Enabling Langfuse export

In your NixOS configuration (`configurations/hetzner.nix` or equivalent):

```nix
services.grafana-alloy = {
  enable = true;
  # ... other settings ...

  langfuse = {
    enable = true;
    endpoint = "https://cloud.langfuse.com/api/public/otel";
    # Option 1: Key files (recommended for production)
    # publicKeyFile = config.sops.secrets.langfuse-public-key.path;
    # secretKeyFile = config.sops.secrets.langfuse-secret-key.path;
    # Option 2: Environment variables (for development)
    # Set LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY in systemd service
    batchTimeout = "10s";
    batchSize = 100;
  };
};
```

Set `LANGFUSE_ENABLED=1` in your shell or Claude Code environment to activate Langfuse attribute enrichment.

### Environment variables

| Variable | Description |
|----------|-------------|
| `LANGFUSE_ENABLED` | Set to `1` to enable Langfuse-specific attributes |
| `LANGFUSE_USER_ID` | Optional user ID for trace attribution |
| `LANGFUSE_TAGS` | JSON array or comma-separated list of tags (e.g., `["production","team-a"]`) |
| `LANGFUSE_PUBLIC_KEY` | Langfuse public key (if not using key files) |
| `LANGFUSE_SECRET_KEY` | Langfuse secret key (if not using key files) |

### Trace hierarchy mapping

Traces use [OpenInference semantic conventions](https://github.com/Arize-ai/openinference) for Langfuse compatibility:

| Span Type | OpenInference Kind | Langfuse Observation |
|-----------|-------------------|---------------------|
| Session | `CHAIN` | Trace root |
| Turn | `AGENT` | Nested span |
| LLM Call | `LLM` | Generation |
| Tool Call | `TOOL` | Span |
| Subagent (Task) | `AGENT` | Nested agent span |

### Key attributes

Langfuse-specific attributes added to spans:

| Attribute | Description |
|-----------|-------------|
| `openinference.span.kind` | Span type (CHAIN, LLM, TOOL, AGENT) |
| `langfuse.session.id` | Session ID for trace grouping |
| `langfuse.user.id` | User ID for attribution |
| `langfuse.observation.name` | Human-readable observation name |
| `langfuse.observation.type` | Observation type (generation, span) |
| `langfuse.observation.usage_details` | JSON with token breakdown |
| `langfuse.observation.cost_details` | JSON with cost breakdown |
| `langfuse.observation.level` | Error level for failed operations |
| `langfuse.trace.tags` | JSON array of trace tags |

### Using Langfuse UI

1. **Traces view**: Filter by `gen_ai.system` (anthropic, openai, google) or `gen_ai.request.model`
2. **Sessions view**: Group related traces by `langfuse.session.id`
3. **Generations**: View LLM calls with input/output content and token usage
4. **Analytics**: Aggregate cost and usage metrics across sessions

### Graceful degradation

When Langfuse is unavailable:
- Alloy buffers traces locally (100MB default)
- Traces are retried with exponential backoff
- Local EWW monitoring continues to work via otel-ai-monitor

### Multi-provider support

All three AI CLIs (Claude Code, Codex, Gemini) export Langfuse-compatible traces:

| CLI | Provider | Model Examples |
|-----|----------|---------------|
| Claude Code | anthropic | claude-sonnet-4-20250514, claude-opus-4-5-20251101 |
| Codex CLI | openai | gpt-4o, o3-mini |
| Gemini CLI | google | gemini-2.5-pro, gemini-2.5-flash |

Filter in Langfuse by `gen_ai.system` to view traces from specific providers.
