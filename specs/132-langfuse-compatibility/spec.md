# Feature Specification: Langfuse-Compatible AI CLI Tracing

**Feature Branch**: `132-langfuse-compatibility`
**Created**: 2025-12-22
**Status**: Draft
**Input**: User description: "Enhance tracing system for Claude Code CLI, Gemini CLI, and Codex CLI to be optimized for Langfuse functionality. Review Langfuse documentation for best practices representing trace data using semantic conventions that match Langfuse expectations to maximize user experience in Langfuse UI. Review tool calling, MCP, and ensure tracing methodology follows Langfuse and OpenTelemetry best practices."

## Clarifications

### Session 2025-12-22

- Q: Should privacy mode support content redaction? → A: No redaction - full and complete data capture required.
- Q: Maximum tool calls per trace before chunking? → A: No limit - rely on Langfuse/Alloy to reject oversized payloads.

## Prior Art: LangSmith SDK Integration Patterns

This specification adapts proven patterns from the LangSmith SDK integration (`langsmith.integrations`):

1. **Trace Hierarchy**: `chain` (conversation) → `llm` (assistant turn) → `tool` (tool calls)
2. **Hook-Based Tool Tracing**: PreToolUse/PostToolUse hooks with `tool_use_id` correlation for reliable tool call tracking across async boundaries
3. **Content Block Serialization**: Converting SDK-specific content blocks (TextBlock, ThinkingBlock, ToolUseBlock, ToolResultBlock) into serializable message formats
4. **Usage Metadata Extraction**: Structured extraction of `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, and `total_cost`
5. **OTEL Span Processor**: Configurable exporter with endpoint, API key, and project parameters for any OTLP-compatible backend

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View AI Sessions as Langfuse Traces (Priority: P1)

As a developer using AI CLIs (Claude Code, Codex, Gemini), I want my AI interactions to appear as properly structured traces in Langfuse so I can analyze conversation flows, debug issues, and understand model behavior using Langfuse's native UI features.

**Why this priority**: This is the core value proposition - without proper trace structure, the Langfuse UI cannot display meaningful insights. Every other feature depends on traces being correctly formatted.

**Independent Test**: Can be fully tested by running a Claude Code session, then viewing the resulting trace in Langfuse UI with correctly nested generations, tool calls, and token metrics displayed.

**Acceptance Scenarios**:

1. **Given** a user starts a Claude Code session and submits a prompt, **When** the session completes, **Then** a single Langfuse trace appears as a "chain" type with nested "llm" observations for each assistant turn and "tool" observations for each tool execution.

2. **Given** a user runs multiple AI CLI sessions across Claude Code, Codex, and Gemini, **When** viewing Langfuse dashboard, **Then** all sessions appear as separate traces with correct provider attribution and the Langfuse filters (by model, by user, by session) work correctly.

3. **Given** a user has an ongoing multi-turn conversation, **When** each turn completes, **Then** Langfuse shows the trace updating in near-real-time with each generation and tool call appearing as nested observations following the chain → llm → tool hierarchy.

---

### User Story 2 - Analyze Token Usage and Costs in Langfuse (Priority: P1)

As a developer, I want accurate token counts and cost metrics to appear in Langfuse so I can track AI spending, compare model efficiency, and analyze usage patterns using Langfuse's built-in analytics.

**Why this priority**: Cost visibility is critical for production AI applications. Without accurate token/cost data, users cannot effectively manage AI budgets or optimize prompts for efficiency.

**Independent Test**: Can be fully tested by running an AI CLI command with known token counts, then verifying Langfuse displays matching input/output/cache token counts and calculated costs.

**Acceptance Scenarios**:

1. **Given** a Claude Code API request completes with token usage data, **When** viewing the generation observation in Langfuse, **Then** the observation shows usage_metadata containing: `input_tokens` (including cache tokens summed per LangSmith pattern), `output_tokens`, `total_tokens`, `input_token_details.cache_read`, `input_token_details.cache_creation`, and `total_cost`.

2. **Given** multiple LLM calls occur within a single trace, **When** viewing the trace summary in Langfuse, **Then** aggregate token counts and total cost are correctly summed across all generation observations.

3. **Given** a model is used that isn't in the pricing table, **When** viewing in Langfuse, **Then** an estimated cost is shown with appropriate metadata indicating the estimate.

---

### User Story 3 - Trace Tool Calls and MCP Operations (Priority: P2)

As a developer using AI agents with tools and MCP servers, I want tool invocations to appear as distinct observations in Langfuse so I can debug tool execution, analyze tool usage patterns, and understand agent decision-making.

**Why this priority**: Tool calling is central to agentic AI workflows. Proper tool tracing enables debugging of agent behavior, identifying failed tool calls, and optimizing tool usage.

**Independent Test**: Can be fully tested by running a Claude Code session that uses file operations (Read, Write, Bash), then verifying each tool call appears as a "tool" type observation in Langfuse with input parameters and results.

**Acceptance Scenarios**:

1. **Given** Claude Code executes a Read tool to examine a file, **When** viewing in Langfuse, **Then** a "tool" type observation appears as a child of the requesting LLM turn, with inputs containing `{"input": {"file_path": "..."}}` and outputs containing the file content.

2. **Given** an AI CLI makes multiple tool calls in sequence (Read → Edit → Bash), **When** viewing the trace, **Then** each tool appears as a correctly ordered child observation under the parent "llm" observation that requested it, correlated via `tool_use_id`.

3. **Given** a tool call fails with an error, **When** viewing in Langfuse, **Then** the tool observation shows error status with `is_error: true` and the error message in outputs, matching the LangSmith hook pattern.

4. **Given** an MCP server is invoked from Claude Code, **When** viewing in Langfuse, **Then** the MCP tool call is visible as a tool observation with the MCP server name prefixed to the tool name.

5. **Given** a Task tool spawns a subagent, **When** viewing in Langfuse, **Then** the subagent appears as a nested "chain" under the parent trace, with its own LLM and tool observations properly nested within.

---

### User Story 4 - Group Related Traces by Session (Priority: P2)

As a developer working on a project over multiple interactions, I want related AI sessions to be grouped in Langfuse so I can analyze conversation continuity, track project-level usage, and understand multi-session workflows.

**Why this priority**: Real-world AI usage spans multiple sessions. Session grouping enables project-level analytics and helps users understand long-running AI-assisted development workflows.

**Independent Test**: Can be fully tested by running multiple Claude Code sessions within the same project context, then verifying Langfuse shows them grouped under the same session ID with proper chronological ordering.

**Acceptance Scenarios**:

1. **Given** a user runs three Claude Code sessions within the same i3pm project, **When** filtering by session in Langfuse, **Then** all three traces appear grouped together with the project name visible in metadata.

2. **Given** a user switches between projects, **When** viewing Langfuse sessions, **Then** traces from different projects appear in separate sessions with distinct identifiers.

---

### User Story 5 - View Prompt and Response Content (Priority: P2)

As a developer debugging AI behavior, I want to see the actual prompts sent to models and responses received in Langfuse so I can analyze prompt effectiveness, debug unexpected outputs, and iterate on prompt design.

**Why this priority**: Full prompt/response visibility is essential for prompt engineering and debugging. This enables users to understand exactly what the model saw and produced.

**Independent Test**: Can be fully tested by submitting a specific prompt to Claude Code, then viewing the generation observation in Langfuse and confirming the input messages and output content are correctly displayed.

**Acceptance Scenarios**:

1. **Given** a user submits a prompt to Claude Code, **When** viewing the generation in Langfuse, **Then** the inputs show the conversation history as serialized message dicts with `role` and `content` keys, and outputs show the assistant's response with flattened content blocks.

2. **Given** a multi-turn conversation with tool calls, **When** viewing the generation's input in Langfuse, **Then** the message history is displayed in order with appropriate role labels (user, assistant) and tool results included, following the `build_llm_input` pattern.

3. **Given** Claude returns thinking blocks, **When** viewing in Langfuse, **Then** the output includes serialized thinking blocks with `type: "thinking"`, `thinking`, and `signature` fields.

---

### User Story 6 - Filter and Search Traces Effectively (Priority: P3)

As a developer with many AI sessions, I want traces to have rich, queryable metadata so I can efficiently find specific interactions using Langfuse's filtering and search capabilities.

**Why this priority**: As usage scales, finding specific traces becomes challenging. Proper tagging and metadata enable efficient retrieval and analysis of historical sessions.

**Independent Test**: Can be fully tested by running sessions with different models/projects, then using Langfuse filters (by model, by tag, by user, by metadata) to find specific traces.

**Acceptance Scenarios**:

1. **Given** traces from multiple AI providers (Anthropic, OpenAI, Google), **When** filtering by provider in Langfuse, **Then** traces are correctly categorized and filterable via `ls_provider` metadata.

2. **Given** traces with different model versions (claude-opus-4-5, gpt-4o, gemini-2.0-flash), **When** filtering by model in Langfuse, **Then** each model's traces appear correctly via `ls_model_name` metadata.

3. **Given** traces tagged with project names and environments, **When** searching by tag in Langfuse, **Then** matching traces are returned accurately.

---

### Edge Cases

- What happens when the Langfuse endpoint is unreachable? Traces should be queued locally (via existing Alloy buffering) and delivered when connectivity resumes.
- How does the system handle very long traces with hundreds of tool calls? No artificial limits are imposed; traces are sent complete and Langfuse/Alloy handles any payload size constraints.
- What happens when token counts are missing from the CLI output? The system should still create valid traces with metadata indicating incomplete usage data.
- How are concurrent sessions from multiple terminal windows handled? Each window should produce distinct traces with unique identifiers, not interleaved events. Tool runs are correlated via `tool_use_id` to handle async context propagation issues.
- What happens if a CLI session is abruptly terminated? Partial traces should be flushed to Langfuse with appropriate status indicating incomplete execution. Orphaned tool runs should be ended with error status per the `clear_active_tool_runs` pattern.

## Requirements *(mandatory)*

### Functional Requirements

#### Trace Structure (adapted from LangSmith patterns)

- **FR-001**: System MUST create traces with a three-level hierarchy: "chain" (conversation/session) → "llm" (assistant turn) → "tool" (tool execution), matching the LangSmith `TracedClaudeSDKClient` pattern
- **FR-002**: System MUST use run types compatible with both LangSmith and Langfuse: "chain" for traces and agent sessions, "llm" for model generations, "tool" for tool invocations
- **FR-003**: System MUST track each assistant turn as a separate "llm" observation using a `TurnLifecycle` pattern that starts on AssistantMessage and ends on next message or completion

#### Tool Call Tracing (adapted from LangSmith hook pattern)

- **FR-004**: System MUST correlate tool calls using `tool_use_id` to handle async context propagation issues, maintaining `_active_tool_runs` and `_client_managed_runs` dictionaries
- **FR-005**: System MUST capture tool inputs as `{"input": <tool_parameters>}` and outputs as the tool response, with `is_error` flag for failures
- **FR-006**: System MUST handle subagent spawning (Task tool) by creating nested "chain" observations that contain their own LLM and tool children
- **FR-007**: System MUST clean up orphaned tool runs on conversation end, marking them with error status per `clear_active_tool_runs`

#### Content Serialization (adapted from LangSmith message handling)

- **FR-008**: System MUST serialize content blocks using `flatten_content_blocks` pattern, converting TextBlock → `{type: "text", text}`, ThinkingBlock → `{type: "thinking", thinking, signature}`, ToolUseBlock → `{type: "tool_use", id, name, input}`, ToolResultBlock → `{type: "tool_result", tool_use_id, content, is_error}`
- **FR-009**: System MUST build LLM inputs using `build_llm_input` pattern: `[{content: prompt, role: "user"}, ...history]`
- **FR-010**: System MUST extract final outputs from the last message's flattened content for trace-level outputs

#### Usage and Cost Tracking (adapted from LangSmith usage extraction)

- **FR-011**: System MUST extract usage metadata following `extract_usage_metadata` pattern: `input_tokens`, `output_tokens`, `input_token_details.cache_read`, `input_token_details.cache_creation`
- **FR-012**: System MUST sum cache tokens into total input tokens and calculate `total_tokens` per `sum_anthropic_tokens` pattern
- **FR-013**: System MUST include `total_cost` in usage_metadata when available from ResultMessage
- **FR-014**: System MUST include model name in metadata as `ls_model_name` for Langfuse model filtering

#### OTEL Export (adapted from LangSmith OtelSpanProcessor)

- **FR-015**: System MUST export traces to Langfuse's OTEL endpoint using OTLP HTTP/protobuf protocol, with configurable endpoint URL (default: `https://cloud.langfuse.com/api/public/otel`)
- **FR-016**: System MUST authenticate using Langfuse API key in `x-api-key` header and project in `Langsmith-Project` header (Langfuse uses same header)
- **FR-017**: System MUST support configuration via environment variables: `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`, or via NixOS module options
- **FR-018**: System MUST use batch processing for OTEL export with flush on conversation end to prevent data loss

