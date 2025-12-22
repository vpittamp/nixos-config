# Gemini CLI telemetry (notes for tracing)

Gemini CLI emits OpenTelemetry (OTLP) **log events** with high-signal `event.name` values, but its native OTLP traces are currently low-signal (generic HTTP auto-instrumentation spans like `POST`).

To mirror our Claude Code + Codex tracing model (Session → Turn → LLM/Tool), we synthesize traces from Gemini’s structured log events and export them via OTLP/HTTP.

## 0) Native Gemini telemetry config (settings, env, flags)

Per `https://gemini-cli-docs.pages.dev/telemetry` (Observability Guide + Configuration):

- Primary config file: `~/.gemini/settings.json`
  - `telemetry.enabled` (boolean)
  - `telemetry.target` (e.g. `"local"`)
  - `telemetry.otlpEndpoint` (OTLP endpoint)
  - `telemetry.logPrompts` (boolean)
- Precedence:
  - CLI flags like `--telemetry` can override settings
  - `OTEL_EXPORTER_OTLP_ENDPOINT` overrides `telemetry.otlpEndpoint`

Important for *our* setup:
- We route Gemini telemetry through a local interceptor on `http://127.0.0.1:4322` so we can synthesize coherent Session → Turn → LLM/Tool traces.
- Avoid setting `OTEL_EXPORTER_OTLP_ENDPOINT` globally to the collector (it would bypass the interceptor and you’ll lose synthesized traces).

## 1) What Gemini emits (OTEL logs / metrics / traces)

In our setup, Gemini CLI sends OTLP **JSON** payloads that our interceptor receives as “OTLP envelopes”:

- Logs payloads: `{ "resourceLogs": [...] }`
- Metrics payloads: `{ "resourceMetrics": [...] }`
- Traces payloads: `{ "resourceSpans": [...] }` (usually low-signal today)

### Common metadata (present on all log events)

- `session.id` (primary join key)
- `installation.id`
- `interactive` (bool)
- `user.email` (if available)
- `event.timestamp` (ISO string)
- `event.name` (e.g. `gemini_cli.api_response`)

### Key log events (per `https://gemini-cli-docs.pages.dev/telemetry`)

- `gemini_cli.config`
  - model + runtime config: `model`, `sandbox_enabled`, `approval_mode`, `mcp_servers`, …
- `gemini_cli.user_prompt`
  - `prompt_length`, `prompt` (if `logPrompts` enabled); we also observe `prompt_id` in practice
- `gemini_cli.api_request`
  - `model`, `request_text`; we also observe `prompt_id` in practice (may include working directory)
- `gemini_cli.api_response`
  - `duration_ms`, token counts: `input_token_count`, `output_token_count`, `cached_content_token_count`, `thoughts_token_count`, `tool_token_count`, `total_token_count`, plus `status_code`
- `gemini_cli.api_error`
  - `error`, `error_type`, `status_code`, `latency_ms`; we also observe `prompt_id` in practice
- `gemini_cli.tool_call`
  - `function_name`, `function_args`, `duration_ms`, `success` (bool), `decision` (string), `error`, `error_type`

## 2) Tracing strategy (Claude/Codex-like) for Gemini

We synthesize spans from log events:

- **Session span (CHAIN)**: created on first event for a `session.id`, ended on idle timeout.
- **Turn span (AGENT)**: start on `gemini_cli.user_prompt`, end via idle debounce (Gemini has no `notify`/hook equivalent today).
- **LLM spans (LLM/CLIENT)**: from `gemini_cli.api_response` / `gemini_cli.api_error`, enriched with `gemini_cli.api_request` where available.
- **Tool spans (TOOL)**: from `gemini_cli.tool_call`.

Join key alignment:

- Gemini already uses `session.id`; the interceptor also copies it into `conversation.id` and `gen_ai.conversation.id` on forwarded logs for parity with our Codex/Claude conventions.

## 3) Where this is implemented in this repo

- OTLP envelope forwarder + log→trace synthesis: `scripts/gemini-otel-interceptor.js`
- Gemini config + user service wiring: `home-modules/ai-assistants/gemini-cli.nix`
