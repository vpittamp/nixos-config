"""Pydantic models for OpenTelemetry AI Assistant Monitor.

This module defines the data models for session tracking and JSON output.
Based on the data model specification in specs/123-otel-tracing/data-model.md
and specs/125-tracing-parity-codex/data-model.md.
"""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, model_validator


class SessionState(str, Enum):
    """Session state machine states."""

    IDLE = "idle"
    WORKING = "working"
    COMPLETED = "completed"
    EXPIRED = "expired"
    ATTENTION = "attention"  # Feature 135: User action needed (permissions, errors)


class SessionStage(str, Enum):
    """Canonical user-facing session stages."""

    STARTING = "starting"
    THINKING = "thinking"
    TOOL_RUNNING = "tool_running"
    STREAMING = "streaming"
    WAITING_INPUT = "waiting_input"
    ATTENTION = "attention"
    OUTPUT_READY = "output_ready"
    IDLE = "idle"


class TurnOwner(str, Enum):
    """Who currently owns the turn for the tracked session."""

    LLM = "llm"
    USER = "user"
    BLOCKED = "blocked"
    UNKNOWN = "unknown"


class ActivityFreshness(str, Enum):
    """User-facing freshness bucket for last session activity."""

    FRESH = "fresh"
    WARM = "warm"
    STALE = "stale"


class UserActionReason(str, Enum):
    """Normalized reasons for user intervention."""

    NONE = ""
    PERMISSION = "permission"
    AUTH = "auth"
    RATE_LIMIT = "rate_limit"
    MAX_TOKENS = "max_tokens"
    ERROR = "error"


class TerminalState(str, Enum):
    """Explicit terminal stop provenance for the current session turn."""

    NONE = ""
    EXPLICIT_COMPLETE = "explicit_complete"
    INFERRED_COMPLETE = "inferred_complete"


class AITool(str, Enum):
    """Supported AI assistant tools."""

    CLAUDE_CODE = "claude-code"
    CODEX_CLI = "codex"
    GEMINI_CLI = "gemini"


class Provider(str, Enum):
    """AI service providers for cost calculation and attribute mapping."""

    ANTHROPIC = "anthropic"
    OPENAI = "openai"
    GOOGLE = "google"


class IdentityConfidence(str, Enum):
    """Confidence level for how a session identity was established."""

    NATIVE = "native"
    PID = "pid"
    PANE = "pane"
    HEURISTIC = "heuristic"


class TerminalContext(BaseModel):
    """Terminal/tmux context used for session correlation."""

    terminal_anchor_id: Optional[str] = Field(
        default=None, description="Current live terminal anchor bound to the tracked tmux pane"
    )
    binding_anchor_id: Optional[str] = Field(
        default=None, description="Current live terminal anchor bound to the tmux/session surface"
    )
    binding_state: Optional[str] = Field(
        default=None, description="Binding state for the tracked surface (bound_local, rebound_local, tmux_present_unbound, unresolved)"
    )
    binding_source: Optional[str] = Field(
        default=None, description="Source of the current binding anchor (tmux_metadata, daemon_anchor_lookup, or process_env)"
    )
    anchor_lookup: Optional[str] = Field(
        default=None, description="Daemon lookup status for the terminal anchor"
    )
    window_id: Optional[int] = Field(
        default=None, description="Sway container ID of originating terminal window"
    )
    tmux_session: Optional[str] = Field(
        default=None, description="Tmux session name if process is running under tmux"
    )
    tmux_window: Optional[str] = Field(
        default=None, description="Tmux window identifier/name"
    )
    tmux_pane: Optional[str] = Field(
        default=None, description="Tmux pane identifier"
    )
    tmux_socket: Optional[str] = Field(
        default=None, description="Tmux socket path for the server that owns the pane"
    )
    tmux_server_key: Optional[str] = Field(
        default=None, description="Host-scoped tmux server identity derived from the socket path"
    )
    tmux_resolution_source: Optional[str] = Field(
        default=None, description="How tmux identity was resolved (explicit, discovered, or missing)"
    )
    pane_pid: Optional[int] = Field(
        default=None, description="Root PID reported by tmux for the pane"
    )
    pane_title: Optional[str] = Field(
        default=None, description="Current tmux pane title"
    )
    pane_active: Optional[bool] = Field(
        default=None, description="True when the pane is currently active in its tmux window"
    )
    window_active: Optional[bool] = Field(
        default=None, description="True when the tmux window is currently selected"
    )
    pty: Optional[str] = Field(
        default=None, description="Controlling terminal PTY path (e.g. /dev/pts/3)"
    )
    ai_trace_token: Optional[str] = Field(
        default=None, description="Deterministic token for correlating native AI telemetry with wrapper process"
    )
    host_name: Optional[str] = Field(
        default=None, description="Host name where the terminal process is running"
    )
    execution_mode: Optional[str] = Field(
        default=None, description="Execution context mode (local or ssh)"
    )
    connection_key: Optional[str] = Field(
        default=None, description="Normalized connection identity for context-aware matching"
    )
    context_key: Optional[str] = Field(
        default=None, description="Canonical context identity key (<project>::<mode>::<connection>)"
    )
    remote_target: Optional[str] = Field(
        default=None, description="Human-readable SSH target user@host:port when available"
    )