#### Compatibility and Graceful Degradation

- **FR-019**: System MUST maintain backward compatibility with existing local EWW panel monitoring while adding Langfuse export
- **FR-020**: System MUST gracefully degrade when Langfuse is unavailable, queuing traces for later delivery via Alloy's batch retry mechanism
- **FR-021**: System MUST support multi-provider telemetry (Anthropic, OpenAI, Google) with provider-specific usage extraction patterns

#### Langfuse-Specific Attributes

- **FR-022**: System MUST use `langfuse.*` namespaced attributes for Langfuse-specific data: `langfuse.user.id`, `langfuse.session.id`, `langfuse.trace.tags`
- **FR-023**: System MUST include conversation-level metadata in trace: `num_turns`, `session_id`, `duration_ms`, `duration_api_ms`, `is_error`
- **FR-024**: System MUST propagate trace context using W3C Trace Context format for distributed tracing across MCP boundaries

### Key Entities *(include if feature involves data)*

- **Trace (chain)**: Root observation representing a complete AI CLI conversation; named `claude.conversation` / `codex.conversation` / `gemini.conversation`; contains nested LLM and tool observations; carries session-level metadata

- **LLM Observation (llm)**: Represents a single assistant turn; named `claude.assistant.turn` / `codex.assistant.turn` / `gemini.assistant.turn`; includes:
  - `inputs`: Message history as `[{role, content}]` array
  - `outputs`: Flattened content blocks from assistant response
  - `metadata.usage_metadata`: Token counts and costs
  - `metadata.ls_model_name`: Model identifier

