# Research: Logical Multi-Span Trace Hierarchy

**Feature**: 130-create-logical-multi
**Date**: 2025-12-20
**Status**: Complete

## Research Topics

### 1. OpenTelemetry GenAI Semantic Conventions

**Decision**: Follow the official OpenTelemetry GenAI semantic conventions (2025 edition) for span naming and attribute conventions.

**Rationale**:
- OpenTelemetry has official semantic conventions for GenAI systems that define standard attribute names
- Following conventions enables interoperability with observability tools (Grafana, Honeycomb, Datadog)
- The 2025 conventions add agent and tool span types specifically for AI assistant workflows

**Alternatives Considered**:
- OpenInference (Arize): Similar but less widely adopted, we already use some OpenInference attributes
- Custom conventions: Would require documentation and reduce interoperability
- LangChain conventions: Too specific to LangChain framework

**Key Attributes** (from GenAI semantic conventions):
```
# All spans
gen_ai.system = "anthropic"
gen_ai.conversation.id = "claude-{pid}-{timestamp}"

# LLM spans (API calls)
gen_ai.request.model = "claude-sonnet-4-20250514"
gen_ai.usage.input_tokens = 1500
gen_ai.usage.output_tokens = 500
gen_ai.response.finish_reasons = ["end_turn"]

# Agent spans (turns)
gen_ai.operation.name = "chat"

# Tool spans
gen_ai.tool.name = "Read"
gen_ai.tool.call.id = "toolu_01XYZ"
```

### 2. Turn Boundary Detection in Claude Code

**Decision**: Detect turn boundaries by analyzing the `messages` array in Anthropic API requests - a new turn starts when the last message has `role: user`.

**Rationale**:
- Claude Code sends the full conversation history in each API request
- The last message's role indicates whether this is a new user turn or a continuation
- This approach requires no external state and works within the fetch interceptor

**Detection Logic**:
```javascript
function isNewTurn(requestBody) {
  const messages = requestBody.messages || [];
  if (messages.length === 0) return true;

  const lastMessage = messages[messages.length - 1];
  return lastMessage.role === 'user';
}
```

**Alternatives Considered**:
- Hook into Claude Code's prompt submission: Requires modifying Claude Code source or using hooks
- Time-based detection: Unreliable, can't distinguish thinking time from user waiting
- Count-based: Doesn't capture the semantic meaning of "turn"

### 3. Tool Execution Tracing Strategy

**Decision**: Infer tool executions from Claude's response content_blocks, not from intercepting actual tool calls.

**Rationale**:
- The Anthropic API response contains `content` array with `type: tool_use` blocks
- Each tool_use block has `name`, `id`, and `input` - all we need for Tool spans
- The subsequent request contains `tool_result` blocks with execution results
- This approach works entirely within the fetch interceptor

**Tool Flow**:
```
Request 1: user message
Response 1: assistant message with tool_use blocks
  → Create Tool spans (start time = response received)

Request 2: includes tool_result blocks
  → Update Tool spans with results (end time, status)

Response 2: assistant continuation or final response
```

**Alternatives Considered**:
- PostToolUse hook: Only fires after tools complete, no timing for start
- Instrument Node.js child_process: Too invasive, breaks with Claude Code updates
- Parse stderr output: Unreliable, Claude Code doesn't log tool execution

### 4. Subagent (Task Tool) Correlation

**Decision**: Use span links to correlate parent and subagent traces, propagate trace context via environment variable.

**Rationale**:
- OpenTelemetry recommends span links for causal relationships across trace boundaries
- Subagents run as separate Claude Code processes with fresh interceptors
- Sharing trace_id would make subagent spans children (wrong semantically)
- Environment variables are the only reliable way to pass context to child processes

**Implementation**:
```javascript
// Parent: When detecting Task tool use
const traceparent = `00-${traceId}-${currentSpanId}-01`;
process.env.OTEL_TRACE_PARENT = traceparent;

// Child (subagent): On startup
const parentContext = process.env.OTEL_TRACE_PARENT;
if (parentContext) {
  sessionSpan.addLink({
    context: { traceId: parentTraceId, spanId: parentSpanId },
    attributes: { 'link.type': 'parent_task' }
  });
}
```

**Alternatives Considered**:
- Shared trace_id: Makes subagent spans children, but they're independent traces
- File-based context: More complex, requires cleanup
- Named pipe/socket: Too complex for simple context propagation

### 5. Token Aggregation Strategy

**Decision**: Aggregate tokens at span end time - turn spans sum their LLM children, session span sums all turns.

**Rationale**:
- Token counts are only available after API response
- Aggregation at end time allows accurate totals
- JavaScript's event loop ensures child spans complete before parent

**Implementation Approach**:
```javascript
// On LLM span completion
currentTurn.tokens.input += llmSpan.inputTokens;
currentTurn.tokens.output += llmSpan.outputTokens;

// On Turn span completion
session.tokens.input += turn.tokens.input;
session.tokens.output += turn.tokens.output;

// Final session span attributes include totals
```

**Alternatives Considered**:
- Real-time aggregation: More complex, requires careful state management
- Separate metrics: Loses correlation with trace spans
- Post-export aggregation: Requires backend processing

### 6. Span Lifecycle and State Machine

**Decision**: Implement a state machine to track active spans and their relationships.

**State Structure**:
```javascript
const state = {
  session: {
    spanId: string,
    traceId: string,
    startTime: number,
    tokens: { input: 0, output: 0, cache: 0 }
  },
  currentTurn: {
    spanId: string | null,
    startTime: number | null,
    turnNumber: number,
    tokens: { input: 0, output: 0 },
    activeTools: Map<toolCallId, ToolSpan>
  },
  pendingToolResults: Map<toolCallId, { startTime, name, input }>
};
```

**State Transitions**:
1. **Session Start**: First API call → create session span
2. **Turn Start**: API request with user message → create turn span
3. **LLM Call**: API request → create LLM span (child of current turn)
4. **Tool Use**: Response contains tool_use → create pending tool span
5. **Tool Result**: Request contains tool_result → complete tool span
6. **Turn End**: Response without tool_use → complete turn span
7. **Session End**: Process exit → complete session span

**Rationale**:
- State machine provides clear transitions and invariants
- Active tools map handles concurrent tool executions
- Pending tool results bridge request/response pairs

## Summary of Decisions

| Topic | Decision | Key Insight |
|-------|----------|-------------|
| Semantic conventions | OpenTelemetry GenAI | Industry standard, tool interoperability |
| Turn detection | Last message role | Works within fetch interceptor, no external state |
| Tool tracing | Parse response content | tool_use blocks contain all needed info |
| Subagent correlation | Span links + env var | OpenTelemetry recommended pattern |
| Token aggregation | End-time rollup | Simple, accurate, correlation preserved |
| State management | State machine | Clear transitions, handles concurrent tools |

## Open Questions Resolved

All research questions have been resolved. No blocking unknowns remain.