# Tool to Provider mapping
TOOL_PROVIDER: dict[AITool, Provider] = {
    AITool.CLAUDE_CODE: Provider.ANTHROPIC,
    AITool.CODEX_CLI: Provider.OPENAI,
    AITool.GEMINI_CLI: Provider.GOOGLE,
}


class Session(BaseModel):
    """An active AI assistant session.

    Represents a tracked conversation identified by thread/conversation ID.
    Tracks state transitions and optional token metrics.
    """

    session_id: str = Field(
        description="Unique identifier from telemetry (thread_id or conversation.id)"
    )
    native_session_id: Optional[str] = Field(
        default=None,
        description="Native AI CLI session identifier (session.id/conversation.id) when available",
    )
    context_fingerprint: Optional[str] = Field(
        default=None,
        description="Deterministic context key suffix for disambiguating same native session IDs",
    )
    identity_phase: str = Field(
        default="provisional",
        description="Whether the session identity is still provisional or has been promoted to canonical",
    )
    collision_group_id: Optional[str] = Field(
        default=None,
        description="Native collision group identifier in format tool:native_session_id",
    )
    canonicalization_blocker: Optional[str] = Field(
        default=None,
        description="Reason the session could not yet be promoted to canonical identity",
    )
    identity_confidence: IdentityConfidence = Field(
        default=IdentityConfidence.HEURISTIC,
        description="How strongly session identity was established",
    )
    tool: AITool = Field(description="Which AI tool this session belongs to")
    provider: Provider = Field(
        default=Provider.ANTHROPIC,
        description="AI service provider for cost calculation"
    )
    state: SessionState = Field(
        default=SessionState.IDLE, description="Current session state"
    )
    project: Optional[str] = Field(
        default=None, description="Project context if available from telemetry"
    )
    project_path: Optional[str] = Field(
        default=None, description="Canonical full project path when available"
    )
    window_id: Optional[int] = Field(
        default=None, description="Sway container ID of originating terminal window"
    )
    terminal_context: TerminalContext = Field(
        default_factory=TerminalContext,
        description="Terminal/tmux context used for process/session correlation",
    )
    pid: Optional[int] = Field(
        default=None, description="Process PID from telemetry for session correlation"
    )
    trace_id: Optional[str] = Field(
        default=None, description="OTLP trace ID for Langfuse link"
    )
    focusable: bool = Field(
        default=True, description="True when the session has deterministic focus/navigation context"
    )
    invalid_reason: Optional[str] = Field(
        default=None, description="Machine-readable invalidation reason when the session is not focusable"
    )

    # Timestamps
    created_at: datetime = Field(description="When session was first detected")
    last_event_at: datetime = Field(description="When last telemetry event was received")
    last_activity_at: Optional[datetime] = Field(
        default=None,
        description="When last real AI work activity was observed",
    )
    state_changed_at: datetime = Field(description="When state last transitioned")

    # Error tracking
    error_count: int = Field(default=0, description="Cumulative error count")
    last_error_type: Optional[str] = Field(default=None, description="Last error type if any")

    # Tool execution tracking
    pending_tools: int = Field(default=0, description="Count of active tool executions")
    is_streaming: bool = Field(default=False, description="True if currently receiving streaming response")
    state_seq: int = Field(default=0, description="Monotonic state sequence for UI dedupe")
    status_reason: Optional[str] = Field(
        default=None, description="Machine-readable reason for current state"
    )
    last_event_name: Optional[str] = Field(
        default=None,
        description="Most recent normalized telemetry event name observed for the session",
    )
    turn_owner: TurnOwner = Field(
        default=TurnOwner.UNKNOWN,
        description="Whether the model, user, or a blocking condition currently owns the turn",
    )
    activity_substate: SessionStage = Field(
        default=SessionStage.IDLE,
        description="Canonical activity substate used to refine the current turn owner",
    )
    terminal_state: TerminalState = Field(
        default=TerminalState.NONE,
        description="Explicit terminal stop provenance for the current session turn",
    )
    terminal_state_at: Optional[datetime] = Field(
        default=None,
        description="Timestamp when terminal_state was most recently established",
    )
    terminal_state_source: Optional[str] = Field(
        default=None,
        description="Machine-readable source for terminal_state",
    )
    provider_stop_signal: Optional[str] = Field(
        default=None,
        description="Provider-native signal that triggered the explicit stop state",
    )

    # Streaming metrics (Feature 136: fix missing fields referenced by session_tracker.py)
    first_token_time: Optional[datetime] = Field(
        default=None, description="Timestamp of first streaming token for TTFT calculation"
    )
    streaming_tokens: int = Field(
        default=0, description="Count of streaming tokens received in current response"
    )

    class Config:
        """Pydantic configuration."""

        use_enum_values = True

    @model_validator(mode="after")
    def _normalize_identity_phase(self) -> "Session":
        phase = str(self.identity_phase or "").strip().lower()
        if phase not in {"provisional", "canonical"}:
            phase = ""
        if not phase:
            phase = (
                "canonical"
                if self.native_session_id and self.context_fingerprint
                else "provisional"
            )
        elif phase == "provisional" and self.native_session_id and self.context_fingerprint:
            phase = "canonical"
        self.identity_phase = phase
        return self


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


