# Feature Specification: Logical Multi-Span Trace Hierarchy for Claude Code

**Feature Branch**: `130-create-logical-multi`
**Created**: 2025-12-20
**Status**: Implemented ✅
**Validated**: 2025-12-20
**Input**: User description: "Revise Claude Code interceptor to correctly generate traces that fully reflect the nature of requests, work, tool calls, asynchronous processing, use of subagents, with proper parent/child/span correlation following OpenTelemetry best practices."

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Interceptor v3.4.0 | ✅ Ready | Multi-span hierarchy with Session→Turn→LLM/Tool spans |
| SessionStart hook | ✅ Verified | Creates `.claude-trace-context.json`, sets OTEL_* env vars |
| PreToolUse hook | ✅ Verified | Propagates trace context to subagents |
| SessionEnd hook | ✅ Ready | Finalizes session span on exit |
| Subagent correlation | ✅ Verified | Trace ID inherited: `b3540f524bb42d1b86bc0d8eda61ece4` test passed |
| NixOS integration | ✅ Deployed | Via `home-modules/ai-assistants/claude-code.nix` |

**Verified Trace Propagation Chain**:
```
SessionStart hook (parent)
    ├── Creates trace context file + env vars
    ├── Root trace ID: b3540f524bb42d1b86bc0d8eda61ece4
    └── PreToolUse hook (on Task tool)
        └── Subagent SessionStart hook
            ├── Inherits same trace ID ✅
            ├── Has parentSessionId reference ✅
            └── W3C traceparent format valid ✅
```

## Background

The current implementation (Feature 123) creates a two-level trace hierarchy:
- Root span "Claude Code Session" (one per process)
- Child spans "Claude API Call" (one per Anthropic API request)

This structure works but fails to capture:
1. **User turns** - logical groupings of work in response to user prompts
2. **Tool executions** - file reads, writes, bash commands as distinct operations
3. **Subagent spawns** - Task tool launching parallel Claude Code instances
4. **Async processing** - concurrent operations and their relationships
5. **Conversation flow** - the request/response/tool-use cycle that defines each turn

The goal is to implement a trace hierarchy that follows OpenTelemetry GenAI semantic conventions, enabling visualization of the complete Claude Code workflow in Grafana Tempo.

## Target Trace Hierarchy

```
Claude Code Session (root, CHAIN)
├── User Turn #1 (AGENT)
│   ├── API Request #1 (LLM) - initial user message
│   ├── Tool: Read file1.ts (TOOL)
│   ├── API Request #2 (LLM) - with tool result
│   ├── Tool: Write file2.ts (TOOL)
│   └── API Request #3 (LLM) - final response
├── User Turn #2 (AGENT)
│   ├── API Request #4 (LLM)
│   ├── Tool: Bash "npm test" (TOOL)
│   ├── Task: Subagent (AGENT) [linked via span link, separate trace]
│   │   ├── API Request (LLM)
│   │   └── Tool: Grep (TOOL)
│   └── API Request #5 (LLM) - incorporating subagent result
└── User Turn #3 (AGENT)
    └── API Request #6 (LLM) - simple Q&A
```

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete Turn Visibility (Priority: P1)

As a developer analyzing Claude Code performance, I want to see each user turn as a distinct span containing all its operations, so I can understand the cost and time for each interaction.

**Why this priority**: This is the fundamental improvement - grouping work by user turn makes traces meaningful for debugging and cost analysis.

**Independent Test**: Run Claude Code, submit a prompt that triggers multiple API calls and tool uses, then view the trace in Grafana Tempo and confirm operations are grouped under a "User Turn" parent span.

**Acceptance Scenarios**:

1. **Given** I submit a prompt to Claude Code, **When** I view the trace in Tempo, **Then** I see a "User Turn" span containing all API calls and tool executions for that prompt
2. **Given** I submit multiple prompts in one session, **When** I view the trace, **Then** each prompt creates a separate "User Turn" span under the session root
3. **Given** a turn involves multiple tool calls, **When** I view the turn span, **Then** each tool has its own child span with name, timing, and result status

