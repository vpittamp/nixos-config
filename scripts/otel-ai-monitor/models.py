"""Pydantic models for OpenTelemetry AI Assistant Monitor.

This module defines the data models for session tracking and JSON output.
Based on the data model specification in specs/123-otel-tracing/data-model.md.
"""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class SessionState(str, Enum):
    """Session state machine states."""

    IDLE = "idle"
    WORKING = "working"
    COMPLETED = "completed"
    EXPIRED = "expired"


class AITool(str, Enum):
    """Supported AI assistant tools."""

    CLAUDE_CODE = "claude-code"
    CODEX_CLI = "codex"
    GEMINI_CLI = "gemini"


class Session(BaseModel):
    """An active AI assistant session.

    Represents a tracked conversation identified by thread/conversation ID.
    Tracks state transitions and optional token metrics.
    """

    session_id: str = Field(
        description="Unique identifier from telemetry (thread_id or conversation.id)"
    )
    tool: AITool = Field(description="Which AI tool this session belongs to")
    state: SessionState = Field(
        default=SessionState.IDLE, description="Current session state"
    )
    project: Optional[str] = Field(
        default=None, description="Project context if available from telemetry"
    )
    window_id: Optional[int] = Field(
        default=None, description="Sway container ID of originating terminal window"
    )

    # Timestamps
    created_at: datetime = Field(description="When session was first detected")
    last_event_at: datetime = Field(description="When last telemetry event was received")
    state_changed_at: datetime = Field(description="When state last transitioned")

    # Metrics (optional, for P3 user story)
    input_tokens: int = Field(default=0, description="Cumulative input tokens")
    output_tokens: int = Field(default=0, description="Cumulative output tokens")
    cache_tokens: int = Field(default=0, description="Cumulative cache tokens")

    class Config:
        """Pydantic configuration."""

        use_enum_values = True


class TelemetryEvent(BaseModel):
    """Parsed telemetry event from OTLP log record.

    Represents a single event extracted from an OTLP ExportLogsServiceRequest.
    Used internally for session state updates.
    """

    event_name: str = Field(
        description="Event type (e.g., claude_code.user_prompt, codex.api_request)"
    )
    timestamp: datetime = Field(description="Event timestamp from telemetry")

    # Session identification
    session_id: Optional[str] = Field(
        default=None, description="thread_id, conversation_id, or conversation.id"
    )
    tool: Optional[AITool] = Field(
        default=None, description="Inferred from service.name or event prefix"
    )

    # Event-specific attributes
    attributes: dict = Field(
        default_factory=dict, description="All attributes from the log record"
    )

    # Trace context (for correlation)
    trace_id: Optional[str] = Field(default=None, description="OTLP trace ID")
    span_id: Optional[str] = Field(default=None, description="OTLP span ID")

    class Config:
        """Pydantic configuration."""

        use_enum_values = True


class SessionUpdate(BaseModel):
    """Output event for EWW deflisten consumption.

    Emitted immediately on session state changes for real-time UI updates.
    """

    type: str = Field(default="session_update", description="Event type for consumer routing")
    session_id: str = Field(description="Session identifier")
    tool: str = Field(description="AI tool type (claude-code or codex)")
    state: str = Field(description="Current session state")
    project: Optional[str] = Field(default=None, description="Project context if available")
    timestamp: int = Field(description="Unix timestamp in seconds")
    metrics: Optional[dict] = Field(
        default=None, description="Token counts if available"
    )


class SessionListItem(BaseModel):
    """Session summary for list output."""

    session_id: str = Field(description="Session identifier")
    tool: str = Field(description="AI tool type")
    state: str = Field(description="Current session state")
    project: Optional[str] = Field(default=None, description="Project context")
    window_id: Optional[int] = Field(default=None, description="Sway container ID for focus")


class SessionList(BaseModel):
    """Full session list output.

    Broadcast periodically for EWW initialization and recovery.
    Allows widgets to get full state on startup or after reconnection.
    """

    type: str = Field(default="session_list", description="Event type for consumer routing")
    sessions: list[SessionListItem] = Field(
        default_factory=list, description="All active sessions"
    )
    timestamp: int = Field(description="Unix timestamp in seconds")
    has_working: bool = Field(
        default=False, description="True if any session is in working state"
    )


# Event name constants for state machine triggers
class EventNames:
    """Known event names from Claude Code, Codex CLI, and Gemini CLI telemetry."""

    # Claude Code events
    CLAUDE_USER_PROMPT = "claude_code.user_prompt"
    CLAUDE_TOOL_RESULT = "claude_code.tool_result"
    CLAUDE_API_REQUEST = "claude_code.api_request"
    CLAUDE_API_ERROR = "claude_code.api_error"

    # Codex CLI events
    CODEX_CONVERSATION_STARTS = "codex.conversation_starts"
    CODEX_USER_PROMPT = "codex.user_prompt"
    CODEX_API_REQUEST = "codex.api_request"
    CODEX_SSE_EVENT = "codex.sse_event"
    CODEX_TOOL_DECISION = "codex.tool_decision"
    CODEX_TOOL_RESULT = "codex.tool_result"

    # Gemini CLI events (OpenTelemetry GenAI semantic conventions)
    GEMINI_USER_PROMPT = "gemini_cli.user_prompt"
    GEMINI_API_REQUEST = "gemini_cli.api.request"
    GEMINI_TOOL_CALL = "gemini_cli.tool.call"
    GEMINI_TOKEN_USAGE = "gen_ai.client.token.usage"
    GEMINI_CONVERSATION_STARTS = "gemini_cli.conversation_starts"

    # Events that trigger WORKING state
    # Note: claude_code.api_request is included because Claude Code doesn't emit
    # explicit user_prompt events - API requests indicate user activity
    WORKING_TRIGGERS = {
        CLAUDE_USER_PROMPT,
        CLAUDE_API_REQUEST,  # Claude Code uses this to indicate activity
        CODEX_USER_PROMPT,
        CODEX_CONVERSATION_STARTS,
        GEMINI_USER_PROMPT,
        GEMINI_API_REQUEST,
        GEMINI_CONVERSATION_STARTS,
    }

    # Claude Code additional events
    CLAUDE_TOOL_DECISION = "claude_code.tool_decision"
    CLAUDE_AGENT_RUN = "claude_code.agent_run"  # From trace spans

    # Events that reset the quiet timer (keep WORKING)
    ACTIVITY_EVENTS = {
        CLAUDE_TOOL_RESULT,
        CLAUDE_API_REQUEST,
        CLAUDE_TOOL_DECISION,  # Claude Code emits this for tool calls
        CLAUDE_AGENT_RUN,  # From trace spans
        CODEX_API_REQUEST,
        CODEX_SSE_EVENT,
        CODEX_TOOL_DECISION,
        CODEX_TOOL_RESULT,
        GEMINI_API_REQUEST,
        GEMINI_TOOL_CALL,
        GEMINI_TOKEN_USAGE,
    }

    @staticmethod
    def get_tool_from_event(event_name: str) -> Optional[AITool]:
        """Infer AI tool from event name prefix."""
        if event_name.startswith("claude_code."):
            return AITool.CLAUDE_CODE
        elif event_name.startswith("codex."):
            return AITool.CODEX_CLI
        elif event_name.startswith("gemini_cli.") or event_name.startswith("gen_ai."):
            return AITool.GEMINI_CLI
        return None
