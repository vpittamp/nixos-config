# Research: OpenTelemetry AI Assistant Monitoring

**Feature**: 123-otel-tracing
**Date**: 2025-12-16
**Status**: Complete

## R1: OTLP HTTP Protocol

### Decision
Implement OTLP HTTP receiver on port 4318 supporting both protobuf and JSON encoding.

### Rationale
- Standard OTLP port (4318 for HTTP, 4317 for gRPC)
- Both Claude Code and Codex CLI default to HTTP/protobuf
- Single port can multiplex based on Content-Type header
- Simpler than gRPC (no HTTP/2 requirement)

### Alternatives Considered
- **gRPC (port 4317)**: Rejected - requires HTTP/2, more complex, no benefit for local use
- **Custom protocol**: Rejected - native OTLP support available in both tools

### Technical Details

**Endpoints Required**:
| Path | Purpose | Priority |
|------|---------|----------|
| `POST /v1/logs` | Log records & events | HIGH - primary data source |
| `POST /v1/traces` | Trace spans | LOW - accept but ignore |
| `POST /v1/metrics` | Metric data | LOW - accept but ignore |

**Content-Type Handling**:
- `application/x-protobuf` → Parse with `opentelemetry-proto` library
- `application/json` → Parse as JSON with protobuf field names
- Response must use same Content-Type as request

**Response Codes**:
| Code | Meaning | Client Behavior |
|------|---------|-----------------|
| 200 | Success (full or partial) | No retry |
| 400 | Malformed request | MUST NOT retry |
| 429 | Rate limited | Exponential backoff |
| 5xx | Server error | Exponential backoff |

**Response Format** (ExportLogsServiceResponse):
```protobuf
message ExportLogsServiceResponse {
  ExportLogsPartialSuccess partial_success = 1;
}

message ExportLogsPartialSuccess {
  int64 rejected_log_records = 1;  // 0 = full success
  string error_message = 2;
}
```

---

## R2: Claude Code Telemetry

### Decision
Configure Claude Code with OTLP logs exporter to localhost:4318.

### Rationale
- Native support via environment variables
- Logs exporter provides event-level granularity
- Metrics exporter provides aggregate data (secondary)

### Configuration

**Environment Variables** (in claude-code.nix):
```nix
env = {
  CLAUDE_CODE_ENABLE_TELEMETRY = "1";
  OTEL_LOGS_EXPORTER = "otlp";
  OTEL_METRICS_EXPORTER = "otlp";
  OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
  OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318";
};
```

### Events Emitted

| Event Name | State Mapping | Key Attributes |
|------------|---------------|----------------|
| `claude_code.user_prompt` | → "working" | prompt_length |
| `claude_code.tool_result` | (during working) | tool_name, decision_source |
| `claude_code.api_request` | (during working) | - |
| `claude_code.api_error` | (error state) | error_message |
| Turn completion (inferred) | → "completed" | - |

### Session Identification
- **Primary**: `thread_id` or `conversation_id` attribute
- **Fallback**: Generate from first event timestamp + source

### Metrics Available (Secondary)
- Input/output token counts
- Cache read/creation tokens
- Session count
- Active time

---

## R3: Codex CLI Telemetry

### Decision
Configure Codex CLI with OTLP HTTP exporter in ~/.codex/config.toml.

### Rationale
- Native support via config file
- Same OTLP protocol as Claude Code
- Single receiver handles both tools

### Configuration

**~/.codex/config.toml**:
```toml
[otel]
exporter = { otlp-http = {
  endpoint = "http://localhost:4318/v1/logs",
  protocol = "binary"
}}
environment = "dev"
log_user_prompt = false
```

### Events Emitted

| Event Name | State Mapping | Key Attributes |
|------------|---------------|----------------|
| `codex.conversation_starts` | → session created | model, conversation_id |
| `codex.user_prompt` | → "working" | prompt_length |
| `codex.api_request` | (during working) | duration_ms, http_status |
| `codex.sse_event` | (during working) | token counts |
| `codex.tool_decision` | (during working) | tool_name, decision |
| `codex.tool_result` | (during working) | success_status |
| Turn completion (inferred) | → "completed" | - |

### Session Identification
- **Primary**: `conversation.id` attribute
- Service name: `codex-cli` or `codex_cli_rs`

---

## R4: Session State Machine

### Decision
Implement three-state machine: idle → working → completed → idle.

### Rationale
- Matches user mental model (waiting, processing, done)
- Minimal state for UI display
- Timeout-based cleanup for stale sessions

### State Transitions

```
                    ┌─────────────────────────────────┐
                    │                                 │
                    ▼                                 │
    ┌─────────┐  prompt   ┌─────────┐  completion  ┌──────────┐
    │  IDLE   │ ────────► │ WORKING │ ──────────► │ COMPLETED │
    └─────────┘           └─────────┘              └──────────┘
         ▲                     │                        │
         │                     │ timeout (5min)         │ user_ack OR
         │                     ▼                        │ timeout (30s)
         │              ┌─────────┐                     │
         └────────────── │ EXPIRED │ ◄─────────────────┘
                        └─────────┘
```

### Trigger Events

| Current State | Event | New State |
|---------------|-------|-----------|
| IDLE | `user_prompt` | WORKING |
| IDLE | `conversation_starts` | WORKING |
| WORKING | `tool_result` (last) | COMPLETED |
| WORKING | Turn completion inferred | COMPLETED |
| WORKING | No events for 5 min | EXPIRED → IDLE |
| COMPLETED | User acknowledges | IDLE |
| COMPLETED | No ack for 30s | IDLE |

### Completion Detection

