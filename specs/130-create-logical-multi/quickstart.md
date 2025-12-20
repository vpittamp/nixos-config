# Quickstart: Logical Multi-Span Trace Hierarchy

**Feature**: 130-create-logical-multi
**Date**: 2025-12-20

## Overview

This feature replaces the existing `minimal-otel-interceptor.js` with a new implementation that creates a proper hierarchical trace structure: Session → Turns → LLM/Tool spans.

## Prerequisites

- NixOS with home-manager
- Grafana Alloy running on port 4318
- Grafana Tempo for trace visualization
- Claude Code installed via home-manager

## Quick Verification

### 1. Check Current Interceptor

```bash
# Verify the interceptor is loaded
cat /etc/profiles/per-user/vpittamp/etc/profile.d/hm-session-vars.sh | grep NODE_OPTIONS
# Should show: --require /path/to/minimal-otel-interceptor.js
```

### 2. Test Trace Generation

```bash
# Start Claude Code and submit a simple prompt
claude "What is 2+2?"

# Check Alloy received traces
curl -s http://localhost:12345/metrics | grep otelcol_exporter
```

### 3. View Traces in Tempo

1. Open Grafana at https://grafana.tail286401.ts.net
2. Navigate to Explore → Tempo
3. Search for `service.name = "claude-code"`
4. Verify trace hierarchy shows: Session → Turn → LLM spans

## Key Changes from Previous Implementation

### Before (Feature 123)
```
Claude Code Session (root)
├── Claude API Call #1
├── Claude API Call #2
└── Claude API Call #3
```

### After (Feature 130)
```
Claude Code Session (root, CHAIN)
├── User Turn #1 (AGENT)
│   ├── Claude API Call (LLM)
│   ├── Tool: Read (TOOL)
│   └── Claude API Call (LLM)
├── User Turn #2 (AGENT)
│   ├── Claude API Call (LLM)
│   ├── Tool: Bash (TOOL)
│   └── Claude API Call (LLM)
└── User Turn #3 (AGENT)
    └── Claude API Call (LLM)
```

## Testing Scenarios

### Scenario 1: Simple Q&A (No Tools)

```bash
claude "What is the capital of France?"
```

**Expected Trace**:
- 1 Session span
- 1 Turn span
- 1 LLM span

### Scenario 2: Tool Use

```bash
claude "Read the contents of package.json"
```

**Expected Trace**:
- 1 Session span
- 1 Turn span
- 2 LLM spans (request, response with tool result)
- 1 Tool span (Read)

### Scenario 3: Multi-Turn Conversation

```bash
claude
# Submit prompt 1
# Submit prompt 2
# Submit prompt 3
```

**Expected Trace**:
- 1 Session span
- 3 Turn spans (one per user prompt)
- Multiple LLM/Tool spans under each turn

### Scenario 4: Subagent (Task Tool)

```bash
claude "Use the Task tool to research the codebase"
```

**Expected Traces**:
- Parent trace: Session → Turn → LLM/Tool spans, including Task tool span
- Child trace: Subagent Session → Turn → LLM/Tool spans, with span link to parent

## Debugging

### No Traces Appearing

```bash
# Check interceptor is loaded
ps aux | grep claude | grep NODE_OPTIONS

# Check Alloy is receiving data
journalctl -u grafana-alloy -f

# Test OTLP endpoint directly
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'
```

### Traces Missing Tool Spans

- Tool spans are created from API response `content` blocks
- Check if response contains `type: tool_use` blocks
- Verify tool result is in subsequent request

### Subagent Traces Not Linked

- Check `OTEL_TRACE_PARENT` environment variable is set
- Subagent should have span link in root session span
- Both traces should have matching `gen_ai.conversation.id`

## Files Modified

| File | Change |
|------|--------|
| `scripts/minimal-otel-interceptor.js` | Complete replacement with new implementation |
| `modules/services/grafana-alloy.nix` | May need updates for new span types |
| `home-modules/ai-assistants/claude-code.nix` | No changes expected |

## Rollback Procedure

If issues arise:

```bash
# The old interceptor should be backed up
# Restore from backup or checkout previous version
git checkout HEAD~1 -- scripts/minimal-otel-interceptor.js

# Rebuild
sudo nixos-rebuild switch --flake .#hetzner-sway

# Verify rollback
claude --version  # Start Claude Code to test
```

## Next Steps

After implementation:
1. Run test scenarios above
2. Verify traces in Grafana Tempo
3. Check token aggregation matches actual usage
4. Test subagent correlation with Task tool
