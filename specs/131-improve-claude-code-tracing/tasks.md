# Tasks: Improve Claude Code Tracing (v131)

## Status: Complete ✅

All tasks for Phase 1 and Phase 2 have been implemented and tested.

---

## Phase 1: Core Tracing (v3.5.0-v3.6.0)

### A) Turn Boundary Detection
- [x] Identify that `tool_result` messages have `role: "user"`
- [x] Add check for `type: "tool_result"` content blocks
- [x] Ensure single Turn span across tool loops
- [x] Add test case for tool loop boundary

### B) Session ID Hydration
- [x] Create `otel-session-start.sh` hook script
- [x] Write session UUID to `$XDG_RUNTIME_DIR/claude-session-${pid}.json`
- [x] Update interceptor to read session file
- [x] Apply `session.id` to all spans
- [x] Create `otel-session-end.sh` for cleanup

### C) Causality Links
- [x] Add `produced_by_llm` link to Tool spans
- [x] Add `consumes_tool_result` link to LLM spans
- [x] Track LLM span IDs for tool linking
- [x] Extract tool_use_id from responses

### D) Subagent Correlation
- [x] Create per-Task context files: `claude-task-context-${pid}-${tool_use_id}.json`
- [x] Implement atomic claim pattern for subagent linking
- [x] Add `claude.parent_session_id` attribute
- [x] Handle multiple concurrent Tasks correctly

### E) Hook-Driven Turn Boundaries
- [x] Create `otel-user-prompt-submit.sh` hook
- [x] Create `otel-stop.sh` hook
- [x] Register hooks in `claude-code.nix`
- [x] Add hook polling to interceptor
- [x] Fallback to heuristics when hooks unavailable

### F) Test Harness
- [x] Create `test-otel-interceptor-harness.js`
- [x] Mock OTLP receiver
- [x] Mock Anthropic API
- [x] Validate turn boundaries
- [x] Validate session.id hydration
- [x] Validate causal links

---

## Phase 2: Enhanced Observability (v3.7.0-v3.8.0)

### G) Cost Metrics
- [x] Add `MODEL_PRICING` table with Anthropic pricing
- [x] Implement `calculateCostUsd(model, tokens)` function
- [x] Add `gen_ai.usage.cost_usd` attribute to LLM spans
- [x] Aggregate cost to turn spans
- [x] Aggregate cost to session spans
- [x] Add `cost_usd` field to `models.py` Session
- [x] Update `session_tracker.py` to parse and accumulate cost
- [x] Add cost test to harness

### H) Error Handling
- [x] Implement `classifyErrorType(statusCode, responseBody)` function
- [x] Classify: auth, rate_limit, timeout, validation, server
- [x] Add `error.type` attribute to LLM spans
- [x] Add `turn.error_count` attribute to turn spans
- [x] Add `error_count` field to `models.py` Session
- [x] Add `last_error_type` field to `models.py` Session
- [x] Update `session_tracker.py` to track errors
- [x] Add error test to harness

### I) Permission Wait Visibility
- [x] Create `otel-permission-request.sh` hook script
- [x] Write permission metadata to runtime file
- [x] Register `PermissionRequest` hook in `claude-code.nix` with matcher `*`
- [x] Add `pendingPermissions` Map to interceptor state
- [x] Implement `pollPermissionFiles()` function
- [x] Implement `completePermissionSpan()` function
- [x] Complete as "approved" on tool_result
- [x] Complete as "denied" on turn end (orphaned permissions)
- [x] Add permission test to harness

### J) Enhanced Test Coverage
- [x] Create modular `TestHarness` class
- [x] Refactor basic test into `testBasicTurnBoundaries()`
- [x] Add `testStreamingResponse()` - SSE parsing
- [x] Add `testConcurrentTasks()` - Multiple Task tool_use
- [x] Add `testErrorScenarios()` - 429, 500 errors
- [x] Add `testPermissionFlow()` - PERMISSION spans
- [x] Add `testCostMetrics()` - cost_usd calculation
- [x] Add `--test=<name>` CLI option for selective tests

---

## Verification

### Local Tests
```bash
node scripts/test-otel-interceptor-harness.js
# Expected: Results: 6/6 tests passed
```

### Integration Tests
```bash
# After NixOS rebuild
claude --version
# Expected: [OTEL-Interceptor v3.8.0] Active

# Start session and verify in Grafana Tempo
# Search: service.name="claude-code" session.id="<uuid>"
# Verify: Session → Turn → LLM + Tool + Permission spans
# Verify: gen_ai.usage.cost_usd, error.type, permission.* attributes
```

---

## Dependencies

| Task | Depends On |
|------|------------|
| Cost Metrics | Core interceptor (Phase 1) |
| Error Handling | Core interceptor (Phase 1) |
| Permission Visibility | Hook infrastructure (Phase 1) |
| Enhanced Tests | All Phase 2 features |

---

## Files Modified

### Phase 1
| File | Changes |
|------|---------|
| `scripts/minimal-otel-interceptor.js` | v3.5.0: Turn boundaries, session hydration, causal links |
| `scripts/claude-hooks/otel-session-start.sh` | New: Write session UUID |
| `scripts/claude-hooks/otel-session-end.sh` | New: Cleanup session file |
| `scripts/claude-hooks/otel-user-prompt-submit.sh` | New: Turn start signal |
| `scripts/claude-hooks/otel-stop.sh` | New: Turn end signal |
| `home-modules/ai-assistants/claude-code.nix` | Register hooks |
| `scripts/test-otel-interceptor-harness.js` | New: Test harness |

### Phase 2
| File | Changes |
|------|---------|
| `scripts/minimal-otel-interceptor.js` | v3.8.0: Cost, errors, permissions |
| `scripts/claude-hooks/otel-permission-request.sh` | New: Permission tracking |
| `home-modules/ai-assistants/claude-code.nix` | PermissionRequest hook |
| `scripts/otel-ai-monitor/models.py` | cost_usd, error_count fields |
| `scripts/otel-ai-monitor/session_tracker.py` | Parse cost, errors |
| `scripts/test-otel-interceptor-harness.js` | 6 test suites |
