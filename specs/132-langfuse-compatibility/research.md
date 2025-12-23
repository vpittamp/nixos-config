# Research: Langfuse-Compatible AI CLI Tracing

**Feature**: 132-langfuse-compatibility
**Date**: 2025-12-22
**Status**: Complete

## Executive Summary

This research consolidates findings from Langfuse documentation, LangSmith SDK patterns, and the existing tracing implementation to define the optimal integration approach.

---

## 1. Langfuse OTEL Integration

### Decision: Use Langfuse's OTEL HTTP Endpoint

**Rationale**: Langfuse provides a native OTEL endpoint that accepts OTLP HTTP/protobuf traces, allowing reuse of the existing Grafana Alloy pipeline with an additional export destination.

**Alternatives Considered**:
- **Langfuse Python SDK**: Rejected - would require rewriting interceptors; OTEL approach allows unified pipeline
- **LangSmith-style direct API**: Rejected - Langfuse's OTEL endpoint is the recommended integration path

### Endpoint Details

| Environment | Endpoint URL |
|-------------|--------------|
| EU Cloud | `https://cloud.langfuse.com/api/public/otel` |
| US Cloud | `https://us.cloud.langfuse.com/api/public/otel` |
| Self-hosted | `http://localhost:3000/api/public/otel` |

**Authentication**: HTTP Basic Auth with base64-encoded `LANGFUSE_PUBLIC_KEY:LANGFUSE_SECRET_KEY`

```
Authorization: Basic <base64(pk-lf-xxx:sk-lf-xxx)>
```

**Protocol**: HTTP/protobuf only (gRPC not supported)

---

## 2. Observation Types Mapping

### Decision: Map to Langfuse's Extended Observation Types

Langfuse supports 10 observation types. Our AI CLI traces should map as follows:

| Our Span Type | Langfuse Observation Type | Rationale |
|---------------|---------------------------|-----------|
| Session root | `span` (implicit trace) | Top-level container |
| Assistant turn | `generation` | LLM call with token usage |
| Tool execution | `tool` | Direct mapping |
| Subagent (Task) | `agent` | Agent deciding flow |
| MCP tool call | `tool` | External tool invocation |

**Setting Observation Type via OTEL**:
```python
span.set_attribute("langfuse.observation.type", "generation")  # or "tool", "agent", "span"
```

**Automatic Detection**: Any span with `gen_ai.request.model` attribute is automatically classified as `generation`.

---

## 3. Attribute Mapping Strategy

### Decision: Dual-Namespace Approach

Use both GenAI semantic conventions (`gen_ai.*`) and Langfuse-specific attributes (`langfuse.*`) for maximum compatibility.

### Priority Order (Langfuse Processing)

1. **langfuse.\*** attributes (highest priority)
2. **gen_ai.\*** semantic conventions
3. **openinference.\*** attributes (OpenLLMetry)
4. **mlflow.\*** attributes

### Core Attribute Mapping

| Langfuse Field | Primary Attribute | Fallback Attributes |
|----------------|-------------------|---------------------|
| name | `langfuse.observation.name` | span name |
| model | `langfuse.observation.model` | `gen_ai.request.model`, `gen_ai.response.model` |
| input | `langfuse.observation.input` | `gen_ai.prompt_json`, `input.value` |
| output | `langfuse.observation.output` | `gen_ai.completion_json`, `output.value` |
| level | `langfuse.observation.level` | inferred from span status |
| statusMessage | `langfuse.observation.status_message` | span status message |

### Session/User Mapping

| Langfuse Field | Attribute |
|----------------|-----------|
| userId | `langfuse.user.id` |
| sessionId | `langfuse.session.id` |
| tags | `langfuse.trace.tags` (JSON array string) |
| metadata | `langfuse.trace.metadata` (JSON object string) |

---

## 4. Token Usage & Cost Tracking

### Decision: Follow LangSmith Usage Extraction Pattern

The LangSmith SDK's `extract_usage_metadata` and `sum_anthropic_tokens` patterns provide the correct format.

### Usage Metadata Structure

```json
{
  "input_tokens": 150,
  "output_tokens": 50,
  "total_tokens": 200,
  "input_token_details": {
    "cache_read": 100,
    "cache_creation": 25
  },
  "total_cost": 0.0025
}
```

### OTEL Attributes for Usage

| Langfuse Field | OTEL Attribute |
|----------------|----------------|
| input_tokens | `gen_ai.usage.input_tokens` or `gen_ai.usage.prompt_tokens` |
| output_tokens | `gen_ai.usage.output_tokens` or `gen_ai.usage.completion_tokens` |
| total_cost | `gen_ai.usage.cost` |
| usage_details (JSON) | `langfuse.observation.usage_details` |
| cost_details (JSON) | `langfuse.observation.cost_details` |

### Anthropic Cache Token Handling

Per LangSmith `sum_anthropic_tokens` pattern:
```python
total_input = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
total_tokens = total_input + output_tokens
```

---

## 5. Content Serialization

### Decision: Use LangSmith Content Block Patterns

Adopt the `flatten_content_blocks` pattern from LangSmith SDK for consistent serialization.

