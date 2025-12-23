# Data Model: Langfuse-Compatible AI CLI Tracing

**Feature**: 132-langfuse-compatibility
**Date**: 2025-12-22
**Derived From**: [spec.md](./spec.md), [research.md](./research.md)

## Entity Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Trace                                │
│  (Langfuse trace = root span representing full session)     │
├─────────────────────────────────────────────────────────────┤
│  ├── Generation (assistant turn with LLM call)              │
│  │   ├── Tool (file read, edit, bash)                       │
│  │   ├── Tool (another tool call)                           │
│  │   └── Agent (subagent from Task tool)                    │
│  │       ├── Generation (subagent turn)                     │
│  │       └── Tool (subagent tool)                           │
│  ├── Generation (next assistant turn)                       │
│  │   └── Tool (tool call)                                   │
│  └── ...                                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Entities

### 1. Trace (Session Root)

Represents a complete AI CLI conversation/session.

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| id | string | OTEL trace_id | W3C trace context format |
| name | string | `langfuse.observation.name` | e.g., "claude.conversation" |
| userId | string | `langfuse.user.id` | Optional user identifier |
| sessionId | string | `langfuse.session.id` | Groups related traces |
| tags | string[] | `langfuse.trace.tags` | JSON array, e.g., ["claude-code", "project:nixos"] |
| metadata | object | `langfuse.trace.metadata` | JSON object with custom data |
| input | any | First generation's input | Conversation prompt |
| output | any | Last generation's output | Final response |
| startTime | datetime | Span start_time | Trace begin |
| endTime | datetime | Span end_time | Trace complete |

**OTEL Span Attributes**:
```
langfuse.user.id = "vpittamp"
langfuse.session.id = "i3pm-project-123"
langfuse.trace.tags = '["claude-code", "nixos-config"]'
langfuse.trace.metadata = '{"git_branch": "132-langfuse-compatibility"}'
openinference.span.kind = "CHAIN"
service.name = "claude-code"
```

---

### 2. Generation (LLM Observation)

Represents a single assistant turn with LLM API call.

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| id | string | OTEL span_id | Unique observation ID |
| traceId | string | OTEL trace_id | Parent trace |
| parentObservationId | string | OTEL parent_span_id | Parent observation |
| name | string | span name | e.g., "claude.assistant.turn" |
| type | "generation" | `langfuse.observation.type` | Fixed value |
| model | string | `gen_ai.request.model` | e.g., "claude-opus-4-5-20251101" |
| input | object | `langfuse.observation.input` | Message history (see below) |
| output | object | `langfuse.observation.output` | Assistant response content |
| usage | UsageMetadata | See usage section | Token counts |
| metadata | object | `langfuse.observation.metadata` | ls_model_name, ls_provider, etc. |
| level | string | Inferred from status | DEFAULT, DEBUG, WARNING, ERROR |
| startTime | datetime | Span start_time | |
| endTime | datetime | Span end_time | |

**Input Format (Message History)**:
```json
[
  {"role": "user", "content": "Fix the bug in auth.py"},
  {"role": "assistant", "content": [{"type": "text", "text": "I'll analyze..."}]},
  {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "abc", "content": "file contents"}]}
]
```

**Output Format (Flattened Content Blocks)**:
```json
{
  "role": "assistant",
  "content": [
    {"type": "thinking", "thinking": "Let me analyze...", "signature": "abc123"},
    {"type": "text", "text": "I found the issue..."},
    {"type": "tool_use", "id": "xyz", "name": "Edit", "input": {"file_path": "/auth.py"}}
  ]
}
```

**OTEL Span Attributes**:
```
langfuse.observation.type = "generation"
langfuse.observation.name = "claude.assistant.turn"
gen_ai.request.model = "claude-opus-4-5-20251101"
gen_ai.system = "anthropic"
gen_ai.prompt_json = '[{"role":"user","content":"..."}]'
gen_ai.completion_json = '{"role":"assistant","content":[...]}'
gen_ai.usage.input_tokens = 1500
gen_ai.usage.output_tokens = 500
gen_ai.usage.cost = 0.045
langfuse.observation.metadata = '{"ls_provider":"anthropic","ls_model_name":"claude-opus-4-5"}'
openinference.span.kind = "LLM"
```

---

### 3. Tool Observation

Represents a tool execution (Read, Edit, Bash, etc.).

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| id | string | OTEL span_id | Unique observation ID |
| traceId | string | OTEL trace_id | Parent trace |
| parentObservationId | string | OTEL parent_span_id | Parent generation |
| name | string | `gen_ai.tool.name` | Tool name, e.g., "Read", "Edit" |
| type | "tool" | `langfuse.observation.type` | Fixed value |
| input | object | `langfuse.observation.input` | Tool parameters |
| output | any | `langfuse.observation.output` | Tool response |
| level | string | Inferred | ERROR if tool failed |
| statusMessage | string | Error message | If tool failed |
| metadata | object | Tool-specific | duration_ms, exit_code, etc. |
| startTime | datetime | Span start_time | |
| endTime | datetime | Span end_time | |

**Input Format**:
```json
{
  "input": {
    "file_path": "/home/user/project/src/auth.py",
    "limit": 100
  }
}
```

**Output Format** (varies by tool):
```json
{
  "content": "file contents here...",
  "lines_read": 100
}
```
or for errors:
```json
{
  "is_error": true,
  "output": "File not found: /auth.py"
}
```

**OTEL Span Attributes**:
```
langfuse.observation.type = "tool"
gen_ai.tool.name = "Read"
gen_ai.tool.call.id = "toolu_abc123"
langfuse.observation.input = '{"input":{"file_path":"/auth.py"}}'
langfuse.observation.output = '{"content":"..."}'
tool.success = true
tool.duration_ms = 45
openinference.span.kind = "TOOL"
```