- **Tool Observation (tool)**: Represents a tool execution; named by tool name (e.g., "Read", "Edit", "Bash", "mcp__server__tool"); includes:
  - `inputs.input`: Tool parameters
  - `outputs`: Tool response (dict, list, or string)
  - `error`: Error message if `is_error` is true

- **Subagent Observation (chain)**: Nested chain for Task tool spawning subagents; named by subagent type (e.g., "Explore", "Plan"); contains its own LLM and tool children

- **Content Blocks**: Serialized message content types:
  - TextBlock → `{type: "text", text: string}`
  - ThinkingBlock → `{type: "thinking", thinking: string, signature: string}`
  - ToolUseBlock → `{type: "tool_use", id: string, name: string, input: any}`
  - ToolResultBlock → `{type: "tool_result", tool_use_id: string, content: any, is_error: boolean}`

- **Usage Metadata**: Token and cost tracking structure:
  - `input_tokens`: Total input tokens (including cache)
  - `output_tokens`: Output tokens
  - `total_tokens`: Sum of input and output
  - `input_token_details.cache_read`: Cached tokens read
  - `input_token_details.cache_creation`: Tokens used for cache creation
  - `total_cost`: USD cost when available

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All AI CLI sessions (Claude Code, Codex, Gemini) appear as valid traces in Langfuse UI within 60 seconds of session completion
- **SC-002**: Token counts in Langfuse match CLI-reported values with 100% accuracy, including cache token accounting per `sum_anthropic_tokens` pattern
- **SC-003**: Tool calls appear as properly typed "tool" observations with correct parent-child relationships in at least 95% of traces
- **SC-004**: Users can filter traces by provider (`ls_provider`), model (`ls_model_name`), project (via tags), and session in Langfuse with no false negatives
- **SC-005**: Cost calculations in Langfuse are within 5% of actual billed amounts for supported models
- **SC-006**: Local EWW panel monitoring continues to function with no degradation in latency or accuracy
- **SC-007**: Traces are successfully delivered to Langfuse after network recovery for queued data during outages
- **SC-008**: Multi-turn conversations display complete message history with flattened content blocks in Langfuse generation observations
- **SC-009**: MCP tool calls include server identification and are traceable across client/server boundary in Langfuse UI
- **SC-010**: Subagent traces (from Task tool) appear as properly nested chains with their own LLM/tool hierarchies

## Assumptions

- Langfuse Cloud or self-hosted instance is accessible from the workstation (via Tailscale or direct internet)
- Users will configure Langfuse API credentials (public key, secret key) during setup
- The existing Grafana Alloy infrastructure can be extended with an additional OTLP export destination for Langfuse
- Langfuse's OTEL endpoint accepts the same header format as LangSmith (`x-api-key`, `Langsmith-Project`)
- The LangSmith SDK patterns (run types, content serialization, usage extraction) are compatible with Langfuse's data model
- The current otel-ai-monitor service can be extended to produce Langfuse-compatible OTEL spans following the LangSmith patterns
- Full and complete data capture is required with no redaction or privacy filtering
- The async context propagation issues addressed by LangSmith's thread-local storage may also apply to our implementation
