# Feature Specification: Tracing Parity for Gemini CLI and Codex CLI

**Feature Branch**: `125-tracing-parity-codex`
**Created**: 2025-12-21
**Status**: Draft
**Input**: User description: "Review our tracing architecture for Claude Code, Gemini CLI and Codex CLI. We've strengthened Claude Code tracing. Now we want to strengthen and solidify Gemini CLI and Codex CLI tracing approach, capturing full tracing information via OTEL and standardizing the approach for similar trace analysis."

## Context

Claude Code tracing has been enhanced through Feature 131 (Improve Claude Code Tracing) to provide rich, coherent traces with:
- Logical span hierarchy (Session → Turn → LLM/Tool)
- Causal links between LLM and Tool spans
- Cost metrics (USD per call/turn/session)
- Error classification
- Permission wait visibility
- Tool lifecycle (exit_code, output_summary)
- Subagent completion tracking
- Notification and compaction events

Since Claude Code doesn't emit OTEL natively, this required a Node.js interceptor and 10+ bash hooks.

**Gemini CLI** and **Codex CLI** both have **native OTEL support**, but their current configuration only sends basic telemetry. This feature brings them to parity with Claude Code's rich trace model while leveraging their native capabilities.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unified Trace Analysis in Grafana (Priority: P1)

As a developer using multiple AI CLIs (Claude Code, Gemini CLI, Codex CLI), I want to analyze traces from all three tools in Grafana Tempo with a consistent experience, so that I can compare performance, costs, and behavior across tools without learning different trace structures.

**Why this priority**: This is the core value proposition - unified observability across all AI coding assistants enables meaningful cross-tool comparisons and consistent debugging workflows.

**Independent Test**: Can be fully tested by running each CLI, sending traces to Grafana, and verifying all three produce similar span hierarchies with comparable attributes (session, turn, LLM, tool spans).

**Acceptance Scenarios**:

1. **Given** Gemini CLI is running with OTEL enabled, **When** I make a multi-turn conversation with tool usage, **Then** traces appear in Tempo with native hierarchy and normalized attributes queryable using the same filters as Claude Code (session.id, openinference.span.kind, gen_ai.*).

2. **Given** Codex CLI is running with OTEL enabled, **When** I complete a coding task with file operations, **Then** traces include tool spans with consistent attribute names (gen_ai.usage.*, tool.name, session.id).

3. **Given** I have traces from all three CLIs in Tempo, **When** I query by `openinference.span.kind = LLM`, **Then** I see LLM spans from all three tools with comparable attributes (input_tokens, output_tokens, model).

---

### User Story 2 - Cost Visibility Across All CLIs (Priority: P2)

As a developer tracking AI spending, I want to see cost metrics for Gemini CLI and Codex CLI sessions alongside Claude Code costs, so that I can understand my total AI expenditure and compare cost efficiency.

**Why this priority**: Cost tracking is critical for budget management but requires the foundational trace structure from P1.

**Independent Test**: Can be fully tested by running sessions on each CLI and verifying cost metrics appear in session metrics and Grafana dashboards.

**Acceptance Scenarios**:

1. **Given** Gemini CLI has pricing data configured, **When** I complete a session, **Then** `gen_ai.usage.cost_usd` appears on LLM spans with calculated cost.

2. **Given** Codex CLI has pricing data configured, **When** I run a multi-turn task, **Then** session-level cost aggregation is visible in otel-ai-monitor and Grafana.

---

### User Story 3 - Local Session Tracking for All CLIs (Priority: P2)

As a developer using the EWW monitoring panel, I want to see session status (idle/working/completed) for Gemini CLI and Codex CLI sessions just like Claude Code, so that I get notifications when any AI task completes.

**Why this priority**: Real-time session feedback improves productivity but depends on correct trace/event emission from P1.

**Independent Test**: Can be fully tested by running each CLI and observing the EWW panel status transitions and completion notifications.

**Acceptance Scenarios**:

1. **Given** otel-ai-monitor is running, **When** I start a Gemini CLI session, **Then** the EWW panel shows "gemini: working" status.

2. **Given** a Codex CLI session is active, **When** the task completes and quiet period expires, **Then** I receive a desktop notification and status shows "completed".

---

### User Story 4 - Trace-Log-Metric Correlation in Grafana (Priority: P3)

As a developer debugging a slow AI response, I want to jump from traces to logs to metrics for any CLI session, so that I can understand the full context of what happened.

**Why this priority**: Advanced debugging capability that builds on the unified trace structure.

**Independent Test**: Can be fully tested by following a trace in Grafana and verifying links to Loki logs and Mimir metrics via session.id.

**Acceptance Scenarios**:

1. **Given** a Gemini CLI trace in Tempo, **When** I click on session.id, **Then** I can navigate to matching logs in Loki filtered by the same session.id.

2. **Given** span metrics are configured in Alloy, **When** I view a slow operation in metrics, **Then** exemplars link back to the originating trace.

