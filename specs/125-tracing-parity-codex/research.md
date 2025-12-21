# Research: Multi-CLI Tracing Parity with OpenTelemetry

**Feature**: `125-tracing-parity-codex`
**Date**: 2025-12-21

## Research Summary

This document consolidates research findings for implementing OpenTelemetry-based tracing for Codex CLI and Gemini CLI alongside the existing Claude Code tracing infrastructure.

---

## 1. Codex CLI OpenTelemetry Support

### Decision
Use Codex CLI v0.73.0+ which includes native OpenTelemetry tracing via PR #2103 (December 2025).

### Rationale
- Native OTEL support eliminates need for interceptor/proxy approach
- Session span tracking built-in
- Events emitted: API requests, responses, user input, tool approvals, tool results
- Follows OpenTelemetry semantic conventions

### Configuration
```toml
# ~/.codex/config.toml
[otel]
environment = "production"
exporter = "otlp-http"
endpoint = "http://localhost:4318"
log_user_prompt = false  # Security: redact prompts
```

### Key Attributes Emitted
| Attribute | Description |
|-----------|-------------|
| `service.name` | "codex" |
| `conversation_id` | Session correlation ID |
| `gen_ai.system` | "openai" |
| `gen_ai.model` | Model identifier (e.g., "gpt-4o") |
| `gen_ai.usage.input_tokens` | Input token count |
| `gen_ai.usage.output_tokens` | Output token count |

### Alternatives Considered
1. **mitmproxy interception**: Rejected - adds latency, complex CA cert management
2. **Python httpx patching**: Rejected - requires maintaining custom interceptor
3. **Native OTEL (selected)**: Zero overhead, upstream-maintained