---

### User Story 2 - Tool Execution Tracing (Priority: P1)

As a developer debugging slow operations, I want to see individual tool executions with their durations, so I can identify bottlenecks.

**Why this priority**: Tool calls are often the longest operations; visibility is critical for performance analysis.

**Independent Test**: Execute a bash command that takes 5+ seconds via Claude Code, confirm the trace shows a Tool span with accurate duration.

**Acceptance Scenarios**:

1. **Given** Claude Code executes a Read tool, **When** I view the trace, **Then** I see a span "Tool: Read" with file path and duration
2. **Given** Claude Code executes a Bash command, **When** I view the trace, **Then** I see a span "Tool: Bash" with command (truncated for security) and exit status
3. **Given** a tool execution fails, **When** I view the trace, **Then** the tool span shows error status with failure reason

---

### User Story 3 - Subagent Correlation (Priority: P2)

As a developer using the Task tool for parallel work, I want to see subagent traces linked to the parent, so I can understand the full work graph.

**Why this priority**: Subagents are common in complex tasks; without correlation, traces are fragmented and unusable for debugging.

**Independent Test**: Use the Task tool to spawn a subagent, confirm both traces are linked via span links in Tempo.

**Acceptance Scenarios**:

1. **Given** Claude Code spawns a subagent via Task tool, **When** I view the parent trace, **Then** I see a span link to the subagent's trace
2. **Given** a subagent completes, **When** I view both traces, **Then** they share the same conversation.id attribute for correlation
3. **Given** multiple subagents run in parallel, **When** I view the parent trace, **Then** each has a distinct linked trace

---

### User Story 4 - Token Cost Attribution (Priority: P2)

As a developer tracking AI costs, I want token usage attributed to each turn and session, so I can understand cost drivers.

**Why this priority**: Cost visibility is essential for production use and budget management.

**Independent Test**: Complete a multi-turn session, verify token counts roll up from API calls to turns to session.

**Acceptance Scenarios**:

1. **Given** an API call completes, **When** I view the LLM span, **Then** I see input_tokens, output_tokens, and cache tokens
2. **Given** a turn completes, **When** I view the turn span, **Then** I see aggregated token totals for that turn
3. **Given** a session ends, **When** I view the session span, **Then** I see total token usage across all turns

---

### Edge Cases

- What happens when Claude Code crashes mid-turn? The turn span remains open; session span end time is set to last known activity
- How are streaming responses handled? A single LLM span covers the entire streaming duration (start to final chunk)
- What happens when tool execution is cancelled? Tool span shows cancelled status with partial duration
- How are MCP (Model Context Protocol) tool calls traced? Same as built-in tools, with `tool.provider: mcp` attribute

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST create a root session span on first API call, persisting for the Claude Code process lifetime
- **FR-002**: System MUST create a "User Turn" span for each user prompt, containing all subsequent operations until the next prompt
- **FR-003**: System MUST create child LLM spans under the current turn for each Anthropic API call
- **FR-004**: System MUST create child Tool spans under the current turn for each tool execution
- **FR-005**: System MUST use span links (not parent-child) to connect subagent traces to the parent orchestrator span
- **FR-006**: System MUST propagate trace context (trace_id, parent_span_id) via W3C traceparent when spawning subagents
- **FR-007**: System MUST use OpenTelemetry GenAI semantic conventions for attribute names (gen_ai.*, llm.*)
- **FR-008**: System MUST capture token usage (input, output, cache) on each LLM span
- **FR-009**: System MUST aggregate token totals on turn and session spans upon completion
- **FR-010**: System MUST handle concurrent tool executions as sibling spans under the same turn
- **FR-011**: System MUST set span status to ERROR when API calls fail or tools return errors
- **FR-012**: System MUST include conversation.id (session identifier) on all spans for cross-trace correlation

