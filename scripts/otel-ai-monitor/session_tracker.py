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
import logging
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
    get_focused_window_info,
    get_process_i3pm_env,
    find_window_by_i3pm_env,
    find_window_by_pid,
    find_window_by_i3pm_app_id,
    find_all_terminal_windows_for_project,
    # Feature 135: Deterministic correlation
    find_window_for_session,
    parse_correlation_key,
)

if TYPE_CHECKING:
    from .output import OutputWriter

logger = logging.getLogger(__name__)

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

    async def start(self) -> None:
        """Start background tasks for broadcasting and expiry."""
        self._running = True

        # Start periodic broadcast task
        self._broadcast_task = asyncio.create_task(self._broadcast_loop())

        # Start session expiry checker
        self._expiry_task = asyncio.create_task(self._expiry_loop())

        logger.info("Session tracker started")

    async def stop(self) -> None:
        """Stop background tasks and cleanup."""
        self._running = False

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

    async def process_event(self, event: TelemetryEvent) -> None:
        """Process a telemetry event and update session state.

        Args:
            event: Parsed telemetry event from OTLP receiver
        """
        # Generate session ID if not present
        session_id = event.session_id
        if not session_id:
            # Feature 136: Use PID for more stable session ID fallback
            # This prevents creating a new session every second for the same process
            pid = event.attributes.get("process.pid") or event.attributes.get("pid")
            tool_name = event.tool if event.tool else "unknown"
            if pid:
                session_id = f"{tool_name}-{pid}"
            else:
                # Last resort fallback: use minute-level timestamp for stability
                # Sessions within the same minute will be grouped together,
                # preventing ephemeral 1-second sessions when PID is unavailable
                minute_ts = int(event.timestamp.timestamp()) // 60 * 60
                session_id = f"{tool_name}-{minute_ts}"

        async with self._lock:
            session = self._sessions.get(session_id)
            now = datetime.now(timezone.utc)

            if session is None:
                # Create new session
                # Feature 135: Deterministic PID-based correlation via daemon IPC
                # No fallback strategies - either we find the exact window or None
                window_id, window_project = None, None
                client_pid = event.attributes.get("process.pid") or event.attributes.get("pid")

                # Feature 135: If no PID in event, try cached PID from earlier trace
                # Traces from interceptor have PID, but native logs don't.
                # Cross-signal correlation: use cached PID for same session_id.
                if not client_pid and session_id in self._session_pids:
                    client_pid = self._session_pids[session_id]
                    logger.debug(f"Using cached PID {client_pid} for session {session_id}")

                # Cache PID for future correlation with logs
                if client_pid:
                    try:
                        pid_int = int(client_pid)
                        if session_id not in self._session_pids:
                            self._session_pids[session_id] = pid_int
                            logger.debug(f"Cached PID {pid_int} for session {session_id}")
                    except (ValueError, TypeError):
                        pass

                # Feature 135: Use deterministic daemon IPC correlation
                # This is the ONLY correlation strategy - no fallbacks.
                # Works with tmux, multiple terminals, and is 100% accurate.
                if client_pid:
                    try:
                        pid = int(client_pid)
                        # Read I3PM environment for project context
                        i3pm_env = get_process_i3pm_env(pid)
                        window_project = i3pm_env.get("I3PM_PROJECT_NAME") if i3pm_env else None

                        # Deterministic correlation via daemon IPC
                        window_id = await find_window_for_session(pid)
                        if window_id:
                            logger.debug(f"Deterministic correlation: PID {pid} → window {window_id}")
                        else:
                            logger.debug(f"No window found for PID {pid} (daemon returned not_found)")
                    except (ValueError, TypeError) as e:
                        logger.debug(f"PID correlation failed: {e}")

                # Feature 135: NO FALLBACK - if daemon doesn't find the window, window_id stays None
                # This is intentional: we prefer "unknown" over "wrong window"

                # Check for existing session with same window_id AND tool (deduplicate)
                # Important: Different AI tools (Claude, Codex, Gemini) in the same terminal
                # should have separate sessions, so we check both window_id AND tool type.
                existing_for_window = None
                if window_id and event.tool:
                    for existing_id, existing_session in self._sessions.items():
                        if existing_session.window_id == window_id and existing_session.tool == event.tool:
                            existing_for_window = existing_session
                            break

                if existing_for_window:
                    # Reuse existing session for this window
                    session = existing_for_window
                    session.last_event_at = now
                    logger.debug(f"Reusing session {session.session_id} for window {window_id}")
                else:
                    # Prefer project from window marks, fall back to telemetry
                    project = window_project or self._extract_project(event)
                    tool = event.tool or AITool.CLAUDE_CODE
                    # Derive provider from tool
                    provider = TOOL_PROVIDER.get(tool, Provider.ANTHROPIC)
                    session = Session(
                        session_id=session_id,
                        tool=tool,
                        provider=provider,
                        state=SessionState.IDLE,
                        project=project,
                        window_id=window_id,
                        created_at=now,
                        last_event_at=now,
                        state_changed_at=now,
                    )
                    self._sessions[session_id] = session
                    logger.info(f"Created session {session_id} for {session.tool}/{provider.value} (window_id={window_id}, project={project})")

            # Update last event time
            session.last_event_at = now

            # Feature 135: PID-based window correlation on every event
            # Always try PID correlation to handle worktree switching where
            # the window changes but session continues.
            client_pid = event.attributes.get("process.pid") or event.attributes.get("pid")

            # Use cached PID if not in event attributes
            if not client_pid and session_id in self._session_pids:
                client_pid = self._session_pids[session_id]

            # Cache PID for future correlation and store in session
            if client_pid:
                try:
                    pid_int = int(client_pid)
                    if session_id not in self._session_pids:
                        self._session_pids[session_id] = pid_int
                    # Feature 135: Also store in session model for heartbeat correlation
                    if session.pid is None:
                        session.pid = pid_int
                except (ValueError, TypeError):
                    pass

            # Feature 135: Deterministic PID-based window re-correlation
            # Use daemon IPC to re-check window correlation on every event.
            # This handles worktree switching where the window may change.
            # Multiple tmux panes in one Ghostty share the same I3PM_* env,
            # so they'll all correlate to the same Sway window. This is correct
            # for the UI model (one badge per window, not per pane).
            if client_pid:
                try:
                    pid = int(client_pid)
                    i3pm_env = get_process_i3pm_env(pid)
                    new_project = i3pm_env.get("I3PM_PROJECT_NAME") if i3pm_env else None

                    # Feature 135: Deterministic correlation via daemon IPC
                    new_window_id = await find_window_for_session(pid)

                    if new_window_id and new_window_id != session.window_id:
                        old_window = session.window_id
                        session.window_id = new_window_id
                        if new_project:
                            session.project = new_project
                        logger.info(
                            f"Session {session.session_id}: window {old_window} → "
                            f"{new_window_id} via PID {pid} (project={new_project})"
                        )
                    elif new_window_id and session.window_id is None:
                        session.window_id = new_window_id
                        if new_project:
                            session.project = new_project
                        logger.info(
                            f"Session {session.session_id}: correlated to "
                            f"window {new_window_id} via PID {pid}"
                        )
                except (ValueError, TypeError):
                    pass

            # Feature 135: NO FALLBACK - if daemon doesn't find the window, leave it as-is
            # This is intentional: we prefer "unknown" over "wrong window"

            # Update project if available
            project = self._extract_project(event)
            if project:
                session.project = project

            # Update token metrics if available
            self._update_metrics(session, event)

            # Feature 135: Handle tool lifecycle events for pending tool tracking
            await self._handle_tool_lifecycle(session, event)

            # Feature 135: Handle streaming events for TTFT metrics
            await self._handle_streaming_events(session, event)

            # Handle state transitions based on event
            old_state = session.state
            new_state = self._compute_new_state(session, event)

            if new_state != old_state:
                session.state = new_state
                session.state_changed_at = now
                logger.info(f"Session {session_id}: {old_state} → {new_state}")

                # Handle state-specific actions
                await self._handle_state_change(session, old_state, new_state)

            # Reset or start quiet timer for WORKING state
            if session.state == SessionState.WORKING:
                self._reset_quiet_timer(session_id)

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

        Args:
            tool: AI tool type (CLAUDE_CODE, CODEX_CLI, etc.)
            pid: Optional process PID for more accurate session targeting
        """
        async with self._lock:
            now = datetime.now(timezone.utc)
            found_by_pid = False

            # If PID provided, try to find specific session first
            if pid:
                for session_id, session in self._sessions.items():
                    if (
                        session.tool == tool
                        and session.state == SessionState.WORKING
                        and session.pid == pid
                    ):
                        session.last_event_at = now
                        self._reset_quiet_timer(session_id)
                        logger.debug(
                            f"Session {session_id}: heartbeat extended by metrics (pid={pid})"
                        )
                        found_by_pid = True
                        break

            # Fall back to extending all working sessions for tool
            if not found_by_pid:
                for session_id, session in self._sessions.items():
                    if session.tool == tool and session.state == SessionState.WORKING:
                        session.last_event_at = now
                        self._reset_quiet_timer(session_id)
                        logger.debug(f"Session {session_id}: heartbeat extended by metrics")

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
        # Emit full session list on every state change
        # EWW deflisten replaces the entire variable, so SessionUpdate would
        # overwrite SessionList and break the widget. Always send full state.
        # Note: Caller already holds the lock, use unlocked version.
        await self._broadcast_sessions_unlocked()

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
        """Periodically broadcast full session list."""
        while self._running:
            try:
                await asyncio.sleep(self.broadcast_interval_sec)
                await self._broadcast_sessions()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Broadcast error: {e}")

    async def _broadcast_sessions(self) -> None:
        """Broadcast current session list (acquires lock)."""
        async with self._lock:
            await self._broadcast_sessions_unlocked()

    async def _broadcast_sessions_unlocked(self) -> None:
        """Broadcast current session list (caller must hold lock).

        Feature 136: Removed feature-based deduplication. All sessions are now
        included, grouped by window_id for multi-indicator display.

        Sessions are sorted by state priority within each window:
        - ATTENTION > WORKING > COMPLETED > IDLE
        """
        active_sessions = [
            s for s in self._sessions.values()
            if s.state != SessionState.EXPIRED
        ]

        # Feature 136: Build all items list (no deduplication)
        items = [
            SessionListItem(
                session_id=s.session_id,
                tool=s.tool,
                state=s.state,
                project=s.project,
                window_id=s.window_id,
                pending_tools=s.pending_tools,
                is_streaming=s.is_streaming,
            )
            for s in active_sessions
        ]

        # Feature 136: Group sessions by window_id for efficient EWW lookup
        # Orphaned sessions (window_id=None) are grouped under window_id=-1
        # for display in a "Global AI Sessions" section
        sessions_by_window: dict[int, list[SessionListItem]] = {}
        orphan_sessions: list[SessionListItem] = []
        for item in items:
            if item.window_id is not None:
                if item.window_id not in sessions_by_window:
                    sessions_by_window[item.window_id] = []
                sessions_by_window[item.window_id].append(item)
            else:
                orphan_sessions.append(item)

        # Add orphan sessions under special window_id -1 for global display
        if orphan_sessions:
            sessions_by_window[-1] = orphan_sessions

        # Sort each window's sessions by state priority (highest first)
        for window_id in sessions_by_window:
            sessions_by_window[window_id].sort(
                key=lambda s: state_priority(SessionState(s.state)),
                reverse=True
            )

        has_working = any(s.state == SessionState.WORKING for s in active_sessions)

        session_list = SessionList(
            sessions=items,
            sessions_by_window=sessions_by_window,
            timestamp=int(datetime.now(timezone.utc).timestamp()),
            has_working=has_working,
        )
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
                await self.output.write_update(update)

    async def _cleanup_orphaned_windows(self) -> None:
        """Remove sessions whose windows no longer exist.

        This handles the case where a terminal is closed but the session
        hasn't timed out yet. We validate that window_id still exists in Sway.
        """
        # Get current window IDs from Sway
        current_windows = get_all_window_ids()
        if not current_windows:
            # Can't get window list - skip cleanup to avoid false positives
            return

        orphaned = []

        async with self._lock:
            for session_id, session in self._sessions.items():
                # Skip sessions without window_id
                if not session.window_id:
                    continue

                # Check if window still exists
                if session.window_id not in current_windows:
                    orphaned.append(session_id)

            # Remove orphaned sessions
            for session_id in orphaned:
                session = self._sessions.pop(session_id)
                logger.info(f"Session {session_id} orphaned (window {session.window_id} closed)")

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
                await self._broadcast_sessions_unlocked()
