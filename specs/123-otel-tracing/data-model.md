# Data Model: OpenTelemetry AI Assistant Monitoring

**Feature**: 123-otel-tracing
**Date**: 2025-12-16

## Entities

### Session

Represents an active AI assistant conversation being monitored.

```python
from pydantic import BaseModel, Field
from enum import Enum
from datetime import datetime
from typing import Optional

class SessionState(str, Enum):
    IDLE = "idle"
    WORKING = "working"
    COMPLETED = "completed"
    EXPIRED = "expired"

class AITool(str, Enum):
    CLAUDE_CODE = "claude-code"
    CODEX_CLI = "codex"

class Session(BaseModel):
    """An active AI assistant session."""

    session_id: str = Field(
        description="Unique identifier from telemetry (thread_id or conversation.id)"
    )
    tool: AITool = Field(
        description="Which AI tool this session belongs to"
    )
    state: SessionState = Field(
        default=SessionState.IDLE,
        description="Current session state"
    )
    project: Optional[str] = Field(
        default=None,
        description="Project context if available from telemetry"
    )

    # Timestamps
    created_at: datetime = Field(
        description="When session was first detected"
    )
    last_event_at: datetime = Field(
        description="When last telemetry event was received"
    )
    state_changed_at: datetime = Field(
        description="When state last transitioned"
    )

    # Metrics (optional, for P3 user story)
    input_tokens: int = Field(default=0)
    output_tokens: int = Field(default=0)
    cache_tokens: int = Field(default=0)

    class Config:
        use_enum_values = True
```

### TelemetryEvent

Represents a parsed OTLP log record relevant to AI session tracking.

```python
class TelemetryEvent(BaseModel):
    """Parsed telemetry event from OTLP log record."""

    event_name: str = Field(
        description="Event type (e.g., claude_code.user_prompt, codex.api_request)"
    )
    timestamp: datetime = Field(
        description="Event timestamp from telemetry"
    )

    # Session identification
    session_id: Optional[str] = Field(
        default=None,
        description="thread_id, conversation_id, or conversation.id"
    )
    tool: Optional[AITool] = Field(
        default=None,
        description="Inferred from service.name or event prefix"
    )

    # Event-specific attributes
    attributes: dict = Field(
        default_factory=dict,
        description="All attributes from the log record"
    )

    # Trace context (for correlation)
    trace_id: Optional[str] = Field(default=None)
    span_id: Optional[str] = Field(default=None)
```

### SessionUpdate

JSON output format for EWW consumption.

```python
class SessionUpdate(BaseModel):
    """Output event for EWW deflisten consumption."""

    type: str = Field(
        default="session_update",
        description="Event type for consumer routing"
    )
    session_id: str
    tool: str
    state: str
    project: Optional[str] = None
    timestamp: int = Field(
        description="Unix timestamp in seconds"
    )
    metrics: Optional[dict] = Field(
        default=None,
        description="Token counts if available"
    )
```

### SessionList

Periodic full state broadcast for EWW initialization and recovery.

```python
class SessionListItem(BaseModel):
    """Session summary for list output."""
    session_id: str
    tool: str
    state: str
    project: Optional[str] = None

class SessionList(BaseModel):
    """Full session list output."""

    type: str = Field(default="session_list")
    sessions: list[SessionListItem]
    timestamp: int
```

## State Transitions

### Session State Machine

```
State: IDLE
  Events that trigger transition:
    - claude_code.user_prompt → WORKING
    - codex.user_prompt → WORKING
    - codex.conversation_starts → WORKING

State: WORKING
  Events that trigger transition:
    - Quiet period (3s no events) → COMPLETED
    - Timeout (5 min no events) → EXPIRED
  Events that keep state:
    - claude_code.tool_result (stay WORKING)
    - codex.api_request (stay WORKING)
    - codex.sse_event (stay WORKING)
    - codex.tool_decision (stay WORKING)
    - codex.tool_result (stay WORKING)

State: COMPLETED
  Events that trigger transition:
    - User acknowledgment (notification click) → IDLE
    - Timeout (30s) → IDLE
    - New user_prompt → WORKING

State: EXPIRED
  Automatic transition:
    - Immediate cleanup → removed from tracking
```

### Event to Tool Mapping

| Event Prefix | Tool |
|--------------|------|
| `claude_code.*` | CLAUDE_CODE |
| `codex.*` | CODEX_CLI |

### Event to State Action Mapping

| Event Name | Action |
|------------|--------|
| `claude_code.user_prompt` | Set WORKING, reset quiet timer |
| `claude_code.tool_result` | Reset quiet timer |
| `claude_code.api_request` | Reset quiet timer |
| `codex.conversation_starts` | Create session, set WORKING |
| `codex.user_prompt` | Set WORKING, reset quiet timer |
| `codex.api_request` | Reset quiet timer |
| `codex.sse_event` | Reset quiet timer, update token metrics |
| `codex.tool_decision` | Reset quiet timer |
| `codex.tool_result` | Reset quiet timer |

## Validation Rules

### Session ID
- Must be non-empty string
- Extracted from: `thread_id`, `conversation_id`, or `conversation.id` attribute
- If not present, generate from: `{tool}-{first_event_timestamp}`

### Timestamps
- All timestamps stored as UTC datetime
- OTLP timestamps are nanoseconds since epoch, convert to datetime
- Output timestamps are Unix seconds (for JSON compatibility)

### Token Metrics
- All token counts are non-negative integers
- Cumulative within session (not per-event)
- Updated from `codex.sse_event` token_count attributes

## Relationships

```
┌─────────────────┐
│ TelemetryEvent  │
└────────┬────────┘
         │ parsed from
         ▼
┌─────────────────┐
│ OTLP LogRecord  │
└────────┬────────┘
         │ updates
         ▼
┌─────────────────┐
│    Session      │
└────────┬────────┘
         │ emits
         ▼
┌─────────────────┐      ┌─────────────────┐
│ SessionUpdate   │      │  SessionList    │
└────────┬────────┘      └────────┬────────┘
         │                        │
         └────────────┬───────────┘
                      │ consumed by
                      ▼
              ┌─────────────────┐
              │  EWW deflisten  │
              └─────────────────┘
```

## Storage

**In-Memory Only** (no persistence):
- `Dict[str, Session]` keyed by session_id
- Maximum 100 sessions tracked (oldest expired first)
- Sessions removed after transition to EXPIRED or IDLE

**No Database Required**:
- Sessions are transient (lifetime of service)
- No historical data retention
- Restart clears all session state
