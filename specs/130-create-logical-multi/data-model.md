# Data Model: Logical Multi-Span Trace Hierarchy

**Feature**: 130-create-logical-multi
**Date**: 2025-12-20

## Overview

This document defines the data structures for the multi-span trace hierarchy. All structures are JavaScript objects that get serialized to OTLP JSON for export.

## Core Entities

### 1. InterceptorState

The main state object maintained throughout the Claude Code session.

```typescript
interface InterceptorState {
  // Session-level state (stable for entire process)
  session: SessionState;

  // Current turn state (changes with each user prompt)
  currentTurn: TurnState | null;

  // Pending tool executions awaiting results
  pendingTools: Map<string, PendingToolSpan>;
}
```

### 2. SessionState

Represents the root span for the entire Claude Code session.

```typescript
interface SessionState {
  // Span identification
  traceId: string;         // 32 hex chars, shared by all spans in session
  spanId: string;          // 16 hex chars, unique to session span
  sessionId: string;       // Format: "claude-{pid}-{timestamp}"

  // Timing
  startTime: number;       // Unix timestamp in milliseconds

  // Aggregated metrics
  tokens: TokenCounts;
  turnCount: number;
  apiCallCount: number;

  // Export state
  exported: boolean;       // Whether initial span was exported
}
```

### 3. TurnState

Represents an agent span for a single user turn (prompt → response cycle).

```typescript
interface TurnState {
  // Span identification
  spanId: string;          // 16 hex chars
  turnNumber: number;      // Sequential turn number (1, 2, 3...)

  // Timing
  startTime: number;       // When user prompt was detected
  endTime: number | null;  // When final response received

  // Aggregated metrics
  tokens: TokenCounts;
  llmCallCount: number;
  toolCallCount: number;

  // Active tools in this turn
  activeTools: Set<string>;  // Tool call IDs currently executing
}
```

### 4. PendingToolSpan

Represents a tool execution that has started but not completed.

```typescript
interface PendingToolSpan {
  // Tool identification
  toolCallId: string;      // Anthropic tool_use id (e.g., "toolu_01XYZ")
  toolName: string;        // Tool name (e.g., "Read", "Bash")

  // Span identification
  spanId: string;          // 16 hex chars

  // Timing
  startTime: number;       // When tool_use was detected in response

  // Tool input (for attributes)
  input: object;           // Tool input parameters (truncated for security)
}
```

### 5. TokenCounts

Aggregated token usage.

```typescript
interface TokenCounts {
  input: number;           // Input tokens (prompt)
  output: number;          // Output tokens (completion)
  cacheRead: number;       // Cache read tokens
  cacheWrite: number;      // Cache creation tokens
}
```

## OTLP Span Structures

### 6. OTLPSpan

The JSON structure for a single OTLP span (following OTLP JSON format).

```typescript
interface OTLPSpan {
  traceId: string;              // 32 hex chars
  spanId: string;               // 16 hex chars
  parentSpanId?: string;        // 16 hex chars, omit for root span
  name: string;                 // Span name (e.g., "Claude Code Session")
  kind: SpanKind;               // OTLP span kind string
  startTimeUnixNano: string;    // Nanoseconds since epoch as string
  endTimeUnixNano: string;      // Nanoseconds since epoch as string
  attributes: OTLPAttribute[];  // Key-value attributes
  status: OTLPStatus;           // Span status
  links?: OTLPLink[];           // Optional span links (for subagents)
}

type SpanKind =
  | 'SPAN_KIND_INTERNAL'   // Session, Turn, Tool spans
  | 'SPAN_KIND_CLIENT';    // LLM spans (API calls)

interface OTLPStatus {
  code: 'STATUS_CODE_UNSET' | 'STATUS_CODE_OK' | 'STATUS_CODE_ERROR';
  message?: string;
}

interface OTLPLink {
  traceId: string;
  spanId: string;
  attributes?: OTLPAttribute[];
}
```

### 7. OTLPAttribute

Key-value attribute in OTLP JSON format.