---

### User Story 5 - Error Tracking Across All CLIs (Priority: P3)

As a developer experiencing API errors, I want to see error classifications (auth, rate_limit, timeout, server) for all CLI traces, so that I can identify patterns and troubleshoot issues.

**Why this priority**: Error visibility is important for reliability but requires trace infrastructure from P1.

**Independent Test**: Can be fully tested by inducing errors (rate limits, auth failures) and verifying error.type attributes appear consistently.

**Acceptance Scenarios**:

1. **Given** Gemini CLI hits a rate limit (429), **When** the trace is recorded, **Then** the span includes `error.type = rate_limit` attribute.

2. **Given** Codex CLI experiences an auth error, **When** I view the trace, **Then** `error.type = auth` is present and otel-ai-monitor tracks error_count.

---

### Edge Cases

- What happens when a CLI doesn't emit session.id? Generate a fallback ID from tool + timestamp.
- How does the system handle CLIs that emit different event names? Normalize via Alloy transform or otel-ai-monitor parsing.
- What if a CLI's native OTEL format changes in an update? Version-specific parsing with graceful fallback to basic detection.
- How are concurrent sessions from different CLIs distinguished in the UI? Use window_id correlation and project context from window marks.
- What happens when OTEL collector is unavailable? Alloy buffers up to 100MB, then silently drops with periodic health warnings; telemetry is best-effort and does not block CLI operation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST receive traces from Gemini CLI via its native OTEL export capability
- **FR-002**: System MUST receive traces from Codex CLI via its native OTEL export capability
- **FR-003**: System MUST normalize span attributes to use consistent naming conventions aligned with OpenInference/GenAI semantic conventions (attribute normalization only; native trace hierarchy is preserved as-is)
- **FR-004**: System MUST extract session.id from Gemini CLI telemetry (via `session.id` or `conversation.id` attributes)
- **FR-005**: System MUST extract session.id from Codex CLI telemetry (via `conversation_id` attribute)
- **FR-006**: System MUST calculate cost metrics for Gemini CLI LLM spans using configurable pricing tables; for unrecognized models, use a default rate (~$5/1M tokens) and set `cost.estimated = true`
- **FR-007**: System MUST calculate cost metrics for Codex CLI LLM spans using OpenAI pricing tables; for unrecognized models, use a default rate and set `cost.estimated = true`
- **FR-008**: otel-ai-monitor MUST track session state (idle/working/completed) for Gemini CLI based on native events
- **FR-009**: otel-ai-monitor MUST track session state for Codex CLI based on native events
- **FR-010**: System MUST classify errors (auth, rate_limit, timeout, server) based on HTTP status or error messages
- **FR-011**: Grafana Alloy MUST apply attribute transformations to normalize span data from all three CLIs
- **FR-012**: System MUST emit desktop notifications when Gemini CLI or Codex CLI sessions complete

### Key Entities *(include if feature involves data)*

- **Session**: A single conversation/task identified by session.id/conversation.id, tracked across its lifecycle (idle → working → completed)
- **Span**: An OTEL span representing an operation (LLM call, tool execution, turn boundary)
- **Event**: A telemetry event (log record) from the CLI indicating activity
- **Pricing Table**: Configurable mapping of model name → token costs for cost calculation

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can query Tempo for traces from all three CLIs using the same attribute filters (openinference.span.kind, session.id, gen_ai.request.model)
- **SC-002**: Session tracking in otel-ai-monitor works for Gemini CLI and Codex CLI with state transitions visible in EWW panel
- **SC-003**: Cost metrics appear on LLM spans for all three CLIs with accuracy within 1% of actual API charges
- **SC-004**: Error classification attributes appear on failed spans from all three CLIs
- **SC-005**: Correlation via session.id works across traces, logs, and metrics in Grafana for all CLIs
- **SC-006**: Desktop notifications fire on session completion for all three CLIs

## Clarifications

### Session 2025-12-21

- Q: What happens when a model is not recognized in the pricing table for cost calculation? → A: Use a default "unknown model" rate (e.g., $5/1M tokens) and add `cost.estimated = true` attribute
- Q: Should we build synthetic Session/Turn hierarchy to match Claude Code, or accept native trace structures? → A: Accept native trace hierarchy from each CLI; normalize attributes only (no synthetic parent spans)
- Q: How should telemetry handle collector/endpoint unavailability? → A: Silent drop with periodic health warning in logs (current Alloy behavior - 100MB buffer, then drop); telemetry is best-effort

## Assumptions

- Gemini CLI's native OTEL support includes traces, logs, and metrics as documented
- Codex CLI's native OTEL support includes session/conversation tracking as documented
- Both CLIs emit sufficient event data to detect working/idle state transitions
- OpenAI and Google pricing is publicly available and stable enough for reasonable cost estimates
- The existing Grafana Alloy pipeline can be extended with additional transform processors
- Native OTEL emission from Gemini/Codex provides richer context than an interceptor approach would
