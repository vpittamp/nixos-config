# Contract: Langfuse OTEL Attribute Mapping

**Feature**: 132-langfuse-compatibility
**Date**: 2025-12-22
**Version**: 1.0.0

## Overview

This contract defines the mapping between OTEL span attributes emitted by AI CLI interceptors and the Langfuse data model. All interceptors MUST emit attributes conforming to this contract for proper Langfuse UI rendering.

---

## Attribute Namespaces

### Priority Order (Langfuse Processing)

1. `langfuse.*` - Highest priority, direct Langfuse mapping
2. `gen_ai.*` - OpenTelemetry GenAI semantic conventions
3. `openinference.*` - OpenInference/Phoenix conventions
4. Standard OTEL - Fallback (span name, status, etc.)

---

## Trace-Level Attributes

Set on the root span of each session/conversation.

| Attribute | Type | Required | Example | Maps To |
|-----------|------|----------|---------|---------|
| `langfuse.user.id` | string | No | `"vpittamp"` | trace.userId |
| `langfuse.session.id` | string | No | `"i3pm-project-123"` | trace.sessionId |
| `langfuse.trace.tags` | string (JSON) | No | `'["claude-code","nixos"]'` | trace.tags |
| `langfuse.trace.metadata` | string (JSON) | No | `'{"branch":"main"}'` | trace.metadata |
| `service.name` | string | Yes | `"claude-code"` | Inferred provider |
| `service.version` | string | No | `"1.0.0"` | trace.release |

### Example Root Span

```
span_name: "claude.conversation"
attributes:
  langfuse.user.id: "vpittamp"
  langfuse.session.id: "project-nixos-config"
  langfuse.trace.tags: '["claude-code", "feature-132"]'
  service.name: "claude-code"
  service.version: "1.0.115"
  openinference.span.kind: "CHAIN"
```

---

## Generation Observation Attributes

Set on LLM/assistant turn spans.

| Attribute | Type | Required | Example | Maps To |
|-----------|------|----------|---------|---------|
| `langfuse.observation.type` | string | Yes | `"generation"` | observation.type |
| `langfuse.observation.name` | string | No | `"claude.assistant.turn"` | observation.name |
| `gen_ai.request.model` | string | Yes | `"claude-opus-4-5-20251101"` | observation.model |
| `gen_ai.system` | string | No | `"anthropic"` | metadata.ls_provider |
| `gen_ai.prompt_json` | string (JSON) | No | `'[{"role":"user",...}]'` | observation.input |
| `gen_ai.completion_json` | string (JSON) | No | `'{"role":"assistant",...}'` | observation.output |
| `gen_ai.usage.input_tokens` | int | Yes | `1500` | usage.input_tokens |
| `gen_ai.usage.output_tokens` | int | Yes | `500` | usage.output_tokens |
| `gen_ai.usage.cost` | float | No | `0.045` | usage.total_cost |
| `langfuse.observation.usage_details` | string (JSON) | No | See below | usage (detailed) |
| `langfuse.observation.cost_details` | string (JSON) | No | `'{"total":0.045}'` | cost (detailed) |
| `openinference.span.kind` | string | No | `"LLM"` | Type inference |

### Usage Details JSON Format

```json
{
  "input_tokens": 1500,
  "output_tokens": 500,
  "total_tokens": 2000,
  "input_token_details": {
    "cache_read": 1000,
    "cache_creation": 100
  }
}
```

### Alternative Prompt/Completion Formats

If `gen_ai.prompt_json` is not set, indexed attributes are supported:

```
gen_ai.prompt.0.role: "system"
gen_ai.prompt.0.content: "You are a helpful assistant"
gen_ai.prompt.1.role: "user"
gen_ai.prompt.1.content: "Hello"
gen_ai.completion.0.role: "assistant"
gen_ai.completion.0.content: "Hi there!"
```

### Example Generation Span

```
span_name: "claude.assistant.turn"
parent_span_id: <trace_root>
attributes:
  langfuse.observation.type: "generation"
  gen_ai.request.model: "claude-opus-4-5-20251101"
  gen_ai.system: "anthropic"
  gen_ai.prompt_json: '[{"role":"user","content":"Fix the auth bug"}]'
  gen_ai.completion_json: '{"role":"assistant","content":[{"type":"text","text":"..."}]}'
  gen_ai.usage.input_tokens: 1500
  gen_ai.usage.output_tokens: 500
  gen_ai.usage.cost: 0.045
  openinference.span.kind: "LLM"
  turn.number: 1
```

---

## Tool Observation Attributes

Set on tool execution spans.

| Attribute | Type | Required | Example | Maps To |
|-----------|------|----------|---------|---------|
| `langfuse.observation.type` | string | Yes | `"tool"` | observation.type |
| `gen_ai.tool.name` | string | Yes | `"Read"` | observation.name |
| `gen_ai.tool.call.id` | string | Yes | `"toolu_abc123"` | Correlation ID |
| `langfuse.observation.input` | string (JSON) | No | `'{"input":{"file_path":"..."}}'` | observation.input |
| `langfuse.observation.output` | string (JSON) | No | `'{"content":"..."}'` | observation.output |
| `langfuse.observation.level` | string | No | `"ERROR"` | observation.level |
| `langfuse.observation.status_message` | string | No | `"File not found"` | observation.statusMessage |
| `tool.success` | bool | No | `true` | Inferred level |
| `tool.duration_ms` | int | No | `45` | metadata |
| `openinference.span.kind` | string | No | `"TOOL"` | Type inference |

