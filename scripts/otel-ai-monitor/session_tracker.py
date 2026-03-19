"""Session tracker for OpenTelemetry AI Assistant Monitor.

This module implements the session state machine that tracks AI assistant
sessions based on incoming telemetry events. It handles state transitions,
timeout management, and output emission.

State Machine:
    IDLE → WORKING (on user_prompt or conversation_starts)
    WORKING → COMPLETED (after quiet period with no events)
    COMPLETED → IDLE (after timeout or user acknowledgment)
    Any → EXPIRED → removed (after session timeout)
"""

import asyncio
import glob
import hashlib
import json
import logging
import os
import time
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING, Optional

import psutil

from .models import (
    ActivityFreshness,
    AITool,
    EventNames,
    IdentityConfidence,
    Provider,
    Session,
    SessionList,
    SessionListItem,
    SessionStage,
    SessionState,
    TerminalContext,
    TerminalState,
    SessionUpdate,
    TurnOwner,
    TelemetryEvent,
    TOOL_PROVIDER,
    UserActionReason,
)
from .sway_helper import (
    get_focused_window_info,
    get_all_window_ids,
    get_tmux_context_for_pid,
    get_process_i3pm_env,
    pid_exists,
    list_tmux_panes_sync,
    read_tmux_session_i3pm_metadata_sync,
    tmux_target_exists,
    get_window_context_by_id,
    query_daemon_for_terminal_anchor,
)

if TYPE_CHECKING:
    from .output import OutputWriter

logger = logging.getLogger(__name__)

_DISCOVERED_TMUX_PROJECT_HINT_CACHE: dict[str, object] = {
    "mtime_ns": None,
    "size": None,
    "mapping": {},
}

_tmux_panes_cache: tuple[float, list[dict]] = (0.0, [])
_TMUX_PANES_CACHE_TTL = 4.0


def _cached_list_tmux_panes_sync() -> list[dict]:
    """Cached wrapper around list_tmux_panes_sync() to avoid spawning tmux every broadcast."""
    global _tmux_panes_cache
    now = time.monotonic()
    if now - _tmux_panes_cache[0] < _TMUX_PANES_CACHE_TTL:
        return _tmux_panes_cache[1]
    result = list_tmux_panes_sync()
    _tmux_panes_cache = (now, result)
    return result


_BOOTSTRAP_RESTOREABLE_STATES = {
    SessionState.WORKING,
    SessionState.ATTENTION,
    SessionState.COMPLETED,
}
_PROCESS_STATS_CACHE_TTL_SEC = 2.0
_MIN_VALID_SESSION_TIMESTAMP_YEAR = 2020

# Feature 137: Maximum session count to prevent memory exhaustion
MAX_SESSIONS = 100
UNRESOLVED_SESSION_TTL_SEC = 60.0
_HEARTBEAT_ACTIVE_STATUS_REASONS = {
    f"event:{EventNames.CLAUDE_API_REQUEST}",
    f"event:{EventNames.CLAUDE_LLM_CALL}",
    f"event:{EventNames.CLAUDE_STREAM_START}",
    f"event:{EventNames.CLAUDE_STREAM_TOKEN}",
    f"event:{EventNames.CODEX_API_REQUEST}",
    f"event:{EventNames.CODEX_TOOL_DECISION}",
    f"event:{EventNames.CODEX_TOOL_RESULT}",
    f"event:{EventNames.GEMINI_API_REQUEST}",
    f"event:{EventNames.GEMINI_API_REQUEST_DOT}",
    f"event:{EventNames.GEMINI_API_RESPONSE}",
    f"event:{EventNames.GEMINI_API_RESPONSE_DOT}",
}


def _normalized_codex_sse_kind(event: TelemetryEvent) -> str:
    if not event or event.event_name != EventNames.CODEX_SSE_EVENT:
        return ""
    raw = event.attributes.get("event.kind") or event.attributes.get("event_kind") or ""
    return str(raw).strip().lower()


def _codex_sse_counts_as_activity(kind: str) -> bool:
    normalized = str(kind or "").strip().lower()
    if not normalized:
        return True
    if normalized in {
        "response.completed",
        "response.failed",
        "response.cancelled",
        "response.canceled",
        "response.incomplete",
    }:
        return False
    return True


def _event_status_reason(event: TelemetryEvent) -> str:
    if not event or not event.event_name:
        return ""
    if event.event_name == EventNames.CODEX_SSE_EVENT:
        kind = _normalized_codex_sse_kind(event)
        if kind:
            return f"event:{event.event_name}:{kind}"
    return f"event:{event.event_name}"


def _event_counts_as_activity(event: TelemetryEvent) -> bool:
    """Return True when an incoming event represents real model/tool activity."""
    if not event or not event.event_name:
        return False
    if event.event_name == EventNames.CODEX_SSE_EVENT:
        return _codex_sse_counts_as_activity(_normalized_codex_sse_kind(event))
    if event.event_name in EventNames.WORKING_TRIGGERS:
        return True
    if event.event_name in EventNames.ACTIVITY_EVENTS:
        return True
    return False


def state_priority(state: SessionState) -> int:
    """Return priority for state comparison (higher = more important).

    Feature 135: Added ATTENTION state with highest priority.
    """
    return {
        SessionState.ATTENTION: 4,  # Feature 135: Highest priority - needs user action
        SessionState.WORKING: 3,
        SessionState.COMPLETED: 2,
        SessionState.IDLE: 1,
        SessionState.EXPIRED: 0,
    }.get(state, 0)


_STAGE_LABELS = {
    SessionStage.STARTING: "Starting",
    SessionStage.THINKING: "Thinking",
    SessionStage.TOOL_RUNNING: "Tool",
    SessionStage.STREAMING: "Streaming",
    SessionStage.WAITING_INPUT: "Waiting",
    SessionStage.ATTENTION: "Attention",
    SessionStage.OUTPUT_READY: "Ready",
    SessionStage.IDLE: "Idle",
}

_STAGE_RANKS = {
    SessionStage.ATTENTION: 7,
    SessionStage.WAITING_INPUT: 6,
    SessionStage.TOOL_RUNNING: 5,
    SessionStage.STREAMING: 4,
    SessionStage.THINKING: 3,
    SessionStage.STARTING: 2,
    SessionStage.OUTPUT_READY: 1,
    SessionStage.IDLE: 0,
}
_STAGE_VISUAL_STATES = {
    SessionStage.STARTING: "working",
    SessionStage.THINKING: "working",
    SessionStage.TOOL_RUNNING: "working",
    SessionStage.STREAMING: "working",
    SessionStage.WAITING_INPUT: "attention",
    SessionStage.ATTENTION: "attention",
    SessionStage.OUTPUT_READY: "completed",
    SessionStage.IDLE: "idle",
}

_STATUS_REASON_DETAILS = {
    "created": "Session created",
    "trace_correlated": "Trace connected",
    "window_correlated_fallback": "Window correlated",
    "window_correlated_process_candidate": "Process attached to terminal",
    "metrics_heartbeat_created": "Heartbeat detected",
    "process_detected": "Process detected",
    "process_keepalive": "Still active",
    "tmux_keepalive": "Still attached",
    "process_exited_retained": "Exited, retaining result",
    "quiet_period_expired": "Response finished",
    "completed_timeout": "Session idle",
}
_EXPLICIT_STOP_METADATA: dict[AITool, tuple[str, str]] = {
    AITool.CODEX_CLI: ("codex_notify", "agent-turn-complete"),
    AITool.CLAUDE_CODE: ("claude_stop_hook", "Stop"),
    AITool.GEMINI_CLI: ("gemini_after_agent", "AfterAgent"),
}


def _classify_user_action_reason(session: Session) -> UserActionReason:
    """Normalize the session's current blocking reason for the UI."""
    status_reason = str(session.status_reason or "").strip().lower()
    last_error_type = str(session.last_error_type or "").strip().lower()

    if "permission" in status_reason:
        return UserActionReason.PERMISSION
    if "max_tokens" in status_reason:
        return UserActionReason.MAX_TOKENS
    if last_error_type == "auth":
        return UserActionReason.AUTH
    if last_error_type == "rate_limit":
        return UserActionReason.RATE_LIMIT
    if session.state == SessionState.ATTENTION or session.error_count > 0:
        return UserActionReason.ERROR
    return UserActionReason.NONE


def _activity_freshness(age_seconds: int) -> ActivityFreshness:
    """Bucket last activity age for display."""
    if age_seconds <= 15:
        return ActivityFreshness.FRESH
    if age_seconds <= 90:
        return ActivityFreshness.WARM
    return ActivityFreshness.STALE


def _humanize_status_reason(session: Session) -> str:
    """Convert machine reason fields into concise user-facing detail."""
    user_action_reason = _classify_user_action_reason(session)
    if user_action_reason == UserActionReason.PERMISSION:
        return "Waiting on permission"
    if user_action_reason == UserActionReason.AUTH:
        return "Authentication needed"
    if user_action_reason == UserActionReason.RATE_LIMIT:
        return "Rate limited"
    if user_action_reason == UserActionReason.MAX_TOKENS:
        return "Response hit max tokens"
    if user_action_reason == UserActionReason.ERROR:
        return "Needs user attention"
    if session.terminal_state == TerminalState.EXPLICIT_COMPLETE:
        return "Model stopped"

    status_reason = str(session.status_reason or "").strip()
    if not status_reason:
        return ""
    lowered = status_reason.lower()
    if lowered in _STATUS_REASON_DETAILS:
        return _STATUS_REASON_DETAILS[lowered]
    if lowered.startswith("event:"):
        event_name = lowered.split("event:", 1)[1]
        if event_name == EventNames.AG_UI_RUN_FINISHED:
            return "Model stopped"
        if "tool_start" in event_name:
            return "Tool started"
        if "tool_complete" in event_name or "tool_result" in event_name:
            return "Tool completed"
        if "stream_start" in event_name or "stream_token" in event_name:
            return "Streaming response"
        if "api_request" in event_name:
            return "Model request active"
        if "user_prompt" in event_name:
            return "Prompt sent"
        if "permission" in event_name:
            return "Waiting on permission"
    return status_reason.replace("_", " ").strip().capitalize()


def _identity_source(session: Session) -> str:
    """Return a stable user-facing identity source label."""
    confidence = session.identity_confidence
    if confidence == IdentityConfidence.NATIVE or session.native_session_id:
        return "native"
    if confidence == IdentityConfidence.PID:
        return "pid"
    if confidence == IdentityConfidence.PANE:
        return "pane"
    return "heuristic"


def _lifecycle_source(session: Session) -> str:
    """Describe the primary lifecycle source backing the current status."""
    status_reason = str(session.status_reason or "").strip().lower()
    if status_reason in {"metrics_heartbeat_created", "process_keepalive", "tmux_keepalive"}:
        return "heartbeat"
    if session.trace_id or session.native_session_id:
        return "trace"
    return "process"


_SESSION_PHASE_LABELS: dict[str, str] = {
    "working": "Working",
    "needs_attention": "Needs attention",
    "stopped": "Stopped",
    "quiet_alive": "Quiet",
    "done": "Done",
    "idle": "Idle",
    "tmux_missing": "Tmux missing",
}
_TERMINAL_STATE_LABELS: dict[TerminalState, str] = {
    TerminalState.NONE: "",
    TerminalState.EXPLICIT_COMPLETE: "Stopped",
    TerminalState.INFERRED_COMPLETE: "",
}
_TURN_OWNER_LABELS: dict[TurnOwner, str] = {
    TurnOwner.LLM: "LLM",
    TurnOwner.USER: "User",
    TurnOwner.BLOCKED: "Blocked",
    TurnOwner.UNKNOWN: "Unknown",
}


def _status_reason_event_name(status_reason: Optional[str]) -> str:
    lowered = str(status_reason or "").strip().lower()
    if not lowered.startswith("event:"):
        return ""
    return lowered.split("event:", 1)[1]


def _status_reason_is_heartbeat_like(status_reason: Optional[str]) -> bool:
    """Return whether a status reason is only a liveness heartbeat."""
    lowered = str(status_reason or "").strip().lower()
    if not lowered:
        return False
    if lowered in {"process_detected", "process_keepalive", "tmux_keepalive", "metrics_heartbeat_created"}:
        return True
    return lowered.startswith("event:codex.sse_event:response.completed")


def _is_newer_than_terminal_boundary(session: Session, event: TelemetryEvent) -> bool:
    """Return whether an event happened after the current explicit terminal boundary."""
    boundary = session.terminal_state_at
    if boundary is None:
        return True
    return event.timestamp > boundary


def _event_should_clear_explicit_terminal_state(session: Session, event: TelemetryEvent) -> bool:
    """Return whether an event proves a newer turn has started."""
    if session.terminal_state != TerminalState.EXPLICIT_COMPLETE:
        return False
    if event.event_name not in EventNames.WORKING_TRIGGERS:
        return False
    return _is_newer_than_terminal_boundary(session, event)


def _clear_terminal_state(session: Session) -> None:
    """Clear persisted terminal-state metadata from the raw session."""
    session.terminal_state = TerminalState.NONE
    session.terminal_state_at = None
    session.terminal_state_source = None
    session.provider_stop_signal = None


def _set_explicit_terminal_state(session: Session, event: TelemetryEvent) -> None:
    """Persist explicit provider stop metadata on the raw session."""
    source, provider_signal = _EXPLICIT_STOP_METADATA.get(
        session.tool,
        ("explicit_signal", None),
    )
    session.terminal_state = TerminalState.EXPLICIT_COMPLETE
    session.terminal_state_at = event.timestamp
    session.terminal_state_source = str(
        event.attributes.get("terminal_state_source") or source or ""
    ).strip() or source
    session.provider_stop_signal = str(
        event.attributes.get("provider_stop_signal") or provider_signal or ""
    ).strip() or provider_signal


def _derive_session_phase(
    *,
    stage: SessionStage,
    output_ready: bool,
    output_unseen: bool,
    needs_user_action: bool,
    terminal_state: TerminalState,
    is_streaming: bool,
    pending_tools: int,
    last_activity_at: Optional[datetime],
    status_reason: Optional[str],
) -> str:
    """Collapse raw session data into the canonical UI phase."""
    if output_unseen or needs_user_action or stage in {SessionStage.WAITING_INPUT, SessionStage.ATTENTION}:
        return "needs_attention"
    if terminal_state == TerminalState.EXPLICIT_COMPLETE:
        return "stopped"
    if output_ready or stage == SessionStage.OUTPUT_READY:
        return "done"
    if is_streaming or pending_tools > 0:
        return "working"
    if stage in {SessionStage.STARTING, SessionStage.THINKING, SessionStage.TOOL_RUNNING, SessionStage.STREAMING}:
        if last_activity_at is not None and not _status_reason_is_heartbeat_like(status_reason):
            return "working"
        return "idle"
    return "idle"


def _derive_session_stage(session: Session, now: Optional[datetime] = None) -> dict[str, object]:
    """Compute canonical user-facing stage fields from raw session state."""
    now = now or datetime.now(timezone.utc)
    activity_timestamp = session.last_activity_at or session.last_event_at
    activity_age_seconds = max(0, int((now - activity_timestamp).total_seconds()))
    if (
        str(session.status_reason or "").strip().lower() == "process_keepalive"
        and session.last_activity_at is None
        and not session.is_streaming
        and session.pending_tools <= 0
    ):
        activity_age_seconds = max(activity_age_seconds, 16)
    freshness = _activity_freshness(activity_age_seconds)
    user_action_reason = _classify_user_action_reason(session)
    output_ready = session.state == SessionState.COMPLETED
    output_unseen = False
    terminal_state = session.terminal_state or TerminalState.NONE
    terminal_state_source: Optional[str] = session.terminal_state_source
    provider_stop_signal: Optional[str] = session.provider_stop_signal

    if terminal_state == TerminalState.EXPLICIT_COMPLETE:
        output_ready = True

    if output_ready and terminal_state != TerminalState.EXPLICIT_COMPLETE:
        status_reason = str(session.status_reason or "").strip().lower()
        event_name = _status_reason_event_name(session.status_reason)
        if event_name in EventNames.EXPLICIT_COMPLETION_EVENTS:
            terminal_state = TerminalState.EXPLICIT_COMPLETE
            terminal_state_source, provider_stop_signal = _EXPLICIT_STOP_METADATA.get(
                session.tool,
                ("explicit_signal", None),
            )
        elif status_reason in {
            "quiet_period_expired",
            "completed_timeout",
            "finished_unseen_retained",
            "process_exited_retained",
        } or "response.completed" in event_name:
            terminal_state = TerminalState.INFERRED_COMPLETE
            if status_reason in {"quiet_period_expired", "completed_timeout"}:
                terminal_state_source = "quiet_period"
            elif status_reason == "process_exited_retained":
                terminal_state_source = "process_exit"
            elif "response.completed" in event_name:
                terminal_state_source = "sse_response_completed"

    if user_action_reason == UserActionReason.PERMISSION:
        stage = SessionStage.WAITING_INPUT
    elif user_action_reason != UserActionReason.NONE or session.state == SessionState.ATTENTION:
        stage = SessionStage.ATTENTION
    elif terminal_state == TerminalState.EXPLICIT_COMPLETE:
        stage = SessionStage.OUTPUT_READY
    elif session.pending_tools > 0:
        stage = SessionStage.TOOL_RUNNING
    elif session.is_streaming:
        stage = SessionStage.STREAMING
    elif _status_reason_event_name(session.status_reason).endswith("response.completed"):
        stage = SessionStage.OUTPUT_READY
    elif output_ready:
        stage = SessionStage.OUTPUT_READY
    elif (
        session.state == SessionState.WORKING
        and _identity_source(session) != "native"
        and str(session.status_reason or "").strip().lower() in {"process_detected", "metrics_heartbeat_created"}
    ):
        stage = SessionStage.STARTING
    elif session.state == SessionState.WORKING:
        stage = SessionStage.THINKING
    else:
        stage = SessionStage.IDLE

    event_name = _status_reason_event_name(session.status_reason)

    if user_action_reason != UserActionReason.NONE or stage in {SessionStage.WAITING_INPUT, SessionStage.ATTENTION}:
        turn_owner = TurnOwner.BLOCKED
    elif output_ready or stage == SessionStage.OUTPUT_READY:
        turn_owner = TurnOwner.USER
    elif session.pending_tools > 0 or session.is_streaming:
        turn_owner = TurnOwner.LLM
    elif stage in {SessionStage.STARTING, SessionStage.THINKING, SessionStage.TOOL_RUNNING, SessionStage.STREAMING}:
        if session.last_activity_at is not None and not _status_reason_is_heartbeat_like(session.status_reason):
            turn_owner = TurnOwner.LLM
        elif "response.completed" in event_name or str(session.status_reason or "").strip().lower() in {
            "quiet_period_expired",
            "completed_timeout",
            "finished_unseen_retained",
            "process_exited_retained",
        }:
            turn_owner = TurnOwner.USER
        else:
            turn_owner = TurnOwner.UNKNOWN
    elif event_name.endswith("user_prompt") or event_name == str(EventNames.CODEX_CONVERSATION_STARTS):
        turn_owner = TurnOwner.LLM
    elif str(session.status_reason or "").strip().lower() in {
        "quiet_period_expired",
        "completed_timeout",
        "finished_unseen_retained",
        "process_exited_retained",
    } or "response.completed" in event_name:
        turn_owner = TurnOwner.USER
    elif session.state == SessionState.IDLE:
        turn_owner = TurnOwner.USER
    else:
        turn_owner = TurnOwner.UNKNOWN

    session_phase = _derive_session_phase(
        stage=stage,
        output_ready=output_ready,
        output_unseen=output_unseen,
        needs_user_action=stage in {SessionStage.WAITING_INPUT, SessionStage.ATTENTION},
        terminal_state=terminal_state,
        is_streaming=session.is_streaming,
        pending_tools=session.pending_tools,
        last_activity_at=session.last_activity_at,
        status_reason=session.status_reason,
    )
    terminal_context = session.terminal_context or TerminalContext()
    has_tmux_identity = bool(
        str(terminal_context.tmux_session or "").strip()
        and str(terminal_context.tmux_window or "").strip()
        and str(terminal_context.tmux_pane or "").strip()
    )
    tmux_resolution_source = str(terminal_context.tmux_resolution_source or "").strip().lower()
    if (
        session_phase in {"idle", "working", "quiet_alive"}
        and session.state == SessionState.WORKING
        and not has_tmux_identity
        and tmux_resolution_source == "missing"
    ):
        session_phase = "tmux_missing"
    elif (
        session_phase == "idle"
        and session.state == SessionState.WORKING
        and _status_reason_is_heartbeat_like(session.status_reason)
    ):
        session_phase = "quiet_alive"

    return {
        "stage": stage,
        "stage_label": _STAGE_LABELS[stage],
        "stage_detail": _humanize_status_reason(session),
        "stage_class": f"stage-{str(stage.value)}",
        "stage_visual_state": _STAGE_VISUAL_STATES[stage],
        "stage_rank": _STAGE_RANKS[stage],
        "needs_user_action": stage in {SessionStage.WAITING_INPUT, SessionStage.ATTENTION},
        "user_action_reason": user_action_reason,
        "output_ready": output_ready,
        "output_unseen": output_unseen,
        "llm_stopped": terminal_state == TerminalState.EXPLICIT_COMPLETE,
        "terminal_state": terminal_state,
        "terminal_state_at": session.terminal_state_at.isoformat() if session.terminal_state_at else None,
        "terminal_state_label": _TERMINAL_STATE_LABELS.get(terminal_state, ""),
        "terminal_state_source": terminal_state_source,
        "provider_stop_signal": provider_stop_signal,
        "session_phase": session_phase,
        "session_phase_label": _SESSION_PHASE_LABELS.get(session_phase, "Idle"),
        "turn_owner": turn_owner,
        "turn_owner_label": _TURN_OWNER_LABELS.get(turn_owner, "Unknown"),
        "activity_substate": stage,
        "activity_substate_label": _STAGE_LABELS[stage],
        "activity_freshness": freshness,
        "activity_age_seconds": activity_age_seconds,
        "last_activity_at": session.last_activity_at.isoformat() if session.last_activity_at else None,
        "identity_source": _identity_source(session),
        "lifecycle_source": _lifecycle_source(session),
    }


