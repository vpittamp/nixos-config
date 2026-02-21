"""Process-based monitoring for AI assistants.

This module provides a fallback detection mechanism for tools that don't
emit telemetry in real-time (like Codex which batches until shutdown).

It periodically scans for running processes and creates/updates sessions
based on process presence.
"""

import asyncio
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Optional

from .models import AITool, Session, SessionState
from .sway_helper import get_focused_window_info

if TYPE_CHECKING:
    from .session_tracker import SessionTracker

logger = logging.getLogger(__name__)


class ProcessMonitor:
    """Monitors running processes for AI assistant tools.

    Provides fallback detection when telemetry is unavailable or delayed.
    """

    def __init__(
        self,
        tracker: "SessionTracker",
        poll_interval_sec: float = 2.0,
    ) -> None:
        """Initialize process monitor.

        Args:
            tracker: SessionTracker to update with detected sessions
            poll_interval_sec: How often to scan for processes
        """
        self.tracker = tracker
        self.poll_interval_sec = poll_interval_sec
        self._running = False
        self._monitor_task: Optional[asyncio.Task] = None

        # Track known process sessions: pid -> session_id
        self._process_sessions: dict[int, str] = {}

    async def start(self) -> None:
        """Start the process monitor loop."""
        self._running = True
        self._monitor_task = asyncio.create_task(self._monitor_loop())
        logger.info("Process monitor started")

    async def stop(self) -> None:
        """Stop the process monitor."""
        self._running = False
        if self._monitor_task:
            self._monitor_task.cancel()
            try:
                await self._monitor_task
            except asyncio.CancelledError:
                pass
        logger.info("Process monitor stopped")

    async def _monitor_loop(self) -> None:
        """Main monitoring loop."""
        while self._running:
            try:
                await self._scan_processes()
                await asyncio.sleep(self.poll_interval_sec)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Process monitor error: {e}")
                await asyncio.sleep(self.poll_interval_sec)

    async def _scan_processes(self) -> None:
        """Scan /proc for AI assistant processes."""
        current_pids: dict[int, AITool] = {}

        try:
            proc_path = Path("/proc")
            for entry in proc_path.iterdir():
                if not entry.name.isdigit():
                    continue

                pid = int(entry.name)
                cmdline_path = entry / "cmdline"

                try:
                    cmdline = cmdline_path.read_text().replace("\x00", " ").strip()

                    # Detect Codex CLI
                    if self._is_codex_process(cmdline):
                        current_pids[pid] = AITool.CODEX_CLI

                except (PermissionError, FileNotFoundError, ProcessLookupError):
                    # Process may have exited
                    continue

        except Exception as e:
            logger.error(f"Error scanning /proc: {e}")
            return

        # Update sessions based on detected processes
        await self._update_sessions(current_pids)

    def _is_codex_process(self, cmdline: str) -> bool:
        """Check if command line is a Codex CLI process.

        Args:
            cmdline: Process command line

        Returns:
            True if this is a Codex CLI process
        """
        # Match /nix/store/.../codex or just "codex" binary
        # Exclude our wrapper script
        if "/bin/codex" in cmdline and "exec" not in cmdline:
            # Ensure it's actually running (not just the wrapper)
            return True
        return False

    async def _update_sessions(self, current_pids: dict[int, AITool]) -> None:
        """Update session tracker based on detected processes.

        Args:
            current_pids: Map of pid -> tool for detected processes
        """
        now = datetime.now(timezone.utc)

        # Find new processes
        for pid, tool in current_pids.items():
            if pid not in self._process_sessions:
                # New process detected - create session
                session_id = f"proc-{tool.value}-{pid}"
                self._process_sessions[pid] = session_id

                # Get window context
                window_id, window_project = get_focused_window_info()

                # Create session in tracker
                await self._create_process_session(
                    session_id=session_id,
                    tool=tool,
                    pid=pid,
                    window_id=window_id,
                    project=window_project,
                )

            else:
                # Existing process - keep session alive
                session_id = self._process_sessions[pid]
                await self._keepalive_session(session_id)

        # Find terminated processes
        terminated_pids = set(self._process_sessions.keys()) - set(current_pids.keys())
        for pid in terminated_pids:
            session_id = self._process_sessions.pop(pid)
            await self._complete_session(session_id)

    async def _create_process_session(
        self,
        session_id: str,
        tool: AITool,
        pid: int,
        window_id: Optional[int],
        project: Optional[str],
    ) -> None:
        """Create a new session for a detected process.

        Args:
            session_id: Unique session identifier
            tool: AI tool type
            pid: Process ID
            window_id: Sway window ID if available
            project: Project name if available
        """
        now = datetime.now(timezone.utc)

        async with self.tracker._lock:
            # Check if session already exists (from telemetry)
            if session_id in self.tracker._sessions:
                return

            session = Session(
                session_id=session_id,
                tool=tool,
                state=SessionState.WORKING,
                project=project,
                window_id=window_id,
                pid=pid,
                created_at=now,
                last_event_at=now,
                state_changed_at=now,
                state_seq=1,
                status_reason="process_detected",
            )
            self.tracker._sessions[session_id] = session
            logger.info(f"Process monitor: created session {session_id} for pid {pid}")
            self.tracker._mark_dirty_unlocked()

    async def _keepalive_session(self, session_id: str) -> None:
        """Keep a process-based session alive.

        Args:
            session_id: Session to keep alive
        """
        now = datetime.now(timezone.utc)

        async with self.tracker._lock:
            session = self.tracker._sessions.get(session_id)
            if not session:
                return

            # Update last event time
            session.last_event_at = now

            # Ensure still in WORKING state
            if session.state != SessionState.WORKING:
                old_state = session.state
                session.state = SessionState.WORKING
                session.state_changed_at = now
                session.state_seq += 1
                session.status_reason = "process_keepalive"
                logger.info(f"Process monitor: session {session_id} {old_state} → WORKING")
                self.tracker._mark_dirty_unlocked()

    async def _complete_session(self, session_id: str) -> None:
        """Mark a process-based session as completed.

        Args:
            session_id: Session to complete
        """
        now = datetime.now(timezone.utc)

        async with self.tracker._lock:
            session = self.tracker._sessions.get(session_id)
            if not session:
                return

            if session.state == SessionState.WORKING:
                old_state = session.state
                session.state = SessionState.COMPLETED
                session.state_changed_at = now
                session.state_seq += 1
                session.status_reason = "process_exited"
                logger.info(f"Process monitor: session {session_id} {old_state} → COMPLETED (process exited)")

                # Start completed timeout timer
                self.tracker._start_completed_timer(session_id)

                # Broadcast and notify
                self.tracker._mark_dirty_unlocked()
                if self.tracker.enable_notifications:
                    await self.tracker._send_completion_notification(session)