class SessionListItem(BaseModel):
    """Session summary for list output."""

    session_id: str = Field(description="Session identifier")
    native_session_id: Optional[str] = Field(
        default=None, description="Native AI CLI session identifier"
    )
    context_fingerprint: Optional[str] = Field(
        default=None, description="Deterministic context key suffix for collision handling"
    )
    identity_phase: str = Field(
        default="provisional",
        description="Whether the rendered session identity is provisional or canonical",
    )
    collision_group_id: Optional[str] = Field(
        default=None, description="Native collision group ID (tool:native_session_id)"
    )
    canonicalization_blocker: Optional[str] = Field(
        default=None,
        description="Reason the rendered session identity remains provisional",
    )
    identity_confidence: IdentityConfidence = Field(
        default=IdentityConfidence.HEURISTIC,
        description="How strongly session identity was established",
    )
    tool: str = Field(description="AI tool type")
    state: str = Field(description="Current session state")
    project: Optional[str] = Field(default=None, description="Project context")
    session_kind: str = Field(
        default="native",
        description="Session origin classification (native, process, or review)",
    )
    live: bool = Field(default=True, description="True when the session is currently live")
    session_project: Optional[str] = Field(
        default=None,
        description="Project the AI session is actually operating on",
    )
    window_project: Optional[str] = Field(
        default=None,
        description="Project owning the focus/navigation window",
    )
    focus_project: Optional[str] = Field(
        default=None,
        description="Project context used for focus/navigation actions",
    )
    display_project: Optional[str] = Field(
        default=None,
        description="Primary project label to show in the UI",
    )
    project_source: Optional[str] = Field(
        default=None,
        description="Source of the resolved project label",
    )
    project_path: Optional[str] = Field(default=None, description="Canonical project path")
    window_id: Optional[int] = Field(default=None, description="Sway container ID for focus")
    terminal_context: TerminalContext = Field(
        default_factory=TerminalContext, description="Terminal/tmux correlation context"
    )
    binding_anchor_id: Optional[str] = Field(
        default=None,
        description="Current live terminal anchor bound to the exported session surface",
    )
    binding_state: Optional[str] = Field(
        default=None,
        description="Binding state for the exported session surface",
    )
    binding_source: Optional[str] = Field(
        default=None,
        description="Source of the exported session binding state",
    )
    surface_kind: str = Field(
        default="terminal-window",
        description="Canonical tracked interaction surface kind",
    )
    surface_key: Optional[str] = Field(
        default=None,
        description="Deterministic surface identity used for pane/window tracking",
    )
    pane_label: Optional[str] = Field(
        default=None,
        description="User-facing tmux pane label when pane tracking is available",
    )
    conflict_state: Optional[str] = Field(
        default=None,
        description="Conflict classification for unsupported multi-session layouts",
    )
    conflict_detail: Optional[str] = Field(
        default=None,
        description="Human-readable explanation for the conflict state",
    )
    focusable: bool = Field(
        default=True, description="True when the session can be focused deterministically"
    )
    invalid_reason: Optional[str] = Field(
        default=None, description="Reason the session is hidden from the active session rail"
    )
    pid: Optional[int] = Field(default=None, description="Process ID for debugging/correlation")
    trace_id: Optional[str] = Field(default=None, description="OTLP trace ID for Langfuse link")
    process_running: bool = Field(default=False, description="True when the session PID is currently alive")
    rss_mb: Optional[float] = Field(default=None, description="Resident memory usage in MB")
    cpu_percent: Optional[float] = Field(default=None, description="Recent CPU usage percent for the session process")
    uptime_seconds: Optional[int] = Field(default=None, description="Approximate process uptime in seconds")
    stats_sampled_at: Optional[str] = Field(default=None, description="RFC3339 timestamp of the latest process sample")
    stats_source: str = Field(default="missing", description="Process stats source classification")
    process_tree_rss_mb: Optional[float] = Field(
        default=None,
        description="Resident memory usage aggregated over the tracked pane process tree in MB",
    )
    process_tree_cpu_percent: Optional[float] = Field(
        default=None,
        description="CPU usage aggregated over the tracked pane process tree in percent",
    )
    process_count: Optional[int] = Field(
        default=None,
        description="Number of processes currently visible in the tracked pane process tree",
    )
    # Feature 136: Additional fields for multi-indicator support
    pending_tools: int = Field(default=0, description="Count of active tool executions")
    is_streaming: bool = Field(default=False, description="True if currently receiving streaming response")
    state_seq: int = Field(default=0, description="Monotonic state sequence")
    status_reason: Optional[str] = Field(default=None, description="Machine-readable status reason")
    last_event_name: Optional[str] = Field(
        default=None,
        description="Most recent normalized telemetry event name observed for the session",
    )
    stage: SessionStage = Field(default=SessionStage.IDLE, description="Canonical user-facing stage")
    stage_label: str = Field(default="Idle", description="Short user-facing stage label")
    stage_detail: str = Field(default="", description="Short user-facing detail for the current stage")
    stage_class: str = Field(default="stage-idle", description="CSS-friendly stage class")
    stage_visual_state: str = Field(default="idle", description="Collapsed visual state for styling")
    stage_rank: int = Field(default=0, description="Canonical sort priority for UI")
    needs_user_action: bool = Field(default=False, description="True when the session is blocked on the user")
    user_action_reason: UserActionReason = Field(
        default=UserActionReason.NONE,
        description="Normalized user action reason when attention is required",
    )
    output_ready: bool = Field(default=False, description="True when the session has a completed result")
    output_unseen: bool = Field(default=False, description="True when output is ready but still unseen")
    llm_stopped: bool = Field(
        default=False,
        description="True when an explicit provider completion signal says the model has fully stopped",
    )
    terminal_state: TerminalState = Field(
        default=TerminalState.NONE,
        description="Explicit terminal stop provenance for the current session turn",
    )
    terminal_state_at: Optional[str] = Field(
        default=None,
        description="RFC3339 timestamp when terminal_state was most recently established",
    )
    terminal_state_label: str = Field(
        default="",
        description="User-facing label for terminal_state",
    )
    terminal_state_source: Optional[str] = Field(
        default=None,
        description="Machine-readable source for terminal_state",
    )
    provider_stop_signal: Optional[str] = Field(
        default=None,
        description="Provider-native signal that triggered the explicit stop state",
    )
    session_phase: str = Field(
        default="idle",
        description="Collapsed session phase used by downstream UIs (working, needs_attention, stopped, done, idle)",
    )
    session_phase_label: str = Field(
        default="Idle",
        description="User-facing label for the collapsed session phase",
    )
    turn_owner: TurnOwner = Field(
        default=TurnOwner.UNKNOWN,
        description="Whether the model, user, or a blocking condition currently owns the turn",
    )
    turn_owner_label: str = Field(
        default="Unknown",
        description="User-facing label for the current turn owner",
    )
    activity_substate: SessionStage = Field(
        default=SessionStage.IDLE,
        description="Canonical activity substate used to refine the current turn owner",
    )
    activity_substate_label: str = Field(
        default="Idle",
        description="User-facing label for the current activity substate",
    )
    activity_freshness: ActivityFreshness = Field(
        default=ActivityFreshness.FRESH,
        description="Freshness bucket for last activity",
    )
    activity_age_seconds: int = Field(default=0, description="Age of last activity in seconds")
    last_activity_at: Optional[str] = Field(
        default=None,
        description="RFC3339 timestamp for the last real activity event",
    )
    identity_source: str = Field(default="heuristic", description="How identity was established for display")
    lifecycle_source: str = Field(default="trace", description="Primary source of lifecycle state")
    updated_at: str = Field(description="RFC3339 timestamp when session was last updated")

    @model_validator(mode="after")
    def _normalize_identity_phase(self) -> "SessionListItem":
        phase = str(self.identity_phase or "").strip().lower()
        if phase not in {"provisional", "canonical"}:
            phase = ""
        if not phase:
            phase = (
                "canonical"
                if self.native_session_id and self.context_fingerprint
                else "provisional"
            )
        elif phase == "provisional" and self.native_session_id and self.context_fingerprint:
            phase = "canonical"
        self.identity_phase = phase
        return self


