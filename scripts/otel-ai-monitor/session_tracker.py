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
import re
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Optional

from .models import (
    AITool,
    EventNames,
    Session,
    SessionList,
    SessionListItem,
    SessionState,
    SessionUpdate,
    TelemetryEvent,
)
from .sway_helper import get_all_window_ids, get_focused_window_info

if TYPE_CHECKING:
    from .output import OutputWriter

logger = logging.getLogger(__name__)

# Feature number extraction pattern: matches ":<number>" or "<number>-" at start of branch name
_FEATURE_NUMBER_PATTERN = re.compile(r":(\d+)")


def extract_feature_number(project: Optional[str]) -> Optional[str]:
    """Extract feature number from project name for deduplication.

    Examples:
        "vpittamp/nixos-config:123-otel-tracing" → "123"
        "owner/repo:456-feature" → "456"
        "Global" → None
        None → None
    """
    if not project or project == "Global":
        return None
    match = _FEATURE_NUMBER_PATTERN.search(project)
    return match.group(1) if match else None


def state_priority(state: SessionState) -> int:
    """Return priority for state comparison (higher = more important)."""
    return {
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
        quiet_period_sec: float = 3.0,
        session_timeout_sec: float = 300.0,
        completed_timeout_sec: float = 30.0,
        enable_notifications: bool = True,
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

        # Quiet period timers: session_id -> Task
        self._quiet_timers: dict[str, asyncio.Task] = {}

        # Completed timeout timers: session_id -> Task
        self._completed_timers: dict[str, asyncio.Task] = {}

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
            # Generate from tool + timestamp
            # Note: event.tool is already a string due to use_enum_values = True in TelemetryEvent
            tool_name = event.tool if event.tool else "unknown"
            session_id = f"{tool_name}-{int(event.timestamp.timestamp())}"

        async with self._lock:
            session = self._sessions.get(session_id)
            now = datetime.now(timezone.utc)

            if session is None:
                # Create new session
                # Capture focused window ID and project from window marks
                window_id, window_project = get_focused_window_info()

                # Check for existing session with same window_id (deduplicate)
                existing_for_window = None
                if window_id:
                    for existing_id, existing_session in self._sessions.items():
                        if existing_session.window_id == window_id:
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
                    session = Session(
                        session_id=session_id,
                        tool=event.tool or AITool.CLAUDE_CODE,
                        state=SessionState.IDLE,
                        project=project,
                        window_id=window_id,
                        created_at=now,
                        last_event_at=now,
                        state_changed_at=now,
                    )
                    self._sessions[session_id] = session
                    logger.info(f"Created session {session_id} for {session.tool} (window_id={window_id}, project={project})")

            # Update last event time
            session.last_event_at = now

            # Update project if available
            project = self._extract_project(event)
            if project:
                session.project = project

            # Update token metrics if available
            self._update_metrics(session, event)

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

    async def process_heartbeat_for_tool(self, tool: AITool) -> None:
        """Process a heartbeat signal for all sessions of a given tool.

        Since Claude Code metrics don't include session_id, we extend the quiet
        period for ALL working sessions of that tool. This is safe because:
        1. Metrics are only sent when the tool is actively running
        2. Multiple sessions of the same tool are rare

        Args:
            tool: AI tool type (CLAUDE_CODE, CODEX_CLI, etc.)
        """
        async with self._lock:
            now = datetime.now(timezone.utc)
            for session_id, session in self._sessions.items():
                if session.tool == tool and session.state == SessionState.WORKING:
                    session.last_event_at = now
                    self._reset_quiet_timer(session_id)
                    logger.debug(f"Session {session_id}: heartbeat extended by metrics")

    def _compute_new_state(
        self, session: Session, event: TelemetryEvent
    ) -> SessionState:
        """Compute new state based on current state and event.

        Args:
            session: Current session
            event: Incoming event

        Returns:
            New session state (may be same as current)
        """
        current = session.state
        event_name = event.event_name

        # Events that trigger WORKING state
        if event_name in EventNames.WORKING_TRIGGERS:
            return SessionState.WORKING

        # Events that keep WORKING state (activity)
        if current == SessionState.WORKING and event_name in EventNames.ACTIVITY_EVENTS:
            return SessionState.WORKING

        # COMPLETED → WORKING on new prompt
        if current == SessionState.COMPLETED and event_name in EventNames.WORKING_TRIGGERS:
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

        # Handle Codex token events
        if event.event_name == EventNames.CODEX_SSE_EVENT:
            if "input_tokens" in attrs:
                session.input_tokens = int(attrs["input_tokens"])
            if "output_tokens" in attrs:
                session.output_tokens = int(attrs["output_tokens"])
            if "cache_tokens" in attrs:
                session.cache_tokens = int(attrs["cache_tokens"])

        # Handle Gemini/GenAI standard token events
        elif event.event_name == EventNames.GEMINI_TOKEN_USAGE:
            # GenAI semantic conventions use gen_ai.usage.*
            # but CLI might use flattened attributes
            input_keys = ("gen_ai.usage.input_tokens", "input_tokens", "prompt_tokens")
            output_keys = ("gen_ai.usage.output_tokens", "output_tokens", "completion_tokens")

            for key in input_keys:
                if key in attrs:
                    session.input_tokens = int(attrs[key])
                    break

            for key in output_keys:
                if key in attrs:
                    session.output_tokens = int(attrs[key])
                    break

        # Handle Claude Code per-request token usage (sum across the session)
        elif event.event_name == EventNames.CLAUDE_API_REQUEST:
            try:
                session.input_tokens += int(attrs.get("input_tokens") or 0)
                session.output_tokens += int(attrs.get("output_tokens") or 0)
                cache_read = int(attrs.get("cache_read_tokens") or 0)
                cache_create = int(attrs.get("cache_creation_tokens") or 0)
                session.cache_tokens += cache_read + cache_create
            except Exception:
                # Best-effort only; don't let parsing break session tracking
                pass

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

        Args:
            session_id: Session that has been quiet
        """
        async with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return

            if session.state != SessionState.WORKING:
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

        # Send notification on completion
        if new_state == SessionState.COMPLETED and self.enable_notifications:
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
            Dictionary of token metrics
        """
        return {
            "input_tokens": session.input_tokens,
            "output_tokens": session.output_tokens,
            "cache_tokens": session.cache_tokens,
        }

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

        Deduplicates sessions by feature number - when multiple sessions have
        the same feature number, only the highest priority one is shown:
        - WORKING > COMPLETED > IDLE
        - Within same priority, prefer the most recent session
        """
        active_sessions = [
            s for s in self._sessions.values()
            if s.state != SessionState.EXPIRED
        ]

        # Deduplicate by feature number
        # Key: feature_number (or project if no feature number, or session_id for Global)
        # Value: best session for that key
        best_by_feature: dict[str, Session] = {}
        for session in active_sessions:
            feature = extract_feature_number(session.project)
            # Use feature number as key, fallback to full project, fallback to session_id
            key = feature or session.project or session.session_id

            if key not in best_by_feature:
                best_by_feature[key] = session
            else:
                existing = best_by_feature[key]
                # Compare by state priority, then by most recent state change
                if state_priority(session.state) > state_priority(existing.state):
                    best_by_feature[key] = session
                elif (state_priority(session.state) == state_priority(existing.state)
                      and session.state_changed_at > existing.state_changed_at):
                    best_by_feature[key] = session

        # Build deduplicated items list
        deduplicated_sessions = list(best_by_feature.values())
        items = [
            SessionListItem(
                session_id=s.session_id,
                tool=s.tool,
                state=s.state,
                project=s.project,
                window_id=s.window_id,
            )
            for s in deduplicated_sessions
        ]
        has_working = any(s.state == SessionState.WORKING for s in deduplicated_sessions)

        session_list = SessionList(
            sessions=items,
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

            # Broadcast updated list if any were removed
            if orphaned:
                await self._broadcast_sessions_unlocked()