### Tool Input Format

```json
{
  "input": {
    "file_path": "/home/user/project/auth.py",
    "limit": 100
  }
}
```

### Tool Output Formats

**Success:**
```json
{
  "content": "file contents...",
  "lines_read": 50
}
```

**Error:**
```json
{
  "is_error": true,
  "output": "Permission denied: /etc/shadow"
}
```

### Example Tool Span

```
span_name: "Read"
parent_span_id: <generation_span>
attributes:
  langfuse.observation.type: "tool"
  gen_ai.tool.name: "Read"
  gen_ai.tool.call.id: "toolu_01ABC123"
  langfuse.observation.input: '{"input":{"file_path":"/auth.py"}}'
  langfuse.observation.output: '{"content":"import hashlib..."}'
  tool.success: true
  tool.duration_ms: 23
  openinference.span.kind: "TOOL"
```

---

## Agent Observation Attributes

Set on subagent/Task spans.

| Attribute | Type | Required | Example | Maps To |
|-----------|------|----------|---------|---------|
| `langfuse.observation.type` | string | Yes | `"agent"` | observation.type |
| `langfuse.observation.name` | string | Yes | `"Explore"` | observation.name |
| `claude.parent_session_id` | string | No | `"parent-123"` | Cross-trace link |
| `langfuse.observation.input` | string (JSON) | No | `'{"prompt":"..."}'` | observation.input |
| `langfuse.observation.output` | string (JSON) | No | `'{"result":"..."}'` | observation.output |
| `openinference.span.kind` | string | No | `"CHAIN"` | Type inference |

### Example Agent Span

```
span_name: "Explore"
parent_span_id: <generation_span>
attributes:
  langfuse.observation.type: "agent"
  langfuse.observation.name: "Explore"
  langfuse.observation.input: '{"prompt":"Find authentication files","subagent_type":"Explore"}'
  claude.parent_session_id: "session-abc123"
  openinference.span.kind: "CHAIN"
```

---

## Provider-Specific Attributes

### Claude Code

| Attribute | Type | Description |
|-----------|------|-------------|
| `session.id` | string | Session identifier from hooks |
| `conversation.id` | string | Alternative session ID |
| `turn.number` | int | Turn sequence number |
| `turn.end_reason` | string | Why turn ended |
| `turn.tool_call_count` | int | Tools called in turn |

### Codex CLI

| Attribute | Type | Description |
|-----------|------|-------------|
| `conversation.id` | string | Codex conversation ID |
| `codex.usage.cached_token_count` | int | Cached tokens |
| `codex.usage.reasoning_token_count` | int | Reasoning tokens |
| `codex.usage.tool_token_count` | int | Tool tokens |
| `reasoning_effort` | string | low/medium/high |

### Gemini CLI

| Attribute | Type | Description |
|-----------|------|-------------|
| `gemini.session_id` | string | Gemini session |
| `gemini.visible_text` | string | Visible response text |
| `gemini.thought_text` | string | Internal reasoning |

---

## Span Hierarchy Rules

### Valid Parent-Child Relationships

```
trace_root (CHAIN)
├── generation (LLM)
│   ├── tool (TOOL)
│   ├── tool (TOOL)
│   └── agent (CHAIN)
│       ├── generation (LLM)
│       └── tool (TOOL)
└── generation (LLM)
    └── tool (TOOL)
```

### Nesting Constraints

1. `generation` spans MUST be direct children of trace root or agent
2. `tool` spans MUST be children of `generation` spans
3. `agent` spans MUST be children of `generation` spans (from Task tool)
4. `agent` spans MAY contain nested `generation` and `tool` spans

---

## Error Handling

### Setting Error Status

```
langfuse.observation.level: "ERROR"
langfuse.observation.status_message: "Descriptive error message"
```

Or infer from OTEL span status:
```
span.status.code: STATUS_CODE_ERROR
span.status.message: "Error description"
```

### Tool Error Pattern

```
tool.success: false
langfuse.observation.output: '{"is_error":true,"output":"Error message"}'
langfuse.observation.level: "ERROR"
```

---

## Backward Compatibility

### Existing Attributes (Preserved)

The following attributes from existing interceptors continue to work:

| Existing Attribute | Langfuse Mapping |
|-------------------|------------------|
| `openinference.span.kind` | Infers observation type |
| `input.value` | Falls back to observation.input |
| `output.value` | Falls back to observation.output |
| `gen_ai.request.model` | Triggers generation type |

### Migration Path

1. Existing spans without `langfuse.observation.type` are auto-classified:
   - Spans with `gen_ai.request.model` → `generation`
   - Spans with `gen_ai.tool.name` → `tool`
   - Spans with `openinference.span.kind=CHAIN` and nested structure → `agent`
   - Default → `span`

2. Explicitly setting `langfuse.*` attributes takes priority

---

## Validation Checklist

Before deployment, verify:

- [ ] All generation spans have `gen_ai.request.model`
- [ ] All tool spans have `gen_ai.tool.name` and `gen_ai.tool.call.id`
- [ ] Token counts are integers (not strings)
- [ ] JSON attributes are valid JSON strings
- [ ] Parent-child relationships follow hierarchy rules
- [ ] Session ID propagated to root span