### Source
- [OpenTelemetry events PR #2103](https://github.com/openai/codex/pull/2103)
- [Codex CLI changelog v0.73.0](https://developers.openai.com/codex/changelog/)

---

## 2. Gemini CLI OpenTelemetry Support

### Decision
Use Gemini CLI with native OpenTelemetry implementation that follows GenAI semantic conventions.

### Rationale
- Full OTEL implementation from the ground up
- Follows OpenTelemetry GenAI semantic conventions
- Supports multiple export targets (local, GCP, custom)
- No vendor lock-in

### Configuration
```json
// ~/.gemini/settings.json
{
  "telemetry": {
    "enabled": true,
    "target": "local",
    "otlpEndpoint": "http://localhost:4318"
  }
}
```

### Key Metrics Emitted
| Metric | Type | Description |
|--------|------|-------------|
| `gen_ai.client.token.usage` | Histogram | Input/output tokens per operation |
| `gemini_cli.tool.call.count` | Counter | Tool invocation count |
| `gemini_cli.api.request.count` | Counter | API request count |
| `gemini_cli.token.usage` | Counter | Cumulative token usage |
| `gemini_cli.file.operation.count` | Counter | File operation count |

### Alternatives Considered
1. **mitmproxy interception**: Rejected - unnecessary given native support
2. **eBPF auto-instrumentation (Beyla)**: Rejected - less semantic richness
3. **Native OTEL (selected)**: Rich metrics, upstream-maintained

### Source
- [Gemini CLI Telemetry Docs](https://google-gemini.github.io/gemini-cli/docs/cli/telemetry.html)
- [Gemini CLI GitHub](https://github.com/google-gemini/gemini-cli)

---

## 3. Nix Flake Input Strategy

### Decision
Use flake inputs pinned to upstream repositories for both CLIs.

### Rationale
- Reproducible builds with specific commit pins
- Easy updates via `nix flake update`
- Access to latest OTEL features
- No dependency on nixpkgs packaging lag

### Implementation
```nix
# flake.nix
{
  inputs = {
    codex-cli = {
      url = "github:openai/codex";
      flake = false;
    };
    gemini-cli = {
      url = "github:google-gemini/gemini-cli";
      flake = false;
    };
  };
}
```

### Build Strategy
- Codex CLI: Rust-based, use `buildRustPackage` or `crane`
- Gemini CLI: Node.js-based, use `buildNpmPackage` or native Deno compile

### Alternatives Considered
1. **nixpkgs unstable**: Rejected - may lag upstream releases
2. **Manual installation**: Rejected - violates declarative principles
3. **Flake inputs (selected)**: Best reproducibility + freshness balance

---

## 4. OAuth Authentication

### Decision
Use personal OAuth for all CLIs, no API keys stored.

### Rationale
- Enhanced security - no long-lived credentials
- Consistent user experience across providers
- Leverages existing browser-based auth flows
- Matches Claude Code's OAuth approach

### Implementation
- Codex CLI: OpenAI OAuth via `codex auth login`
- Gemini CLI: Google OAuth via `gemini auth login`
- Token refresh handled automatically by CLIs

### Alternatives Considered
1. **API keys in env vars**: Rejected - security risk, credential management burden
2. **API keys via sops-nix**: Rejected - complexity, still requires key rotation
3. **Personal OAuth (selected)**: Simplest, most secure

---

## 5. Session ID Attribute Mapping

### Decision
Map provider-specific session ID attributes to unified `session.id` for correlation.

### Mapping Table
| Provider | Native Attribute | Mapped To |
|----------|------------------|-----------|
| Claude Code | `session.id` (from SessionStart hook) | `session.id` |
| Codex CLI | `conversation_id` | `session.id` |
| Gemini CLI | (TBD - likely `session.id` per GenAI conventions) | `session.id` |

### Implementation Location
- `scripts/otel-ai-monitor/receiver.py`: Add attribute normalization

### Rationale
- Unified session tracking in EWW widgets
- Consistent Grafana queries across providers
- Enables cost aggregation by session

---

## 6. Provider Pricing Models

### Decision
Implement provider-specific pricing tables for cost calculation.

### Pricing Tables (USD per 1M tokens)
| Provider | Model | Input | Output |
|----------|-------|-------|--------|
| Anthropic | claude-opus-4-5 | $15.00 | $75.00 |
| Anthropic | claude-sonnet-4 | $3.00 | $15.00 |
| Anthropic | claude-3-5-haiku | $0.80 | $4.00 |
| OpenAI | gpt-4o | $2.50 | $10.00 |
| OpenAI | gpt-4o-mini | $0.15 | $0.60 |
| Google | gemini-2.0-flash | $0.075 | $0.30 |
| Google | gemini-1.5-pro | $1.25 | $5.00 |

### Implementation Location
- `scripts/otel-ai-monitor/models.py`: Add `PROVIDER_PRICING` dictionary

### Update Strategy
- Pricing hardcoded initially
- Future: Consider external config file for easy updates

---

## 7. Event Name Mapping

### Decision
Map provider-specific event/span names to unified event types for session tracking.

### Event Mapping
| Event Type | Claude Code | Codex CLI | Gemini CLI |
|------------|-------------|-----------|------------|
| Session Start | `SessionStart` hook | First API call | First API call |
| User Prompt | `UserPromptSubmit` hook | `messages[-1].role=user` | `messages[-1].role=user` |
| API Request | LLM span | API span | API span |
| Tool Use | `PostToolUse` hook | `tool_calls` in response | `function_calls` in response |
| Session End | `SessionEnd` hook | Process exit | Process exit |

### Implementation Location
- `scripts/otel-ai-monitor/receiver.py`: Add event name mapping logic

---

## 8. Graceful Degradation

### Decision
Queue telemetry locally when Alloy collector is unavailable; retry on reconnection.

### Rationale
- EWW widgets must update regardless of network
- No data loss during collector outages
- Matches existing Claude Code behavior

### Implementation
- Codex/Gemini CLIs: Native OTEL retry mechanisms
- otel-ai-monitor: Already handles connection loss gracefully

---

## Resolved Technical Questions

All technical questions from the spec have been resolved:

| Question | Resolution |
|----------|------------|
| How to source CLI packages? | Flake inputs pinned to upstream repos |
| How to authenticate? | Personal OAuth (no API keys) |
| Session ID correlation? | Map `conversation_id` (Codex) to `session.id` |
| Event format parsing? | Event name mapping table in receiver.py |
| Cost calculation? | Provider-specific pricing tables |

---

## Next Steps

1. **Phase 1: Data Model** - Define Provider/Session/TelemetryEvent entities
2. **Phase 1: Contracts** - Document event name mappings and attribute schemas
3. **Phase 1: Quickstart** - Create validation guide for testing OTEL flow