class SessionTracker:
    """Tracks AI assistant sessions and manages state transitions.

    Thread-safe session management using asyncio locks.
    Emits SessionUpdate events on state changes and broadcasts
    SessionList periodically for UI recovery.
    """

    def __init__(
        self,
        output: "OutputWriter",
        quiet_period_sec: float = 10.0,  # Feature 135: Increased from 3.0 to reduce flickering
        session_timeout_sec: float = 300.0,
        completed_timeout_sec: float = 30.0,
        enable_notifications: bool = False,
        broadcast_interval_sec: float = 5.0,
    ) -> None:
        """Initialize the session tracker.

        Args:
            output: OutputWriter for emitting JSON events
            quiet_period_sec: Seconds of quiet before WORKING → COMPLETED
            session_timeout_sec: Seconds before expiring inactive sessions
            completed_timeout_sec: Seconds before COMPLETED → IDLE
            enable_notifications: Whether to send desktop notifications
            broadcast_interval_sec: Seconds between SessionList broadcasts
        """
        self.output = output
        self.quiet_period_sec = quiet_period_sec
        self.session_timeout_sec = session_timeout_sec
        self.completed_timeout_sec = completed_timeout_sec
        self.enable_notifications = enable_notifications
        self.broadcast_interval_sec = broadcast_interval_sec

        # Session storage: session_id -> Session
        self._sessions: dict[str, Session] = {}
        self._lock = asyncio.Lock()

        # Feature 135: PID cache for cross-signal correlation
        # Traces from interceptor include process.pid but native logs don't.
        # When we see a trace with PID, cache it by session_id so we can
        # correlate logs from the same session to the correct window.
        self._session_pids: dict[str, int] = {}

        # Quiet period timers: session_id -> Task
        self._quiet_timers: dict[str, asyncio.Task] = {}

        # Completed timeout timers: session_id -> Task
        self._completed_timers: dict[str, asyncio.Task] = {}

        # Notification debounce: session_id -> last notification timestamp
        # Prevents rapid-fire notifications during multi-turn conversations
        self._last_notification: dict[str, datetime] = {}
        self._notification_debounce_sec = 120.0  # Feature 136: Increased from 30.0 to reduce spam
        self._min_working_duration_sec = 5.0     # Feature 136: Min activity before notifying

        # Background tasks
        self._broadcast_task: Optional[asyncio.Task] = None
        self._expiry_task: Optional[asyncio.Task] = None
        self._running = False
        self._dirty = True
        self._broadcast_event = asyncio.Event()
        self._last_broadcast_fingerprint: Optional[str] = None
        self._broadcast_debounce_sec = 0.25

        # PID correlation cache: pid -> (expires_at_ts, window_id, project)
        self._pid_context_cache: dict[
            int, tuple[float, Optional[int], Optional[str], dict]
        ] = {}

        # Native-session mapping:
        #   collision_group_id(tool:native_id) -> set(canonical session IDs)
        # Supports concurrent sessions that share the same native session ID.
        self._native_session_map: dict[str, set[str]] = {}
        self._native_preferred_session: dict[str, str] = {}

        # Monotonic counter for fallback session keys when native session_id is absent.
        self._fallback_counter = 0

        # Feature 138: Cache session metadata sidecars written by hooks.
        # Session-keyed view supports native log correlation; pid-keyed view
        # lets the process monitor recover stronger identity on restart.
        self._metadata_file_cache: dict[str, dict[str, object]] = {}
        self._pid_metadata_cache: dict[int, dict[str, object]] = {}
        self._metadata_cache_mtime: float = 0.0
        self._metadata_watch_task: Optional[asyncio.Task] = None
        self._display_filter_stats = {
            "suppressed_missing_project": 0,
            "suppressed_non_native": 0,
        }
        self._session_diagnostics: dict[str, dict[str, object]] = {}
        self._process_stats_cache: dict[int, tuple[float, dict[str, object]]] = {}
        self._process_tree_stats_cache: dict[int, tuple[float, dict[str, object]]] = {}

    def _refresh_metadata_cache(self) -> None:
        """Fully reload the session metadata cache."""
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        metadata_patterns = (
            os.path.join(runtime_dir, "claude-session-*.json"),
            os.path.join(runtime_dir, "codex-session-*.json"),
        )
        try:
            metadata_files: list[str] = []
            for pattern in metadata_patterns:
                metadata_files.extend(glob.glob(pattern))

            if not metadata_files:
                self._metadata_file_cache.clear()
                return

            new_cache: dict[str, dict[str, object]] = {}
            new_pid_cache: dict[int, dict[str, object]] = {}
            for filepath in metadata_files:
                try:
                    with open(filepath, "r") as f:
                        data = json.load(f)
                        sid = data.get("sessionId")
                        if not sid:
                            sid = data.get("threadId") or data.get("conversationId")
                        pid = data.get("pid") or data.get("processPid")
                        if sid and pid:
                            pid_int = int(pid)
                            entry = {
                                "session_id": str(sid),
                                "pid": pid_int,
                                "tool": str(data.get("tool") or "").strip().lower() or None,
                                "project": str(data.get("projectName") or "").strip() or None,
                                "project_path": str(data.get("projectPath") or data.get("cwd") or "").strip() or None,
                                "terminal_anchor_id": str(data.get("terminalAnchorId") or "").strip() or None,
                                "tmux_session": str(data.get("tmuxSession") or "").strip() or None,
                                "tmux_window": str(data.get("tmuxWindow") or "").strip() or None,
                                "tmux_pane": str(data.get("tmuxPane") or "").strip() or None,
                                "pty": str(data.get("pty") or "").strip() or None,
                                "host_name": str(data.get("hostName") or "").strip() or None,
                                "execution_mode": str(data.get("executionMode") or "").strip().lower() or None,
                                "connection_key": str(data.get("connectionKey") or "").strip() or None,
                                "context_key": str(data.get("contextKey") or "").strip() or None,
                                "remote_target": str(data.get("remoteTarget") or "").strip() or None,
                                "updated_at": str(data.get("updatedAt") or "").strip() or None,
                            }
                            new_cache[str(sid)] = entry
                            new_pid_cache[pid_int] = entry
                except (json.JSONDecodeError, IOError, KeyError) as e:
                    logger.debug(f"Failed to read metadata file {filepath}: {e}")
                    
            if new_cache != self._metadata_file_cache or new_pid_cache != self._pid_metadata_cache:
                self._metadata_file_cache = new_cache
                self._pid_metadata_cache = new_pid_cache
                logger.debug(f"Refreshed session metadata cache: {len(self._metadata_file_cache)} entries")

        except OSError as e:
            logger.debug(f"Failed to scan metadata files: {e}")

    def _collect_process_stats(self, pid: Optional[int], now_ts: float) -> dict[str, object]:
        """Collect lightweight process stats for the session rail."""
        default_stats: dict[str, object] = {
            "process_running": False,
            "rss_mb": None,
            "cpu_percent": None,
            "uptime_seconds": None,
            "stats_sampled_at": None,
            "stats_source": "missing",
        }
        if pid is None or int(pid) <= 0:
            return dict(default_stats)

        pid_int = int(pid)
        cached = self._process_stats_cache.get(pid_int)
        if cached and (now_ts - cached[0]) < _PROCESS_STATS_CACHE_TTL_SEC:
            return dict(cached[1])

        try:
            process = psutil.Process(pid_int)
            with process.oneshot():
                running = process.is_running() and process.status() != psutil.STATUS_ZOMBIE
                stats = dict(default_stats)
                stats["process_running"] = bool(running)
                if running:
                    stats["rss_mb"] = round(process.memory_info().rss / (1024 * 1024), 1)
                    stats["cpu_percent"] = round(float(process.cpu_percent(interval=None)), 1)
                    stats["uptime_seconds"] = max(0, int(now_ts - process.create_time()))
                    stats["stats_sampled_at"] = datetime.fromtimestamp(now_ts, timezone.utc).isoformat()
                    stats["stats_source"] = "local_process"
                self._process_stats_cache[pid_int] = (now_ts, stats)
                return dict(stats)
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess, OSError, ValueError):
            pass

        self._process_stats_cache[pid_int] = (now_ts, default_stats)
        return dict(default_stats)

    def _collect_process_tree_stats(self, root_pid: Optional[int], now_ts: float) -> dict[str, object]:
        """Collect aggregate process-tree stats for a tmux pane/session surface."""
        default_stats: dict[str, object] = {
            "process_tree_rss_mb": None,
            "process_tree_cpu_percent": None,
            "process_count": None,
        }
        if root_pid is None or int(root_pid) <= 0:
            return dict(default_stats)

        pid_int = int(root_pid)
        cached = self._process_tree_stats_cache.get(pid_int)
        if cached and (now_ts - cached[0]) < _PROCESS_STATS_CACHE_TTL_SEC:
            return dict(cached[1])

        try:
            root_process = psutil.Process(pid_int)
            processes = [root_process]
            try:
                processes.extend(root_process.children(recursive=True))
            except (psutil.Error, OSError):
                pass

            live_processes: list[psutil.Process] = []
            rss_bytes = 0
            cpu_percent = 0.0
            for process in processes:
                try:
                    with process.oneshot():
                        if not process.is_running() or process.status() == psutil.STATUS_ZOMBIE:
                            continue
                        live_processes.append(process)
                        rss_bytes += int(process.memory_info().rss)
                        cpu_percent += float(process.cpu_percent(interval=None))
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess, OSError, ValueError):
                    continue

            stats = {
                "process_tree_rss_mb": round(rss_bytes / (1024 * 1024), 1) if live_processes else None,
                "process_tree_cpu_percent": round(cpu_percent, 1) if live_processes else None,
                "process_count": len(live_processes) if live_processes else None,
            }
            self._process_tree_stats_cache[pid_int] = (now_ts, stats)
            return dict(stats)
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess, OSError, ValueError):
            pass

        self._process_tree_stats_cache[pid_int] = (now_ts, default_stats)
        return dict(default_stats)

    async def _metadata_watch_loop(self) -> None:
        """Watch the runtime directory for changes to session metadata files."""
        import shutil
        inotify_cmd = shutil.which("inotifywait")
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")

        # Initial load
        self._refresh_metadata_cache()

        if not inotify_cmd:
            logger.debug("inotifywait not found, falling back to polling for metadata cache")
            while self._running:
                await asyncio.sleep(2.0)
                self._refresh_metadata_cache()
            return

        while self._running:
            try:
                proc = await asyncio.create_subprocess_exec(
                    inotify_cmd, "-m", "-q", "-e", "create,modify,delete,moved_to", "--format", "%f",
                    runtime_dir,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.DEVNULL,
                )
                if proc.stdout is None:
                    continue
                    
                while self._running:
                    line = await proc.stdout.readline()
                    if not line:
                        break
                    filename = line.decode().strip()
                    if filename.startswith("claude-session-") or filename.startswith("codex-session-"):
                        self._refresh_metadata_cache()
            except asyncio.CancelledError:
                if 'proc' in locals() and proc.returncode is None:
                    proc.terminate()
                break
            except Exception as e:
                logger.debug(f"Metadata watch loop error: {e}")
                await asyncio.sleep(2.0)

    def _load_session_metadata_pid(self, session_id: str) -> Optional[int]:
        """Look up PID for a session ID from hook-written metadata files.

        Feature 138: Claude Code hooks write $XDG_RUNTIME_DIR/claude-session-{PID}.json
        with {sessionId, pid}. Codex notify hook writes
        $XDG_RUNTIME_DIR/codex-session-{PID}.json with the same sessionId/pid
        bridge. This method scans those files to find the PID for a given
        session_id, enabling window correlation for native OTEL logs which may
        omit process.pid.

        Args:
            session_id: The session ID (UUID) to look up

        Returns:
            PID if found in metadata files, None otherwise
        """
        # Cache is now maintained asynchronously by _metadata_watch_loop
        entry = self._metadata_file_cache.get(session_id) or {}
        pid = entry.get("pid")
        try:
            return int(pid) if pid is not None else None
        except (TypeError, ValueError):
            return None

    def _load_session_metadata(self, session_id: str) -> dict[str, object]:
        entry = self._metadata_file_cache.get(session_id)
        return dict(entry) if isinstance(entry, dict) else {}

    def _load_pid_metadata(self, pid: int) -> dict[str, object]:
        entry = self._pid_metadata_cache.get(pid)
        return dict(entry) if isinstance(entry, dict) else {}

    async def _ensure_process_session_for_pid(
        self,
        tool: AITool,
        pid: int,
    ) -> Optional[str]:
        """Bootstrap or refresh a live session from an already-running AI process."""
        self._refresh_metadata_cache()

        resolved_window_id, resolved_project, resolved_terminal_context = await self._resolve_window_context(pid)
        terminal_context = (
            dict(resolved_terminal_context)
            if isinstance(resolved_terminal_context, dict)
            else {}
        )
        metadata = self._load_pid_metadata(pid)
        live_tmux_target = bool(
            terminal_context.get("tmux_session")
            or terminal_context.get("tmux_window")
        )

        for key in (
            "terminal_anchor_id",
            "binding_anchor_id",
            "binding_state",
            "binding_source",
            "host_name",
            "execution_mode",
            "connection_key",
            "context_key",
            "remote_target",
        ):
            if terminal_context.get(key):
                continue
            value = metadata.get(key)
            if value:
                terminal_context[key] = value

        if not live_tmux_target:
            terminal_context["tmux_session"] = None
            terminal_context["tmux_window"] = None
            terminal_context["tmux_pane"] = None

        terminal_context = self._normalize_terminal_binding_context(
            terminal_context,
            window_id=resolved_window_id,
        )

        project = str(metadata.get("project") or "").strip() or resolved_project
        project_path = str(metadata.get("project_path") or "").strip() or None
        if not project and project_path:
            project = self._project_from_path(project_path)

        native_session_id = str(metadata.get("session_id") or "").strip() or None
        if not self._has_full_tmux_identity(terminal_context):
            return None
        if not project and not project_path:
            return None

        context_fingerprint = self._build_context_fingerprint(
            pid,
            resolved_window_id,
            terminal_context,
            project,
            project_path,
        )
        native_group_id = self._build_native_group_id(tool, native_session_id)
        desired_session_id = (
            self._compose_native_session_key(native_group_id, context_fingerprint)
            if native_group_id
            else f"{tool.value}:pid:{pid}"
        )
        provider = TOOL_PROVIDER.get(tool, Provider.ANTHROPIC)
        now = datetime.now(timezone.utc)

        async with self._lock:
            canonical_session_id = desired_session_id
            session: Optional[Session] = None

            if native_group_id:
                resolved_native_key = self._resolve_native_session_key_unlocked(
                    native_group_id=native_group_id,
                    context_fingerprint=context_fingerprint,
                    client_pid=pid,
                    terminal_context=terminal_context,
                    window_id=resolved_window_id,
                    preferred_project=project,
                )
                if resolved_native_key:
                    canonical_session_id = resolved_native_key
                    session = self._sessions.get(canonical_session_id)

            if session is None:
                session = self._sessions.get(canonical_session_id)

            if session is None:
                if len(self._sessions) >= MAX_SESSIONS:
                    self._evict_oldest_idle_session()
                session = Session(
                    session_id=canonical_session_id,
                    native_session_id=native_session_id,
                    context_fingerprint=context_fingerprint if native_session_id else None,
                    collision_group_id=native_group_id if native_session_id else None,
                    identity_confidence=(
                        IdentityConfidence.NATIVE
                        if native_session_id
                        else IdentityConfidence.PID
                    ),
                    tool=tool,
                    provider=provider,
                    state=SessionState.WORKING,
                    project=project,
                    project_path=project_path,
                    window_id=resolved_window_id,
                    pid=pid,
                    trace_id=None,
                    created_at=now,
                    last_event_at=now,
                    last_activity_at=None,
                    state_changed_at=now,
                    state_seq=1,
                    status_reason="process_detected",
                )
                self._sessions[canonical_session_id] = session
                logger.info(
                    "Bootstrapped live session %s for %s (pid=%s, window_id=%s, project=%s)",
                    canonical_session_id,
                    tool.value,
                    pid,
                    resolved_window_id,
                    project,
                )

            if native_session_id and native_group_id:
                desired_native_session_id = self._compose_native_session_key(
                    native_group_id,
                    context_fingerprint,
                )
                if (
                    desired_native_session_id != session.session_id
                    and desired_native_session_id not in self._sessions
                ):
                    rekeyed = self._rekey_session_unlocked(
                        session.session_id,
                        desired_native_session_id,
                    )
                    if rekeyed:
                        session = rekeyed
                session.native_session_id = native_session_id
                session.collision_group_id = native_group_id
                if context_fingerprint:
                    session.context_fingerprint = context_fingerprint
                self._register_native_session_unlocked(native_group_id, session.session_id)
                self._session_pids[native_group_id] = pid
                self._session_pids[native_session_id] = pid

            session.pid = pid
            session.project = project or session.project
            session.project_path = project_path or session.project_path
            session.window_id = resolved_window_id if resolved_window_id is not None else session.window_id
            session.last_event_at = now
            if not session.native_session_id and not native_session_id:
                if session.state != SessionState.WORKING:
                    session.state = SessionState.WORKING
                    session.state_changed_at = now
                    session.state_seq += 1
                session.status_reason = "process_detected"
            if not native_session_id and session.identity_confidence != IdentityConfidence.NATIVE:
                session.identity_confidence = IdentityConfidence.PID

            session.terminal_context.window_id = session.window_id
            session.terminal_context.terminal_anchor_id = terminal_context.get("terminal_anchor_id")
            session.terminal_context.binding_anchor_id = terminal_context.get("binding_anchor_id")
            session.terminal_context.binding_state = terminal_context.get("binding_state")
            session.terminal_context.binding_source = terminal_context.get("binding_source")
            session.terminal_context.anchor_lookup = terminal_context.get("anchor_lookup")
            session.terminal_context.tmux_session = terminal_context.get("tmux_session")
            session.terminal_context.tmux_window = terminal_context.get("tmux_window")
            session.terminal_context.tmux_pane = terminal_context.get("tmux_pane")
            session.terminal_context.tmux_socket = terminal_context.get("tmux_socket")
            session.terminal_context.tmux_server_key = terminal_context.get("tmux_server_key")
            session.terminal_context.tmux_resolution_source = terminal_context.get("tmux_resolution_source")
            session.terminal_context.pane_pid = terminal_context.get("pane_pid")
            session.terminal_context.pane_title = terminal_context.get("pane_title")
            session.terminal_context.pane_active = terminal_context.get("pane_active")
            session.terminal_context.window_active = terminal_context.get("window_active")
            session.terminal_context.pty = terminal_context.get("pty")
            session.terminal_context.host_name = terminal_context.get("host_name")
            session.terminal_context.execution_mode = terminal_context.get("execution_mode")
            session.terminal_context.connection_key = terminal_context.get("connection_key")
            session.terminal_context.context_key = terminal_context.get("context_key")
            session.terminal_context.remote_target = terminal_context.get("remote_target")
            session.terminal_context = TerminalContext(
                **self._normalize_terminal_binding_context(
                    session.terminal_context.model_dump(),
                    window_id=session.window_id,
                )
            )

            self._session_pids[session.session_id] = pid
            self._apply_tracking_contract_unlocked(session)
            self._mark_dirty_unlocked()
            return session.session_id

    @staticmethod
    def _parse_datetime(value: Optional[str]) -> Optional[datetime]:
        raw = str(value or "").strip()
        if not raw:
            return None
        try:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        else:
            parsed = parsed.astimezone(timezone.utc)
        if parsed.year < _MIN_VALID_SESSION_TIMESTAMP_YEAR:
            return None
        return parsed

    async def _restore_previous_snapshot(self) -> None:
        """Best-effort bootstrap from the last emitted live session snapshot.

        This preserves native identity and richer stage hints across monitor
        restarts, avoiding a temporary collapse to PID-only "Starting" chips.
        """
        snapshot_path = getattr(self.output, "json_file_path", None)
        if snapshot_path is None or not snapshot_path.exists():
            return

        try:
            with open(snapshot_path, "r", encoding="utf-8") as f:
                payload = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            logger.debug("Failed to load previous session snapshot: %s", exc)
            return

        items = payload.get("sessions", [])
        if not isinstance(items, list):
            return

        now = datetime.now(timezone.utc)
        restored = 0
        async with self._lock:
            for raw in items:
                if not isinstance(raw, dict):
                    continue
                session_id = str(raw.get("session_id") or "").strip()
                if not session_id or session_id in self._sessions:
                    continue

                tool_raw = str(raw.get("tool") or "").strip().lower()
                try:
                    tool = self._normalize_tool(tool_raw)
                    state = SessionState(str(raw.get("state") or SessionState.IDLE.value))
                except Exception:
                    continue
                if state not in _BOOTSTRAP_RESTOREABLE_STATES:
                    continue

                updated_at = self._parse_datetime(raw.get("updated_at")) or now
                last_activity_at = self._parse_datetime(raw.get("last_activity_at"))
                age_seconds = max(0.0, (now - updated_at).total_seconds())
                if state == SessionState.COMPLETED:
                    if age_seconds > self.completed_timeout_sec:
                        continue
                elif age_seconds > self.session_timeout_sec:
                    continue

                provider = TOOL_PROVIDER.get(tool, Provider.ANTHROPIC)
                terminal_context_raw = raw.get("terminal_context", {}) or {}
                if not isinstance(terminal_context_raw, dict):
                    terminal_context_raw = {}
                identity_raw = str(raw.get("identity_confidence") or IdentityConfidence.HEURISTIC.value)
                try:
                    identity_confidence = IdentityConfidence(identity_raw)
                except ValueError:
                    identity_confidence = IdentityConfidence.HEURISTIC

                session = Session(
                    session_id=session_id,
                    native_session_id=str(raw.get("native_session_id") or "").strip() or None,
                    context_fingerprint=str(raw.get("context_fingerprint") or "").strip() or None,
                    collision_group_id=str(raw.get("collision_group_id") or "").strip() or None,
                    identity_confidence=identity_confidence,
                    tool=tool,
                    provider=provider,
                    state=state,
                    project=str(
                        raw.get("session_project")
                        or raw.get("project")
                        or raw.get("display_project")
                        or ""
                    ).strip() or None,
                    project_path=str(raw.get("project_path") or "").strip() or None,
                    window_id=raw.get("window_id"),
                    pid=raw.get("pid"),
                    trace_id=str(raw.get("trace_id") or "").strip() or None,
                    created_at=updated_at,
                    last_event_at=updated_at,
                    last_activity_at=last_activity_at,
                    state_changed_at=updated_at,
                    state_seq=int(raw.get("state_seq", 1) or 1),
                    status_reason=str(raw.get("status_reason") or "").strip() or "restored_snapshot",
                    pending_tools=int(raw.get("pending_tools", 0) or 0),
                    is_streaming=bool(raw.get("is_streaming", False)),
                    terminal_state=raw.get("terminal_state") or TerminalState.NONE,
                    terminal_state_at=(
                        updated_at if str(raw.get("terminal_state") or "").strip() else None
                    ),
                    terminal_state_source=str(raw.get("terminal_state_source") or "").strip() or None,
                    provider_stop_signal=str(raw.get("provider_stop_signal") or "").strip() or None,
                )
                session.terminal_context.window_id = raw.get("window_id")
                for key in (
                    "terminal_anchor_id",
                    "binding_anchor_id",
                    "binding_state",
                    "binding_source",
                    "anchor_lookup",
                    "tmux_session",
                    "tmux_window",
                    "tmux_pane",
                    "tmux_socket",
                    "tmux_server_key",
                    "tmux_resolution_source",
                    "pty",
                    "host_name",
                    "execution_mode",
                    "connection_key",
                    "context_key",
                    "remote_target",
                ):
                    value = terminal_context_raw.get(key)
                    if value is not None:
                        setattr(session.terminal_context, key, value)
                normalized_terminal_context = self._normalize_terminal_binding_context(
                    session.terminal_context.model_dump(),
                    window_id=session.window_id,
                )
                session.terminal_context = TerminalContext(**normalized_terminal_context)
                if (
                    str(getattr(session.terminal_context, "execution_mode", "") or "").strip().lower() == "local"
                    and (
                        session.terminal_context.tmux_session
                        or session.terminal_context.tmux_window
                        or session.terminal_context.tmux_pane
                        or session.terminal_context.pty
                    )
                    and not tmux_target_exists(
                        tmux_session=session.terminal_context.tmux_session,
                        tmux_window=session.terminal_context.tmux_window,
                        tmux_pane=session.terminal_context.tmux_pane,
                        pty=session.terminal_context.pty,
                        tmux_socket=session.terminal_context.tmux_socket,
                        tmux_server_key=session.terminal_context.tmux_server_key,
                    )
                ):
                    session.terminal_context.tmux_session = None
                    session.terminal_context.tmux_window = None
                    session.terminal_context.tmux_pane = None
                    session.terminal_context.tmux_socket = None
                    session.terminal_context.tmux_server_key = None
                    session.terminal_context.tmux_resolution_source = "missing"
                    session.terminal_context.pane_pid = None
                    session.terminal_context.pane_title = None
                    session.terminal_context.pane_active = None
                    session.terminal_context.window_active = None
                    session.terminal_context.pty = None

                self._sessions[session_id] = session
                self._apply_tracking_contract_unlocked(session)
                if session.pid is not None:
                    pid_int = int(session.pid)
                    self._session_pids[session_id] = pid_int
                    if session.native_session_id:
                        self._session_pids[session.native_session_id] = pid_int
                if session.collision_group_id:
                    self._register_native_session_unlocked(session.collision_group_id, session_id)
                    if session.pid is not None:
                        self._session_pids[session.collision_group_id] = int(session.pid)
                restored += 1

            if restored:
                self._mark_dirty_unlocked()
        if restored:
            logger.info("Restored %s sessions from previous snapshot", restored)

    async def start(self) -> None:
        """Start background tasks for broadcasting and expiry."""
        self._running = True

        await self._restore_previous_snapshot()

        # Start broadcast worker
        self._broadcast_task = asyncio.create_task(self._broadcast_loop())

        # Start session expiry checker
        self._expiry_task = asyncio.create_task(self._expiry_loop())
        
        # Start metadata file watcher
        self._metadata_watch_task = asyncio.create_task(self._metadata_watch_loop())

        # Emit initial snapshot so consumers have deterministic startup state
        self._broadcast_event.set()
        logger.info("Session tracker started")

    async def stop(self) -> None:
        """Stop background tasks and cleanup."""
        self._running = False
        self._broadcast_event.set()

        # Cancel all timers
        for task in self._quiet_timers.values():
            task.cancel()
        for task in self._completed_timers.values():
            task.cancel()

        # Cancel background tasks
        if self._broadcast_task:
            self._broadcast_task.cancel()
        if self._expiry_task:
            self._expiry_task.cancel()
        if self._metadata_watch_task:
            self._metadata_watch_task.cancel()

        logger.info("Session tracker stopped")

    def _evict_oldest_idle_session(self) -> bool:
        """Evict the oldest IDLE session to make room for new sessions.

        Feature 137: Memory management to prevent unbounded growth.

        Returns:
            True if a session was evicted, False if no IDLE sessions exist.
        """
        # Find all IDLE sessions with their last_event_at timestamps
        idle_sessions = [
            (sid, s.last_event_at)
            for sid, s in self._sessions.items()
            if s.state == SessionState.IDLE
        ]

        if not idle_sessions:
            # No IDLE sessions to evict - log warning but allow creation
            # This means all sessions are actively WORKING or COMPLETED
            logger.warning(
                f"Session limit ({MAX_SESSIONS}) reached with no IDLE sessions to evict. "
                "Consider increasing MAX_SESSIONS or reducing session_timeout_sec."
            )
            return False

        # Sort by last_event_at (oldest first) and evict
        idle_sessions.sort(key=lambda x: x[1])
        oldest_id = idle_sessions[0][0]
        oldest_session = self._sessions.pop(oldest_id)

        # Clean up associated data
        self._remove_session_indexes_unlocked(oldest_id, oldest_session)
        if oldest_id in self._quiet_timers:
            self._quiet_timers[oldest_id].cancel()
            del self._quiet_timers[oldest_id]
        if oldest_id in self._completed_timers:
            self._completed_timers[oldest_id].cancel()
            del self._completed_timers[oldest_id]

        logger.info(
            f"Evicted oldest IDLE session {oldest_id} (tool={oldest_session.tool}, "
            f"last_event={oldest_session.last_event_at}) to stay under limit"
        )
        return True

    async def get_health(self) -> dict:
        """Get health status and metrics for self-telemetry.

        Feature 137: Expose internal metrics for debugging and monitoring.

        Returns:
            Dict with health status and metrics.
        """
        async with self._lock:
            # Count sessions by state (handle both enum and string values)
            state_counts = {}
            for session in self._sessions.values():
                state = session.state.value if hasattr(session.state, 'value') else str(session.state)
                state_counts[state] = state_counts.get(state, 0) + 1

            # Count sessions by tool (handle both enum and string values)
            tool_counts = {}
            for session in self._sessions.values():
                if session.tool is None:
                    tool = "unknown"
                elif hasattr(session.tool, 'value'):
                    tool = session.tool.value
                else:
                    tool = str(session.tool)
                tool_counts[tool] = tool_counts.get(tool, 0) + 1

            return {
                "status": "healthy" if self._running else "stopped",
                "running": self._running,
                "sessions": {
                    "total": len(self._sessions),
                    "max_limit": MAX_SESSIONS,
                    "by_state": state_counts,
                    "by_tool": tool_counts,
                },
                "timers": {
                    "quiet_timers": len(self._quiet_timers),
                    "completed_timers": len(self._completed_timers),
                },
                "native_identity": {
                    "groups": len(self._native_session_map),
                    "collisions": sum(
                        1
                        for group in self._native_session_map.values()
                        if len([sid for sid in group if sid in self._sessions]) > 1
                    ),
                },
                "display_filter": dict(self._display_filter_stats),
                "config": {
                    "quiet_period_sec": self.quiet_period_sec,
                    "session_timeout_sec": self.session_timeout_sec,
                    "completed_timeout_sec": self.completed_timeout_sec,
                    "broadcast_interval_sec": self.broadcast_interval_sec,
                    "broadcast_debounce_sec": self._broadcast_debounce_sec,
                    "notifications_enabled": self.enable_notifications,
                },
            }

    @staticmethod
    def _normalize_tool(tool: Optional[AITool]) -> AITool:
        if isinstance(tool, AITool):
            return tool
        if isinstance(tool, str):
            for candidate in AITool:
                if tool == candidate.value:
                    return candidate
        return AITool.CLAUDE_CODE

    @staticmethod
    def _extract_native_session_id(event: TelemetryEvent) -> Optional[str]:
        if event.session_id and isinstance(event.session_id, str):
            session_id = event.session_id.strip()
            if session_id:
                return session_id
        return None

    @staticmethod
    def _tool_name(tool: Optional[AITool]) -> str:
        if isinstance(tool, AITool):
            return tool.value
        if isinstance(tool, str) and tool.strip():
            return tool.strip()
        return "unknown"

    @classmethod
    def _build_native_group_id(
        cls,
        tool: Optional[AITool],
        native_session_id: Optional[str],
    ) -> Optional[str]:
        if not native_session_id:
            return None
        return f"{cls._tool_name(tool)}:{native_session_id}"

    @staticmethod
    def _compose_native_session_key(
        native_group_id: str,
        context_fingerprint: Optional[str],
    ) -> str:
        if context_fingerprint:
            return f"{native_group_id}:{context_fingerprint}"
        return native_group_id

    @staticmethod
    def _build_context_fingerprint(
        client_pid: Optional[int],
        window_id: Optional[int],
        terminal_context: dict,
        project: Optional[str],
        project_path: Optional[str],
    ) -> Optional[str]:
        parts: list[str] = []
        has_tmux_identity = SessionTracker._has_full_tmux_identity(terminal_context)

        def add_part(name: str, value: Optional[object]) -> None:
            if value is None:
                return
            text = str(value).strip()
            if not text:
                return
            parts.append(f"{name}={text}")

        if not has_tmux_identity:
            return None
        add_part("tmux_server", terminal_context.get("tmux_server_key"))
        add_part("tmux_socket", terminal_context.get("tmux_socket"))
        add_part("pane", terminal_context.get("tmux_pane"))
        add_part("pty", terminal_context.get("pty"))
        add_part("tmux_session", terminal_context.get("tmux_session"))
        add_part("tmux_window", terminal_context.get("tmux_window"))
        add_part("host", terminal_context.get("host_name"))
        add_part("mode", terminal_context.get("execution_mode"))
        add_part("connection", terminal_context.get("connection_key"))
        add_part("context", terminal_context.get("context_key"))
        add_part("window", window_id)
        add_part("pid", client_pid)
        add_part("project_path", project_path)
        add_part("project", project)

        if not parts:
            return None

        raw = "|".join(parts)
        return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:12]

    @staticmethod
    def _build_surface_key(
        terminal_context: TerminalContext,
        *,
        window_id: Optional[int],
    ) -> tuple[str, Optional[str], Optional[str]]:
        """Build canonical tracked surface identity for exported sessions."""
        context_key = str(getattr(terminal_context, "context_key", "") or "").strip()
        tmux_session = str(getattr(terminal_context, "tmux_session", "") or "").strip()
        tmux_window = str(getattr(terminal_context, "tmux_window", "") or "").strip()
        tmux_pane = str(getattr(terminal_context, "tmux_pane", "") or "").strip()
        tmux_server_key = str(getattr(terminal_context, "tmux_server_key", "") or "").strip()
        pane_tty = str(getattr(terminal_context, "pty", "") or "").strip()

        if tmux_pane:
            parts = [
                context_key or "unknown-context",
                tmux_server_key or "unknown-tmux-server",
                tmux_session or "unknown-session",
                tmux_window or "unknown-window",
                tmux_pane,
            ]
            if pane_tty:
                parts.append(pane_tty)
            pane_label = " ".join(
                part
                for part in (
                    tmux_window or None,
                    tmux_pane or None,
                )
                if part
            ) or tmux_pane
            return "tmux-pane", "::".join(parts), pane_label

        return "unsupported", None, None

    @staticmethod
    def _session_list_identity_confidence_rank(value: IdentityConfidence | str | None) -> int:
        """Return a deterministic rank for canonical surface selection."""
        normalized = str(getattr(value, "value", value) or "").strip().lower()
        return {
            "native": 4,
            "pid": 3,
            "pane": 2,
            "heuristic": 1,
        }.get(normalized, 0)

    def _register_native_session_unlocked(self, group_id: str, session_id: str) -> None:
        bucket = self._native_session_map.setdefault(group_id, set())
        bucket.add(session_id)
        self._native_preferred_session[group_id] = session_id

    def _select_preferred_native_session_unlocked(
        self, group_id: str
    ) -> Optional[str]:
        bucket = self._native_session_map.get(group_id)
        if not bucket:
            return None
        live_ids = [sid for sid in bucket if sid in self._sessions]
        if not live_ids:
            self._native_session_map.pop(group_id, None)
            self._native_preferred_session.pop(group_id, None)
            return None

        preferred = max(
            live_ids,
            key=lambda sid: (
                state_priority(SessionState(self._sessions[sid].state)),
                self._sessions[sid].last_event_at.timestamp(),
                sid,
            ),
        )
        self._native_preferred_session[group_id] = preferred
        return preferred

    def _unregister_native_session_unlocked(self, group_id: str, session_id: str) -> None:
        bucket = self._native_session_map.get(group_id)
        if not bucket:
            return
        bucket.discard(session_id)
        if not bucket:
            self._native_session_map.pop(group_id, None)
            self._native_preferred_session.pop(group_id, None)
            return
        if self._native_preferred_session.get(group_id) == session_id:
            self._select_preferred_native_session_unlocked(group_id)

    def _resolve_native_session_key_unlocked(
        self,
        native_group_id: str,
        context_fingerprint: Optional[str],
        client_pid: Optional[int],
        terminal_context: dict,
        window_id: Optional[int],
        preferred_project: Optional[str],
    ) -> Optional[str]:
        bucket = self._native_session_map.get(native_group_id)
        if not bucket:
            return None
        live_ids = [sid for sid in bucket if sid in self._sessions]
        if not live_ids:
            self._native_session_map.pop(native_group_id, None)
            self._native_preferred_session.pop(native_group_id, None)
            return None

        if context_fingerprint:
            exact_id = self._compose_native_session_key(
                native_group_id, context_fingerprint
            )
            if exact_id in live_ids:
                self._native_preferred_session[native_group_id] = exact_id
                return exact_id

        if client_pid is not None:
            for sid in live_ids:
                session = self._sessions[sid]
                if session.pid == client_pid:
                    self._native_preferred_session[native_group_id] = sid
                    return sid

        pane = terminal_context.get("tmux_pane")
        if pane:
            preferred_server_key = str(terminal_context.get("tmux_server_key") or "").strip()
            for sid in live_ids:
                session = self._sessions[sid]
                if session.terminal_context.tmux_pane != pane:
                    continue
                if preferred_server_key and (
                    str(session.terminal_context.tmux_server_key or "").strip()
                    != preferred_server_key
                ):
                    continue
                if (
                    not preferred_server_key
                    and terminal_context.get("tmux_session")
                    and str(session.terminal_context.tmux_session or "").strip()
                    != str(terminal_context.get("tmux_session") or "").strip()
                ):
                    continue
                self._native_preferred_session[native_group_id] = sid
                return sid

        pty = terminal_context.get("pty")
        if pty:
            for sid in live_ids:
                session = self._sessions[sid]
                if session.terminal_context.pty == pty:
                    self._native_preferred_session[native_group_id] = sid
                    return sid

        if window_id is not None:
            for sid in live_ids:
                session = self._sessions[sid]
                if session.window_id == window_id:
                    self._native_preferred_session[native_group_id] = sid
                    return sid

        if preferred_project:
            for sid in live_ids:
                session = self._sessions[sid]
                if self._project_names_match(preferred_project, session.project):
                    self._native_preferred_session[native_group_id] = sid
                    return sid

        if len(live_ids) == 1:
            chosen = live_ids[0]
            self._native_preferred_session[native_group_id] = chosen
            return chosen

        # When context fingerprint is present but no match across multiple
        # existing sessions, caller should create a distinct collision key.
        if context_fingerprint:
            return None

        preferred = self._native_preferred_session.get(native_group_id)
        if preferred in live_ids:
            return preferred

        return self._select_preferred_native_session_unlocked(native_group_id)

    def _lookup_native_session_from_raw_id_unlocked(
        self, raw_native_session_id: str
    ) -> Optional[str]:
        # Direct canonical or group lookup.
        if raw_native_session_id in self._sessions:
            return raw_native_session_id
        if raw_native_session_id in self._native_session_map:
            return self._select_preferred_native_session_unlocked(raw_native_session_id)

        matched_groups = []
        for group_id in self._native_session_map.keys():
            _, _, native_id = group_id.partition(":")
            if native_id == raw_native_session_id:
                matched_groups.append(group_id)

        if not matched_groups:
            return None
        if len(matched_groups) == 1:
            return self._select_preferred_native_session_unlocked(matched_groups[0])

        candidate_ids = []
        for group_id in matched_groups:
            resolved = self._select_preferred_native_session_unlocked(group_id)
            if resolved and resolved in self._sessions:
                candidate_ids.append(resolved)
        if not candidate_ids:
            return None
        return max(
            candidate_ids,
            key=lambda sid: (
                state_priority(SessionState(self._sessions[sid].state)),
                self._sessions[sid].last_event_at.timestamp(),
                sid,
            ),
        )

    def _build_session_id(
        self,
        event: TelemetryEvent,
        native_session_id: Optional[str],
        context_fingerprint: Optional[str] = None,
    ) -> str:
        """Build canonical session key with native IDs taking priority."""
        tool_name = self._tool_name(event.tool)
        if native_session_id:
            native_group_id = self._build_native_group_id(event.tool, native_session_id)
            if native_group_id:
                return self._compose_native_session_key(
                    native_group_id, context_fingerprint
                )

        pid = event.attributes.get("process.pid") or event.attributes.get("pid")
        if pid is not None:
            return f"{tool_name}:pid:{pid}"

        self._fallback_counter += 1
        return f"{tool_name}:ephemeral:{time.monotonic_ns()}:{self._fallback_counter}"

    def _extract_client_pid(
        self,
        session_id: str,
        native_session_id: Optional[str],
        native_group_id: Optional[str],
        event: TelemetryEvent,
    ) -> Optional[int]:
        """Extract and normalize PID from event/session metadata."""
        _ = native_group_id
        client_pid = event.attributes.get("process.pid") or event.attributes.get("pid")

        if client_pid is None:
            client_pid = self._session_pids.get(session_id)

        if client_pid is None and native_group_id:
            client_pid = self._session_pids.get(native_group_id)

        if client_pid is None and native_session_id:
            client_pid = self._session_pids.get(native_session_id)

        if client_pid is None and native_session_id:
            client_pid = self._load_session_metadata_pid(native_session_id)

        if client_pid is None:
            return None

        try:
            return int(client_pid)
        except (ValueError, TypeError):
            return None

    def _remove_session_indexes_unlocked(self, session_id: str, session: Session) -> None:
        self._session_pids.pop(session_id, None)
        if session.native_session_id:
            self._session_pids.pop(session.native_session_id, None)

        native_group_id = session.collision_group_id
        if not native_group_id and session.native_session_id:
            native_group_id = self._build_native_group_id(
                self._normalize_tool(session.tool), session.native_session_id
            )
        if native_group_id:
            self._session_pids.pop(native_group_id, None)
            self._unregister_native_session_unlocked(native_group_id, session_id)

        self._last_notification.pop(session_id, None)
        self._session_diagnostics.pop(session_id, None)

    async def _resolve_window_context(
        self, pid: int
    ) -> tuple[Optional[int], Optional[str], dict]:
        """Resolve PID -> daemon-owned terminal anchor context with short TTL cache."""
        now = datetime.now(timezone.utc).timestamp()
        if len(self._pid_context_cache) > 64:
            self._pid_context_cache = {
                cache_pid: cache_entry
                for cache_pid, cache_entry in self._pid_context_cache.items()
                if cache_entry[0] > now
            }

        cached = self._pid_context_cache.get(pid)
        if cached and cached[0] > now:
            return cached[1], cached[2], dict(cached[3])

        window_id: Optional[int] = None
        project: Optional[str] = None
        terminal_context = {
            "terminal_anchor_id": None,
            "reported_terminal_anchor_id": None,
            "binding_anchor_id": None,
            "binding_state": "unresolved",
            "binding_source": None,
            "anchor_lookup": None,
            "tmux_session": None,
            "tmux_window": None,
            "tmux_pane": None,
            "tmux_socket": None,
            "tmux_server_key": None,
            "tmux_resolution_source": "missing",
            "pane_pid": None,
            "pane_title": None,
            "pane_active": None,
            "window_active": None,
            "pty": None,
            "execution_mode": None,
            "connection_key": None,
            "context_key": None,
            "remote_target": None,
        }
        try:
            i3pm_env = get_process_i3pm_env(pid)
            project = i3pm_env.get("I3PM_PROJECT_NAME") if i3pm_env else None
            if i3pm_env:
                terminal_context["reported_terminal_anchor_id"] = (
                    i3pm_env.get("I3PM_TERMINAL_ANCHOR_ID")
                    or i3pm_env.get("I3PM_APP_ID")
                )
                terminal_context["terminal_anchor_id"] = terminal_context["reported_terminal_anchor_id"]
                remote_user = str(i3pm_env.get("I3PM_REMOTE_USER") or "").strip()
                remote_host = str(i3pm_env.get("I3PM_REMOTE_HOST") or "").strip()
                remote_port = str(i3pm_env.get("I3PM_REMOTE_PORT") or "").strip() or "22"
                remote_target = ""
                if remote_host:
                    remote_target = (
                        f"{remote_user}@{remote_host}:{remote_port}"
                        if remote_user
                        else f"{remote_host}:{remote_port}"
                    )
                terminal_context["execution_mode"] = (
                    i3pm_env.get("I3PM_CONTEXT_VARIANT")
                    or i3pm_env.get("I3PM_EXECUTION_MODE")
                )
                terminal_context["connection_key"] = i3pm_env.get("I3PM_CONNECTION_KEY")
                terminal_context["context_key"] = i3pm_env.get("I3PM_CONTEXT_KEY")
                terminal_context["remote_target"] = remote_target or None
                explicit_tmux_socket = str(i3pm_env.get("I3PM_TMUX_SOCKET") or "").strip()
                explicit_tmux_server_key = str(i3pm_env.get("I3PM_TMUX_SERVER_KEY") or "").strip()
                if explicit_tmux_socket:
                    terminal_context["tmux_socket"] = explicit_tmux_socket
                if explicit_tmux_server_key:
                    terminal_context["tmux_server_key"] = explicit_tmux_server_key
                if explicit_tmux_socket or explicit_tmux_server_key:
                    terminal_context["tmux_resolution_source"] = "explicit"
            raw_tmux_context = await get_tmux_context_for_pid(pid)
            tmux_context = (
                dict(raw_tmux_context)
                if isinstance(raw_tmux_context, dict)
                else {}
            )
            if not isinstance(raw_tmux_context, dict):
                logger.debug(
                    "PID %s tmux context returned non-dict %s; using empty context",
                    pid,
                    type(raw_tmux_context).__name__,
                )
            for key, value in tmux_context.items():
                terminal_context[key] = value
            if not project:
                project = str(tmux_context.get("project_name") or "").strip() or None

            terminal_context = self._normalize_terminal_binding_context(terminal_context)
            anchor_id = str(
                terminal_context.get("binding_anchor_id")
                or terminal_context.get("terminal_anchor_id")
                or ""
            ).strip()
            if anchor_id:
                anchor_context = await query_daemon_for_terminal_anchor(anchor_id)
                if isinstance(anchor_context, dict):
                    terminal_context["anchor_lookup"] = (
                        anchor_context.get("binding")
                        or anchor_context.get("error")
                        or "unknown"
                    )
                    window_id_raw = anchor_context.get("window_id")
                    try:
                        window_id = int(window_id_raw) if window_id_raw is not None else None
                    except (TypeError, ValueError):
                        window_id = None
                    project = str(
                        anchor_context.get("project_name")
                        or project
                        or ""
                    ).strip() or None
                    if window_id is not None:
                        terminal_context["window_id"] = window_id
                        terminal_context["binding_anchor_id"] = anchor_id
                        terminal_context["binding_source"] = (
                            terminal_context.get("binding_source") or "daemon_anchor_lookup"
                        )
                    window_context = get_window_context_by_id(window_id) if window_id is not None else {}
                    if isinstance(window_context, dict):
                        for key in ("execution_mode", "connection_key", "context_key", "remote_target"):
                            value = window_context.get(key)
                            if value:
                                terminal_context[key] = value
        except Exception as e:
            logger.debug(f"PID correlation failed for {pid}: {e}")

        terminal_context = self._normalize_terminal_binding_context(terminal_context, window_id=window_id)
        ttl = 5.0 if window_id else 1.0
        self._pid_context_cache[pid] = (now + ttl, window_id, project, terminal_context)
        return window_id, project, dict(terminal_context)

    @staticmethod
    def _project_names_match(
        preferred_project: Optional[str], candidate_project: Optional[str]
    ) -> bool:
        """Best-effort project name matching across short/qualified forms."""
        try:
            from i3_project_manager.core.identity import project_names_match
            return project_names_match(preferred_project, candidate_project)
        except ImportError:
            # Fallback if module is missing
            if not preferred_project or not candidate_project:
                return False
            preferred = preferred_project.strip().lower()
            candidate = candidate_project.strip().lower()
            if preferred == candidate:
                return True
            import re
            return re.sub(r"[^a-z0-9]+", "-", preferred).strip("-") == re.sub(r"[^a-z0-9]+", "-", candidate).strip("-")

    @staticmethod
    def _normalize_project_path(value: Optional[str]) -> Optional[str]:
        """Normalize filesystem path for project comparisons."""
        if not value or not isinstance(value, str):
            return None
        try:
            expanded = os.path.expanduser(value.strip())
            if not expanded:
                return None
            return os.path.realpath(expanded)
        except Exception:
            return value

    @staticmethod
    def _parse_context_key(value: Optional[str]) -> dict[str, str]:
        """Parse context key format '<qualified>::<mode>::<connection>'."""
        raw = str(value or "").strip()
        parsed = {
            "context_key": raw,
            "qualified_name": "",
            "execution_mode": "",
            "connection_key": "",
        }
        if not raw:
            return parsed

        parts = raw.split("::")
        if len(parts) < 3:
            return parsed

        parsed["qualified_name"] = "::".join(parts[:-2]).strip()
        parsed["execution_mode"] = str(parts[-2]).strip().lower()
        parsed["connection_key"] = str(parts[-1]).strip()
        return parsed

    @staticmethod
    def _session_project_candidates(raw_project: Optional[str]) -> tuple[set[str], set[str]]:
        """Return exact/prefix project candidates from project names or paths."""
        exact: set[str] = set()
        prefixes: set[str] = set()
        value = str(raw_project or "").strip()
        if not value:
            return exact, prefixes

        if "/" in value:
            if ":" in value:
                exact.add(value)
                prefixes.add(value.split(":", 1)[0])
            else:
                prefixes.add(value)

        normalized_path = None
        if value.startswith("/") or value.startswith("~"):
            normalized_path = SessionTracker._normalize_project_path(value)
        if normalized_path:
            parts = [segment for segment in normalized_path.split(os.sep) if segment]
            for idx, segment in enumerate(parts):
                if segment != "repos":
                    continue
                if idx + 3 >= len(parts):
                    continue
                account = parts[idx + 1].strip()
                repo = parts[idx + 2].strip()
                branch = parts[idx + 3].strip()
                if not account or not repo:
                    continue
                prefixes.add(f"{account}/{repo}")
                if branch:
                    exact.add(f"{account}/{repo}:{branch}")
                break

        return exact, prefixes

    @staticmethod
    def _project_session_suffix(project_name: Optional[str]) -> str:
        """Convert qualified project name to the common tmux session suffix."""
        name = str(project_name or "").strip()
        if ":" not in name:
            return ""
        repo_part, branch = name.split(":", 1)
        repo_name = repo_part.split("/")[-1].strip()
        if not repo_name or not branch:
            return ""
        return f"{repo_name}/{branch}"

    @staticmethod
    def _projects_align(left: Optional[str], right: Optional[str]) -> bool:
        """Check whether two project labels refer to the same logical project."""
        left_exact, left_prefixes = SessionTracker._session_project_candidates(left)
        right_exact, right_prefixes = SessionTracker._session_project_candidates(right)
        return bool(
            (left_exact and right_exact and left_exact.intersection(right_exact))
            or (left_prefixes and right_prefixes and left_prefixes.intersection(right_prefixes))
        )

    @classmethod
    def _tmux_session_project_hints(cls) -> dict[str, str]:
        """Map normalized tmux session names to unique discovered worktree projects."""
        repos_file = os.path.expanduser("~/.config/i3/repos.json")
        if not os.path.exists(repos_file):
            _DISCOVERED_TMUX_PROJECT_HINT_CACHE.update({
                "mtime_ns": None,
                "size": None,
                "mapping": {},
            })
            return {}

        try:
            stat_result = os.stat(repos_file)
        except OSError:
            return {}

        cached_mapping = _DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("mapping")
        if (
            _DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("mtime_ns") == stat_result.st_mtime_ns
            and _DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("size") == stat_result.st_size
            and isinstance(cached_mapping, dict)
        ):
            return dict(cached_mapping)

        try:
            with open(repos_file, "r") as f:
                payload = json.load(f)
        except (OSError, json.JSONDecodeError):
            return {}

        repositories = payload.get("repositories", []) if isinstance(payload, dict) else []
        grouped: dict[str, set[str]] = {}
        for repo in repositories if isinstance(repositories, list) else []:
            if not isinstance(repo, dict):
                continue
            account = str(repo.get("account") or "").strip()
            repo_name = str(repo.get("name") or "").strip()
            if not account or not repo_name:
                continue
            for worktree in repo.get("worktrees", []) if isinstance(repo.get("worktrees", []), list) else []:
                if not isinstance(worktree, dict):
                    continue
                branch = str(worktree.get("branch") or "").strip()
                if not branch:
                    continue
                qualified_name = f"{account}/{repo_name}:{branch}"
                suffix_key = cls._normalize_tmux_session_key(cls._project_session_suffix(qualified_name))
                if not suffix_key:
                    continue
                grouped.setdefault(suffix_key, set()).add(qualified_name)

        mapping = {
            session_key: sorted(qualified_names)[0]
            for session_key, qualified_names in grouped.items()
            if len(qualified_names) == 1
        }
        _DISCOVERED_TMUX_PROJECT_HINT_CACHE.update({
            "mtime_ns": stat_result.st_mtime_ns,
            "size": stat_result.st_size,
            "mapping": dict(mapping),
        })
        return mapping

    @staticmethod
    def _normalize_tmux_session_key(value: Optional[str]) -> str:
        try:
            from i3_project_manager.core.identity import normalize_session_name_key
            return normalize_session_name_key(value)
        except ImportError:
            raw = str(value or "").strip().lower()
            return "".join(ch if ch.isalnum() else "-" for ch in raw).strip("-")

    def _resolve_export_project_labels(self, session: Session) -> dict[str, str]:
        """Resolve canonical project fields from daemon-backed anchor state only."""
        session_project = str(session.project or "").strip()
        project_path = str(session.project_path or "").strip()
        if not session_project and project_path:
            session_project = self._project_from_path(project_path) or project_path

        display_project = session_project or "unknown"
        focus_project = session_project
        return {
            "session_project": session_project,
            "window_project": session_project,
            "focus_project": focus_project,
            "display_project": display_project,
            "project_source": "anchor",
        }

    def _set_session_diagnostic_unlocked(
        self,
        session: Session,
        reason: Optional[str],
        *,
        detail: Optional[str] = None,
    ) -> None:
        key = session.session_id
        reason_text = str(reason or "").strip()
        if not reason_text:
            session.focusable = True
            session.invalid_reason = None
            self._session_diagnostics.pop(key, None)
            return

        session.focusable = False
        session.invalid_reason = reason_text
        self._session_diagnostics[key] = {
            "session_id": session.session_id,
            "tool": str(session.tool.value if hasattr(session.tool, "value") else session.tool),
            "pid": session.pid,
            "terminal_anchor_id": session.terminal_context.terminal_anchor_id,
            "reason": reason_text,
            "detail": str(detail or reason_text),
            "updated_at": session.last_event_at.isoformat(),
        }

    def _apply_tracking_contract_unlocked(self, session: Session) -> None:
        terminal_context = session.terminal_context
        has_tmux_identity = self._has_full_tmux_identity(terminal_context.model_dump())
        binding_anchor_id = str(terminal_context.binding_anchor_id or "").strip()
        if not has_tmux_identity:
            self._set_session_diagnostic_unlocked(
                session,
                "missing_tmux_identity",
                detail="Tracked session is missing full tmux pane identity.",
            )
            return
        if not str(session.project or "").strip() and not str(session.project_path or "").strip():
            self._set_session_diagnostic_unlocked(
                session,
                "missing_project",
                detail="Tracked session has no project context available.",
            )
            return
        if session.window_id is None:
            if self._session_is_remote_projection_candidate(session):
                self._set_session_diagnostic_unlocked(session, None)
                return
            if has_tmux_identity:
                terminal_context.binding_state = "tmux_present_unbound"
                self._set_session_diagnostic_unlocked(session, None)
                return
            anchor_lookup = str(getattr(session.terminal_context, "anchor_lookup", "") or "").strip()
            reason = "unknown_terminal_anchor" if anchor_lookup in {"not_found", "daemon_unavailable"} else "anchor_window_unbound"
            self._set_session_diagnostic_unlocked(
                session,
                reason,
                detail=(
                    "Telemetry references a terminal anchor unknown to the daemon."
                    if reason == "unknown_terminal_anchor"
                    else "Daemon knows the terminal anchor but no live Sway window is bound."
                ),
            )
            return
        if binding_anchor_id:
            terminal_context.binding_state = (
                terminal_context.binding_state
                if str(terminal_context.binding_state or "").strip() == "rebound_local"
                else "bound_local"
            )
        else:
            terminal_context.binding_state = "tmux_present_unbound"
        self._set_session_diagnostic_unlocked(session, None)

    @staticmethod
    def _session_is_remote_projection_candidate(session: Session) -> bool:
        """Allow SSH sessions to be exported before local UI binds them to a window."""
        terminal_context = session.terminal_context
        execution_mode = str(getattr(terminal_context, "execution_mode", "") or "").strip().lower()
        connection_key = str(getattr(terminal_context, "connection_key", "") or "").strip()
        context_key = str(getattr(terminal_context, "context_key", "") or "").strip()
        has_project = bool(str(session.project or "").strip() or str(session.project_path or "").strip())
        has_terminal_identity = SessionTracker._has_full_tmux_identity(terminal_context.model_dump())
        return bool(
            execution_mode == "ssh"
            and has_project
            and has_terminal_identity
            and (
                context_key
                or (connection_key and not connection_key.startswith("local@"))
            )
        )

    @staticmethod
    def _project_from_path(path_value: Optional[str]) -> Optional[str]:
        """Best-effort derive <account>/<repo>:<branch> from a repos path."""
        normalized = SessionTracker._normalize_project_path(path_value)
        if not normalized:
            return None
        try:
            parts = [segment for segment in normalized.split(os.sep) if segment]
            for idx, segment in enumerate(parts):
                if segment != "repos":
                    continue
                if idx + 3 >= len(parts):
                    continue
                account = parts[idx + 1].strip()
                repo = parts[idx + 2].strip()
                branch = parts[idx + 3].strip()
                if not account or not repo or not branch:
                    continue
                return f"{account}/{repo}:{branch}"
        except Exception:
            return None
        return None

    def _extract_project_context(
        self, event: TelemetryEvent
    ) -> tuple[Optional[str], Optional[str]]:
        """Extract project display name and canonical path from event attributes."""
        attrs = event.attributes
        project: Optional[str] = None
        project_path = None

        for key in ("project", "project_name", "i3pm.project_name"):
            value = attrs.get(key)
            if isinstance(value, str) and value.strip():
                project = value.strip()
                break

        for key in ("project_path", "cwd", "working_directory", "i3pm.project_path"):
            value = attrs.get(key)
            if isinstance(value, str) and value.strip():
                project_path = self._normalize_project_path(value)
                break

        project_from_path = self._project_from_path(project_path)
        if project_from_path:
            if not project:
                project = project_from_path
            elif not self._project_names_match(project, project_from_path):
                # Resource/env project names can become stale after context
                # switches; path-derived identity is more reliable.
                logger.debug(
                    "Project mismatch detected; preferring path-derived project: raw=%s path=%s derived=%s",
                    project,
                    project_path,
                    project_from_path,
                )
                project = project_from_path
        elif not project and project_path:
            project = project_path

        return project, project_path

    @staticmethod
    def _extract_terminal_context_from_event(event: TelemetryEvent) -> dict:
        attrs = event.attributes
        reported_anchor = attrs.get("terminal.anchor_id") or attrs.get("i3pm.terminal_anchor_id")
        return {
            "terminal_anchor_id": reported_anchor,
            "reported_terminal_anchor_id": reported_anchor,
            "binding_anchor_id": None,
            "binding_state": "unresolved",
            "binding_source": None,
            "anchor_lookup": None,
            "tmux_session": attrs.get("terminal.tmux.session") or attrs.get("tmux.session"),
            "tmux_window": attrs.get("terminal.tmux.window") or attrs.get("tmux.window"),
            "tmux_pane": attrs.get("terminal.tmux.pane") or attrs.get("tmux.pane"),
            "tmux_socket": attrs.get("terminal.tmux.socket") or attrs.get("tmux.socket"),
            "tmux_server_key": attrs.get("terminal.tmux.server_key") or attrs.get("tmux.server_key"),
            "tmux_resolution_source": attrs.get("terminal.tmux.resolution_source") or attrs.get("tmux.resolution_source"),
            "pty": attrs.get("terminal.pty") or attrs.get("pty"),
            "ai_trace_token": attrs.get("i3pm.ai_trace_token"),
            "host_name": attrs.get("host.name") or attrs.get("service.instance.id"),
            "execution_mode": attrs.get("terminal.execution_mode") or attrs.get("i3pm.execution_mode"),
            "connection_key": attrs.get("terminal.connection_key") or attrs.get("i3pm.connection_key"),
            "context_key": attrs.get("terminal.context_key") or attrs.get("i3pm.context_key"),
            "remote_target": attrs.get("terminal.remote_target") or attrs.get("i3pm.remote_target"),
        }

    @staticmethod
    def _has_full_tmux_identity(terminal_context: dict) -> bool:
        return bool(
            str(terminal_context.get("tmux_session") or "").strip()
            and str(terminal_context.get("tmux_window") or "").strip()
            and str(terminal_context.get("tmux_pane") or "").strip()
        )

    @classmethod
    def _normalize_terminal_binding_context(
        cls,
        terminal_context: dict,
        *,
        window_id: Optional[int] = None,
    ) -> dict:
        normalized = dict(terminal_context or {})
        if window_id is not None:
            normalized["window_id"] = window_id

        has_tmux_identity = cls._has_full_tmux_identity(normalized)
        raw_terminal_anchor = str(normalized.get("terminal_anchor_id") or "").strip() or None
        reported_anchor = str(normalized.get("reported_terminal_anchor_id") or "").strip() or None
        binding_anchor = str(normalized.get("binding_anchor_id") or "").strip() or None
        binding_source = str(normalized.get("binding_source") or "").strip() or None

        if has_tmux_identity and not binding_anchor and raw_terminal_anchor:
            binding_anchor = raw_terminal_anchor
            binding_source = binding_source or (
                "tmux_metadata"
                if str(normalized.get("tmux_resolution_source") or "").strip() not in {"", "missing"}
                else "process_env"
            )

        if has_tmux_identity:
            if binding_anchor and window_id is not None:
                binding_state = (
                    "rebound_local"
                    if reported_anchor and reported_anchor != binding_anchor
                    else "bound_local"
                )
            else:
                binding_state = "tmux_present_unbound"
        else:
            binding_anchor = None
            binding_source = None
            binding_state = "unresolved"

        normalized["binding_anchor_id"] = binding_anchor
        normalized["binding_state"] = binding_state
        normalized["binding_source"] = binding_source
        normalized["terminal_anchor_id"] = binding_anchor or raw_terminal_anchor
        return normalized

    def _resolve_context_from_process_sessions_unlocked(
        self,
        tool: AITool,
        preferred_project: Optional[str] = None,
        preferred_terminal_context: Optional[dict] = None,
    ) -> tuple[Optional[int], Optional[str], Optional[int], dict, IdentityConfidence]:
        """Fallback correlation using active process-backed sessions.

        Used when telemetry lacks PID but we already have process-backed sessions
        for the same tool with concrete context.
        Caller must hold self._lock.
        """
        candidates = [
            s
            for s in self._sessions.values()
            if s.tool == tool
            and s.pid is not None
            and s.state != SessionState.EXPIRED
        ]
        if not candidates:
            return None, None, None, {}, IdentityConfidence.HEURISTIC

        preferred_tmux_pane = (
            preferred_terminal_context.get("tmux_pane")
            if preferred_terminal_context
            else None
        )
        if preferred_tmux_pane:
            preferred_server_key = (
                str(preferred_terminal_context.get("tmux_server_key") or "").strip()
                if preferred_terminal_context
                else ""
            )
            pane_matched = [
                s
                for s in candidates
                if s.terminal_context.tmux_pane == preferred_tmux_pane
                and (
                    not preferred_server_key
                    or str(s.terminal_context.tmux_server_key or "").strip()
                    == preferred_server_key
                )
                and (
                    not preferred_terminal_context.get("tmux_session")
                    or s.terminal_context.tmux_session
                    == preferred_terminal_context.get("tmux_session")
                )
            ]
            if pane_matched:
                chosen = max(pane_matched, key=lambda s: s.last_event_at.timestamp())
                return (
                    chosen.window_id,
                    chosen.project,
                    chosen.pid,
                    chosen.terminal_context.model_dump(),
                    IdentityConfidence.PANE,
                )

        if preferred_project:
            project_matched = [
                s
                for s in candidates
                if self._project_names_match(preferred_project, s.project)
            ]
            if project_matched:
                candidates = project_matched

        contexts = {
            (
                s.window_id,
                s.project,
                s.terminal_context.tmux_server_key,
                s.terminal_context.tmux_session,
                s.terminal_context.tmux_window,
                s.terminal_context.tmux_pane,
            )
            for s in candidates
        }
        if len(contexts) > 1:
            focused_window_id, _ = get_focused_window_info()
            if focused_window_id is not None:
                focused_candidates = [
                    s for s in candidates if s.window_id == focused_window_id
                ]
                if len(focused_candidates) == 1:
                    chosen = max(
                        focused_candidates, key=lambda s: s.last_event_at.timestamp()
                    )
                    return (
                        chosen.window_id,
                        chosen.project,
                        chosen.pid,
                        chosen.terminal_context.model_dump(),
                        IdentityConfidence.HEURISTIC,
                    )
                if len(focused_candidates) > 1:
                    # Ambiguous in the focused window; let caller apply
                    # stronger native-to-process candidate binding logic.
                    return None, None, None, {}, IdentityConfidence.HEURISTIC
            return None, None, None, {}, IdentityConfidence.HEURISTIC

        chosen = max(candidates, key=lambda s: s.last_event_at.timestamp())
        confidence = (
            IdentityConfidence.PID if chosen.window_id is not None else IdentityConfidence.HEURISTIC
        )
        return (
            chosen.window_id,
            chosen.project,
            chosen.pid,
            chosen.terminal_context.model_dump(),
            confidence,
        )

    def _bind_native_to_process_candidate_unlocked(
        self,
        session: Session,
        tool: AITool,
    ) -> bool:
        """Bind unresolved native session to an unclaimed process-backed session.

        Native OTEL events may omit process.pid/tmux fields. When several tool
        processes are active, pick an unclaimed process-backed session so each
        native session can map to a distinct terminal pane/window.
        Caller must hold self._lock.
        """
        if (
            session.window_id is not None
            or session.terminal_context.tmux_pane
            or session.terminal_context.pty
        ):
            return False

        # Feature 139: Exact correlation using ai_trace_token
        trace_token = session.terminal_context.ai_trace_token
        if trace_token:
            for s in self._sessions.values():
                if (
                    s.tool == tool
                    and s.pid is not None
                    and s.terminal_context.ai_trace_token == trace_token
                    and s.session_id != session.session_id
                ):
                    session.window_id = s.window_id
                    session.project = s.project or session.project
                    session.pid = s.pid
                    
                    # Merge terminal contexts while preserving the token
                    merged_context = s.terminal_context.model_dump()
                    merged_context["ai_trace_token"] = trace_token
                    session.terminal_context = TerminalContext(**merged_context)
                    
                    s.native_session_id = session.session_id
                    return True

        candidates = [
            s
            for s in self._sessions.values()
            if s.tool == tool
            and s.pid is not None
            and s.native_session_id is None
            and s.state != SessionState.EXPIRED
        ]
        if not candidates:
            return False

        used_pids = {
            s.pid
            for s in self._sessions.values()
            if s.tool == tool and s.native_session_id and s.pid is not None
        }
        unclaimed = [s for s in candidates if s.pid not in used_pids]
        pool = unclaimed if unclaimed else candidates

        if session.project:
            project_matched = [
                s
                for s in pool
                if not s.project or self._project_names_match(session.project, s.project)
            ]
            if project_matched:
                pool = project_matched

        # Prefer freshly-created process sessions to avoid binding new native
        # events to long-lived unrelated Codex processes.
        recent_cutoff = datetime.now(timezone.utc) - timedelta(seconds=45)
        recent_pool = [s for s in pool if s.created_at >= recent_cutoff]
        if recent_pool:
            pool = recent_pool

        chosen = max(
            pool,
            key=lambda s: (
                s.created_at.timestamp(),
                s.last_event_at.timestamp(),
                int(s.pid or 0),
            ),
        )

        if chosen.window_id is not None and session.window_id is None:
            session.window_id = chosen.window_id
            session.terminal_context.window_id = chosen.window_id
        if chosen.project and not session.project:
            session.project = chosen.project
        if chosen.project_path and not session.project_path:
            session.project_path = chosen.project_path

        if chosen.pid is not None and session.pid is None:
            session.pid = chosen.pid
            self._session_pids[session.session_id] = chosen.pid
            if session.collision_group_id:
                self._session_pids[session.collision_group_id] = chosen.pid

        for key in (
            "binding_anchor_id",
            "binding_state",
            "binding_source",
            "tmux_socket",
            "tmux_server_key",
            "tmux_resolution_source",
            "tmux_session",
            "tmux_window",
            "tmux_pane",
            "pty",
            "host_name",
            "execution_mode",
            "connection_key",
            "context_key",
            "remote_target",
        ):
            if not getattr(session.terminal_context, key):
                value = getattr(chosen.terminal_context, key)
                if value:
                    setattr(session.terminal_context, key, value)

        if session.window_id is None and session.project is None and session.pid is None:
            return False

        session.status_reason = "window_correlated_process_candidate"
        logger.info(
            "Process candidate correlation: %s -> pid=%s pane=%s window=%s",
            session.session_id,
            session.pid,
            session.terminal_context.tmux_pane,
            session.window_id,
        )
        return True

    def _mark_dirty_unlocked(self) -> None:
        """Mark output as dirty and signal broadcast worker.

        Caller must hold _lock when mutating session state.
        """
        self._dirty = True
        self._broadcast_event.set()

    def _rekey_session_unlocked(self, old_id: str, new_id: str) -> Optional[Session]:
        """Re-key a session and associated timer/cache maps.

        Caller must hold self._lock.
        """
        if old_id == new_id:
            return self._sessions.get(new_id)

        session = self._sessions.pop(old_id, None)
        if not session:
            return self._sessions.get(new_id)

        session.session_id = new_id
        self._sessions[new_id] = session

        if old_id in self._quiet_timers:
            self._quiet_timers[new_id] = self._quiet_timers.pop(old_id)
        if old_id in self._completed_timers:
            self._completed_timers[new_id] = self._completed_timers.pop(old_id)
        if old_id in self._last_notification:
            self._last_notification[new_id] = self._last_notification.pop(old_id)
        if old_id in self._session_pids:
            self._session_pids[new_id] = self._session_pids.pop(old_id)
        if session.collision_group_id:
            bucket = self._native_session_map.get(session.collision_group_id)
            if bucket and old_id in bucket:
                bucket.discard(old_id)
                bucket.add(new_id)
            if self._native_preferred_session.get(session.collision_group_id) == old_id:
                self._native_preferred_session[session.collision_group_id] = new_id

        return session

    @staticmethod
    def _session_is_resolved_for_display(session: Session, now_ts: float) -> bool:
        """Whether a session should be visible in project-scoped UI output."""
        _ = now_ts
        terminal_context = session.terminal_context
        execution_mode = str(
            getattr(terminal_context, "execution_mode", "") or ""
        ).strip().lower()
        connection_key = str(
            getattr(terminal_context, "connection_key", "") or ""
        ).strip()
        context_key = str(getattr(terminal_context, "context_key", "") or "").strip()
        has_terminal_identity = SessionTracker._has_full_tmux_identity(terminal_context.model_dump())
        has_project = bool(str(session.project or "").strip() or str(session.project_path or "").strip())
        has_window_binding = session.window_id is not None
        has_remote_projection = bool(
            execution_mode == "ssh"
            and has_terminal_identity
            and (
                context_key
                or (connection_key and not connection_key.startswith("local@"))
            )
        )
        has_local_tmux_projection = bool(
            execution_mode != "ssh"
            and has_terminal_identity
        )
        return bool(
            not session.invalid_reason
            and (
                has_window_binding
                or has_remote_projection
                or has_local_tmux_projection
            )
            and has_project
        )

    async def process_event(self, event: TelemetryEvent) -> None:
        """Process a telemetry event and update session state.

        Args:
            event: Parsed telemetry event from OTLP receiver
        """
        event_terminal_context_raw = self._extract_terminal_context_from_event(event)
        native_session_id = self._extract_native_session_id(event)
        native_group_id = self._build_native_group_id(event.tool, native_session_id)

        provisional_session_id = self._build_session_id(
            event, native_session_id, None
        )
        explicit_pid_raw = (
            event.attributes.get("process.pid")
            if event.attributes.get("process.pid") is not None
            else event.attributes.get("pid")
        )
        explicit_client_pid: Optional[int] = None
        if explicit_pid_raw is not None:
            try:
                explicit_client_pid = int(explicit_pid_raw)
            except (TypeError, ValueError):
                explicit_client_pid = None

        if explicit_client_pid is not None and not pid_exists(explicit_client_pid):
            logger.debug(
                "Dropping telemetry for exited pid=%s event=%s session=%s",
                explicit_client_pid,
                event.event_name,
                native_session_id or provisional_session_id,
            )
            return

        client_pid = self._extract_client_pid(
            provisional_session_id,
            native_session_id,
            native_group_id,
            event,
        )
        event_project, event_project_path = self._extract_project_context(event)

        resolved_window_id: Optional[int] = None
        resolved_project: Optional[str] = None
        resolved_terminal_context: dict = {}
        # Skip expensive /proc + daemon resolution for established NATIVE sessions
        # that already have window context.  The session won't move terminals mid-run.
        _skip_resolve = False
        if client_pid is not None and native_session_id:
            _sid_hint = self._session_pids.get(native_group_id) or self._session_pids.get(
                f"{event.tool}:{native_session_id}"
            )
            if _sid_hint is not None:
                _s = self._sessions.get(
                    f"{event.tool}:{native_session_id}:{_sid_hint}"
                ) or self._sessions.get(
                    f"{event.tool}:{native_session_id}"
                )
                if not _s:
                    # Try looking up by the sid hint itself as session_id
                    for _candidate_sid, _candidate in self._sessions.items():
                        if (
                            _candidate.native_session_id == native_session_id
                            and _candidate.identity_confidence == IdentityConfidence.NATIVE
                        ):
                            _s = _candidate
                            break
                if (
                    _s
                    and _s.identity_confidence == IdentityConfidence.NATIVE
                    and _s.window_id is not None
                    and _s.project is not None
                    and (
                        not event_project
                        or self._projects_align(_s.project, event_project)
                    )
                ):
                    _skip_resolve = True
        if client_pid is not None and not _skip_resolve:
            (
                resolved_window_id,
                resolved_project,
                resolved_terminal_context,
            ) = await self._resolve_window_context(client_pid)

        event_terminal_context = dict(event_terminal_context_raw)
        resolved_context_keys: set[str] = set()
        authoritative_resolved_keys = {
            "tmux_session",
            "tmux_window",
            "tmux_pane",
            "tmux_socket",
            "tmux_server_key",
            "tmux_resolution_source",
            "pty",
            "host_name",
            "execution_mode",
            "connection_key",
            "context_key",
            "remote_target",
        }
        for key, value in resolved_terminal_context.items():
            if not value:
                continue
            if key in authoritative_resolved_keys:
                event_terminal_context[key] = value
                resolved_context_keys.add(key)
                continue
            if not event_terminal_context.get(key):
                event_terminal_context[key] = value
                resolved_context_keys.add(key)

        explicit_anchor_id = str(
            event_terminal_context.get("terminal_anchor_id") or ""
        ).strip()
        if explicit_anchor_id and resolved_window_id is None:
            anchor_context = await query_daemon_for_terminal_anchor(explicit_anchor_id)
            if isinstance(anchor_context, dict):
                event_terminal_context["anchor_lookup"] = (
                    anchor_context.get("binding")
                    or anchor_context.get("error")
                    or "unknown"
                )
                window_id_raw = anchor_context.get("window_id")
                try:
                    resolved_window_id = int(window_id_raw) if window_id_raw is not None else None
                except (TypeError, ValueError):
                    resolved_window_id = None
                anchor_project = str(anchor_context.get("project_name") or "").strip()
                if anchor_project:
                    resolved_project = anchor_project

        event_terminal_context = self._normalize_terminal_binding_context(
            event_terminal_context,
            window_id=resolved_window_id,
        )

        project_for_identity = event_project or resolved_project
        has_explicit_terminal_identity = bool(
            event_terminal_context_raw.get("tmux_session")
            or event_terminal_context_raw.get("tmux_window")
            or event_terminal_context_raw.get("tmux_pane")
            or event_terminal_context_raw.get("pty")
            or event_terminal_context_raw.get("execution_mode")
            or event_terminal_context_raw.get("connection_key")
            or event_terminal_context_raw.get("context_key")
            or event_terminal_context_raw.get("remote_target")
        )
        allow_native_context_override = bool(
            explicit_client_pid is not None or has_explicit_terminal_identity
        )
        context_fingerprint = self._build_context_fingerprint(
            client_pid,
            resolved_window_id,
            event_terminal_context,
            project_for_identity,
            event_project_path,
        )
        desired_session_id = self._build_session_id(
            event, native_session_id, context_fingerprint
        )

        async with self._lock:
            now = datetime.now(timezone.utc)
            tool = self._normalize_tool(event.tool)
            provider = TOOL_PROVIDER.get(tool, Provider.ANTHROPIC)

            session_id = desired_session_id
            if native_group_id:
                resolved_native_key = self._resolve_native_session_key_unlocked(
                    native_group_id=native_group_id,
                    context_fingerprint=context_fingerprint,
                    client_pid=client_pid,
                    terminal_context=event_terminal_context,
                    window_id=resolved_window_id,
                    preferred_project=project_for_identity,
                )
                if resolved_native_key:
                    session_id = resolved_native_key

            session = self._sessions.get(session_id)

            # If we first saw this process without native session ID, upgrade that
            # process-keyed session once native session ID appears.
            if session is None and native_session_id and client_pid is not None:
                pid_key = f"{tool.value}:pid:{client_pid}"
                if pid_key in self._sessions:
                    if session_id not in self._sessions or session_id == pid_key:
                        upgraded = self._rekey_session_unlocked(pid_key, session_id)
                        if upgraded:
                            session = upgraded
                            logger.info(
                                "Upgraded process session %s -> native session %s",
                                pid_key,
                                session_id,
                            )

            if session is None:
                if native_session_id:
                    identity_confidence = IdentityConfidence.NATIVE
                elif client_pid is not None:
                    identity_confidence = IdentityConfidence.PID
                elif self._has_full_tmux_identity(event_terminal_context):
                    identity_confidence = IdentityConfidence.PANE
                else:
                    identity_confidence = IdentityConfidence.HEURISTIC

                project = event_project or resolved_project
                session = Session(
                    session_id=session_id,
                    native_session_id=native_session_id,
                    context_fingerprint=context_fingerprint if native_session_id else None,
                    collision_group_id=native_group_id if native_session_id else None,
                    identity_confidence=identity_confidence,
                    tool=tool,
                    provider=provider,
                    state=SessionState.IDLE,
                    project=project,
                    project_path=event_project_path,
                    window_id=resolved_window_id,
                    pid=client_pid,
                    trace_id=event.trace_id,
                    created_at=now,
                    last_event_at=now,
                    last_activity_at=event.timestamp if _event_counts_as_activity(event) else None,
                    state_changed_at=now,
                    state_seq=1,
                    status_reason="created",
                )
                session.terminal_context.window_id = resolved_window_id
                session.terminal_context.terminal_anchor_id = event_terminal_context.get(
                    "terminal_anchor_id"
                )
                session.terminal_context.binding_anchor_id = event_terminal_context.get(
                    "binding_anchor_id"
                )
                session.terminal_context.binding_state = event_terminal_context.get(
                    "binding_state"
                )
                session.terminal_context.binding_source = event_terminal_context.get(
                    "binding_source"
                )
                session.terminal_context.anchor_lookup = event_terminal_context.get(
                    "anchor_lookup"
                )
                session.terminal_context.tmux_session = event_terminal_context.get(
                    "tmux_session"
                )
                session.terminal_context.tmux_window = event_terminal_context.get(
                    "tmux_window"
                )
                session.terminal_context.tmux_pane = event_terminal_context.get(
                    "tmux_pane"
                )
                session.terminal_context.tmux_socket = event_terminal_context.get(
                    "tmux_socket"
                )
                session.terminal_context.tmux_server_key = event_terminal_context.get(
                    "tmux_server_key"
                )
                session.terminal_context.tmux_resolution_source = event_terminal_context.get(
                    "tmux_resolution_source"
                )
                session.terminal_context.pane_pid = event_terminal_context.get("pane_pid")
                session.terminal_context.pane_title = event_terminal_context.get("pane_title")
                session.terminal_context.pane_active = event_terminal_context.get("pane_active")
                session.terminal_context.window_active = event_terminal_context.get("window_active")
                session.terminal_context.pty = event_terminal_context.get("pty")
                session.terminal_context.host_name = event_terminal_context.get("host_name")
                session.terminal_context.execution_mode = event_terminal_context.get("execution_mode")
                session.terminal_context.connection_key = event_terminal_context.get("connection_key")
                session.terminal_context.context_key = event_terminal_context.get("context_key")
                session.terminal_context.remote_target = event_terminal_context.get("remote_target")

                if len(self._sessions) >= MAX_SESSIONS:
                    self._evict_oldest_idle_session()
                self._sessions[session_id] = session
                logger.info(
                    "Created session %s for %s/%s (window_id=%s, project=%s, native=%s)",
                    session_id,
                    session.tool,
                    provider.value,
                    resolved_window_id,
                    project,
                    native_session_id,
                )

            canonical_session_id = session.session_id

            if native_session_id and native_group_id:
                previous_group_id = session.collision_group_id
                if (
                    previous_group_id
                    and previous_group_id != native_group_id
                    and canonical_session_id in self._sessions
                ):
                    self._unregister_native_session_unlocked(
                        previous_group_id, canonical_session_id
                    )

                desired_native_session_id = self._build_session_id(
                    event, native_session_id, context_fingerprint
                )
                if (
                    desired_native_session_id != canonical_session_id
                    and desired_native_session_id not in self._sessions
                ):
                    rekeyed = self._rekey_session_unlocked(
                        canonical_session_id, desired_native_session_id
                    )
                    if rekeyed:
                        session = rekeyed
                        canonical_session_id = session.session_id

                session.native_session_id = native_session_id
                if context_fingerprint:
                    session.context_fingerprint = context_fingerprint
                session.collision_group_id = native_group_id
                session.identity_confidence = IdentityConfidence.NATIVE
                self._register_native_session_unlocked(
                    native_group_id, canonical_session_id
                )

            # Cache PID for this session and native group alias to preserve correlation.
            if client_pid is not None:
                if session.pid is None or explicit_client_pid is not None:
                    self._session_pids[canonical_session_id] = client_pid
                    session.pid = client_pid
                if native_group_id and explicit_client_pid is not None:
                    self._session_pids[native_group_id] = client_pid
                if session.identity_confidence != IdentityConfidence.NATIVE:
                    session.identity_confidence = IdentityConfidence.PID

            has_fresh_pid_context = bool(client_pid is not None)
            stale_window_binding = bool(
                resolved_window_id is not None
                and session.window_id is not None
                and session.window_id != resolved_window_id
            )
            stale_event_project = bool(
                event_project
                and session.project
                and not self._project_names_match(session.project, event_project)
            )
            stale_resolved_project = bool(
                resolved_project
                and session.project
                and not self._project_names_match(session.project, resolved_project)
            )

            if (
                resolved_window_id is not None
                and (
                    session.window_id is None
                    or not session.native_session_id
                    or allow_native_context_override
                    or (has_fresh_pid_context and stale_window_binding)
                )
            ):
                session.window_id = resolved_window_id
                session.terminal_context.window_id = resolved_window_id

            if event_project and (
                not session.project
                or not session.native_session_id
                or allow_native_context_override
                or (has_fresh_pid_context and stale_event_project)
            ):
                session.project = event_project
            if resolved_project and (
                not session.project
                or (has_fresh_pid_context and stale_resolved_project)
            ):
                session.project = resolved_project
            if event_project_path and (
                not session.project_path
                or not session.native_session_id
                or allow_native_context_override
            ):
                session.project_path = event_project_path
            if session.project is None and session.project_path:
                session.project = session.project_path

            for key in (
                "terminal_anchor_id",
                "binding_anchor_id",
                "binding_state",
                "binding_source",
                "anchor_lookup",
                "tmux_session",
                "tmux_window",
                "tmux_pane",
                "tmux_socket",
                "tmux_server_key",
                "tmux_resolution_source",
                "pty",
                "host_name",
                "execution_mode",
                "connection_key",
                "context_key",
                "remote_target",
            ):
                value = event_terminal_context.get(key)
                if not value:
                    continue
                has_explicit_key = bool(event_terminal_context_raw.get(key))
                if (
                    session.native_session_id
                    and getattr(session.terminal_context, key)
                    and not has_explicit_key
                    and key not in resolved_context_keys
                ):
                    continue
                if value:
                    setattr(session.terminal_context, key, value)

            # Only rebuild TerminalContext when terminal fields actually changed.
            # For established NATIVE sessions with stable context, this avoids
            # model_dump() + dict manipulation + Pydantic construction per event.
            if resolved_context_keys or not session.native_session_id:
                session.terminal_context = TerminalContext(
                    **self._normalize_terminal_binding_context(
                        session.terminal_context.model_dump(),
                        window_id=session.window_id,
                    )
                )

            session.last_event_at = now
            session.last_event_name = event.event_name

            if session.trace_id is None and event.trace_id:
                session.trace_id = event.trace_id
                session.status_reason = "trace_correlated"

            event_status_reason = _event_status_reason(event)
            if _event_counts_as_activity(event):
                session.last_activity_at = event.timestamp
                session.status_reason = event_status_reason
            elif event_status_reason:
                session.status_reason = event_status_reason

            if event.event_name in EventNames.EXPLICIT_COMPLETION_EVENTS:
                _set_explicit_terminal_state(session, event)
            elif _event_should_clear_explicit_terminal_state(session, event):
                _clear_terminal_state(session)

            if self._has_full_tmux_identity(event_terminal_context) and session.identity_confidence not in (
                IdentityConfidence.NATIVE,
                IdentityConfidence.PID,
            ):
                session.identity_confidence = IdentityConfidence.PANE

            self._apply_tracking_contract_unlocked(session)

            self._update_metrics(session, event)
            await self._handle_tool_lifecycle(session, event)
            await self._handle_streaming_events(session, event)

            old_state = session.state
            new_state = self._compute_new_state(session, event)
            if new_state != old_state:
                session.state = new_state
                session.state_changed_at = now
                session.state_seq += 1
                if not _event_counts_as_activity(event) and event_status_reason:
                    session.status_reason = event_status_reason
                logger.info(
                    "Session %s: %s -> %s",
                    session.session_id,
                    old_state,
                    new_state,
                )
                await self._handle_state_change(session, old_state, new_state)
                if new_state == SessionState.COMPLETED:
                    if canonical_session_id in self._quiet_timers:
                        self._quiet_timers.pop(canonical_session_id).cancel()
                    self._start_completed_timer(canonical_session_id)
                elif new_state in {SessionState.WORKING, SessionState.ATTENTION}:
                    if canonical_session_id in self._completed_timers:
                        self._completed_timers.pop(canonical_session_id).cancel()

            if (
                session.state == SessionState.WORKING
                and (
                    _event_counts_as_activity(event)
                    or session.pending_tools > 0
                    or session.is_streaming
                )
            ):
                self._reset_quiet_timer(session.session_id)

            self._mark_dirty_unlocked()

    @staticmethod
    def _heartbeat_should_extend_working(session: Session) -> bool:
        """Deterministically decide whether metrics heartbeat implies active work."""
        if session.pending_tools > 0:
            return True
        if session.is_streaming:
            return True
        status_reason = str(session.status_reason or "").strip().lower()
        if status_reason.startswith(f"event:{EventNames.CODEX_SSE_EVENT}:"):
            kind = status_reason.split(f"event:{EventNames.CODEX_SSE_EVENT}:", 1)[1]
            return _codex_sse_counts_as_activity(kind)
        return status_reason in _HEARTBEAT_ACTIVE_STATUS_REASONS

    async def process_heartbeat(self, session_id: str) -> None:
        """Process a heartbeat signal (from metrics) for a session.

        Heartbeats extend the quiet period for WORKING sessions without
        changing state. This allows metrics to serve as a keep-alive signal
        while Claude Code is actively running.

        Args:
            session_id: Session ID from metrics resource attributes
        """
        async with self._lock:
            lookup_id = self._lookup_native_session_from_raw_id_unlocked(session_id)
            if lookup_id is None:
                lookup_id = session_id
            session = self._sessions.get(lookup_id)
            if session is None:
                # No session found - don't create one from metrics alone
                return

            # Only extend quiet period for WORKING sessions
            if session.state == SessionState.WORKING and self._heartbeat_should_extend_working(session):
                now = datetime.now(timezone.utc)
                session.last_event_at = now
                self._reset_quiet_timer(session.session_id)
                logger.debug(f"Session {session.session_id}: heartbeat extended quiet period")

    async def process_heartbeat_for_tool(
        self, tool: AITool, pid: Optional[int] = None
    ) -> None:
        """Process a heartbeat signal for sessions of a given tool.

        Feature 135: When PID is provided, we target the specific session with that
        process.pid. This enables accurate heartbeat correlation when multiple
        sessions of the same tool are running.

        Falls back to extending ALL working sessions of the tool when PID is
        unavailable or doesn't match any session.

        Feature 136: Creates a session from heartbeat if none exists for the pid.
        This enables Gemini CLI sessions to appear even when idle (only sending metrics).

        Args:
            tool: AI tool type (CLAUDE_CODE, CODEX_CLI, etc.)
            pid: Optional process PID for more accurate session targeting
        """
        resolved_window_id: Optional[int] = None
        resolved_project: Optional[str] = None
        resolved_terminal_context: dict = {}
        if pid:
            try:
                (
                    resolved_window_id,
                    resolved_project,
                    resolved_terminal_context,
                ) = await self._resolve_window_context(pid)
            except Exception as e:
                logger.debug(f"Could not find window for pid {pid}: {e}")

        async with self._lock:
            now = datetime.now(timezone.utc)
            found_session = False
            changed = False

            # If PID provided, try to find specific session first
            if pid:
                for session_id, session in self._sessions.items():
                    if session.tool == tool and session.pid == pid:
                        if resolved_window_id is not None:
                            session.window_id = resolved_window_id
                            session.terminal_context.window_id = resolved_window_id
                        if resolved_project:
                            session.project = resolved_project
                        resolved_tmux_target = bool(
                            resolved_terminal_context.get("tmux_session")
                            or resolved_terminal_context.get("tmux_window")
                        )
                        for key in (
                            "terminal_anchor_id",
                            "anchor_lookup",
                            "tmux_socket",
                            "tmux_server_key",
                            "tmux_resolution_source",
                            "pty",
                            "host_name",
                            "execution_mode",
                            "connection_key",
                            "context_key",
                            "remote_target",
                        ):
                            value = resolved_terminal_context.get(key)
                            if value:
                                setattr(session.terminal_context, key, value)
                        if resolved_tmux_target:
                            session.terminal_context.tmux_session = resolved_terminal_context.get(
                                "tmux_session"
                            )
                            session.terminal_context.tmux_window = resolved_terminal_context.get(
                                "tmux_window"
                            )
                            session.terminal_context.tmux_pane = resolved_terminal_context.get(
                                "tmux_pane"
                            )
                            session.terminal_context.tmux_socket = resolved_terminal_context.get(
                                "tmux_socket"
                            )
                            session.terminal_context.tmux_server_key = resolved_terminal_context.get(
                                "tmux_server_key"
                            )
                            session.terminal_context.tmux_resolution_source = resolved_terminal_context.get(
                                "tmux_resolution_source"
                            )
                            session.terminal_context.pane_pid = resolved_terminal_context.get("pane_pid")
                            session.terminal_context.pane_title = resolved_terminal_context.get("pane_title")
                            session.terminal_context.pane_active = resolved_terminal_context.get("pane_active")
                            session.terminal_context.window_active = resolved_terminal_context.get("window_active")
                        session.terminal_context = TerminalContext(
                            **self._normalize_terminal_binding_context(
                                session.terminal_context.model_dump(),
                                window_id=session.window_id,
                            )
                        )
                        self._apply_tracking_contract_unlocked(session)
                        if session.state == SessionState.WORKING and self._heartbeat_should_extend_working(session):
                            session.last_event_at = now
                            self._reset_quiet_timer(session_id)
                            logger.debug(
                                f"Session {session_id}: heartbeat extended by metrics (pid={pid})"
                            )
                            changed = True
                        found_session = True
                        break

                # Feature 136: Create session from metrics heartbeat if none exists
                if not found_session:
                    # Generate a session ID based on tool and pid
                    session_id = f"{tool.value}:pid:{pid}"
                    provider = TOOL_PROVIDER.get(tool, Provider.ANTHROPIC)

                    logger.debug(
                        "Ignoring heartbeat-only session for %s pid=%s; anchor-only cutover requires telemetry-backed session creation",
                        tool.value,
                        pid,
                    )

            # Fall back to extending all working sessions for tool
            if not found_session:
                for session_id, session in self._sessions.items():
                    if session.tool == tool and session.state == SessionState.WORKING:
                        if not self._heartbeat_should_extend_working(session):
                            continue
                        session.last_event_at = now
                        self._reset_quiet_timer(session_id)
                        logger.debug(f"Session {session_id}: heartbeat extended by metrics")
                        changed = True

            if changed:
                self._mark_dirty_unlocked()

    def _compute_new_state(
        self, session: Session, event: TelemetryEvent
    ) -> SessionState:
        """Compute new state based on current state and event.

        Feature 135: Added ATTENTION state detection for permissions and errors.
        Feature 135: Pending tool tracking - stay WORKING while tools are active.

        Args:
            session: Current session
            event: Incoming event

        Returns:
            New session state (may be same as current)
        """
        current = session.state
        event_name = event.event_name
        attrs = event.attributes

        if event_name in EventNames.EXPLICIT_COMPLETION_EVENTS:
            return SessionState.COMPLETED

        if (
            session.terminal_state == TerminalState.EXPLICIT_COMPLETE
            and event_name in EventNames.WORKING_TRIGGERS
            and not _is_newer_than_terminal_boundary(session, event)
        ):
            return current

        # Feature 135: Pending tool tracking
        # If there are active tools, stay WORKING regardless of other signals.
        # This prevents premature COMPLETED transitions during long tool executions.
        if session.pending_tools > 0:
            return SessionState.WORKING

        # Feature 135: Detect ATTENTION state from permission prompts or errors
        # Check for permission-related events
        if "permission" in event_name.lower():
            logger.debug(f"ATTENTION: Permission event detected: {event_name}")
            return SessionState.ATTENTION

        # Check for error types that need user attention
        error_type = attrs.get("error.type") or attrs.get("error_type") or ""
        if isinstance(error_type, str) and error_type.lower() in (
            "rate_limit",
            "rate_limit_error",
            "auth",
            "authentication_error",
            "authorization_error",
            "overloaded",
            "overloaded_error",
        ):
            logger.debug(f"ATTENTION: Error type needs attention: {error_type}")
            return SessionState.ATTENTION

        # Check for needs_attention flag in attributes
        needs_attention = attrs.get("needs_attention", False)
        if needs_attention and str(needs_attention).lower() in ("true", "1", "yes"):
            return SessionState.ATTENTION

        # Feature 135: finish_reasons detection for UI hints
        # We used to transition to COMPLETED immediately here, but it caused
        # notification spam for multi-turn tasks. Now we just log it and let
        # the quiet period (10s) handle the state transition.
        finish_reasons = attrs.get("gen_ai.response.finish_reasons") or ""
        if isinstance(finish_reasons, str) and finish_reasons:
            finish_lower = finish_reasons.lower()
            if finish_lower in ("end_turn", "stop"):
                logger.debug(f"Turn complete: finish_reasons={finish_reasons} (waiting for quiet period)")
            elif finish_lower == "max_tokens":
                logger.debug(f"ATTENTION: finish_reasons=max_tokens")
                return SessionState.ATTENTION

        # Events that trigger WORKING state
        if event_name in EventNames.WORKING_TRIGGERS:
            return SessionState.WORKING

        # Events that keep WORKING state (activity)
        # Feature 136: Any event from the same tool counts as activity
        if current == SessionState.WORKING and _event_counts_as_activity(event):
            return SessionState.WORKING

        # COMPLETED → WORKING on new prompt
        if current == SessionState.COMPLETED and event_name in EventNames.WORKING_TRIGGERS:
            return SessionState.WORKING

        # ATTENTION → WORKING on new activity (user resolved the issue)
        if current == SessionState.ATTENTION and event_name in EventNames.WORKING_TRIGGERS:
            return SessionState.WORKING

        # Default: keep current state
        return current

    def _update_metrics(self, session: Session, event: TelemetryEvent) -> None:
        """Update session error metrics from event attributes."""
        attrs = event.attributes

        # Gemini API response/error events may carry error info
        if event.event_name in {
            EventNames.GEMINI_API_RESPONSE,
            EventNames.GEMINI_API_ERROR,
            EventNames.GEMINI_API_RESPONSE_DOT,
            EventNames.GEMINI_API_ERROR_DOT,
        }:
            try:
                error_type = self._extract_error(attrs)
                if error_type:
                    session.error_count += 1
                    session.last_error_type = error_type
            except Exception:
                pass

        # Claude LLM call spans may carry error info
        elif event.event_name == EventNames.CLAUDE_LLM_CALL:
            try:
                error_type = attrs.get("error.type")
                if error_type:
                    session.error_count += 1
                    session.last_error_type = str(error_type)
            except Exception:
                pass

    async def _handle_tool_lifecycle(self, session: Session, event: TelemetryEvent) -> None:
        """Handle tool lifecycle events for pending tool tracking.

        Feature 135: Tracks active tool executions to prevent premature COMPLETED
        transitions. When pending_tools > 0, the quiet timer is suppressed.

        Args:
            session: Session to update
            event: Telemetry event
        """
        event_name = event.event_name

        if event_name == EventNames.CLAUDE_TOOL_START:
            session.pending_tools += 1
            logger.debug(
                f"Session {session.session_id}: tool_start, pending_tools={session.pending_tools}"
            )
            # Don't reset quiet timer - it will be suppressed by _compute_new_state

        elif event_name == EventNames.CLAUDE_TOOL_COMPLETE:
            session.pending_tools = max(0, session.pending_tools - 1)
            logger.debug(
                f"Session {session.session_id}: tool_complete, pending_tools={session.pending_tools}"
            )
            # If all tools completed, the quiet timer will start in process_event
        elif event_name == EventNames.CODEX_TOOL_DECISION:
            decision = str(event.attributes.get("decision") or "").strip().lower()
            if decision not in {"denied", "abort", "cancelled", "canceled"}:
                session.pending_tools += 1
                logger.debug(
                    f"Session {session.session_id}: codex tool_decision, pending_tools={session.pending_tools}"
                )
        elif event_name == EventNames.CODEX_TOOL_RESULT:
            session.pending_tools = max(0, session.pending_tools - 1)
            logger.debug(
                f"Session {session.session_id}: codex tool_result, pending_tools={session.pending_tools}"
            )

    async def _handle_streaming_events(self, session: Session, event: TelemetryEvent) -> None:
        """Handle streaming events for TTFT metrics.

        Feature 135: Tracks Time to First Token (TTFT) for streaming responses.
        Also tracks streaming state for visual indicators.

        Args:
            session: Session to update
            event: Telemetry event
        """
        event_name = event.event_name
        attrs = event.attributes

        if event_name == EventNames.CLAUDE_STREAM_START:
            session.is_streaming = True
            # Extract TTFT from attributes if provided by interceptor
            ttft_ms = attrs.get("ttft_ms") or attrs.get("time_to_first_token_ms")
            if ttft_ms:
                logger.debug(
                    f"Session {session.session_id}: stream_start, TTFT={ttft_ms}ms"
                )
            # Set first_token_time from event timestamp
            session.first_token_time = event.timestamp

        elif event_name == EventNames.CLAUDE_STREAM_TOKEN:
            # Update streaming token count if available
            tokens = attrs.get("tokens") or attrs.get("token_count") or 1
            try:
                session.streaming_tokens += int(tokens)
            except (ValueError, TypeError):
                session.streaming_tokens += 1

        # Reset streaming state on LLM call completion
        elif event_name == EventNames.CLAUDE_LLM_CALL:
            if session.is_streaming:
                session.is_streaming = False
                session.streaming_tokens = 0
                session.first_token_time = None
        elif event_name == EventNames.CODEX_SSE_EVENT:
            kind = _normalized_codex_sse_kind(event)
            if _codex_sse_counts_as_activity(kind):
                session.is_streaming = True
                if session.first_token_time is None:
                    session.first_token_time = event.timestamp
            elif kind in {
                "response.completed",
                "response.failed",
                "response.cancelled",
                "response.canceled",
                "response.incomplete",
            }:
                session.is_streaming = False
                session.streaming_tokens = 0
                session.first_token_time = None

    def _extract_error(self, attrs: dict) -> Optional[str]:
        """Extract and classify error type from event attributes.

        Normalizes error indicators from different providers to a standard set:
        - auth: Authentication/authorization errors (401, 403)
        - rate_limit: Rate limiting errors (429)
        - timeout: Request timeout errors
        - server: Server-side errors (5xx)
        - client: Client-side errors (4xx, other than above)

        Args:
            attrs: Event attributes dict

        Returns:
            Normalized error type, or None if no error
        """
        # Check for explicit error.type attribute
        error_type = attrs.get("error.type")
        if error_type:
            return self._classify_error(str(error_type))

        # Check for OTEL status code
        status_code = attrs.get("otel.status_code")
        if status_code == "ERROR":
            # Try to get more info from error.message
            error_msg = attrs.get("error.message", "")
            return self._classify_error(str(error_msg))

        # Check HTTP status code
        http_status = attrs.get("http.status_code") or attrs.get("http.response.status_code")
        if http_status:
            return self._classify_http_status(int(http_status))

        return None

    def _classify_error(self, error_str: str) -> str:
        """Classify error string to normalized type."""
        error_lower = error_str.lower()

        if any(x in error_lower for x in ["auth", "401", "403", "unauthorized", "forbidden"]):
            return "auth"
        if any(x in error_lower for x in ["rate", "limit", "429", "too many", "throttl"]):
            return "rate_limit"
        if any(x in error_lower for x in ["timeout", "timed out", "deadline"]):
            return "timeout"
        if any(x in error_lower for x in ["server", "500", "502", "503", "504", "internal"]):
            return "server"

        return "client"

    def _classify_http_status(self, status: int) -> Optional[str]:
        """Classify HTTP status code to error type."""
        if status < 400:
            return None
        if status == 401 or status == 403:
            return "auth"
        if status == 429:
            return "rate_limit"
        if status == 408 or status == 504:
            return "timeout"
        if status >= 500:
            return "server"
        return "client"

    def _reset_quiet_timer(self, session_id: str) -> None:
        """Reset the quiet period timer for a session.

        Cancels existing timer and starts a new one.
        When timer fires, transitions WORKING → COMPLETED.
        """
        # Cancel existing timer
        if session_id in self._quiet_timers:
            self._quiet_timers[session_id].cancel()

        # Start new timer
        async def quiet_timer():
            try:
                await asyncio.sleep(self.quiet_period_sec)
                await self._on_quiet_period_expired(session_id)
            except asyncio.CancelledError:
                pass

        self._quiet_timers[session_id] = asyncio.create_task(quiet_timer())

    async def _on_quiet_period_expired(self, session_id: str) -> None:
        """Handle quiet period expiration - transition to COMPLETED.

        Feature 135: Suppresses transition if pending_tools > 0 (tools still active).

        Args:
            session_id: Session that has been quiet
        """
        async with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return

            if session.state != SessionState.WORKING:
                return

            # Feature 135: Don't transition if tools are still active
            if session.pending_tools > 0:
                logger.debug(
                    f"Session {session_id}: quiet period expired but {session.pending_tools} "
                    f"tools pending, staying WORKING"
                )
                return

            # Transition to COMPLETED
            old_state = session.state
            session.state = SessionState.COMPLETED
            session.state_changed_at = datetime.now(timezone.utc)
            session.state_seq += 1
            session.status_reason = "quiet_period_expired"
            logger.info(f"Session {session_id}: quiet period expired → COMPLETED")

            await self._handle_state_change(session, old_state, SessionState.COMPLETED)

            # Start completed timeout timer
            self._start_completed_timer(session_id)

    def _start_completed_timer(self, session_id: str) -> None:
        """Start timer for auto-transitioning COMPLETED → IDLE.

        Args:
            session_id: Session in COMPLETED state
        """
        # Cancel existing timer
        if session_id in self._completed_timers:
            self._completed_timers[session_id].cancel()

        async def completed_timer():
            try:
                await asyncio.sleep(self.completed_timeout_sec)
                await self._on_completed_timeout(session_id)
            except asyncio.CancelledError:
                pass

        self._completed_timers[session_id] = asyncio.create_task(completed_timer())

    async def _on_completed_timeout(self, session_id: str) -> None:
        """Handle completed timeout - transition to IDLE.

        Args:
            session_id: Session that timed out in COMPLETED state
        """
        async with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return

            if session.state != SessionState.COMPLETED:
                return

            # Transition to IDLE
            old_state = session.state
            session.state = SessionState.IDLE
            session.state_changed_at = datetime.now(timezone.utc)
            session.state_seq += 1
            session.status_reason = "completed_timeout"
            logger.info(f"Session {session_id}: completed timeout → IDLE")

            await self._handle_state_change(session, old_state, SessionState.IDLE)

    async def _handle_state_change(
        self, session: Session, old_state: SessionState, new_state: SessionState
    ) -> None:
        """Handle actions triggered by state changes.

        Args:
            session: Session that changed state
            old_state: Previous state
            new_state: New state
        """
        # Mark dirty and let debounced broadcaster emit a deduplicated snapshot.
        self._mark_dirty_unlocked()

        # Send notification on completion - but only if:
        # 1. Coming from WORKING or ATTENTION (not from IDLE or already COMPLETED)
        # 2. Session has a window_id (suppress background/ghost notifications)
        # 3. Session had minimum duration of activity (suppress trivial turns)
        # 4. Not debounced (no notification in last N seconds)
        if new_state == SessionState.COMPLETED and self.enable_notifications:
            # Only notify when we actually completed work, not on spurious transitions
            if old_state not in (SessionState.WORKING, SessionState.ATTENTION):
                logger.debug(
                    f"Session {session.session_id}: skipping notification "
                    f"(transition from {old_state}, not from WORKING/ATTENTION)"
                )
                return

            # Feature 136: Suppress notifications for sessions without a window
            if session.window_id is None:
                logger.debug(
                    f"Session {session.session_id}: skipping notification "
                    f"(no window_id, likely background process)"
                )
                return

            # Feature 136: Suppress notifications for very short bursts of activity
            # Use last_event_at - created_at as a proxy for session duration
            session_duration = (session.last_event_at - session.created_at).total_seconds()
            if session_duration < self._min_working_duration_sec:
                logger.debug(
                    f"Session {session.session_id}: skipping notification "
                    f"(duration {session_duration:.1f}s < {self._min_working_duration_sec}s)"
                )
                return

            # Debounce: don't spam notifications
            now = datetime.now(timezone.utc)
            last_notif = self._last_notification.get(session.session_id)
            if last_notif:
                elapsed = (now - last_notif).total_seconds()
                if elapsed < self._notification_debounce_sec:
                    logger.debug(
                        f"Session {session.session_id}: skipping notification "
                        f"(debounced, {elapsed:.1f}s < {self._notification_debounce_sec}s)"
                    )
                    return

            self._last_notification[session.session_id] = now
            await self._send_completion_notification(session)

    async def _send_completion_notification(self, session: Session) -> None:
        """Send desktop notification for completed session.

        Args:
            session: Completed session
        """
        # Import here to avoid circular dependency
        from .notifier import send_completion_notification

        await send_completion_notification(session)

    async def _broadcast_loop(self) -> None:
        """Debounced session list broadcaster."""
        while self._running:
            try:
                try:
                    await asyncio.wait_for(
                        self._broadcast_event.wait(),
                        timeout=self.broadcast_interval_sec,
                    )
                except asyncio.TimeoutError:
                    pass
                if not self._running:
                    break

                if self._broadcast_event.is_set():
                    self._broadcast_event.clear()
                    await asyncio.sleep(self._broadcast_debounce_sec)

                await self._broadcast_sessions()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Broadcast error: {e}")

    def _build_session_list_unlocked(self) -> tuple[SessionList, str]:
        """Build a session snapshot and deterministic fingerprint.

        Caller must hold _lock.
        """
        now_ts = datetime.now(timezone.utc).timestamp()
        suppressed_missing_project = 0
        suppressed_non_native = 0
        active_sessions = []
        for session in self._sessions.values():
            if session.state == SessionState.EXPIRED:
                continue
            if self._session_is_resolved_for_display(session, now_ts):
                active_sessions.append(session)
                continue
            if not session.project:
                suppressed_missing_project += 1
            else:
                suppressed_non_native += 1

        self._display_filter_stats = {
            "suppressed_missing_project": suppressed_missing_project,
            "suppressed_non_native": suppressed_non_native,
        }
        active_sessions.sort(key=lambda s: s.session_id)

        updated_at = datetime.now(timezone.utc).isoformat()

        items = []
        diagnostics = []
        fingerprint_source = []
        snapshot_now = datetime.now(timezone.utc)
        live_tmux_panes = _cached_list_tmux_panes_sync()
        live_tmux_by_server_pane = {
            (
                str(pane.get("tmux_server_key") or "").strip(),
                str(pane.get("tmux_pane") or "").strip(),
            ): pane
            for pane in live_tmux_panes
            if str(pane.get("tmux_server_key") or "").strip()
            and str(pane.get("tmux_pane") or "").strip()
        }
        live_tmux_by_pty = {
            str(pane.get("pty") or "").strip(): pane
            for pane in live_tmux_panes
            if str(pane.get("pty") or "").strip()
        }
        for s in active_sessions:
            project_labels = self._resolve_export_project_labels(s)
            stage_fields = _derive_session_stage(s, now=snapshot_now)
            session_kind = (
                "native"
                if s.identity_confidence == IdentityConfidence.NATIVE or s.native_session_id
                else "process"
            )
            terminal_context = s.terminal_context
            live_tmux_entry = None
            pane_id = str(getattr(terminal_context, "tmux_pane", "") or "").strip()
            pane_server_key = str(getattr(terminal_context, "tmux_server_key", "") or "").strip()
            pane_tty = str(getattr(terminal_context, "pty", "") or "").strip()
            if pane_id and pane_server_key:
                live_tmux_entry = live_tmux_by_server_pane.get((pane_server_key, pane_id))
            if live_tmux_entry is None and pane_tty:
                live_tmux_entry = live_tmux_by_pty.get(pane_tty)
            if isinstance(live_tmux_entry, dict):
                terminal_context = terminal_context.model_copy()
                terminal_context.tmux_session = str(live_tmux_entry.get("tmux_session") or "").strip() or terminal_context.tmux_session
                terminal_context.tmux_window = str(live_tmux_entry.get("tmux_window") or "").strip() or terminal_context.tmux_window
                terminal_context.tmux_pane = str(live_tmux_entry.get("tmux_pane") or "").strip() or terminal_context.tmux_pane
                terminal_context.tmux_socket = str(live_tmux_entry.get("tmux_socket") or "").strip() or terminal_context.tmux_socket
                terminal_context.tmux_server_key = str(live_tmux_entry.get("tmux_server_key") or "").strip() or terminal_context.tmux_server_key
                terminal_context.tmux_resolution_source = str(live_tmux_entry.get("tmux_resolution_source") or "").strip() or terminal_context.tmux_resolution_source
                terminal_context.pane_pid = live_tmux_entry.get("pane_pid") or terminal_context.pane_pid
                terminal_context.pane_title = str(live_tmux_entry.get("pane_title") or "").strip() or terminal_context.pane_title
                terminal_context.pane_active = bool(live_tmux_entry.get("pane_active", False))
                terminal_context.window_active = bool(live_tmux_entry.get("window_active", False))
                terminal_context.pty = str(live_tmux_entry.get("pty") or "").strip() or terminal_context.pty
                tmux_metadata = read_tmux_session_i3pm_metadata_sync(
                    terminal_context.tmux_socket,
                    terminal_context.tmux_session,
                )
                for key, value in tmux_metadata.items():
                    if value is not None and hasattr(terminal_context, key):
                        setattr(terminal_context, key, value)
            if (
                str(getattr(terminal_context, "execution_mode", "") or "").strip().lower() == "local"
                and (
                    terminal_context.tmux_session
                    or terminal_context.tmux_window
                    or terminal_context.tmux_pane
                    or terminal_context.pty
                )
                and not tmux_target_exists(
                    tmux_session=terminal_context.tmux_session,
                    tmux_window=terminal_context.tmux_window,
                    tmux_pane=terminal_context.tmux_pane,
                    pty=terminal_context.pty,
                    tmux_socket=terminal_context.tmux_socket,
                    tmux_server_key=terminal_context.tmux_server_key,
                )
            ):
                terminal_context = terminal_context.model_copy()
                terminal_context.tmux_session = None
                terminal_context.tmux_window = None
                terminal_context.tmux_pane = None
                terminal_context.tmux_socket = None
                terminal_context.tmux_server_key = None
                terminal_context.tmux_resolution_source = "missing"
                terminal_context.pane_pid = None
                terminal_context.pane_title = None
                terminal_context.pane_active = None
                terminal_context.window_active = None
                terminal_context.pty = None
            terminal_context = TerminalContext(
                **self._normalize_terminal_binding_context(
                    terminal_context.model_dump(),
                    window_id=s.window_id,
                )
            )
            process_stats = self._collect_process_stats(s.pid, now_ts)
            surface_kind, surface_key, pane_label = self._build_surface_key(
                terminal_context,
                window_id=s.window_id,
            )
            process_tree_root = (
                int(getattr(terminal_context, "pane_pid", 0) or 0)
                or int(s.pid or 0)
            )
            process_tree_stats = self._collect_process_tree_stats(
                process_tree_root if process_tree_root > 0 else None,
                now_ts,
            )
            item = SessionListItem(
                session_id=s.session_id,
                native_session_id=s.native_session_id,
                context_fingerprint=s.context_fingerprint,
                collision_group_id=s.collision_group_id,
                identity_confidence=s.identity_confidence,
                tool=s.tool,
                state=s.state,
                project=project_labels["display_project"],
                session_kind=session_kind,
                live=True,
                session_project=project_labels["session_project"],
                window_project=project_labels["window_project"],
                focus_project=project_labels["focus_project"],
                display_project=project_labels["display_project"],
                project_source=project_labels["project_source"],
                project_path=s.project_path,
                window_id=s.window_id,
                terminal_context=terminal_context,
                binding_anchor_id=terminal_context.binding_anchor_id,
                binding_state=terminal_context.binding_state,
                binding_source=terminal_context.binding_source,
                surface_kind=surface_kind,
                surface_key=surface_key,
                pane_label=pane_label or str(getattr(terminal_context, "pane_title", "") or "").strip() or None,
                focusable=s.focusable,
                invalid_reason=s.invalid_reason,
                pid=s.pid,
                trace_id=s.trace_id,
                process_running=bool(process_stats["process_running"]),
                rss_mb=process_stats["rss_mb"],
                cpu_percent=process_stats["cpu_percent"],
                uptime_seconds=process_stats["uptime_seconds"],
                stats_sampled_at=process_stats["stats_sampled_at"],
                stats_source=str(process_stats["stats_source"]),
                process_tree_rss_mb=process_tree_stats["process_tree_rss_mb"],
                process_tree_cpu_percent=process_tree_stats["process_tree_cpu_percent"],
                process_count=process_tree_stats["process_count"],
                pending_tools=s.pending_tools,
                is_streaming=s.is_streaming,
                state_seq=s.state_seq,
                status_reason=s.status_reason,
                last_event_name=s.last_event_name,
                stage=stage_fields["stage"],
                stage_label=str(stage_fields["stage_label"]),
                stage_detail=str(stage_fields["stage_detail"]),
                stage_class=str(stage_fields["stage_class"]),
                stage_visual_state=str(stage_fields["stage_visual_state"]),
                stage_rank=int(stage_fields["stage_rank"]),
                needs_user_action=bool(stage_fields["needs_user_action"]),
                user_action_reason=stage_fields["user_action_reason"],
                output_ready=bool(stage_fields["output_ready"]),
                output_unseen=bool(stage_fields["output_unseen"]),
                llm_stopped=bool(stage_fields["llm_stopped"]),
                terminal_state=stage_fields["terminal_state"],
                terminal_state_at=(
                    str(stage_fields["terminal_state_at"])
                    if stage_fields["terminal_state_at"] is not None
                    else None
                ),
                terminal_state_label=str(stage_fields["terminal_state_label"]),
                terminal_state_source=(
                    str(stage_fields["terminal_state_source"])
                    if stage_fields["terminal_state_source"] is not None
                    else None
                ),
                provider_stop_signal=(
                    str(stage_fields["provider_stop_signal"])
                    if stage_fields["provider_stop_signal"] is not None
                    else None
                ),
                session_phase=str(stage_fields["session_phase"]),
                session_phase_label=str(stage_fields["session_phase_label"]),
                turn_owner=stage_fields["turn_owner"],
                turn_owner_label=str(stage_fields["turn_owner_label"]),
                activity_substate=stage_fields["activity_substate"],
                activity_substate_label=str(stage_fields["activity_substate_label"]),
                activity_freshness=stage_fields["activity_freshness"],
                activity_age_seconds=int(stage_fields["activity_age_seconds"]),
                last_activity_at=stage_fields["last_activity_at"],
                identity_source=str(stage_fields["identity_source"]),
                lifecycle_source=str(stage_fields["lifecycle_source"]),
                updated_at=s.last_event_at.isoformat(),
            )
            items.append(item)
            fingerprint_source.append(
                (
                    s.session_id,
                    s.native_session_id,
                    s.context_fingerprint,
                    s.collision_group_id,
                    str(s.tool),
                    str(s.state),
                    item.project,
                    item.session_project,
                    item.window_project,
                    item.focus_project,
                    item.project_source,
                    s.project_path,
                    s.window_id,
                    terminal_context.terminal_anchor_id,
                    terminal_context.binding_anchor_id,
                    terminal_context.binding_state,
                    terminal_context.binding_source,
                    terminal_context.tmux_session,
                    terminal_context.tmux_window,
                    terminal_context.tmux_pane,
                    terminal_context.pane_pid,
                    terminal_context.pane_title,
                    terminal_context.pane_active,
                    terminal_context.window_active,
                    terminal_context.execution_mode,
                    terminal_context.connection_key,
                    terminal_context.context_key,
                    terminal_context.remote_target,
                    surface_kind,
                    surface_key,
                    pane_label,
                    s.pid,
                    s.trace_id,
                    process_tree_stats["process_tree_rss_mb"],
                    process_tree_stats["process_tree_cpu_percent"],
                    process_tree_stats["process_count"],
                    s.pending_tools,
                    s.is_streaming,
                    s.state_seq,
                    s.status_reason,
                    s.last_event_name,
                    str(stage_fields["stage"]),
                    str(stage_fields["stage_label"]),
                    str(stage_fields["stage_detail"]),
                    str(stage_fields["stage_class"]),
                    str(stage_fields["stage_visual_state"]),
                    int(stage_fields["stage_rank"]),
                    bool(stage_fields["needs_user_action"]),
                    str(stage_fields["user_action_reason"]),
                    bool(stage_fields["output_ready"]),
                    bool(stage_fields["output_unseen"]),
                    str(stage_fields["terminal_state_at"] or ""),
                    str(stage_fields["session_phase"]),
                    str(stage_fields["session_phase_label"]),
                    str(stage_fields["turn_owner"]),
                    str(stage_fields["turn_owner_label"]),
                    str(stage_fields["activity_substate"]),
                    str(stage_fields["activity_substate_label"]),
                    str(stage_fields["activity_freshness"]),
                    int(stage_fields["activity_age_seconds"]),
                    str(stage_fields["last_activity_at"] or ""),
                    str(stage_fields["identity_source"]),
                    str(stage_fields["lifecycle_source"]),
                    bool(s.focusable),
                    str(s.invalid_reason or ""),
                    bool(process_stats["process_running"]),
                    process_stats["rss_mb"],
                    process_stats["cpu_percent"],
                    process_stats["uptime_seconds"],
                    process_stats["stats_sampled_at"],
                    str(process_stats["stats_source"]),
                )
            )

        for diagnostic in sorted(
            self._session_diagnostics.values(),
            key=lambda entry: (
                str(entry.get("reason") or ""),
                str(entry.get("session_id") or ""),
            ),
        ):
            diagnostics.append(dict(diagnostic))
            fingerprint_source.append(
                (
                    "diagnostic",
                    str(diagnostic.get("session_id") or ""),
                    str(diagnostic.get("reason") or ""),
                    str(diagnostic.get("terminal_anchor_id") or ""),
                    str(diagnostic.get("detail") or ""),
                )
            )

        sessions_by_window: dict[int, list[SessionListItem]] = {}
        for item in items:
            if item.window_id is not None:
                if item.window_id not in sessions_by_window:
                    sessions_by_window[item.window_id] = []
                sessions_by_window[item.window_id].append(item)

        for window_id in sessions_by_window:
            sessions_by_window[window_id].sort(
                key=lambda s: (
                    state_priority(SessionState(s.state)),
                    s.session_id,
                ),
                reverse=True
            )
        has_working = any(s.state == SessionState.WORKING for s in active_sessions)
        fingerprint = hashlib.sha256(
            json.dumps(fingerprint_source, separators=(",", ":"), sort_keys=True).encode("utf-8")
        ).hexdigest()

        session_list = SessionList(
            sessions=items,
            sessions_by_window=sessions_by_window,
            diagnostics=diagnostics,
            timestamp=int(datetime.now(timezone.utc).timestamp()),
            updated_at=updated_at,
            has_working=has_working,
        )
        return session_list, fingerprint

    async def _broadcast_sessions(self, force: bool = False) -> None:
        """Broadcast current session list with deduplication."""
        session_list: Optional[SessionList] = None

        async with self._lock:
            if not force and not self._dirty:
                return

            session_list, fingerprint = self._build_session_list_unlocked()
            if not force and fingerprint == self._last_broadcast_fingerprint:
                self._dirty = False
                return

            self._last_broadcast_fingerprint = fingerprint
            self._dirty = False

        await self.output.write_session_list(session_list)

    async def _expiry_loop(self) -> None:
        """Periodically check for and remove expired/orphaned sessions."""
        check_count = 0
        while self._running:
            try:
                await asyncio.sleep(10)  # Check every 10 seconds
                check_count += 1

                # Window validation every 10 seconds (for faster cleanup of closed terminals)
                await self._cleanup_orphaned_windows()

                # Full timeout expiry every 30 seconds (every 3rd check)
                if check_count % 3 == 0:
                    await self._expire_sessions()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Expiry check error: {e}")

    @staticmethod
    def _session_pid_is_running(session: Session) -> bool:
        """Return whether a session still has a live local process."""
        pid = int(session.pid or 0)
        if pid <= 0:
            return False
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        return True

    def _session_has_live_local_tmux_target(self, session: Session) -> bool:
        """Return whether a local working session still has its tmux surface."""
        if session.state != SessionState.WORKING:
            return False

        terminal_context = session.terminal_context or TerminalContext()
        execution_mode = str(terminal_context.execution_mode or "").strip().lower()
        if execution_mode and execution_mode != "local":
            return False
        if not self._has_full_tmux_identity(terminal_context.model_dump()):
            return False

        return tmux_target_exists(
            tmux_session=terminal_context.tmux_session,
            tmux_window=terminal_context.tmux_window,
            tmux_pane=terminal_context.tmux_pane,
            pty=terminal_context.pty,
            tmux_socket=terminal_context.tmux_socket,
            tmux_server_key=terminal_context.tmux_server_key,
        )

    async def _expire_sessions(self) -> None:
        """Check for and remove expired sessions."""
        now = datetime.now(timezone.utc)
        expired: list[tuple[str, str]] = []
        updates: list[SessionUpdate] = []

        async with self._lock:
            for session_id, session in self._sessions.items():
                age = (now - session.last_event_at).total_seconds()
                if not session.project and age > UNRESOLVED_SESSION_TTL_SEC:
                    expired.append((session_id, "unresolved_ttl"))
                elif age > self.session_timeout_sec:
                    if self._session_pid_is_running(session):
                        session.last_event_at = now
                        if session.state == SessionState.WORKING:
                            session.status_reason = "process_keepalive"
                        self._mark_dirty_unlocked()
                        logger.debug(
                            "Retaining session %s after timeout because pid %s is still running",
                            session_id,
                            session.pid,
                        )
                        continue
                    if self._session_has_live_local_tmux_target(session):
                        session.last_event_at = now
                        session.status_reason = "tmux_keepalive"
                        self._mark_dirty_unlocked()
                        logger.debug(
                            "Retaining session %s after timeout because tmux pane %s is still live",
                            session_id,
                            session.terminal_context.tmux_pane,
                        )
                        continue
                    expired.append((session_id, "session_timeout"))

            for session_id, reason in expired:
                session = self._sessions.pop(session_id)
                logger.info(
                    "Session %s expired (%s, age=%.1fs)",
                    session_id,
                    reason,
                    (now - session.last_event_at).total_seconds(),
                )

                # Cancel any timers
                if session_id in self._quiet_timers:
                    self._quiet_timers.pop(session_id).cancel()
                if session_id in self._completed_timers:
                    self._completed_timers.pop(session_id).cancel()
                self._remove_session_indexes_unlocked(session_id, session)

                # Emit expiry update
                update = SessionUpdate(
                    session_id=session_id,
                    tool=session.tool,
                    state=SessionState.EXPIRED,
                    project=session.project,
                    timestamp=int(now.timestamp()),
                )
                updates.append(update)

            if expired:
                self._mark_dirty_unlocked()

        for update in updates:
            await self.output.write_update(update)

    async def _cleanup_orphaned_windows(self) -> None:
        """Remove sessions whose windows or processes no longer exist.

        This handles the case where a terminal is closed but the session
        hasn't timed out yet. We validate that window_id still exists in Sway.

        Feature 137: Also cleans up sessions whose PID has exited. This handles
        the case where a user exits Claude Code but keeps the terminal open.
        The session would otherwise persist until session_timeout_sec (5 min).
        """
        # Get current window IDs from Sway
        current_windows = get_all_window_ids()
        if not current_windows:
            # Can't get window list - skip cleanup to avoid false positives
            return

        orphaned = []

        async with self._lock:
            for session_id, session in self._sessions.items():
                # Check 1: Window no longer exists
                if session.window_id and session.window_id not in current_windows:
                    orphaned.append((session_id, f"window {session.window_id} closed"))
                    continue

                # Check 2: Process no longer running (Feature 137)
                # This catches sessions for Claude processes that exited while
                # the terminal is still open (e.g., user Ctrl+C'd Claude Code)
                if session.pid:
                    try:
                        os.kill(session.pid, 0)  # Check if process exists
                    except ProcessLookupError:
                        # For native sessions, keep session state after process
                        # exit so review lifecycle can finish deterministically.
                        # If a native session is still WORKING when its process
                        # exits, promote to COMPLETED immediately to avoid stale
                        # WORKING sessions when no further telemetry arrives.
                        if session.native_session_id:
                            logger.debug(
                                "Session %s PID %s exited; detaching PID and retaining native session",
                                session_id,
                                session.pid,
                            )
                            session.pid = None
                            if session.state == SessionState.WORKING:
                                session.state = SessionState.COMPLETED
                                session.state_changed_at = datetime.now(timezone.utc)
                                session.state_seq += 1
                                session.status_reason = "process_exited_retained"
                                self._start_completed_timer(session_id)
                            elif (
                                not session.status_reason
                                or str(session.status_reason).startswith("event:")
                            ):
                                session.status_reason = "process_exited_retained"
                            self._mark_dirty_unlocked()
                            continue
                        # Process doesn't exist - mark non-native sessions for cleanup
                        orphaned.append((session_id, f"PID {session.pid} exited"))
                    except PermissionError:
                        # Process exists but we can't signal it - keep session
                        pass

            # Remove orphaned sessions
            for session_id, reason in orphaned:
                session = self._sessions.pop(session_id)
                logger.info(f"Session {session_id} orphaned ({reason})")

                # Cancel any timers
                if session_id in self._quiet_timers:
                    self._quiet_timers.pop(session_id).cancel()
                if session_id in self._completed_timers:
                    self._completed_timers.pop(session_id).cancel()
                self._remove_session_indexes_unlocked(session_id, session)

            # Broadcast updated list if any were removed
            if orphaned:
                self._mark_dirty_unlocked()
