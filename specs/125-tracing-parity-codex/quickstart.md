# Quickstart: Multi-CLI Tracing Validation

**Feature**: `125-tracing-parity-codex`
**Date**: 2025-12-21

Quick guide to validate the multi-CLI tracing implementation.

## Prerequisites

- NixOS with home-manager configured
- Grafana Alloy running on port 4318
- otel-ai-monitor service running
- EWW monitoring panel active

## 1. Verify Infrastructure

```bash
# Check Alloy is receiving telemetry
curl -s http://localhost:4318/v1/traces -X POST -d '{}' -H "Content-Type: application/json"
# Should return 200 OK (empty response is fine)

# Check otel-ai-monitor is running
systemctl --user status otel-ai-monitor
# Should show "active (running)"

# Check EWW panel
eww state | grep -i session
# Should show session-related variables
```

## 2. Test Claude Code (Baseline)

Already working. Verify baseline:

```bash
# Start a Claude Code session
claude

# In another terminal, check telemetry
journalctl --user -u otel-ai-monitor -f
# Should see: "Session update: claude-code WORKING"

# Check EWW widget shows activity
eww state | grep ai_sessions
```

## 3. Test Codex CLI

### 3.1 Verify Installation

```bash
# Check version (must be >= 0.73.0)
codex --version
# Expected: 0.73.0 or later

# Check OAuth status
codex auth status
# Expected: Authenticated

# Check OTEL config
cat ~/.codex/config.toml
# Expected: [otel] section with exporter = "otlp-http"
```

### 3.2 Validate Telemetry

```bash
# Start a Codex session
codex

# In another terminal, watch otel-ai-monitor logs
journalctl --user -u otel-ai-monitor -f
# Expected: "Session update: codex WORKING"

# Check EWW widget
eww state | grep ai_sessions
# Expected: Session with tool="codex"
```

### 3.3 Test Token Tracking

```bash
# Run a simple prompt
echo "What is 2+2?" | codex

# Check Grafana for metrics
# Query: gen_ai.usage.prompt_tokens{service.name="codex"}
```

## 4. Test Gemini CLI

### 4.1 Verify Installation

```bash
# Check Gemini CLI is installed
gemini --version

# Check OAuth status
gemini auth status
# Expected: Authenticated

# Check telemetry config
cat ~/.gemini/settings.json | jq .telemetry
# Expected: enabled: true, target: "local", otlpEndpoint: "http://localhost:4318"
```

### 4.2 Validate Telemetry

```bash
# Start a Gemini session
gemini

# In another terminal, watch otel-ai-monitor logs
journalctl --user -u otel-ai-monitor -f
# Expected: "Session update: gemini WORKING"

# Check EWW widget
eww state | grep ai_sessions
# Expected: Session with tool="gemini"
```

## 5. Test Multi-Provider Scenario

### 5.1 Simultaneous Sessions

```bash
# Terminal 1: Start Claude Code
claude

# Terminal 2: Start Codex
codex

# Terminal 3: Start Gemini
gemini

# Check EWW panel shows all three
eww state | grep ai_sessions
# Expected: 3 sessions with different providers
```

### 5.2 Verify Provider Indicators

In the EWW monitoring panel (`Mod+M`), verify:
- [ ] Claude Code session shows with "Claude" indicator
- [ ] Codex session shows with "Codex" indicator
- [ ] Gemini session shows with "Gemini" indicator

## 6. Test Notifications

```bash
# Start a session
codex

# Ask a quick question and exit
echo "What is 2+2?" | codex

# Wait for quiet period (15 seconds)
# Desktop notification should appear: "Codex session completed"
```

## 7. Test Graceful Degradation

```bash
# Stop Alloy temporarily
sudo systemctl stop grafana-alloy

# Start a Codex session
codex
# Session should work normally

# Restart Alloy
sudo systemctl start grafana-alloy

# Verify buffered telemetry arrives
journalctl --user -u otel-ai-monitor -f
# Should see session events after Alloy restarts
```

## 8. Grafana Dashboard Validation

Open Grafana and verify:

1. **Traces** (Tempo):
   - Filter: `service.name = "codex"` or `service.name = "gemini"`
   - Should see session spans with LLM calls

2. **Metrics** (Mimir):
   - Query: `sum by (service_name) (gen_ai_usage_input_tokens_total)`
   - Should show token usage grouped by provider

3. **Cost Tracking**:
   - Query: `sum by (service_name) (gen_ai_usage_cost_usd)`
   - Should show calculated costs per provider

## Troubleshooting

### No Telemetry from Codex

```bash
# Check OTEL config
cat ~/.codex/config.toml
# Ensure exporter = "otlp-http" and endpoint is correct

# Check version
codex --version
# Must be >= 0.73.0

# Check network
curl -v http://localhost:4318/v1/traces
```

### No Telemetry from Gemini

```bash
# Check telemetry config
cat ~/.gemini/settings.json | jq .telemetry
# Ensure enabled = true

# Check auth
gemini auth status
# Must be authenticated
```

### Session Not Detected by otel-ai-monitor

```bash
# Check service logs
journalctl --user -u otel-ai-monitor -n 100

# Look for parsing errors or unknown provider warnings
# May need to add event name mappings
```

## Success Criteria Checklist

- [ ] SC-001: Codex telemetry in EWW within 5 seconds
- [ ] SC-002: Gemini telemetry in EWW within 5 seconds
- [ ] SC-003: All sessions tracked (no missing sessions)
- [ ] SC-004: Token counts match provider billing (within 1%)
- [ ] SC-005: Notifications fire within 2 seconds
- [ ] SC-006: Graceful degradation works
- [ ] SC-007: Zero manual setup after home-manager switch