### Key Entities

- **Session Span**: Root span (CHAIN kind) representing the Claude Code process, holds trace_id for all child spans
- **Turn Span**: Agent span (AGENT kind) representing work done for a single user prompt
- **LLM Span**: Client span (CLIENT kind) representing a single Anthropic API call with request/response
- **Tool Span**: Internal span (INTERNAL kind) representing execution of Read, Write, Bash, Grep, etc.
- **Span Link**: Association between parent trace and subagent trace for Task tool invocations

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Traces display hierarchically in Grafana Tempo with session → turns → operations structure
- **SC-002**: All LLM spans include model, token counts, and latency attributes visible in trace details
- **SC-003**: Tool spans appear within 100ms of tool start/end in the parent turn
- **SC-004**: Subagent traces are discoverable via span links from the parent Task tool span
- **SC-005**: Token totals on session span match sum of all child LLM spans
- **SC-006**: 95% of traces maintain complete parent-child chain (no orphaned spans)
- **SC-007**: Trace data size increases by less than 2KB per tool call compared to current implementation

## Assumptions

1. Claude Code 2.x+ uses Node.js fetch for Anthropic API calls (interceptable)
2. Tool executions occur synchronously within the Node.js event loop (observable via timing)
3. Subagents (Task tool) spawn new Claude Code processes with fresh interceptors
4. Session boundaries align with Claude Code process lifetime
5. Turn boundaries can be inferred from user message patterns in API requests
6. Grafana Tempo supports span links for visualization

## Out of Scope

- Custom MCP server tracing (MCP servers handle their own telemetry)
- Historical trace storage/querying beyond Tempo defaults
- Real-time streaming trace updates (traces export on completion)
- IDE extension telemetry integration
- Cost calculation or alerting (downstream analytics responsibility)

## Technical Approach

### Interceptor Architecture

The solution replaces `minimal-otel-interceptor.js` with a more sophisticated state machine:

1. **Session State**: Tracks session_id, trace_id, root_span_id, cumulative metrics
2. **Turn State**: Tracks current turn's span_id, start time, tool count
3. **Tool State**: Stack of active tool spans for nested tool calls

### Turn Boundary Detection

Turns are detected by analyzing the message array in Anthropic API requests:
- A new turn starts when the last message is from `role: user`
- Subsequent API calls (with assistant messages) remain in the same turn
- This handles multi-step tool use within a single user prompt

### Subagent Tracing

When Claude Code spawns a subagent via Task tool:
1. Parent creates a Tool span for the Task invocation
2. Parent sets `OTEL_TRACE_PARENT` environment variable with current trace context
3. Subagent's interceptor reads trace context and creates a span link
4. Both traces share `conversation.id` for correlation

### Span Attribute Conventions

Following OpenTelemetry GenAI semantic conventions:

| Attribute | Span Type | Example |
|-----------|-----------|---------|
| gen_ai.system | All | "anthropic" |
| gen_ai.request.model | LLM | "claude-sonnet-4-20250514" |
| gen_ai.usage.input_tokens | LLM | 1500 |
| gen_ai.usage.output_tokens | LLM | 500 |
| gen_ai.conversation.id | All | "claude-123-456789" |
| gen_ai.operation.name | Turn | "chat" |
| gen_ai.tool.name | Tool | "Read" |
| gen_ai.tool.call.id | Tool | "toolu_01XYZ" |
| openinference.span.kind | All | "CHAIN", "AGENT", "LLM", "TOOL" |

## Migration Path

This is a complete replacement of `scripts/minimal-otel-interceptor.js`:

1. Backup existing interceptor (for rollback)
2. Deploy new interceptor
3. Verify traces appear correctly in Tempo
4. Remove backup after 1 week of stable operation

No backward compatibility needed - the new implementation produces strictly better traces that are compatible with all downstream consumers (otel-ai-monitor, Alloy, Tempo).
