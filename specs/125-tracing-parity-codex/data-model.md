# Data Model: Multi-CLI Tracing Parity

**Feature**: `125-tracing-parity-codex`
**Date**: 2025-12-21

## Entities

### Provider

Represents an AI service provider with associated configuration for telemetry processing.

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | string | Provider identifier | Yes |
| `name` | string | Display name | Yes |
| `system` | string | OpenTelemetry `gen_ai.system` value | Yes |
| `session_id_attribute` | string | Attribute name for session correlation | Yes |
| `pricing` | PricingTable | Model pricing configuration | Yes |
| `event_mappings` | EventMappings | Event name to type mappings | Yes |

**Instances**:
- `anthropic`: Claude Code (system: "anthropic", session_id: "session.id")
- `openai`: Codex CLI (system: "openai", session_id: "conversation_id")
- `google`: Gemini CLI (system: "google", session_id: "session.id")

---

### PricingTable

Provider-specific pricing for cost calculation.

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `models` | dict[str, ModelPricing] | Model name to pricing mapping | Yes |

### ModelPricing

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `input_price` | float | USD per 1M input tokens | Yes |
| `output_price` | float | USD per 1M output tokens | Yes |

---

### Session

A continuous interaction period with an AI CLI.

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `session_id` | string | Unique session identifier (UUID) | Yes |
| `provider` | Provider | Associated provider | Yes |
| `tool` | string | CLI tool name ("claude-code", "codex", "gemini") | Yes |
| `state` | SessionState | Current state | Yes |
| `project` | string | Associated project name (if detected) | No |
| `window_id` | string | Terminal window ID for UI correlation | No |
| `created_at` | datetime | Session start time | Yes |
| `last_event_at` | datetime | Most recent telemetry event | Yes |
| `state_changed_at` | datetime | Last state transition | Yes |
| `metrics` | SessionMetrics | Aggregated session metrics | Yes |

### SessionState

Enum: `IDLE` | `WORKING` | `COMPLETED` | `EXPIRED`

### SessionMetrics

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `input_tokens` | int | Total input tokens consumed | Yes |
| `output_tokens` | int | Total output tokens generated | Yes |
| `cache_tokens` | int | Cache read tokens (if applicable) | No |
| `cost_usd` | float | Calculated cost in USD | Yes |
| `error_count` | int | Number of errors in session | Yes |
| `api_request_count` | int | Total API requests | Yes |
| `tool_call_count` | int | Total tool invocations | Yes |

---

### TelemetryEvent

A discrete observation from an AI CLI.

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `event_name` | string | Normalized event type | Yes |
| `timestamp` | datetime | Event occurrence time | Yes |
| `session_id` | string | Associated session | Yes |
| `provider` | Provider | Source provider | Yes |
| `trace_id` | string | W3C trace ID | No |
| `span_id` | string | W3C span ID | No |
| `attributes` | dict | Event-specific attributes | Yes |

### EventType (Normalized)

| Type | Description | Triggers Session State |
|------|-------------|------------------------|
| `session.start` | Session initialization | → WORKING |
| `user.prompt` | User input submission | → WORKING |
| `api.request` | LLM API call | Extends WORKING |
| `api.response` | LLM API response | Extends WORKING |
| `tool.call` | Tool invocation | Extends WORKING |
| `tool.result` | Tool completion | Extends WORKING |
| `session.end` | Session termination | → COMPLETED |
| `error` | Error occurrence | Increments error_count |

---

## State Transitions

```
                ┌──────────────────────────────────────┐
                │                                      │
                ▼                                      │
            ┌──────┐    user.prompt    ┌─────────┐    │
    init    │ IDLE │ ───────────────▶ │ WORKING │ ───┘
    ───────▶│      │                  │         │ (any activity resets quiet timer)
            └──────┘                  └────┬────┘
                ▲                          │
                │                          │ quiet period (15s)
                │    completed timeout     ▼
                │    (30s)            ┌───────────┐
                └──────────────────── │ COMPLETED │
                                      └─────┬─────┘
                                            │
                                            │ session timeout (300s)
                                            ▼
                                      ┌─────────┐
                                      │ EXPIRED │ (removed from tracking)
                                      └─────────┘
```

---

## Validation Rules

### Session
- `session_id` must be a valid UUID
- `provider.id` must be one of: "anthropic", "openai", "google"
- `tool` must be one of: "claude-code", "codex", "gemini"
- `created_at` must be ≤ `last_event_at`
- `metrics.cost_usd` must be ≥ 0

### TelemetryEvent
- `event_name` must be a valid EventType
- `timestamp` must be a valid ISO 8601 datetime
- `session_id` must reference an existing or new session

### Provider Pricing
- All prices must be ≥ 0
- At least one model must be defined per provider

---

## Relationships

```
┌──────────┐     1:N     ┌─────────────────┐
│ Provider │─────────────│ TelemetryEvent  │
└──────────┘             └─────────────────┘
     │                           │
     │ 1:N                       │ N:1
     ▼                           ▼
┌──────────┐     1:N     ┌─────────────────┐
│ Session  │─────────────│ TelemetryEvent  │
└──────────┘             └─────────────────┘
```

---

## Implementation Notes

### Existing Code Locations
- Session model: `scripts/otel-ai-monitor/models.py`
- Session tracker: `scripts/otel-ai-monitor/session_tracker.py`
- Event receiver: `scripts/otel-ai-monitor/receiver.py`

### Changes Required
1. Add `Provider` entity with pricing and event mappings
2. Extend `Session` to include `provider` field
3. Add session ID attribute normalization in receiver
4. Add provider-specific cost calculation logic