```typescript
interface OTLPAttribute {
  key: string;
  value: OTLPAttributeValue;
}

interface OTLPAttributeValue {
  stringValue?: string;
  intValue?: string;        // Integer as string per OTLP JSON spec
  doubleValue?: number;
  boolValue?: boolean;
}
```

## Span Hierarchy

```
Session Span (INTERNAL, CHAIN)
├── traceId: shared by all spans
├── spanId: session root
├── parentSpanId: (none - root)
├── name: "Claude Code Session"
│
├── Turn Span #1 (INTERNAL, AGENT)
│   ├── traceId: same as session
│   ├── spanId: turn-1
│   ├── parentSpanId: session
│   ├── name: "User Turn #1"
│   │
│   ├── LLM Span (CLIENT)
│   │   ├── parentSpanId: turn-1
│   │   └── name: "Claude API Call"
│   │
│   ├── Tool Span (INTERNAL)
│   │   ├── parentSpanId: turn-1
│   │   └── name: "Tool: Read"
│   │
│   └── LLM Span (CLIENT)
│       ├── parentSpanId: turn-1
│       └── name: "Claude API Call"
│
└── Turn Span #2 (INTERNAL, AGENT)
    ├── parentSpanId: session
    └── name: "User Turn #2"
```

## Attribute Conventions

### Session Span Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `openinference.span.kind` | string | "CHAIN" |
| `gen_ai.system` | string | "anthropic" |
| `gen_ai.conversation.id` | string | Session ID |
| `session.turn_count` | int | Total turns in session |
| `session.api_call_count` | int | Total API calls |
| `gen_ai.usage.input_tokens` | int | Total input tokens |
| `gen_ai.usage.output_tokens` | int | Total output tokens |

### Turn Span Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `openinference.span.kind` | string | "AGENT" |
| `gen_ai.operation.name` | string | "chat" |
| `gen_ai.conversation.id` | string | Session ID |
| `turn.number` | int | Turn sequence number |
| `turn.llm_call_count` | int | API calls in this turn |
| `turn.tool_call_count` | int | Tools used in this turn |
| `gen_ai.usage.input_tokens` | int | Turn input tokens |
| `gen_ai.usage.output_tokens` | int | Turn output tokens |

### LLM Span Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `openinference.span.kind` | string | "LLM" |
| `gen_ai.system` | string | "anthropic" |
| `gen_ai.request.model` | string | Model name |
| `gen_ai.usage.input_tokens` | int | Request input tokens |
| `gen_ai.usage.output_tokens` | int | Request output tokens |
| `gen_ai.response.finish_reasons` | string | Stop reason |
| `llm.latency.total_ms` | int | Request duration in ms |
| `llm.request.sequence` | int | API call sequence number |

### Tool Span Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `openinference.span.kind` | string | "TOOL" |
| `gen_ai.tool.name` | string | Tool name (Read, Bash, etc.) |
| `gen_ai.tool.call.id` | string | Anthropic tool call ID |
| `tool.status` | string | "success" or "error" |
| `tool.error_message` | string | Error message if failed |

## State Transitions

### Session Lifecycle

```
[START] → FirstAPICall → SessionCreated → (turns...) → ProcessExit → SessionEnded
```

### Turn Lifecycle

```
[IDLE] → UserMessage → TurnStarted → (llm/tool calls...) → FinalResponse → TurnEnded → [IDLE]
```

### Tool Lifecycle

```
[NONE] → ToolUseInResponse → PendingTool → ToolResultInRequest → ToolCompleted
```

## Validation Rules

1. **Session Invariants**:
   - `traceId` is immutable after session start
   - `turnCount` increments monotonically
   - Token counts are non-negative and monotonically increasing

2. **Turn Invariants**:
   - Only one turn active at a time
   - Turn must have at least one LLM call
   - Turn ends when response has no tool_use blocks

3. **Tool Invariants**:
   - Tool start (from response) always precedes tool result (from request)
   - Tool call IDs are unique within a session
   - Orphaned tools (no result) are completed on turn end with error status