### Block Type Mappings

| SDK Block Type | Serialized Format |
|----------------|-------------------|
| TextBlock | `{"type": "text", "text": "..."}` |
| ThinkingBlock | `{"type": "thinking", "thinking": "...", "signature": "..."}` |
| ToolUseBlock | `{"type": "tool_use", "id": "...", "name": "...", "input": {...}}` |
| ToolResultBlock | `{"type": "tool_result", "tool_use_id": "...", "content": "...", "is_error": bool}` |

### Message Format for LLM Inputs

```json
[
  {"role": "user", "content": "prompt text"},
  {"role": "assistant", "content": [{"type": "text", "text": "..."}]},
  {"role": "user", "content": [{"type": "tool_result", ...}]}
]
```

Set via: `gen_ai.prompt_json` (JSON string) or indexed attributes:
```
gen_ai.prompt.0.role = "user"
gen_ai.prompt.0.content = "..."
```

---

## 6. Tool Call Correlation

### Decision: Use tool_use_id for Parent-Child Linking

The LangSmith hook pattern solves async context propagation issues by using explicit `tool_use_id` correlation.

### Implementation Pattern

```python
# PreToolUse hook
_active_tool_runs[tool_use_id] = (tool_run, start_time)

# PostToolUse hook
tool_run, start_time = _active_tool_runs.pop(tool_use_id)
tool_run.end(outputs=tool_response)
```

### OTEL Attributes for Tool Calls

| Field | Attribute |
|-------|-----------|
| tool name | `gen_ai.tool.name` |
| tool input | `input.value` or `langfuse.observation.input` |
| tool output | `output.value` or `langfuse.observation.output` |
| tool_use_id | `gen_ai.tool.call.id` |
| is_error | `langfuse.observation.level = "ERROR"` |

---

## 7. Subagent/Task Tracing

### Decision: Nested Chain Pattern for Subagents

When Task tool spawns a subagent, create a nested `agent` observation containing its own generations and tools.

### Trace Hierarchy

```
claude.conversation (trace root)
├── claude.assistant.turn (generation)
│   └── Task (agent)
│       ├── subagent.turn (generation)
│       └── Read (tool)
└── claude.assistant.turn (generation)
```

### OTEL Span Links

For subagent correlation across process boundaries, use span links:
```python
span.add_link(subagent_trace_context)
span.set_attribute("claude.parent_session_id", parent_session_id)
```

---

## 8. Alloy Configuration

### Decision: Add Parallel Langfuse Exporter

Extend existing Alloy pipeline with additional OTLP HTTP exporter for Langfuse.

### Configuration Pattern

```alloy
otelcol.exporter.otlphttp "langfuse" {
  client {
    endpoint = env("LANGFUSE_OTEL_ENDPOINT")
    headers = {
      "Authorization" = env("LANGFUSE_AUTH_HEADER"),
    }
  }
}

otelcol.processor.batch "langfuse" {
  output {
    traces = [otelcol.exporter.otlphttp.langfuse.input]
  }
}
```

### Environment Variables

| Variable | Value |
|----------|-------|
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-...` |
| `LANGFUSE_SECRET_KEY` | `sk-lf-...` |
| `LANGFUSE_OTEL_ENDPOINT` | `https://cloud.langfuse.com/api/public/otel` |
| `LANGFUSE_AUTH_HEADER` | `Basic <base64(pk:sk)>` |

---

## 9. Graceful Degradation

### Decision: Local-First with Async Export

Maintain existing local monitoring (EWW) as primary, with Langfuse export as secondary destination.

### Architecture

```
AI CLIs → Alloy :4318
         ├─ otel-ai-monitor :4320 (local, sync)
         └─ Langfuse (remote, async batch)
```

### Failure Handling

- Langfuse unavailable: Traces queued in Alloy's 100MB memory buffer
- Automatic retry with exponential backoff
- Local EWW monitoring unaffected

---

## 10. Provider-Specific Patterns

### Claude Code

- Session ID: From hooks or `session.id` attribute
- Turn boundaries: UserPromptSubmit + Stop hooks
- Model: `gen_ai.request.model` from API response

### Codex CLI

- Session ID: `conversation.id` → normalize to `session.id`
- Turn boundaries: `codex.user_prompt` + notify hook
- Token types: Include `reasoning_token_count`, `tool_token_count`

### Gemini CLI

- Session ID: From config or inferred
- Turn boundaries: `gemini_cli.user_prompt` + idle timeout
- Special handling: Visible text vs thought blocks

---

## References

- [Langfuse OpenTelemetry Integration](https://langfuse.com/integrations/native/opentelemetry)
- [Langfuse Tracing Data Model](https://langfuse.com/docs/observability/data-model)
- [Langfuse Observation Types](https://langfuse.com/docs/observability/features/observation-types)
- [Langfuse OTEL Python SDK Guide](https://langfuse.com/guides/cookbook/otel_integration_python_sdk)
- [OpenTelemetry GenAI Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
- LangSmith SDK integration code (`langsmith.integrations.claude_agent_sdk`)
