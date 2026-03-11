"""Process-based liveness monitoring for already-tracked AI assistant sessions."""

import asyncio
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Optional

from .models import AITool, SessionState

if TYPE_CHECKING:
    from .session_tracker import SessionTracker

logger = logging.getLogger(__name__)


class ProcessMonitor:
    """Monitors AI assistant processes to keep existing sessions alive."""

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
                        continue

                    # Detect Claude Code CLI
                    if self._is_claude_process(cmdline):
                        current_pids[pid] = AITool.CLAUDE_CODE
                        continue

                    # Detect Gemini CLI
                    if self._is_gemini_process(cmdline):
                        current_pids[pid] = AITool.GEMINI_CLI

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
        cmd = str(cmdline or "")
        if not cmd.strip():
            return False
        # Exclude telemetry interceptor process itself.
        if "codex-otel-interceptor" in cmd:
            return False

        parts = cmd.split()
        if not parts:
            return False

        executable = Path(parts[0]).name
        # Match both the wrapper entrypoint and the long-running raw binary.
        # `codex-raw` powers interactive sessions and must be tracked to keep
        # session state alive between telemetry bursts.
        if executable in {"codex", "codex-raw", ".codex-wrapped"}:
            return True
        if parts[0].endswith("/bin/codex") or parts[0].endswith("/bin/codex-raw"):
            return True

        # Wrapped Nix launchers may execute Node with a codex script as argv[1].
        if executable.startswith("node") and len(parts) >= 2:
            target = Path(parts[1]).name
            if target in {"codex", "codex-raw", ".codex-wrapped"}:
                return True

        return False

    def _is_claude_process(self, cmdline: str) -> bool:
        """Check if command line is a Claude Code process."""
        cmd = str(cmdline or "").strip()
        if not cmd:
            return False
        # Exclude the native host helper process (not a user session).
        if "--chrome-native-host" in cmd:
            return False

        # Prefer explicit Claude entrypoints and wrapped binaries.
        return (
            "/bin/.claude-unwrapped " in cmd
            or cmd.endswith("/bin/.claude-unwrapped")
            or "/bin/.claude-wrapped_ " in cmd
            or cmd.endswith("/bin/.claude-wrapped_")
            or "/bin/claude " in cmd
            or cmd.endswith("/bin/claude")
        )

    def _is_gemini_process(self, cmdline: str) -> bool:
        """Check if command line is a Gemini CLI process."""
        cmd = str(cmdline or "").strip()
        if not cmd:
            return False

        cmd_lower = cmd.lower()
        # Exclude telemetry interceptor process itself.
        if "gemini-otel-interceptor" in cmd_lower:
            return False

        parts = cmd.split()
        if not parts:
            return False

        executable = Path(parts[0]).name

        # Direct wrapper entrypoints.
        if executable in {"gemini", ".gemini-wrapped"}:
            return True
        if "/bin/gemini " in cmd or cmd.endswith("/bin/gemini"):
            return True
        if "/bin/.gemini-wrapped " in cmd or cmd.endswith("/bin/.gemini-wrapped"):
            return True

        # Nix wrapper executes Node with the wrapped Gemini script as argv[1].
        if executable.startswith("node") and len(parts) >= 2:
            target = Path(parts[1]).name
            if target in {"gemini", ".gemini-wrapped"}:
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
                resolved_session_id = await self._resolve_session_id_for_pid(
                    f"{tool.value}:pid:{pid}",
                    pid,
                )
                if resolved_session_id:
                    self._process_sessions[pid] = resolved_session_id
                else:
                    logger.debug(
                        "Process monitor: ignoring untracked %s pid=%s during anchor-only cutover",
                        tool.value,
                        pid,
                    )

            else:
                # Existing process - keep session alive
                session_id = self._process_sessions[pid]
                await self._keepalive_session(session_id, pid)

        # Find terminated processes
        terminated_pids = set(self._process_sessions.keys()) - set(current_pids.keys())
        for pid in terminated_pids:
            session_id = self._process_sessions.pop(pid)
            await self._complete_session(session_id, pid)

    async def _resolve_session_id_for_pid(
        self,
        session_id: str,
        pid: int,
    ) -> Optional[str]:
        """Resolve session IDs that may have been re-keyed by native identity."""
        async with self.tracker._lock:
            if session_id in self.tracker._sessions:
                return session_id

            for live_session_id, session in self.tracker._sessions.items():
                if session.pid != pid or session.state == SessionState.EXPIRED:
                    continue
                self._process_sessions[pid] = live_session_id
                logger.debug(
                    "Process monitor: remapped pid %s session %s -> %s after rekey",
                    pid,
                    session_id,
                    live_session_id,
                )
                return live_session_id
        return None

    async def _keepalive_session(self, session_id: str, pid: int) -> None:
        """Keep a process-based session alive.

        Args:
            session_id: Session to keep alive
        """
        resolved_session_id = await self._resolve_session_id_for_pid(session_id, pid)
        if not resolved_session_id:
            return

        now = datetime.now(timezone.utc)

        async with self.tracker._lock:
            session = self.tracker._sessions.get(resolved_session_id)
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
                logger.info(f"Process monitor: session {resolved_session_id} {old_state} → WORKING")
                self.tracker._mark_dirty_unlocked()

    async def _complete_session(self, session_id: str, pid: int) -> None:
        """Mark a process-based session as completed.

        Args:
            session_id: Session to complete
        """
        resolved_session_id = await self._resolve_session_id_for_pid(session_id, pid)
        if not resolved_session_id:
            return

        now = datetime.now(timezone.utc)

        async with self.tracker._lock:
            session = self.tracker._sessions.get(resolved_session_id)
            if not session:
                return

            if session.state == SessionState.WORKING:
                old_state = session.state
                session.state = SessionState.COMPLETED
                session.state_changed_at = now
                session.state_seq += 1
                session.status_reason = "process_exited"
                logger.info(
                    f"Process monitor: session {resolved_session_id} {old_state} → COMPLETED (process exited)"
                )

                # Start completed timeout timer
                self.tracker._start_completed_timer(resolved_session_id)

                # Broadcast and notify
                self.tracker._mark_dirty_unlocked()
                if self.tracker.enable_notifications:
                    await self.tracker._send_completion_notification(session)
