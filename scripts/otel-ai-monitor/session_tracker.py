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
    Session,
    SessionList,
    SessionListItem,
    SessionState,
    SessionUpdate,
    TelemetryEvent,
)

if TYPE_CHECKING:
    from .output import OutputWriter

logger = logging.getLogger(__name__)


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
                session = Session(
                    session_id=session_id,
                    tool=event.tool or AITool.CLAUDE_CODE,
                    state=SessionState.IDLE,
                    project=self._extract_project(event),
                    created_at=now,
                    last_event_at=now,
                    state_changed_at=now,
                )
                self._sessions[session_id] = session
                logger.info(f"Created session {session_id} for {session.tool}")

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
        # Only codex.sse_event typically has token counts
        if event.event_name != EventNames.CODEX_SSE_EVENT:
            return

        attrs = event.attributes
        if "input_tokens" in attrs:
            session.input_tokens = int(attrs["input_tokens"])
        if "output_tokens" in attrs:
            session.output_tokens = int(attrs["output_tokens"])
        if "cache_tokens" in attrs:
            session.cache_tokens = int(attrs["cache_tokens"])

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
        # Emit session update
        update = SessionUpdate(
            session_id=session.session_id,
            tool=session.tool,
            state=new_state,
            project=session.project,
            timestamp=int(datetime.now(timezone.utc).timestamp()),
            metrics=self._get_metrics_dict(session) if session.input_tokens > 0 else None,
        )
        await self.output.write_update(update)

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
        """Broadcast current session list."""
        async with self._lock:
            active_sessions = [
                s for s in self._sessions.values()
                if s.state != SessionState.EXPIRED
            ]
            items = [
                SessionListItem(
                    session_id=s.session_id,
                    tool=s.tool,
                    state=s.state,
                    project=s.project,
                )
                for s in active_sessions
            ]
            has_working = any(s.state == SessionState.WORKING for s in active_sessions)

        session_list = SessionList(
            sessions=items,
            timestamp=int(datetime.now(timezone.utc).timestamp()),
            has_working=has_working,
        )
        await self.output.write_session_list(session_list)

    async def _expiry_loop(self) -> None:
        """Periodically check for and remove expired sessions."""
        while self._running:
            try:
                await asyncio.sleep(30)  # Check every 30 seconds
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
