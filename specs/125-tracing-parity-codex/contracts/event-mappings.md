# Event Mappings Contract

**Feature**: `125-tracing-parity-codex`
**Date**: 2025-12-21

This document defines the mapping between provider-specific telemetry events and the normalized event types used by otel-ai-monitor.

## Provider Detection

Detection is based on `gen_ai.system` or `service.name` span attributes:

| Attribute Value | Provider |
|-----------------|----------|
| `anthropic` | Claude Code |
| `claude-code` | Claude Code |
| `openai` | Codex CLI |
| `codex` | Codex CLI |
| `google` | Gemini CLI |
| `gemini` | Gemini CLI |

## Session ID Extraction

| Provider | Primary Attribute | Fallback Attributes |
|----------|-------------------|---------------------|
| Claude Code | `session.id` | `thread_id`, `conversation_id` |
| Codex CLI | `conversation_id` | `session.id` |
| Gemini CLI | `session.id` | `conversation.id` |

## Event Name Mapping

### Claude Code Events

| Native Event/Span | Normalized Type | Notes |
|-------------------|-----------------|-------|
| `claude_code.user_prompt` | `user.prompt` | From UserPromptSubmit hook |
| `claude_code.api_request` | `api.request` | LLM API call |
| `claude_code.api_response` | `api.response` | LLM response |
| `claude_code.tool_result` | `tool.result` | From PostToolUse hook |
| `SessionStart` span | `session.start` | Session initialization |
| `SessionEnd` span | `session.end` | Session termination |

### Codex CLI Events

| Native Event/Span | Normalized Type | Notes |
|-------------------|-----------------|-------|
| Span with `messages[-1].role=user` | `user.prompt` | User input detection |
| `codex.api_request` | `api.request` | API call to OpenAI |
| `codex.api_response` | `api.response` | API response |
| Response with `tool_calls` | `tool.call` | Tool invocation |
| First span in session | `session.start` | Implicit start |
| Process exit detection | `session.end` | Implicit end |

### Gemini CLI Events

| Native Event/Span | Normalized Type | Notes |
|-------------------|-----------------|-------|
| Span with user role message | `user.prompt` | User input detection |
| `gen_ai.client.operation` | `api.request` | API call to Google |
| Response span | `api.response` | API response |
| `gemini_cli.tool.call` | `tool.call` | Tool invocation |
| First span in session | `session.start` | Implicit start |
| Process exit detection | `session.end` | Implicit end |

## Token Attribute Mapping

| Normalized Attribute | Claude Code | Codex CLI | Gemini CLI |
|---------------------|-------------|-----------|------------|
| `input_tokens` | `gen_ai.usage.input_tokens` | `gen_ai.usage.prompt_tokens` | `gen_ai.client.token.usage` (input) |
| `output_tokens` | `gen_ai.usage.output_tokens` | `gen_ai.usage.completion_tokens` | `gen_ai.client.token.usage` (output) |
| `cache_tokens` | `gen_ai.usage.cache_read_tokens` | N/A | N/A |

## Model Name Extraction

| Provider | Attribute | Example Values |
|----------|-----------|----------------|
| Claude Code | `gen_ai.model` | `claude-opus-4-5-20251101`, `claude-sonnet-4` |
| Codex CLI | `gen_ai.request.model` | `gpt-4o`, `gpt-4o-mini` |
| Gemini CLI | `gen_ai.request.model` | `gemini-2.0-flash`, `gemini-1.5-pro` |

## Error Detection

| Provider | Error Indicator | Attributes |
|----------|-----------------|------------|
| Claude Code | `error.type` present | `error.type`, `http.status_code` |
| Codex CLI | `otel.status_code = ERROR` | `error.message`, `http.status_code` |
| Gemini CLI | `otel.status_code = ERROR` | `error.type`, `error.message` |

## Implementation

```python
# scripts/otel-ai-monitor/receiver.py

PROVIDER_DETECTION = {
    "anthropic": "claude-code",
    "claude-code": "claude-code",
    "openai": "codex",
    "codex": "codex",
    "google": "gemini",
    "gemini": "gemini",
}

SESSION_ID_ATTRIBUTES = {
    "claude-code": ["session.id", "thread_id", "conversation_id"],
    "codex": ["conversation_id", "session.id"],
    "gemini": ["session.id", "conversation.id"],
}

def detect_provider(attributes: dict) -> str:
    """Detect provider from span attributes."""
    system = attributes.get("gen_ai.system", "")
    service = attributes.get("service.name", "")

    for key, provider in PROVIDER_DETECTION.items():
        if key in system.lower() or key in service.lower():
            return provider

    return "unknown"

def extract_session_id(provider: str, attributes: dict) -> str | None:
    """Extract session ID using provider-specific attribute priority."""
    for attr in SESSION_ID_ATTRIBUTES.get(provider, []):
        if attr in attributes:
            return attributes[attr]
    return None
```
