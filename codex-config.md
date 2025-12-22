# Codex CLI config + telemetry (notes for tracing)

Codex CLI currently emits **OpenTelemetry log events** (OTLP Logs) but **does not emit rich OTLP traces** comparable to Claude Code’s native traces + our Node payload interceptor.

This document captures the Codex-side signals we can use to synthesize traces and mirror our Claude Code tracing strategy.

## 1) What Codex emits (OTEL logs)

Codex exports OTEL **log records** (not spans) when `[otel]` is enabled in `~/.codex/config.toml`.

### Native knobs (Codex-side)

- `~/.codex/config.toml` (TOML)
  - `[otel]` enables log export and controls exporter options
  - `notify = ["node", "/path/to/notify.js"]` enables turn-end notifications
- Batch log export timing (env vars read by the Rust OTEL SDK):
  - `OTEL_BLRP_SCHEDULE_DELAY` (ms)
  - `OTEL_BLRP_MAX_EXPORT_BATCH_SIZE`
  - `OTEL_BLRP_MAX_QUEUE_SIZE`
  - We set aggressive defaults in our `codex` wrapper so logs arrive near-real-time.

### Common metadata (present on all events)

- `conversation.id` (session identifier)
- `event.timestamp` (ISO string)
- `event.name` (e.g. `codex.api_request`)
- `service.name` (resource attribute; e.g. `codex_cli_rs`, `codex_tui`, `codex_exec`)
- `service.version` / `app.version`
- `terminal.type`, `model`, `slug`
- Identity fields (when available): `auth_mode`, `user.account_id`, `user.email`

### Event catalog

- `codex.conversation_starts`
  - `provider_name`, `reasoning_effort` (optional), `approval_policy`, `sandbox_policy`, `mcp_servers`, …
- `codex.user_prompt`
  - `prompt_length`, `prompt` (only if `otel.log_user_prompt = true`)
- `codex.api_request`
  - `attempt`, `duration_ms`, `http.response.status_code` (optional), `error.message` (failures)
- `codex.sse_event`
  - `event.kind` (notably `response.completed`)
  - Token counts on `response.completed`: `input_token_count`, `output_token_count`, `cached_token_count` (optional), `reasoning_token_count` (optional), `tool_token_count`
- `codex.tool_decision`
  - `tool_name`, `call_id`, `decision`, `source`
- `codex.tool_result`
  - `tool_name`, `call_id` (optional), `arguments` (optional), `duration_ms`, `success`, `output`

## 2) Hooks we can use (Codex `notify`)

Codex supports a top-level `notify` hook:

```toml
notify = ["node", "/absolute/path/to/notify.js"]
```

Codex invokes this external program with **one JSON argument** per supported notification event.

Currently:
- `notify` emits **only** `agent-turn-complete` (turn boundary signal).

The JSON payload includes:
- `type` = `agent-turn-complete`
- `thread-id` (Codex session id; correlates with `conversation.id`)
- `cwd` (absolute project dir)
- `last-assistant-message` (optional)
- `input-messages` (optional)

## 3) Tracing strategy (Claude-like) for Codex

To mirror our Claude Code trace hierarchy:

- **Session span (CHAIN)**: created from `codex.conversation_starts`, ended on idle timeout.
- **Turn span (AGENT)**: start on `codex.user_prompt`, end on `notify` (`agent-turn-complete`), fallback to idle timeout.
- **LLM spans (LLM/CLIENT)**: start/end derived from `codex.api_request.duration_ms`, token counts attached from `codex.sse_event` `response.completed`.
- **Tool spans (TOOL)**: created from `codex.tool_result.duration_ms`, enriched with `codex.tool_decision` by `call_id` when available.
  - We also parse `arguments` (when present) to generate semantic tool span names and attach `tool.args_preview`.
  - We emit span links:
    - Tool span `produced_by_llm` → the most recent LLM span in the Turn
    - Next LLM span `consumes_tool_result` → prior tool span(s)

To keep the same join key as Claude traces, we treat:
- `session.id = conversation.id` (and inject this into forwarded Codex logs).

## 4) Where this is implemented in this repo

- OTEL log → trace synthesis: `scripts/codex-otel-interceptor.js`
- Codex notify hook handler: `scripts/codex-hooks/notify.js`
- Codex config + user service wiring: `home-modules/ai-assistants/codex.nix`