Neither tool emits explicit "turn complete" events. Detection strategies:
1. **Timeout-based**: No events for 3 seconds after last tool_result
2. **Heuristic**: tool_result with no pending API requests
3. **Pattern**: Sequence ending with successful tool execution

**Recommendation**: 3-second quiet period after last event.

---

## R5: JSON Output Format

### Decision
Stream newline-delimited JSON (NDJSON) to stdout for EWW deflisten.

### Rationale
- EWW deflisten natively consumes stdout streams
- NDJSON allows incremental parsing
- Simple integration, no sockets or files

### Output Schema

**Session Update Event**:
```json
{
  "type": "session_update",
  "session_id": "abc123",
  "tool": "claude-code",
  "state": "working",
  "project": "nixos-config",
  "timestamp": 1734355200,
  "metrics": {
    "input_tokens": 1500,
    "output_tokens": 500
  }
}
```

**Session List Event** (periodic full state):
```json
{
  "type": "session_list",
  "sessions": [
    {
      "session_id": "abc123",
      "tool": "claude-code",
      "state": "working",
      "project": "nixos-config"
    },
    {
      "session_id": "def456",
      "tool": "codex",
      "state": "completed",
      "project": "other-project"
    }
  ],
  "timestamp": 1734355200
}
```

### Output Frequency
- **Session updates**: Immediately on state change
- **Full list**: Every 5 seconds (for EWW initial state and recovery)

---

## R6: Desktop Notifications

### Decision
Use libnotify (notify-send) for desktop notifications via SwayNC.

### Rationale
- SwayNC already configured in the system
- libnotify is the standard Linux notification API
- Supports actions for click-to-focus

### Notification Format

**On Completion**:
```bash
notify-send \
  --app-name="AI Monitor" \
  --urgency=normal \
  --action="focus=Focus Terminal" \
  "Claude Code Ready" \
  "Task completed in nixos-config"
```

### Action Handling
- Click notification → Focus terminal window
- Dismiss → Mark session as acknowledged
- Auto-dismiss after 30 seconds

---

## R7: EWW Integration

### Decision
Replace defpoll with deflisten for AI session widgets.

### Rationale
- deflisten is event-driven (no polling)
- Lower resource usage
- Immediate UI updates

### Current (to remove):
```yuck
(defpoll ai-sessions :interval "2s"
  `scripts/ai-sessions-status.sh`)
```

### New (to implement):
```yuck
(deflisten ai-sessions
  `otel-ai-monitor --json-stream`)

(defwidget ai-indicator []
  (box :class "ai-indicator"
    (for session in ai-sessions
      (box :class "session ${session.state}"
        (label :text "${session.tool}")))))
```

---

## R8: Python Dependencies

### Decision
Use minimal dependencies from nixpkgs Python ecosystem.

### Dependencies

| Package | Purpose | nixpkgs |
|---------|---------|---------|
| `opentelemetry-proto` | OTLP protobuf parsing | python311Packages.opentelemetry-proto |
| `aiohttp` | Async HTTP server | python311Packages.aiohttp |
| `pydantic` | Data models | python311Packages.pydantic |

### Alternatives Considered
- **Flask**: Rejected - synchronous, would need gunicorn
- **FastAPI/uvicorn**: Rejected - heavier than needed
- **Plain asyncio**: Rejected - aiohttp provides better HTTP handling

---

## R9: Service Configuration

### Decision
Run as systemd user service with socket activation consideration.

### Service Design

```nix
systemd.user.services.otel-ai-monitor = {
  Unit = {
    Description = "OpenTelemetry AI Assistant Monitor";
    After = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${pkg}/bin/otel-ai-monitor";
    Restart = "on-failure";
    RestartSec = 2;
    Environment = [
      "OTLP_PORT=4318"
      "PATH=${notify-send}/bin"
    ];
    StandardOutput = "journal";  # Logs to journal
    # Note: JSON stream goes to a named pipe or socket for EWW
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```

### JSON Stream Output
Options for EWW consumption:
1. **Named pipe**: Service writes to FIFO, EWW reads with deflisten
2. **Unix socket**: More robust, allows reconnection
3. **Stdout redirect**: systemd captures, EWW reads via journalctl

**Recommendation**: Named pipe at `$XDG_RUNTIME_DIR/otel-ai-monitor.pipe`

---

## R10: Performance Requirements

### Decision
Design for <30MB memory, <1s latency, 10+ concurrent sessions.

### Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Memory | <30MB | RSS under normal load |
| Event latency | <1s | Time from OTLP receipt to JSON output |
| Concurrent sessions | 10+ | No degradation with 10 active sessions |
| CPU usage | <1% idle | When no events arriving |

### Implementation Notes
- Use asyncio for non-blocking I/O
- Session dict with O(1) lookup by ID
- Bounded event buffer (last 100 events for debugging)
- No persistent storage (in-memory only)

---

## Summary

| Research Item | Decision | Confidence |
|---------------|----------|------------|
| R1: Protocol | OTLP HTTP on 4318 | HIGH |
| R2: Claude Code | Env vars for OTLP export | HIGH |
| R3: Codex CLI | config.toml [otel] section | HIGH |
| R4: State Machine | 3-state with timeouts | HIGH |
| R5: Output Format | NDJSON to stdout/pipe | HIGH |
| R6: Notifications | notify-send via SwayNC | HIGH |
| R7: EWW | deflisten replacing defpoll | HIGH |
| R8: Dependencies | aiohttp + opentelemetry-proto | HIGH |
| R9: Service | systemd user service | HIGH |
| R10: Performance | <30MB, <1s, 10+ sessions | HIGH |

All research items resolved. Ready for Phase 1 design.