---

### 4. Agent Observation (Subagent)

Represents a Task tool spawning a subagent.

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| id | string | OTEL span_id | Unique observation ID |
| traceId | string | OTEL trace_id | Parent trace |
| parentObservationId | string | OTEL parent_span_id | Parent generation |
| name | string | Subagent type | e.g., "Explore", "Plan", "code-reviewer" |
| type | "agent" | `langfuse.observation.type` | Fixed value |
| input | object | Task prompt | Subagent task description |
| output | object | Subagent result | Final subagent output |
| metadata | object | Subagent config | model, subagent_type, etc. |
| startTime | datetime | Span start_time | |
| endTime | datetime | Span end_time | |

**Contains Nested Observations**:
- Generation observations for subagent LLM turns
- Tool observations for subagent tool calls

**OTEL Span Attributes**:
```
langfuse.observation.type = "agent"
langfuse.observation.name = "Explore"
claude.parent_session_id = "parent-session-123"
langfuse.observation.input = '{"prompt":"Find auth files","subagent_type":"Explore"}'
openinference.span.kind = "CHAIN"
```

---

### 5. UsageMetadata

Token usage and cost tracking structure.

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| input_tokens | int | `gen_ai.usage.input_tokens` | Total input tokens (including cache) |
| output_tokens | int | `gen_ai.usage.output_tokens` | Output tokens |
| total_tokens | int | Calculated | input + output |
| input_token_details | object | Nested | Cache token breakdown |
| input_token_details.cache_read | int | API response | Cached tokens read |
| input_token_details.cache_creation | int | API response | Tokens used for cache creation |
| total_cost | float | `gen_ai.usage.cost` | USD cost |

**OTEL Attributes**:
```
gen_ai.usage.input_tokens = 1500
gen_ai.usage.output_tokens = 500
gen_ai.usage.cost = 0.045
langfuse.observation.usage_details = '{"input_tokens":1500,"output_tokens":500,"total_tokens":2000}'
langfuse.observation.cost_details = '{"total":0.045}'
```

**Token Aggregation (per LangSmith pattern)**:
```python
# Claude cache tokens are ADDED to input_tokens for total
total_input = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
total_tokens = total_input + output_tokens
```

---

### 6. ContentBlock Types

Serialized content block formats for input/output.

| Block Type | Serialized Format |
|------------|-------------------|
| TextBlock | `{"type": "text", "text": "content"}` |
| ThinkingBlock | `{"type": "thinking", "thinking": "reasoning", "signature": "abc"}` |
| ToolUseBlock | `{"type": "tool_use", "id": "xyz", "name": "Read", "input": {...}}` |
| ToolResultBlock | `{"type": "tool_result", "tool_use_id": "xyz", "content": "...", "is_error": false}` |

---

## State Transitions

### Trace Lifecycle

```
CREATED → ACTIVE → COMPLETED
           ↓
        ERRORED
```

### Generation Lifecycle

```
STARTED (on AssistantMessage)
    ↓
COLLECTING (accumulating content blocks)
    ↓
ENDED (on next UserMessage or ResultMessage)
    ↓
PATCHED (sent to Langfuse)
```

### Tool Lifecycle

```
PRE_TOOL_USE (tool_use_id captured)
    ↓
EXECUTING (async tool execution)
    ↓
POST_TOOL_USE (result captured)
    ↓
PATCHED (sent to Langfuse)
```

---

## Validation Rules

### Required Fields per Observation Type

| Observation Type | Required Fields |
|------------------|-----------------|
| Trace | id, name, startTime |
| Generation | id, traceId, name, type, model, startTime |
| Tool | id, traceId, parentObservationId, name, type, startTime |
| Agent | id, traceId, parentObservationId, name, type, startTime |

### Attribute Constraints

| Attribute | Constraint |
|-----------|------------|
| `langfuse.observation.type` | One of: "span", "generation", "tool", "agent" |
| `langfuse.observation.level` | One of: "DEFAULT", "DEBUG", "WARNING", "ERROR" |
| `gen_ai.request.model` | Required for `generation` type |
| `gen_ai.tool.name` | Required for `tool` type |
| JSON string attributes | Must be valid JSON |

---

## Provider-Specific Mappings

### Claude Code

| Field | Attribute Source |
|-------|------------------|
| session_id | `session.id` from hooks |
| model | `gen_ai.request.model` from API response |
| turn_number | `turn.number` span attribute |
| is_error | `is_error` from ResultMessage |

### Codex CLI

| Field | Attribute Source |
|-------|------------------|
| session_id | `conversation.id` (normalized) |
| model | From `codex.sse_event` response.completed |
| reasoning_tokens | `codex.usage.reasoning_token_count` |
| tool_tokens | `codex.usage.tool_token_count` |

### Gemini CLI

| Field | Attribute Source |
|-------|------------------|
| session_id | From config or generated |
| model | `gemini_cli.api_request` attributes |
| visible_text | Extracted from response |

---

## Relationships

```
Trace (1) ─────── (N) Generation
  │                    │
  │                    └──── (N) Tool
  │                    │
  │                    └──── (N) Agent ─── (N) Generation
  │                                            │
  │                                            └── (N) Tool
  │
  └─ sessionId ─────── (N) Trace (same session)
```

**Cardinality**:
- One trace has many generations (multi-turn conversation)
- One generation has many tool calls (parallel or sequential)
- One generation may spawn one agent (Task tool)
- One agent has its own generations and tools (nested)
- Many traces share one sessionId (session grouping)
