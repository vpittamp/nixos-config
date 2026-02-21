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
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Optional

from .models import (
    AITool,
    EventNames,
    Provider,
    Session,
    SessionList,
    SessionListItem,
    SessionState,
    SessionUpdate,
    TelemetryEvent,
    TOOL_PROVIDER,
)
from .pricing import calculate_cost
from .sway_helper import (
    get_all_window_ids,
    get_process_i3pm_env,
    find_window_by_pid,
    find_window_for_session,
)

if TYPE_CHECKING:
    from .output import OutputWriter

logger = logging.getLogger(__name__)

# Feature 137: Maximum session count to prevent memory exhaustion
MAX_SESSIONS = 100


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
        self._pid_context_cache: dict[int, tuple[float, Optional[int], Optional[str]]] = {}

        # Feature 138: Cache for session metadata files (sessionId -> pid)
        # These files are written by Claude Code hooks on session start
        self._metadata_file_cache: dict[str, int] = {}
        self._metadata_cache_mtime: float = 0.0

    def _load_session_metadata_pid(self, session_id: str) -> Optional[int]:
        """Look up PID for a session ID from hook-written metadata files.

        Feature 138: Claude Code hooks write $XDG_RUNTIME_DIR/claude-session-{PID}.json
        with {sessionId, pid}. This method scans those files to find the PID
        for a given UUID session_id, enabling window correlation for native OTEL logs
        which don't include process.pid.

        Args:
            session_id: The session ID (UUID) to look up

        Returns:
            PID if found in metadata files, None otherwise
        """
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        metadata_pattern = os.path.join(runtime_dir, "claude-session-*.json")

        # Check if we need to refresh the cache (files changed in last 5 seconds)
        try:
            # Get the most recent mtime from metadata files
            metadata_files = glob.glob(metadata_pattern)
            if not metadata_files:
                return None

            current_mtime = max(os.path.getmtime(f) for f in metadata_files)

            # Refresh cache if files are newer
            if current_mtime > self._metadata_cache_mtime:
                self._metadata_file_cache.clear()
                for filepath in metadata_files:
                    try:
                        with open(filepath, "r") as f:
                            data = json.load(f)
                            sid = data.get("sessionId")
                            pid = data.get("pid")
                            if sid and pid:
                                self._metadata_file_cache[sid] = int(pid)
                                logger.debug(f"Loaded session metadata: {sid} -> PID {pid}")
                    except (json.JSONDecodeError, IOError, KeyError) as e:
                        logger.debug(f"Failed to read metadata file {filepath}: {e}")
                self._metadata_cache_mtime = current_mtime
                logger.debug(f"Refreshed session metadata cache: {len(self._metadata_file_cache)} entries")

        except OSError as e:
            logger.debug(f"Failed to scan metadata files: {e}")
            return None

        return self._metadata_file_cache.get(session_id)

    async def start(self) -> None:
        """Start background tasks for broadcasting and expiry."""
        self._running = True

        # Start broadcast worker
        self._broadcast_task = asyncio.create_task(self._broadcast_loop())

        # Start session expiry checker
        self._expiry_task = asyncio.create_task(self._expiry_loop())

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
        self._session_pids.pop(oldest_id, None)
        if oldest_id in self._quiet_timers:
            self._quiet_timers[oldest_id].cancel()
            del self._quiet_timers[oldest_id]
        if oldest_id in self._completed_timers:
            self._completed_timers[oldest_id].cancel()
            del self._completed_timers[oldest_id]
        self._last_notification.pop(oldest_id, None)

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
                "config": {
                    "quiet_period_sec": self.quiet_period_sec,
                    "session_timeout_sec": self.session_timeout_sec,
                    "completed_timeout_sec": self.completed_timeout_sec,
                    "broadcast_interval_sec": self.broadcast_interval_sec,
                    "broadcast_debounce_sec": self._broadcast_debounce_sec,
                    "notifications_enabled": self.enable_notifications,
                },
            }

    def _build_session_id(self, event: TelemetryEvent) -> str:
        """Build stable session_id fallback when telemetry omits it."""
        if event.session_id:
            return event.session_id

        pid = event.attributes.get("process.pid") or event.attributes.get("pid")
        tool_name = event.tool if event.tool else "unknown"
        if pid:
            return f"{tool_name}-{pid}"

        minute_ts = int(event.timestamp.timestamp()) // 60 * 60
        return f"{tool_name}-{minute_ts}"

    def _extract_client_pid(self, session_id: str, event: TelemetryEvent) -> Optional[int]:
        """Extract and normalize PID from event/session metadata."""
        client_pid = event.attributes.get("process.pid") or event.attributes.get("pid")

        if client_pid is None:
            client_pid = self._session_pids.get(session_id)

        if client_pid is None:
            client_pid = self._load_session_metadata_pid(session_id)

        if client_pid is None:
            return None

        try:
            return int(client_pid)
        except (ValueError, TypeError):
            return None

    async def _resolve_window_context(
        self, pid: int
    ) -> tuple[Optional[int], Optional[str]]:
        """Resolve PID -> window/project with short TTL cache."""
        now = datetime.now(timezone.utc).timestamp()
        if len(self._pid_context_cache) > 512:
            self._pid_context_cache = {
                cache_pid: cache_entry
                for cache_pid, cache_entry in self._pid_context_cache.items()
                if cache_entry[0] > now
            }

        cached = self._pid_context_cache.get(pid)
        if cached and cached[0] > now:
            return cached[1], cached[2]

        window_id: Optional[int] = None
        project: Optional[str] = None
        try:
            i3pm_env = get_process_i3pm_env(pid)
            project = i3pm_env.get("I3PM_PROJECT_NAME") if i3pm_env else None
            window_id = await find_window_for_session(pid)
        except Exception as e:
            logger.debug(f"PID correlation failed for {pid}: {e}")

        ttl = 5.0 if window_id else 1.0
        self._pid_context_cache[pid] = (now + ttl, window_id, project)
        return window_id, project

    def _mark_dirty_unlocked(self) -> None:
        """Mark output as dirty and signal broadcast worker.

        Caller must hold _lock when mutating session state.
        """
        self._dirty = True
        self._broadcast_event.set()

    async def process_event(self, event: TelemetryEvent) -> None:
        """Process a telemetry event and update session state.

        Args:
            event: Parsed telemetry event from OTLP receiver
        """
        session_id = self._build_session_id(event)
        client_pid = self._extract_client_pid(session_id, event)

        resolved_window_id: Optional[int] = None
        resolved_project: Optional[str] = None
        if client_pid is not None:
            resolved_window_id, resolved_project = await self._resolve_window_context(client_pid)

        async with self._lock:
            now = datetime.now(timezone.utc)
            session = self._sessions.get(session_id)

            if session is None:
                existing_for_window = None
                if resolved_window_id is not None and event.tool:
                    for existing_session in self._sessions.values():
                        if (
                            existing_session.window_id == resolved_window_id
                            and existing_session.tool == event.tool
                        ):
                            existing_for_window = existing_session
                            break

                if existing_for_window is not None:
                    session = existing_for_window
                    logger.debug(
                        "Reusing session %s for window %s",
                        session.session_id,
                        resolved_window_id,
                    )
                else:
                    tool = event.tool or AITool.CLAUDE_CODE
                    provider = TOOL_PROVIDER.get(tool, Provider.ANTHROPIC)
                    project = resolved_project or self._extract_project(event)
                    session = Session(
                        session_id=session_id,
                        tool=tool,
                        provider=provider,
                        state=SessionState.IDLE,
                        project=project,
                        window_id=resolved_window_id,
                        pid=client_pid,
                        trace_id=event.trace_id,
                        created_at=now,
                        last_event_at=now,
                        state_changed_at=now,
                        state_seq=1,
                        status_reason="created",
                    )
                    if len(self._sessions) >= MAX_SESSIONS:
                        self._evict_oldest_idle_session()
                    self._sessions[session_id] = session
                    logger.info(
                        "Created session %s for %s/%s (window_id=%s, project=%s)",
                        session_id,
                        session.tool,
                        provider.value,
                        resolved_window_id,
                        project,
                    )

            canonical_session_id = session.session_id

            # Cache PID for this session and alias session IDs to preserve correlation.
            if client_pid is not None:
                self._session_pids[canonical_session_id] = client_pid
                self._session_pids[session_id] = client_pid
                session.pid = client_pid

            # Update primary window/project correlation for the session.
            if resolved_window_id is not None and resolved_window_id != session.window_id:
                old_window = session.window_id
                session.window_id = resolved_window_id
                if resolved_project:
                    session.project = resolved_project
                session.status_reason = "window_correlated"
                logger.info(
                    "Session %s: window %s -> %s via pid=%s",
                    canonical_session_id,
                    old_window,
                    resolved_window_id,
                    client_pid,
                )

            # Cross-session correlation: update orphaned sessions for the same tool.
            if resolved_window_id is not None and event.tool:
                for existing_id, existing_session in self._sessions.items():
                    if existing_id == canonical_session_id:
                        continue
                    if existing_session.tool != event.tool:
                        continue
                    if existing_session.window_id is not None:
                        continue
                    existing_session.window_id = resolved_window_id
                    if resolved_project:
                        existing_session.project = resolved_project
                    existing_session.status_reason = "window_correlated"
                    logger.info(
                        "Cross-session correlation: %s -> window %s via pid=%s",
                        existing_id,
                        resolved_window_id,
                        client_pid,
                    )

            session.last_event_at = now

            if session.trace_id is None and event.trace_id:
                session.trace_id = event.trace_id
                session.status_reason = "trace_correlated"

            extracted_project = self._extract_project(event)
            if extracted_project:
                session.project = extracted_project

            self._update_metrics(session, event)
            await self._handle_tool_lifecycle(session, event)
            await self._handle_streaming_events(session, event)

            old_state = session.state
            new_state = self._compute_new_state(session, event)
            if new_state != old_state:
                session.state = new_state
                session.state_changed_at = now
                session.state_seq += 1
                session.status_reason = f"event:{event.event_name}"
                logger.info(
                    "Session %s: %s -> %s",
                    canonical_session_id,
                    old_state,
                    new_state,
                )
                await self._handle_state_change(session, old_state, new_state)

            if session.state == SessionState.WORKING:
                self._reset_quiet_timer(canonical_session_id)

            self._mark_dirty_unlocked()

    async def process_heartbeat(self, session_id: str) -> None:
        """Process a heartbeat signal (from metrics) for a session.

        Heartbeats extend the quiet period for WORKING sessions without
        changing state. This allows metrics to serve as a keep-alive signal
        while Claude Code is actively running.

        Args:
            session_id: Session ID from metrics resource attributes
        """
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                # No session found - don't create one from metrics alone
                return

            # Only extend quiet period for WORKING sessions
            if session.state == SessionState.WORKING:
                now = datetime.now(timezone.utc)
                session.last_event_at = now
                self._reset_quiet_timer(session_id)
                logger.debug(f"Session {session_id}: heartbeat extended quiet period")

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
        if pid:
            try:
                window = await find_window_by_pid(pid)
                if window:
                    resolved_window_id = window.get("id")
                    marks = window.get("marks", [])
                    for mark in marks:
                        if mark.startswith("scoped:") or mark.startswith("project:"):
                            parts = mark.split(":")
                            if len(parts) >= 3:
                                resolved_project = parts[2]
                                break
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
                        session.last_event_at = now
                        if session.state == SessionState.WORKING:
                            self._reset_quiet_timer(session_id)
                        logger.debug(
                            f"Session {session_id}: heartbeat extended by metrics (pid={pid})"
                        )
                        found_session = True
                        changed = True
                        break

                # Feature 136: Create session from metrics heartbeat if none exists
                if not found_session:
                    # Generate a session ID based on tool and pid
                    session_id = f"{tool.value.replace('_', '-').lower()}-{pid}-{int(now.timestamp() * 1000)}"
                    provider = TOOL_PROVIDER.get(tool, Provider.ANTHROPIC)

                    session = Session(
                        session_id=session_id,
                        tool=tool,
                        provider=provider,
                        state=SessionState.IDLE,
                        project=resolved_project,
                        window_id=resolved_window_id,
                        pid=pid,
                        created_at=now,
                        last_event_at=now,
                        state_changed_at=now,
                        state_seq=1,
                        status_reason="metrics_heartbeat_created",
                    )
                    # Feature 137: Evict oldest IDLE session if at capacity
                    if len(self._sessions) >= MAX_SESSIONS:
                        self._evict_oldest_idle_session()
                    self._sessions[session_id] = session
                    self._session_pids[session_id] = pid
                    logger.info(
                        f"Created session {session_id} from metrics heartbeat "
                        f"for {tool.value} (pid={pid}, window_id={resolved_window_id}, project={resolved_project})"
                    )
                    found_session = True
                    changed = True

            # Fall back to extending all working sessions for tool
            if not found_session:
                for session_id, session in self._sessions.items():
                    if session.tool == tool and session.state == SessionState.WORKING:
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
        if current == SessionState.WORKING:
            if event.tool == session.tool or event_name in EventNames.ACTIVITY_EVENTS:
                return SessionState.WORKING

        # COMPLETED → WORKING on new prompt
        if current == SessionState.COMPLETED and event_name in EventNames.WORKING_TRIGGERS:
            return SessionState.WORKING

        # ATTENTION → WORKING on new activity (user resolved the issue)
        if current == SessionState.ATTENTION and event_name in EventNames.WORKING_TRIGGERS:
            return SessionState.WORKING

        # Default: keep current state
        return current

    def _extract_project(self, event: TelemetryEvent) -> Optional[str]:
        """Extract project context from event attributes.

        Args:
            event: Telemetry event

        Returns:
            Project name if found, None otherwise
        """
        # Look for common project attribute names
        for key in ("project", "project_name", "cwd", "working_directory"):
            if key in event.attributes:
                value = event.attributes[key]
                if isinstance(value, str):
                    # Extract just the directory name
                    if "/" in value:
                        return value.rstrip("/").split("/")[-1]
                    return value
        return None

    def _update_metrics(self, session: Session, event: TelemetryEvent) -> None:
        """Update session token metrics from event attributes.

        Args:
            session: Session to update
            event: Event with potential token metrics
        """
        attrs = event.attributes

        # Extract model name if available (for cost calculation)
        model = self._extract_model(attrs)
        if model and not session.model:
            session.model = model

        # Handle Codex token events
        if event.event_name == EventNames.CODEX_SSE_EVENT:
            # Codex emits per-request token counts on `response.completed`.
            # Prefer the `*_token_count` fields (Codex), but accept generic fallbacks.
            try:
                kind = attrs.get("event.kind")
                if kind and str(kind) != "response.completed":
                    return

                input_tokens = int(
                    attrs.get("input_token_count")
                    or attrs.get("gen_ai.usage.input_tokens")
                    or attrs.get("input_tokens")
                    or 0
                )
                output_tokens = int(
                    attrs.get("output_token_count")
                    or attrs.get("gen_ai.usage.output_tokens")
                    or attrs.get("output_tokens")
                    or 0
                )
                cached_tokens = int(
                    attrs.get("cached_token_count")
                    or attrs.get("cache_tokens")
                    or 0
                )

                session.input_tokens += input_tokens
                session.output_tokens += output_tokens
                session.cache_tokens += cached_tokens

                # Calculate cost for Codex (not included in telemetry)
                if input_tokens > 0 or output_tokens > 0:
                    cost, is_estimated = calculate_cost(
                        session.provider,
                        session.model,
                        input_tokens,
                        output_tokens,
                    )
                    session.cost_usd += cost
                    session.cost_estimated = is_estimated
            except Exception:
                pass

        # Handle Gemini/GenAI standard token events
        elif event.event_name in (EventNames.GEMINI_TOKEN_USAGE, EventNames.GENAI_TOKEN_USAGE):
            # GenAI semantic conventions use gen_ai.usage.*
            # but CLI might use flattened attributes
            input_keys = ("gen_ai.usage.input_tokens", "gen_ai.client.token.usage.input", "input_tokens", "prompt_tokens")
            output_keys = ("gen_ai.usage.output_tokens", "gen_ai.client.token.usage.output", "output_tokens", "completion_tokens")

            input_tokens = 0
            output_tokens = 0

            for key in input_keys:
                if key in attrs:
                    input_tokens = int(attrs[key])
                    session.input_tokens += input_tokens
                    break

            for key in output_keys:
                if key in attrs:
                    output_tokens = int(attrs[key])
                    session.output_tokens += output_tokens
                    break

            # Calculate cost for Gemini (not included in telemetry)
            if input_tokens > 0 or output_tokens > 0:
                cost, is_estimated = calculate_cost(
                    session.provider,
                    session.model,
                    input_tokens,
                    output_tokens,
                )
                session.cost_usd += cost
                session.cost_estimated = is_estimated

        # Gemini CLI per-request token usage (api_response/api_error)
        elif event.event_name in {
            EventNames.GEMINI_API_RESPONSE,
            EventNames.GEMINI_API_ERROR,
            EventNames.GEMINI_API_RESPONSE_DOT,
            EventNames.GEMINI_API_ERROR_DOT,
        }:
            try:
                input_tokens = int(
                    attrs.get("input_token_count")
                    or attrs.get("gen_ai.usage.input_tokens")
                    or attrs.get("prompt_tokens")
                    or 0
                )
                output_tokens = int(
                    attrs.get("output_token_count")
                    or attrs.get("gen_ai.usage.output_tokens")
                    or attrs.get("completion_tokens")
                    or 0
                )
                cached_tokens = int(
                    attrs.get("cached_content_token_count")
                    or attrs.get("cache_tokens")
                    or 0
                )

                session.input_tokens += input_tokens
                session.output_tokens += output_tokens
                session.cache_tokens += cached_tokens

                # Calculate cost for Gemini API events
                if input_tokens > 0 or output_tokens > 0:
                    cost, is_estimated = calculate_cost(
                        session.provider,
                        session.model,
                        input_tokens,
                        output_tokens,
                    )
                    session.cost_usd += cost
                    session.cost_estimated = is_estimated

                # Check for errors
                error_type = self._extract_error(attrs)
                if error_type:
                    session.error_count += 1
                    session.last_error_type = error_type
            except Exception:
                pass

        # Handle Claude Code per-request token usage (sum across the session)
        elif event.event_name == EventNames.CLAUDE_API_REQUEST:
            try:
                input_tokens = int(attrs.get("input_tokens") or 0)
                output_tokens = int(attrs.get("output_tokens") or 0)
                session.input_tokens += input_tokens
                session.output_tokens += output_tokens
                cache_read = int(attrs.get("cache_read_tokens") or 0)
                cache_create = int(attrs.get("cache_creation_tokens") or 0)
                session.cache_tokens += cache_read + cache_create
                # Claude Code interceptor already calculates cost, but if not present, calculate
                if "cost_usd" not in attrs and (input_tokens > 0 or output_tokens > 0):
                    cost, is_estimated = calculate_cost(
                        session.provider,
                        session.model,
                        input_tokens,
                        output_tokens,
                    )
                    session.cost_usd += cost
                    session.cost_estimated = is_estimated
            except Exception:
                # Best-effort only; don't let parsing break session tracking
                pass

        # Handle Claude Code LLM spans (from interceptor) with cost and error metrics
        elif event.event_name == EventNames.CLAUDE_LLM_CALL:
            try:
                # These attributes come from the interceptor spans (gen_ai.usage.*)
                input_tokens = attrs.get("gen_ai.usage.input_tokens") or attrs.get("input_tokens")
                output_tokens = attrs.get("gen_ai.usage.output_tokens") or attrs.get("output_tokens")
                cost_usd = attrs.get("gen_ai.usage.cost_usd") or attrs.get("cost_usd")
                error_type = attrs.get("error.type")

                if input_tokens:
                    session.input_tokens += int(input_tokens)
                if output_tokens:
                    session.output_tokens += int(output_tokens)
                if cost_usd:
                    session.cost_usd += float(cost_usd)
                elif input_tokens or output_tokens:
                    # Calculate cost if not provided by interceptor
                    cost, is_estimated = calculate_cost(
                        session.provider,
                        session.model,
                        int(input_tokens or 0),
                        int(output_tokens or 0),
                    )
                    session.cost_usd += cost
                    session.cost_estimated = is_estimated
                if error_type:
                    session.error_count += 1
                    session.last_error_type = str(error_type)
            except Exception:
                # Best-effort only
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

    def _extract_model(self, attrs: dict) -> Optional[str]:
        """Extract model name from event attributes.

        Args:
            attrs: Event attributes dict

        Returns:
            Model name if found, None otherwise
        """
        # Try various model attribute names
        model_keys = (
            "gen_ai.request.model",
            "gen_ai.model",
            "model",
            "llm.model_name",
        )
        for key in model_keys:
            if key in attrs:
                return str(attrs[key])
        return None

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

    def _get_metrics_dict(self, session: Session) -> dict:
        """Get metrics as dictionary for JSON output.

        Args:
            session: Session with metrics

        Returns:
            Dictionary of token, cost, error, and streaming metrics
        """
        metrics = {
            "input_tokens": session.input_tokens,
            "output_tokens": session.output_tokens,
            "cache_tokens": session.cache_tokens,
            "cost_usd": round(session.cost_usd, 6),  # Round to micro-dollars
        }
        # Only include error metrics if there are errors
        if session.error_count > 0:
            metrics["error_count"] = session.error_count
            if session.last_error_type:
                metrics["last_error_type"] = session.last_error_type

        # Feature 135: Include pending_tools and streaming state for visual indicators
        metrics["pending_tools"] = session.pending_tools
        metrics["is_streaming"] = session.is_streaming

        return metrics

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
        active_sessions = [
            s for s in self._sessions.values()
            if s.state != SessionState.EXPIRED
        ]
        active_sessions.sort(key=lambda s: s.session_id)

        updated_at = datetime.now(timezone.utc).isoformat()

        items = [
            SessionListItem(
                session_id=s.session_id,
                tool=s.tool,
                state=s.state,
                project=s.project,
                window_id=s.window_id,
                pid=s.pid,
                trace_id=s.trace_id,
                pending_tools=s.pending_tools,
                is_streaming=s.is_streaming,
                state_seq=s.state_seq,
                status_reason=s.status_reason,
                updated_at=s.last_event_at.isoformat(),
            )
            for s in active_sessions
        ]

        sessions_by_window: dict[int, list[SessionListItem]] = {}
        orphan_sessions: list[SessionListItem] = []
        for item in items:
            if item.window_id is not None:
                if item.window_id not in sessions_by_window:
                    sessions_by_window[item.window_id] = []
                sessions_by_window[item.window_id].append(item)
            else:
                orphan_sessions.append(item)

        if orphan_sessions:
            sessions_by_window[-1] = orphan_sessions

        for window_id in sessions_by_window:
            sessions_by_window[window_id].sort(
                key=lambda s: (
                    state_priority(SessionState(s.state)),
                    s.session_id,
                ),
                reverse=True
            )

        has_working = any(s.state == SessionState.WORKING for s in active_sessions)
        fingerprint_source = [
            (
                s.session_id,
                str(s.tool),
                str(s.state),
                s.project,
                s.window_id,
                s.pid,
                s.trace_id,
                s.pending_tools,
                s.is_streaming,
                s.state_seq,
                s.status_reason,
            )
            for s in active_sessions
        ]
        fingerprint = hashlib.sha256(
            json.dumps(fingerprint_source, separators=(",", ":"), sort_keys=True).encode("utf-8")
        ).hexdigest()

        session_list = SessionList(
            sessions=items,
            sessions_by_window=sessions_by_window,
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

    async def _expire_sessions(self) -> None:
        """Check for and remove expired sessions."""
        now = datetime.now(timezone.utc)
        expired = []
        updates: list[SessionUpdate] = []

        async with self._lock:
            for session_id, session in self._sessions.items():
                age = (now - session.last_event_at).total_seconds()
                if age > self.session_timeout_sec:
                    expired.append(session_id)

            for session_id in expired:
                session = self._sessions.pop(session_id)
                logger.info(f"Session {session_id} expired after {self.session_timeout_sec}s")

                # Cancel any timers
                if session_id in self._quiet_timers:
                    self._quiet_timers.pop(session_id).cancel()
                if session_id in self._completed_timers:
                    self._completed_timers.pop(session_id).cancel()
                # Feature 135: Clean up PID cache
                self._session_pids.pop(session_id, None)
                # Clean up notification debounce cache
                self._last_notification.pop(session_id, None)

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
                        # Process doesn't exist - mark for cleanup
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
                # Feature 135: Clean up PID cache
                self._session_pids.pop(session_id, None)
                # Clean up notification debounce cache
                self._last_notification.pop(session_id, None)

            # Broadcast updated list if any were removed
            if orphaned:
                self._mark_dirty_unlocked()