class SessionList(BaseModel):
    """Full session list output.

    Broadcast periodically for EWW initialization and recovery.
    Allows widgets to get full state on startup or after reconnection.

    Feature 136: Added sessions_by_window for multiple AI indicators per terminal.
    """

    schema_version: str = Field(default="11", description="Session payload schema version")
    type: str = Field(default="session_list", description="Event type for consumer routing")
    sessions: list[SessionListItem] = Field(
        default_factory=list, description="All active sessions (not deduplicated)"
    )
    # Feature 136: Sessions grouped by window_id for efficient EWW lookup
    sessions_by_window: dict[int, list[SessionListItem]] = Field(
        default_factory=dict,
        description="Sessions grouped by window_id for multi-indicator display"
    )
    diagnostics: list[dict] = Field(
        default_factory=list,
        description="Deterministic diagnostics for invalid or unsupported session records"
    )
    timestamp: int = Field(description="Unix timestamp in seconds")
    updated_at: str = Field(description="RFC3339 timestamp when this payload was generated")
    has_working: bool = Field(
        default=False, description="True if any session is in working state"
    )


# Event name constants for state machine triggers
class EventNames:
    """Known event names from Claude Code, Codex CLI, and Gemini CLI telemetry."""

    # Claude Code events
    CLAUDE_USER_PROMPT = "claude_code.user_prompt"
    CLAUDE_TOOL_RESULT = "claude_code.tool_result"
    CLAUDE_TOOL_START = "claude_code.tool_start"
    CLAUDE_TOOL_COMPLETE = "claude_code.tool_complete"
    CLAUDE_STREAM_START = "claude_code.stream_start"
    CLAUDE_STREAM_TOKEN = "claude_code.stream_token"
    CLAUDE_API_REQUEST = "claude_code.api_request"
    CLAUDE_API_ERROR = "claude_code.api_error"
    # Interceptor / derived spans (kept distinct from native log events)
    CLAUDE_LLM_CALL = "claude_code.llm_call"

    # Normalized AG-UI aligned lifecycle events
    AG_UI_RUN_FINISHED = "ag_ui.run_finished"

    # Codex CLI events
    CODEX_CONVERSATION_STARTS = "codex.conversation_starts"
    CODEX_USER_PROMPT = "codex.user_prompt"
    CODEX_API_REQUEST = "codex.api_request"
    CODEX_SSE_EVENT = "codex.sse_event"
    CODEX_AGENT_TURN_COMPLETE = "codex.agent_turn_complete"
    CODEX_TOOL_DECISION = "codex.tool_decision"
    CODEX_TOOL_RESULT = "codex.tool_result"

    # Gemini CLI events
    # NOTE: Gemini CLI uses underscore-style event names (gemini_cli.api_request, ...)
    # Some docs/tools also refer to dot-style variants; keep both for compatibility.
    GEMINI_CONFIG = "gemini_cli.config"
    GEMINI_USER_PROMPT = "gemini_cli.user_prompt"
    GEMINI_API_REQUEST = "gemini_cli.api_request"
    GEMINI_API_RESPONSE = "gemini_cli.api_response"
    GEMINI_API_ERROR = "gemini_cli.api_error"
    GEMINI_TOOL_CALL = "gemini_cli.tool_call"
    GEMINI_API_REQUEST_DOT = "gemini_cli.api.request"
    GEMINI_API_RESPONSE_DOT = "gemini_cli.api.response"
    GEMINI_API_ERROR_DOT = "gemini_cli.api.error"
    GEMINI_TOKEN_USAGE = "gemini_cli.token.usage"
    # GenAI semantic convention events (used by Gemini CLI)
    GENAI_TOKEN_USAGE = "gen_ai.client.token.usage"
    GENAI_OPERATION = "gen_ai.client.operation"

    # Events that trigger WORKING state
    # Note: claude_code.api_request is included because Claude Code doesn't emit
    # explicit user_prompt events - API requests indicate user activity
    WORKING_TRIGGERS = {
        CLAUDE_USER_PROMPT,
        CLAUDE_API_REQUEST,  # Claude Code uses this to indicate activity
        CLAUDE_LLM_CALL,
        CODEX_USER_PROMPT,
        CODEX_CONVERSATION_STARTS,
        # Codex one-shot/non-interactive flows often emit api_request without
        # user_prompt/conversation_starts, so treat it as an explicit run start.
        CODEX_API_REQUEST,
        GEMINI_USER_PROMPT,
        GEMINI_API_REQUEST,
        GEMINI_API_REQUEST_DOT,
    }

    # Claude Code additional events
    CLAUDE_TOOL_DECISION = "claude_code.tool_decision"
    CLAUDE_AGENT_RUN = "claude_code.agent_run"  # From trace spans

    # Events that reset the quiet timer (keep WORKING)
    ACTIVITY_EVENTS = {
        CLAUDE_TOOL_RESULT,
        CLAUDE_API_REQUEST,
        CLAUDE_LLM_CALL,
        CLAUDE_TOOL_DECISION,  # Claude Code emits this for tool calls
        CLAUDE_AGENT_RUN,  # From trace spans
        CODEX_API_REQUEST,
        CODEX_SSE_EVENT,
        CODEX_TOOL_DECISION,
        CODEX_TOOL_RESULT,
        GEMINI_API_REQUEST,
        GEMINI_API_REQUEST_DOT,
        GEMINI_API_RESPONSE,
        GEMINI_API_RESPONSE_DOT,
        GEMINI_API_ERROR,
        GEMINI_API_ERROR_DOT,
        GEMINI_TOKEN_USAGE,
        GEMINI_TOOL_CALL,
        GENAI_TOKEN_USAGE,
        GENAI_OPERATION,
    }

    EXPLICIT_COMPLETION_EVENTS = {
        AG_UI_RUN_FINISHED,
        CODEX_AGENT_TURN_COMPLETE,
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


# =============================================================================
# Feature 132: Langfuse OTEL Attribute Constants
# =============================================================================
# Langfuse uses OpenInference semantic conventions for trace type detection.
# These constants define the attribute names and valid values for Langfuse
# to properly categorize and display AI CLI traces.
#
# Reference: https://langfuse.com/docs/open-source/observability/opentelemetry

class LangfuseAttributes:
    """Langfuse-specific OTEL span attribute names and values.

    Langfuse's OTLP receiver maps OpenTelemetry spans to Langfuse observations
    using these attribute names. Proper attribute tagging ensures traces appear
    correctly in the Langfuse UI with proper hierarchy and metadata.
    """

    # --- Observation Type Attributes ---
    # Langfuse determines observation type from openinference.span.kind
    SPAN_KIND = "openinference.span.kind"

    # --- Span Kind Values (maps to Langfuse observation types) ---
    # CHAIN -> "span" in Langfuse (parent trace or workflow)
    # LLM -> "generation" in Langfuse (LLM API calls)
    # TOOL -> "span" with tool metadata in Langfuse
    # AGENT -> "span" in Langfuse (agent turns/steps)
    KIND_CHAIN = "CHAIN"
    KIND_LLM = "LLM"
    KIND_TOOL = "TOOL"
    KIND_AGENT = "AGENT"
    KIND_RETRIEVER = "RETRIEVER"
    KIND_EMBEDDING = "EMBEDDING"
    KIND_RERANKER = "RERANKER"

    # --- GenAI Semantic Convention Attributes ---
    # These are standard OpenTelemetry GenAI attributes that Langfuse recognizes
    GEN_AI_SYSTEM = "gen_ai.system"
    GEN_AI_REQUEST_MODEL = "gen_ai.request.model"
    GEN_AI_RESPONSE_MODEL = "gen_ai.response.model"
    GEN_AI_USAGE_INPUT_TOKENS = "gen_ai.usage.input_tokens"
    GEN_AI_USAGE_OUTPUT_TOKENS = "gen_ai.usage.output_tokens"
    GEN_AI_USAGE_TOTAL_TOKENS = "gen_ai.usage.total_tokens"
    GEN_AI_USAGE_COST = "gen_ai.usage.cost"

    # --- Langfuse-Specific Attributes ---
    # These attributes are specific to Langfuse and used for enhanced features
    LANGFUSE_SESSION_ID = "langfuse.session.id"
    LANGFUSE_USER_ID = "langfuse.user.id"
    LANGFUSE_TRACE_NAME = "langfuse.trace.name"
    LANGFUSE_OBSERVATION_NAME = "langfuse.observation.name"
    LANGFUSE_TAGS = "langfuse.tags"
    LANGFUSE_METADATA = "langfuse.metadata"
    LANGFUSE_VERSION = "langfuse.version"
    LANGFUSE_RELEASE = "langfuse.release"

    # --- Usage Details (JSON object) ---
    # Langfuse supports detailed token breakdown in usage_details
    LANGFUSE_USAGE_DETAILS = "langfuse.observation.usage_details"
    LANGFUSE_COST_DETAILS = "langfuse.observation.cost_details"

    # --- Tool Call Attributes ---
    TOOL_NAME = "tool.name"
    TOOL_DESCRIPTION = "tool.description"
    TOOL_INPUT = "input.value"
    TOOL_OUTPUT = "output.value"

    # --- Input/Output for Generations ---
    INPUT_VALUE = "input.value"
    INPUT_MIME_TYPE = "input.mime_type"
    OUTPUT_VALUE = "output.value"
    OUTPUT_MIME_TYPE = "output.mime_type"

    # --- OpenInference Message Attributes ---
    # For structured prompt/response content
    LLM_INPUT_MESSAGES = "llm.input_messages"
    LLM_OUTPUT_MESSAGES = "llm.output_messages"
    LLM_PROMPTS = "llm.prompts"
    LLM_PROMPT_TEMPLATE = "llm.prompt_template"
    LLM_PROMPT_TEMPLATE_VARIABLES = "llm.prompt_template.variables"

    # --- Error Attributes ---
    ERROR_TYPE = "error.type"
    ERROR_MESSAGE = "error.message"
    EXCEPTION_TYPE = "exception.type"
    EXCEPTION_MESSAGE = "exception.message"

    @staticmethod
    def get_span_kind_for_observation_type(obs_type: str) -> str:
        """Map Langfuse observation type to OpenInference span kind.

        Args:
            obs_type: Langfuse observation type ("trace", "generation", "span")

        Returns:
            OpenInference span kind value
        """
        mapping = {
            "trace": LangfuseAttributes.KIND_CHAIN,
            "generation": LangfuseAttributes.KIND_LLM,
            "span": LangfuseAttributes.KIND_CHAIN,
            "tool": LangfuseAttributes.KIND_TOOL,
            "event": LangfuseAttributes.KIND_CHAIN,
        }
        return mapping.get(obs_type.lower(), LangfuseAttributes.KIND_CHAIN)

    @staticmethod
    def build_usage_details(
        input_tokens: int = 0,
        output_tokens: int = 0,
        cache_read_tokens: int = 0,
        cache_creation_tokens: int = 0,
        reasoning_tokens: int = 0,
    ) -> dict:
        """Build a usage_details JSON object for Langfuse.

        Langfuse accepts detailed token breakdown via langfuse.observation.usage_details.

        Args:
            input_tokens: Input/prompt tokens
            output_tokens: Output/completion tokens
            cache_read_tokens: Tokens read from cache
            cache_creation_tokens: Tokens written to cache
            reasoning_tokens: Tokens used for reasoning (o1 models)

        Returns:
            Dictionary suitable for JSON serialization
        """
        details = {
            "input": input_tokens,
            "output": output_tokens,
            "total": input_tokens + output_tokens,
        }
        if cache_read_tokens > 0:
            details["cache_read"] = cache_read_tokens
        if cache_creation_tokens > 0:
            details["cache_creation"] = cache_creation_tokens
        if reasoning_tokens > 0:
            details["reasoning"] = reasoning_tokens
        return details

    @staticmethod
    def build_cost_details(
        input_cost: float = 0.0,
        output_cost: float = 0.0,
        cache_read_cost: float = 0.0,
        cache_creation_cost: float = 0.0,
        total_cost: float = 0.0,
    ) -> dict:
        """Build a cost_details JSON object for Langfuse.

        Args:
            input_cost: Cost for input tokens (USD)
            output_cost: Cost for output tokens (USD)
            cache_read_cost: Cost for cache read tokens (USD)
            cache_creation_cost: Cost for cache creation tokens (USD)
            total_cost: Total cost (USD), or sum if not provided

        Returns:
            Dictionary suitable for JSON serialization
        """
        calculated_total = input_cost + output_cost + cache_read_cost + cache_creation_cost
        return {
            "input": round(input_cost, 8),
            "output": round(output_cost, 8),
            "total": round(total_cost if total_cost > 0 else calculated_total, 8),
        }
