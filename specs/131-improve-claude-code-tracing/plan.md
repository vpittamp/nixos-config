# Implementation Plan: Improve Claude Code Tracing (v131)

## Overview

This plan covers two implementation phases:
- **Phase 1** (v3.5.0-v3.6.0): Core tracing improvements (turn boundaries, session correlation, subagent linking)
- **Phase 2** (v3.7.0-v3.8.0): Enhanced observability (cost metrics, error handling, permission visibility)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Claude Code Process                          │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌──────────────────────────────────────┐   │
│  │ Claude Code CLI │───▶│ minimal-otel-interceptor.js (v3.8.0) │   │
│  └─────────────────┘    └──────────────────────────────────────┘   │
│          │                           │                              │
│          ▼                           ▼                              │
│  ┌─────────────────┐    ┌──────────────────────────────────────┐   │
│  │   Hook Scripts  │───▶│     $XDG_RUNTIME_DIR/*.json          │   │
│  │ (SessionStart,  │    │   - claude-session-${pid}.json       │   │
│  │  UserPrompt,    │    │   - claude-user-prompt-${pid}.json   │   │
│  │  Stop,          │    │   - claude-stop-${pid}.json          │   │
│  │  Permission)    │    │   - claude-permission-${pid}-*.json  │   │
│  └─────────────────┘    │   - claude-task-context-*.json       │   │
│                         └──────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ OTLP/HTTP
┌─────────────────────────────────────────────────────────────────────┐
│                      Grafana Alloy (:4318)                          │
│  ┌─────────────────┐    ┌────────────────┐    ┌─────────────────┐  │
│  │ OTLP Receiver   │───▶│ Span Metrics   │───▶│ Remote Write    │  │
│  └─────────────────┘    └────────────────┘    │ (K8s LGTM)      │  │
│          │                                     └─────────────────┘  │
│          ▼                                                          │
│  ┌─────────────────┐                                                │
│  │ otel-ai-monitor │ (local EWW widgets)                            │
│  │     (:4320)     │                                                │
│  └─────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────┘
```

## Phase 1: Core Tracing (Completed)

### A) Turn Boundary Detection
- **Problem**: `tool_result` messages have `role: "user"`, causing spurious turn creation
- **Solution**: Check if last message content contains `type: "tool_result"` blocks
- **Files**: `scripts/minimal-otel-interceptor.js`

### B) Session ID Hydration
- **Problem**: Interceptor used `claude-${pid}-${timestamp}`, not Claude Code's UUID
- **Solution**: Hook writes UUID to runtime file, interceptor reads and applies to spans
- **Files**: `scripts/claude-hooks/otel-session-start.sh`, interceptor

### C) Causality Links
- **Problem**: LLM→Tool relationship inferred from timing only
- **Solution**: Add span links: Tool→"produced_by_llm", LLM→"consumes_tool_result"
- **Files**: `scripts/minimal-otel-interceptor.js`

### D) Subagent Correlation
- **Problem**: Multiple concurrent Tasks all linked to last Task span
- **Solution**: Per-Task context files with atomic claim pattern
- **Files**: `scripts/minimal-otel-interceptor.js`

### E) Hook-Driven Turn Boundaries
- **Problem**: Heuristic-based turn start/end detection was unreliable
- **Solution**: Use `UserPromptSubmit` and `Stop` hooks for explicit boundaries
- **Files**: `scripts/claude-hooks/otel-user-prompt-submit.sh`, `otel-stop.sh`

## Phase 2: Enhanced Observability (Completed)

### G) Cost Metrics
- **Goal**: Calculate USD cost per LLM call using model-specific pricing
- **Design**:
  1. Add `MODEL_PRICING` table with Anthropic pricing
  2. Calculate cost in `calculateCostUsd(model, tokens)`
  3. Add `gen_ai.usage.cost_usd` attribute to LLM spans
  4. Aggregate cost to turn and session spans
- **Files**: `scripts/minimal-otel-interceptor.js`, `scripts/otel-ai-monitor/*.py`

### H) Error Handling
- **Goal**: Classify errors and track error counts
- **Design**:
  1. Add `classifyErrorType(statusCode, responseBody)` function
  2. Return: auth, rate_limit, timeout, validation, server
  3. Add `error.type` and `turn.error_count` attributes
- **Files**: `scripts/minimal-otel-interceptor.js`, `scripts/otel-ai-monitor/*.py`

### I) Permission Wait Visibility
- **Goal**: Show time spent waiting for user approval
- **Design**:
  1. `PermissionRequest` hook writes permission metadata file
  2. Interceptor polls for permission files in hook poller
  3. On `tool_result`, complete permission span as "approved"
  4. On turn end, complete orphaned permissions as "denied"
- **Files**: `scripts/claude-hooks/otel-permission-request.sh`, interceptor, `claude-code.nix`

### J) Enhanced Test Coverage
- **Goal**: Comprehensive test suite for all features
- **Design**:
  1. Modular `TestHarness` class for test isolation
  2. 6 test suites: basic, streaming, concurrent, error, permission, cost
  3. Each test validates specific span attributes and behavior
- **Files**: `scripts/test-otel-interceptor-harness.js`

## Span Hierarchy

```
Claude Code Session (CHAIN)
├── Turn #1: "User prompt..." (AGENT)
│   ├── LLM Call: claude-3-5-sonnet (LLM)
│   │   └── [links to consumed tool spans]
│   ├── Permission: Write (PERMISSION) [if permission required]
│   ├── Tool: Read file.txt (TOOL)
│   │   └── [links to producing LLM span]
│   └── LLM Call: claude-3-5-sonnet (LLM)
├── Turn #2: "Follow-up..." (AGENT)
│   └── ...
└── [Session attributes: total tokens, cost, error_count]
```

## Configuration

Environment variables for customization:
- `OTEL_INTERCEPTOR_MODEL_PRICING_JSON` - Override model pricing
- `OTEL_INTERCEPTOR_TURN_BOUNDARY_MODE` - "auto"|"hooks"|"heuristic"
- `OTEL_INTERCEPTOR_SESSION_ID_POLICY` - "buffer"|"eager"
- `OTEL_INTERCEPTOR_HOOK_POLL_INTERVAL_MS` - Hook file poll interval (default: 200)
- `OTEL_INTERCEPTOR_DEBUG` - Enable debug logging

## Verification

Run the test harness:
```bash
node scripts/test-otel-interceptor-harness.js

# Run specific test
node scripts/test-otel-interceptor-harness.js --test=permission
```

Expected output: `Results: 6/6 tests passed`
